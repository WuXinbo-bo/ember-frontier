extends SceneTree
## Real startup geometry/readiness, with explicit isolated disk/lifecycle races.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
class StartupClient extends Native:
	var fault:String=""
	var slot:String=""
	var actual_ready:bool=false
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _prepare_mount_ready(capture:Dictionary,assembly:Dictionary={})->Dictionary:
		var candidate:Dictionary=await super._prepare_mount_ready(capture,assembly)
		actual_ready=candidate.get("ok",false) and candidate.get("readiness",{}).get("ready",false)
		if candidate.get("ok",false):
			if fault=="active":
				var f:=FileAccess.open(store.root+"/active.json",FileAccess.WRITE);f.store_string("{}");f.close()
			elif fault=="slot":
				var text:String=FileAccess.get_file_as_string(slot)
				var f:=FileAccess.open(slot,FileAccess.WRITE);f.store_string(text.replace('"format"','"xormat"'));f.close()
			elif fault=="closing":_closing=true
		return candidate
var checks:Array=[]
var output:String
var observations:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func preserves_original(capture:Dictionary,current:Dictionary)->bool:
	# A save produced without a renderer can legitimately need new camera
	# frontier regions. Only their first-time stocks/events may be appended;
	# all original people, stocks, costs, knowledge and clocks stay exact.
	for key:String in capture.facts:
		if key not in ["stocks","ledger"] and not Data.json_equal(capture.facts[key],current.facts.get(key)):return false
	var stock_ids:Dictionary={}
	for stock:Dictionary in current.facts.stocks:
		if stock_ids.has(stock.id):return false
		stock_ids[stock.id]=stock
	var original_ids:Dictionary={}
	for stock:Dictionary in capture.facts.stocks:
		original_ids[stock.id]=true
		if not Data.json_equal(stock,stock_ids.get(stock.id)):return false
	var generated:Dictionary={}
	for id:String in current.world.regions:
		if not capture.world.regions.has(id):generated[id]=true
	for stock:Dictionary in current.facts.stocks:
		if not original_ids.has(stock.id) and not generated.has(str(stock.get("location",{}).get("regionId",""))):return false
	var original_events:Dictionary={}
	for event:Dictionary in capture.facts.ledger:original_events[event.id]=true
	var retained:Array=[]
	var event_ids:Dictionary={}
	for event:Dictionary in current.facts.ledger:
		if event_ids.has(event.id):return false
		event_ids[event.id]=true
		if original_events.has(event.id):retained.append(event)
		elif event.kind!="region_generated" or not generated.has(str(event.get("region_id",""))):return false
	var expected_retained:Array=capture.facts.ledger.slice(capture.facts.ledger.size()-retained.size())
	return Data.json_equal(expected_retained,retained) and Data.json_equal(current.receipts,capture.receipts) and Data.json_equal(current.simulation,capture.simulation)
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=2:quit(2);return
	output=args[0];var input:String=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	var digest:String=FileAccess.get_sha256(input)
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(input))
	check("explicit unedited normal source decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):finish();return
	for fault:String in ["success","active","slot","closing"]:
		var host:=StartupClient.new();host.controls_path=output+"/"+fault+"/controls.json";host.store=Store.new(output+"/"+fault+"/saves");host.fault=fault;root.add_child(host)
		var started:Dictionary=host.store.begin_save(decoded.capture,true)
		var saved:Dictionary={}
		if started.get("ok",false):
			while saved.is_empty():await process_frame;saved=host.store.poll()
		check(fault+" creates actual independent native save",started.get("ok",false) and saved.get("ok",false))
		if not saved.get("ok",false):host.free();finish();return
		host.slot=saved.path
		var active_path:String=host.store.root+"/active.json"
		var before_active:PackedByteArray=FileAccess.get_file_as_bytes(active_path)
		var before_slot:PackedByteArray=FileAccess.get_file_as_bytes(saved.path)
		var read:Dictionary=host.store.load_current()
		check(fault+" reads verified shipping slot with precise basis",read.get("ok",false) and read.get("source_sha256")==FileAccess.get_sha256(saved.path) and read.get("read_active_sha256")==FileAccess.get_sha256(active_path))
		if not read.get("ok",false):host.free();finish();return
		var result:Dictionary=await host._startup_restore(read)
		check(fault+" exercises real camera mesh and physics before publication decision",host.actual_ready)
		var expected_active:PackedByteArray="{}".to_utf8_buffer() if fault=="active" else before_active
		var expected_slot:PackedByteArray=before_slot.get_string_from_utf8().replace('"format"','"xormat"').to_utf8_buffer() if fault=="slot" else before_slot
		check(fault+" startup never rewrites slot or active after explicit stimulus",FileAccess.get_file_as_bytes(active_path)==expected_active and FileAccess.get_file_as_bytes(saved.path)==expected_slot)
		check(fault+" releases startup load and save ownership",not host._world_loading and not host._saving)
		if fault=="success":
			check("valid startup publishes only ready complete world",result.get("ok",false) and host._ready_game and host.runtime!=null and host.scene_root.visible and not is_instance_valid(host._startup_recovery))
			check("valid startup preserves original people stocks knowledge receipts clock and permits only real new camera-region facts",preserves_original(decoded.capture,host.runtime.capture_checkpoint()))
		else:
			var expected:String={"active":"STALE_ACTIVE","slot":"STALE_CANDIDATE","closing":"WORLD_SWITCH_CANCELLED"}[fault]
			check(fault+" refuses stale startup after genuine readiness",not result.get("ok",false) and result.get("code")==expected,result.get("code"))
			check(fault+" leaves no published authority or candidate root",host.runtime==null and host.world==null and host.scene_root==null and not host._ready_game and host.get_children().filter(func(n:Node)->bool:return n is Node3D).is_empty())
			check(fault+" retains explicit original recovery interface",is_instance_valid(host._startup_recovery))
		observations.append({"case":fault,"code":result.get("code","OK"),"actual_ready":host.actual_ready,"fixture":fault!="success"})
		host.free();await process_frame
	check("original external source bytes remain exact",FileAccess.get_sha256(input)==digest)
	finish()
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"observations":observations,"scope":"Actual startup current-slot promotion after real mesh/physics readiness plus explicit isolated active/same-length-slot/closing races. No synthetic readiness success, original user saves, OS/FPS or startup decode async claim."},"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
