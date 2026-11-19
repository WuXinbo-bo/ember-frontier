extends SceneTree
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Residency=preload("res://scripts/runtime/region_residency.gd")
class Host extends Native:
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
class FailedStore extends RefCounted:
	var root:String
	var attempts:=0
	func begin_save(_capture:Dictionary)->Dictionary:
		attempts+=1
		return {"ok":false,"code":"IO_ERROR","reason":"Injected stream working-save write failure"}
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool)->void:
	checks.append({"name":label,"ok":ok})
	if not ok:push_error(label)
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();var out:String=args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var loaded:Dictionary=Store.new(args[1]).load_current()
	check("real complete save decodes",loaded.ok)
	if not loaded.ok:quit(1);return
	var host:=Host.new();root.add_child(host)
	var made:Dictionary=host._assemble(loaded.capture)
	check("real authority assembles",made.ok)
	if not made.ok:host.queue_free();quit(1);return
	host.world=made.world;host.runtime=made.runtime;host._world_epoch=1;host.runtime.set_paused(true);host._residency.attach(host.runtime)
	var pins:Dictionary=Residency.required_regions(host.runtime);var target:String=""
	for id:String in host.world.region_ids():
		if not pins.has(id) and not host.world.region_residency_state(id).paged:target=id;break
	check("real unpinned unpaged region available",not target.is_empty())
	var capture:Dictionary=host.runtime.capture_checkpoint();host._stream_checkpoint_listen();host._stream_checkpoint_capture(capture)
	var failed_store:=FailedStore.new();failed_store.root=out;host._stream_store=failed_store
	var slot:String=out+"/corrupt.json";FileAccess.open(slot,FileAccess.WRITE).store_string("replaced complete slot")
	var receipt:Dictionary={"ok":true,"activated":true,"namespace":"proof","slot":"a","checkpoint_id":"native:proof","sha256":"a".repeat(64),"path":slot}
	var pointer:Dictionary={"namespace":"proof","slot":"a","checkpoint_id":"native:proof","world_id":host.world.identity().worldId,"sha256":receipt.sha256}
	FileAccess.open(out+"/active.json",FileAccess.WRITE).store_string(JSON.stringify(pointer))
	host._stream_checkpoint.receipt=receipt
	check("semantic reuse proof alone matches before detached file validation",host._stream_checkpoint_matches(target))
	var result:Dictionary=await host._change_residency({"region_id":target,"resident":false})
	check("corrupt cached slot forces original full-save fallback",failed_store.attempts==1 and not result.get("checkpoint_reused",true))
	check("failed replacement save refuses actual region eviction",not result.ok and result.code=="IO_ERROR" and not host.world.region_residency_state(target).paged and result.batches==0)
	check("failure preserves complete world and all runtime facts",capture.world==host.world.snapshot() and capture.facts==host.runtime.facts())
	check("failure leaves stream gate available for retry",not host._streaming and not host._stream_state.busy and host._stream_checkpoint.is_empty())
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(out+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"result":result,"scope":"Actual Native failure path on original real authority; injected stream-store write failure only. No performance or GUI claim."},"\t",true,true))
	host.runtime.retire();host.queue_free();await process_frame
	print(JSON.stringify({"suite":"paging_failure16","checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
