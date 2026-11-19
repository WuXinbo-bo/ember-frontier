extends SceneTree
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Residency=preload("res://scripts/runtime/region_residency.gd")
class Host extends Native:
	var chunks:int=64
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _residency_batch_limit()->int:return chunks
class ProofFacts extends RefCounted:
	signal changed(change:Dictionary)
	var stocks:Array=[]
	var actors:Array=[]
	func stock_states()->Array:return stocks.duplicate(true)
	func actor_states()->Array:return actors.duplicate(true)
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool)->void:
	checks.append({"name":label,"ok":ok})
	if not ok:push_error(label)
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args();var out:String=args[0];var input:String=args[1]
	DirAccess.make_dir_recursive_absolute(out)
	var loaded:Dictionary=Store.new(input).load_current()
	check("real content15 complete baseline decodes",loaded.ok)
	if not loaded.ok:quit(1);return
	var input_pointer_sha:String=FileAccess.get_sha256(input+"/active.json")
	var input_slot_sha:String=FileAccess.get_sha256(str(loaded.path))
	var host:=Host.new();root.add_child(host)
	if args.size()>2:host.chunks=int(args[2])
	var made:Dictionary=host._assemble(loaded.capture)
	check("original native authority assembles",made.ok)
	if not made.ok:host.queue_free();quit(1);return
	host.world=made.world;host.runtime=made.runtime;host._world_epoch=1;host.runtime.set_paused(true);host._residency.attach(host.runtime)
	host._stream_store=Store.new(out+"/stream")
	var original:Dictionary=host.runtime.capture_checkpoint();var pins:Dictionary=Residency.required_regions(host.runtime)
	var targets:Array=[]
	for id:String in host.world.region_ids():
		if not pins.has(id) and not host.world.region_residency_state(id).paged:targets.append(id)
	check("two real unpinned warm regions available",targets.size()>=2)
	var rows:Array=[]
	for id:String in targets.slice(0,2):
		var measured:int=Time.get_ticks_usec()
		var result:Dictionary=await host._change_residency({"region_id":id,"resident":false})
		check("complete actual cold transfer succeeds "+id,result.ok and host.world.region_residency_state(id).paged)
		rows.append({"id":id,"elapsed_usec":Time.get_ticks_usec()-measured,"result":result})
	var after:Dictionary=host.runtime.capture_checkpoint()
	check("all real actors remain exact",original.facts.actors==after.facts.actors)
	check("all world entities and extensions remain exact",original.world.entities==after.world.entities and original.world.extensions==after.world.extensions)
	check("original player save pointer and complete slot bytes remain exact",input_pointer_sha==FileAccess.get_sha256(input+"/active.json") and input_slot_sha==FileAccess.get_sha256(str(loaded.path)))
	check("second unchanged cold region reuses complete persisted checkpoint",rows.size()==2 and rows[1].result.get("checkpoint_reused",false))
	await proof_checks(host,after,str(targets[0]),out)
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(out+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"rows":rows,"authority":host.runtime.authority_costs(),"scope":"Two actual unpinned regions from the same saved content15 world; real Native full checkpoint and storage CAS. Paused CPU fixture, no renderer/input/FPS acceptance."},"\t",true,true))
	host.runtime.retire();host.queue_free();await process_frame
	print(JSON.stringify({"suite":"paging16","checks":checks.size(),"failed":failed,"rows":rows}));quit(1 if failed else 0)

