extends "res://tests/buildings/domain_suite.gd"
## Real runtime and delivered rigs, finite explicit cargo/tool fixtures.
const Actors=preload("res://scripts/presentation/actor_view.gd")
const Cargo=preload("res://scripts/presentation/factory_cargo_view.gd")
const Data=preload("res://scripts/world/world_data.gd")
var view:Node3D

func set_actor(patch:Dictionary)->void:
	var facts:Dictionary=runtime.facts();facts.actors[0].merge(patch,true)
	var result:Dictionary=runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}})
	expect("finite actor fixture accepted",result.ok,result)
	view.sync(0)

func run()->void:
	expect("finite real source world loads",world.load_snapshot(Generator.generate(713)).ok)
	initialize_at({"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var state:Dictionary=Production.empty_state()
	state.tools.append({"id":"fixture:axe","kind":"salvaged_axe","holderId":"pack:player","durability":1.0,"qualities":{}})
	var draft:Dictionary=world.prepare_changes([building.extension_change(Production.KEY,state)],world.get_revision())
	expect("finite real owned tool accepted",draft.ok and world.commit_prepared(draft.capability).ok)
	view=Actors.new();root.add_child(view);view.configure(runtime);view.set_process(false)
	set_actor({"pack":{},"pending_delivery":{"phase":"deliver","items":{"log":20.0}}})
	expect("promised delivery without actual pack draws no cargo",not Actors.is_carrying(runtime.actor("player")) and not view._carried.has("player"))
	set_actor({"pack":{"log":1.0},"pending_delivery":{}})
	expect("ordinary player bulk remains packed without a holding fact",view._states.player=="Idle" and not Actors.is_carrying(runtime.actor("player")) and not view._carried.has("player"))
	set_actor({"pending_delivery":{"phase":"deliver","items":{"log":1.0}}})
	expect("actual interrupted delivery retains Carry with its real load",view._states.player=="Carry" and view._carried.player.visible and view._carried.player.get_meta("item_id")=="log")
	var load:Node3D=view._carried.player
	expect("actual log uses bark and endgrain, not generic sack",load.get_child(0) is MeshInstance3D and load.get_child(0).mesh.get_surface_count()==2 and not load.has_meta("fallback_resource"))
	var load_id:int=load.get_instance_id()
	set_actor({"pack":{"log":3.0},"pending_delivery":{"phase":"deliver","items":{"log":999.0}}})
	expect("quantity change retains load model and uses actual pack amount",view._carried.player.get_instance_id()==load_id and view._carried.player.get_meta("actual_items").log==3.0)
	for item:String in ["timber","scrap","soil_m3","r34:salvaged_drive_unit"]:
		set_actor({"pack":{item:1.0},"pending_delivery":{"phase":"deliver","items":{item:1.0}}})
		expect("actual item switches visible type "+item,view._carried.player.get_meta("item_id")==item and view._carried.player.get_instance_id()!=load_id and view._carried.player.visible)
		load_id=view._carried.player.get_instance_id()
	set_actor({"pack":{"log":1.0},"pending_delivery":{"phase":"deliver","items":{"log":1.0}},"intent":{"schema_version":1,"id":"fixture:work","owner":"actions","kind":"harvest","order_id":"fixture:order","tool_id":"fixture:axe","held":true,"elapsed":0.2,"duration":2.0,"request":{"actor_id":"player","command_id":"fixture:work","kind":"harvest","target_id":"fixture:tree","payload":{}}}})
	expect("real work shows actual owned tool and stows cargo",view._states.player=="Use" and not view._carried.player.visible and view._props.has("player") and view._props.player.get_meta("tool_id")=="fixture:axe")
	set_actor({"intent":null})
	expect("work interruption restores held real cargo and removes tool",view._states.player=="Carry" and view._carried.player.visible and not view._props.has("player"))
	set_actor({"intent":{"schema_version":1,"id":"fixture:rest","owner":"runtime","kind":"rest","held":true,"elapsed":0.0,"duration":12.0}})
	expect("rest stows load without deleting actual pack",view._states.player=="RestLying" and not view._carried.player.visible and runtime.actor("player").pack.log==1.0)
	set_actor({"intent":null,"pack":{},"pending_delivery":{}})
	expect("successful empty pack hides old load",view._states.player=="Idle" and not view._carried.player.visible)
	set_actor({"pack":{"food":2.0}})
	expect("personal small supplies do not force hands into Carry",view._states.player=="Idle" and not view._carried.player.visible)
	set_actor({"pending_delivery":{"phase":"deliver","items":{"food":8.0}}})
	expect("real small delivery uses declared existing sack",view._states.player=="Carry" and view._carried.player.has_meta("fallback_resource") and view._carried.player.get_meta("actual_items").food==2.0)
	set_actor({"pack":{"log":1.0},"pending_delivery":{},"hp":0.0})
	expect("incapacitation stows cargo while ownership remains",not view._carried.player.visible and runtime.actor("player").pack.log==1.0)
	var before:Dictionary=runtime.capture_checkpoint();view.sync(0.3)
	expect("all rendering retains authoritative pack tool clock and HP",Data.json_equal(before,runtime.capture_checkpoint()))
	expect("invalid or nonpositive pack values never become loads",Cargo.actual_items({"pack":{"log":NAN,"timber":-1,"scrap":"4"}}).is_empty())
	view.free();await process_frame
	var result:Dictionary={"scope":"real runtime/GLB with explicit finite cargo/tool fixtures; no new logistics owner fields inferred, no OS/VA","checks":checks,"failures":failures}
	var file:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("DDD_FACTORY_CARGO ",JSON.stringify({"checks":checks.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
