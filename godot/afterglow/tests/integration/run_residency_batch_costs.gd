extends SceneTree
## Same actual24 input and Native owner, bounded strategy comparison.
## Paused authority/no terrain view: CPU/callback diagnostics, never OS/FPS.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Residency=preload("res://scripts/runtime/region_residency.gd")
class CostClient extends Native:
	var budget:int=32
	func _ready()->void:pass
	func _residency_batch_limit()->int:return budget
var checks:Array=[]
var rows:Array=[]
var capture:Dictionary
var output:String
var source:String
var source_sha:String
var frames:int=0
var last_frame:int=0
var max_gap:int=0
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func pulse()->void:
	var now:int=Time.get_ticks_usec()
	if last_frame>0:max_gap=maxi(max_gap,now-last_frame)
	last_frame=now;frames+=1
func phase_diff(before:Dictionary,after:Dictionary)->Dictionary:
	var result:Dictionary={}
	for name:String in after.get("phases",{}):
		var a:Dictionary=after.phases[name];var b:Dictionary=before.get("phases",{}).get(name,{})
		result[name]={"count":int(a.get("count",0))-int(b.get("count",0)),"total_usec":int(a.get("total_usec",0))-int(b.get("total_usec",0))}
	return result
func measure(host:Node3D,id:String,warm:bool)->Dictionary:
	var before:Dictionary=host.runtime.authority_costs()
	var start:int=Time.get_ticks_usec();frames=0;last_frame=start;max_gap=0
	var receipt:Dictionary=await host._change_residency({"region_id":id,"resident":warm})
	var wall_usec:int=Time.get_ticks_usec()-start
	# The last CAS is synchronous after the worker's final yield. Observe the
	# next pulse before reading max_gap, or a single-batch run omits its ONLY
	# barrier. Keep operation wall time separate from this sampling tail.
	await process_frame
	return {"warm":warm,"wall_usec":wall_usec,"callback_window_usec":Time.get_ticks_usec()-start,"post_return_frames":1,"frames":frames,"max_callback_gap_usec":max_gap,"receipt":receipt,"commit_phases":phase_diff(before,host.runtime.authority_costs())}
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();output=args[0];source=args[1]
	DirAccess.make_dir_recursive_absolute(output);source_sha=FileAccess.get_sha256(source)
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(source))
	check("explicit actual24 input decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):finish();return
	capture=decoded.capture;check("24 regions and original three actors",capture.world.regions.size()==24 and capture.facts.actors.size()==3)
	process_frame.connect(pulse)
	# Reverse the second round to expose ordering/warm-cache bias.
	for round_index:int in 2:
		for budget:int in ([32,64,128,256] if round_index==0 else [256,128,64,32]):
			var host:=CostClient.new();host.budget=budget;root.add_child(host);host.set_process(false)
			host._stream_store=Store.new(output+"/round%d-budget%d/stream"%[round_index,budget])
			var built:Dictionary=host._assemble(capture)
			check("same complete Native source assembles %d/%d"%[round_index,budget],built.get("ok",false))
			if not built.get("ok",false):host.free();finish();return
			host.world=built.world;host.runtime=built.runtime;host._world_epoch=1;host._residency.attach(host.runtime);host.runtime.set_paused(true)
			var original:Dictionary=host.runtime.capture_checkpoint();var target:String=""
			var pins:Dictionary=Residency.required_regions(host.runtime)
			for region:Dictionary in host.world.regions():
				if not pins.has(region.id) and not host.world.region_residency_state(region.id).paged:target=region.id;break
			check("same real unpinned target available %d/%d"%[round_index,budget],not target.is_empty())
			if target.is_empty():host.free();finish();return
			var cold:Dictionary=await measure(host,target,false)
			var cold_ok:bool=cold.receipt.get("ok",false) and host.world.region_residency_state(target).paged
			check("bounded real cold %d/%d"%[round_index,budget],cold_ok,cold.receipt.get("code"))
			if not cold_ok:host.free();finish();return
			var warm:Dictionary=await measure(host,target,true)
			check("bounded real warm %d/%d"%[round_index,budget],warm.receipt.get("ok",false) and not host.world.region_residency_state(target).paged,warm.receipt.get("code"))
			check("callback window includes final cold and warm CAS %d/%d"%[round_index,budget],cold.frames>1 and warm.frames>1 and cold.max_callback_gap_usec>=cold.receipt.max_barrier_ms*1000.0 and warm.max_callback_gap_usec>=warm.receipt.max_barrier_ms*1000.0)
			var final:Dictionary=host.runtime.capture_checkpoint()
			var before_facts:Dictionary=original.facts.duplicate(true);var after_facts:Dictionary=final.facts.duplicate(true);before_facts.erase("ledger");after_facts.erase("ledger")
			var identical:bool=Data.json_equal(before_facts,after_facts) and Data.json_equal(original.world.extensions,final.world.extensions) and Data.json_equal(original.world.entities,final.world.entities) and Data.json_equal(original.receipts,final.receipts) and Data.json_equal(original.simulation,final.simulation)
			for key:String in host.world.region_chunk_keys(target):identical=identical and original.world.chunks[key].cells==final.world.chunks[key].cells
			check("roundtrip preserves every actual cell and gameplay fact %d/%d"%[round_index,budget],identical)
			rows.append({"round":round_index,"budget":budget,"region_id":target,"cold":cold,"warm":warm})
			host.free();last_frame=0;await process_frame
	check("source input remains byte exact",FileAccess.get_sha256(source)==source_sha)
	finish()
func finish()->void:
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	var result:Dictionary={"scope":"Actual Native24 source, same input reset each case, two reverse-order rounds, original paused clock and no terrain view. CPU phases/callbacks only: no formal frame/RSS/OS/VA or quiet-window qualification.","input":{"path":source,"sha256":source_sha},"checks":checks,"failed":failed,"rows":rows}
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