func proof_checks(source:Node,capture:Dictionary,id:String,out:String)->void:
	# Detached adversarial fixture: real World authority and production proof
	# functions, minimal fact reader. No private live Runtime facts are edited.
	var host:=Host.new();root.add_child(host)
	host.world=Native.World.new();check("proof world loads complete source",host.world.load_snapshot(capture.world).ok)
	var facts:=ProofFacts.new();facts.stocks=capture.facts.stocks.duplicate(true);facts.actors=capture.facts.actors.duplicate(true)
	host.runtime=facts;host._world_epoch=source._world_epoch;host._stream_checkpoint_listen()
	var receipt:Dictionary=source._stream_checkpoint.get("receipt",{}).duplicate(true)
	host._stream_checkpoint_capture(capture);host._stream_checkpoint.receipt=receipt
	check("unchanged target exact semantic protection matches",host._stream_checkpoint_matches(id))
	var unrelated:Dictionary=facts.actors[0].duplicate(true);facts.actors[0]["proof-outside-change"]=true
	check("actor changes outside protected region do not discard safe region proof",host._stream_checkpoint_matches(id));facts.actors[0]=unrelated
	var stock:Dictionary=facts.stocks[0].duplicate(true);facts.stocks[0]["proof-change"]=true
	check("inventory change invalidates even unchanged chunk guards",not host._stream_checkpoint_matches(id));facts.stocks[0]=stock
	facts.actors.append({"id":"proof-target","regionId":id})
	check("target actor change invalidates exact protection",not host._stream_checkpoint_matches(id));facts.actors.pop_back()
	var entities:Array=host.world.entities(id)
	if not entities.is_empty():
		var before:Dictionary=entities[0];var next:Dictionary=before.duplicate(true);next.data["proof-change"]=true
		var draft:Dictionary=host.world.prepare_changes([{"op":"entity.put","id":before.id,"before_exists":true,"before":before,"after":next}],host.world.get_revision())
		check("adversarial target entity edit commits",draft.ok and host.world.commit_prepared(draft.capability).ok)
		# Even if a caller falsely advances the revision observer, exact entity
		# comparison must still refuse the old checkpoint.
		host._stream_checkpoint.revision=host.world.get_revision()
		check("target entity change invalidates semantic protection",not host._stream_checkpoint_matches(id))
	check("same revision reload resets world generation",host.world.load_snapshot(capture.world).ok and not host._stream_checkpoint_matches(id))
	host._stream_checkpoint_capture(capture);host._stream_checkpoint.receipt=receipt
	host._world_epoch+=1
	check("native world switch invalidates protection",not host._stream_checkpoint_matches(id));host._world_epoch-=1
	var display:Array=[{"op":"extension.set","id":"r34:display","before_exists":host.world.has_extension("r34:display"),"before":host.world.extension("r34:display"),"after":{"proof-display":true}}]
	var display_draft:Dictionary=host.world.prepare_changes(display,host.world.get_revision())
	check("derived display edit commits",display_draft.ok and host.world.commit_prepared(display_draft.capability).ok)
	facts.changed.emit({"world":display})
	check("derived display change preserves exact region protection",host._stream_checkpoint_matches(id))
	var ops:Array=[{"op":"extension.set","id":"r34:proof","before_exists":false,"before":null,"after":{"proof":true}}]
	var ext:Dictionary=host.world.prepare_changes(ops,host.world.get_revision())
	check("unknown extension edit commits",ext.ok and host.world.commit_prepared(ext.capability).ok)
	check("unobserved external world write fails revision continuity",not host._stream_checkpoint_matches(id))
	facts.changed.emit({"world":ops})
	check("non-display extension invalidates entire reuse proof",host._stream_checkpoint.is_empty())
	host._stream_checkpoint_capture(capture)
	host._stream_checkpoint.receipt=receipt
	facts.changed.emit({"world":[{"op":"unknown-op"}]})
	check("unknown operation invalidates reuse proof",host._stream_checkpoint.is_empty())
	var directory:String=ProjectSettings.globalize_path(source._stream_store.root)
	check("actual complete save receipt verifies on disk",Native._verify_stream_checkpoint(receipt,directory,str(source.world.identity().worldId)).ok)
	var pointer:String=FileAccess.get_file_as_string(directory+"/active.json")
	FileAccess.open(directory+"/active.json",FileAccess.WRITE).store_string("{}")
	check("replaced active receipt refuses reuse",not Native._verify_stream_checkpoint(receipt,directory,str(source.world.identity().worldId)).ok)
	FileAccess.open(directory+"/active.json",FileAccess.WRITE).store_string(pointer)
	var replaced:String=out+"/replacement.json";FileAccess.open(replaced,FileAccess.WRITE).store_string("replaced")
	var wrong:Dictionary=receipt.duplicate(true);wrong.path=replaced
	check("replaced complete slot refuses reuse",not Native._verify_stream_checkpoint(wrong,directory,str(source.world.identity().worldId)).ok)
	host.queue_free();await process_frame
