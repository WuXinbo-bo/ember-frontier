extends "res://tests/buildings/domain_suite.gd"
## Explicit finite body/tool/delivery fixtures over real24 runtime and rigs.
## No commands are issued by the display. Not normal travel or OS/VA evidence.
const Actors = preload("res://scripts/presentation/actor_view.gd")
const Cargo = preload("res://scripts/presentation/factory_cargo_view.gd")
const Data = preload("res://scripts/world/world_data.gd")
var view: Node3D
var observations: Array = []
var output := ""
const KINDS = ["salvaged_axe","shovel","pickaxe","hammer","hand_saw"]

func patch_actor(id: String, values: Dictionary) -> void:
	var facts: Dictionary = runtime.facts()
	for actor: Dictionary in facts.actors:
		if actor.id == id: actor.merge(values,true)
	var receipt: Dictionary = runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}})
	expect("explicit fixture accepted " + id,receipt.ok)

func sync_views() -> void:
	var before: Dictionary = runtime.capture_checkpoint()
	view.sync(0)
	expect("presentation preserves full authority",Data.json_equal(before,runtime.capture_checkpoint()))

func held(kind: String) -> bool:
	return view._props.has("player") and view._props.player.get_meta("tool_kind","") == kind

func load_visible(id: String) -> bool:
	return is_instance_valid(view._carried.get(id)) and view._carried[id].visible

func npc_same(id: String) -> bool:
	var load: Node3D = view._carried.get(id)
	return load != null and load.visible and view._states[id] == "Carry" and Data.json_equal(load.get_meta("actual_items"),Cargo.actual_items(runtime.actor(id)))

func run() -> void:
	output = OS.get_cmdline_user_args()[0]; DirAccess.make_dir_recursive_absolute(output)
	expect("original24 legacy world fixture loads",world.load_snapshot(Generator.generate(713)).ok)
	var at := {"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	initialize_at(at,[resident("village-resident",at.merged({"x":31},true)),resident("repair-resident",at.merged({"x":32},true))])
	var tools: Dictionary = Production.empty_state(); var slots: Array = []
	for kind: String in KINDS:
		var id := "fixture:" + kind
		tools.tools.append({"id":id,"kind":kind,"holderId":"pack:player","durability":1.0,"qualities":{}})
		slots.append({"kind":"tool","id":id})
	tools.tools.append({"id":"fixture:broken","kind":"hammer","holderId":"pack:player","durability":0.0,"qualities":{}})
	tools.tools.append({"id":"fixture:foreign","kind":"hammer","holderId":"pack:village-resident","durability":1.0,"qualities":{}})
	var draft: Dictionary = world.prepare_changes([building.extension_change(Production.KEY,tools)],world.get_revision())
	expect("finite exact owned tools accepted",draft.ok and world.commit_prepared(draft.capability).ok)
	patch_actor("player",{"pack":{"soil_m3":2.0,"timber":12.0,"scrap":8.0,"cloth":4.0},"pending_delivery":{}})
	runtime.set_hand({"slots":slots,"selected":0})
	view = Actors.new(); root.add_child(view); view.configure(runtime); view.set_process(false)
	for index: int in KINDS.size():
		runtime.set_hand({"slots":slots,"selected":index}); sync_views()
		expect("all personal bulk remains packed and selected tool shows " + KINDS[index],view._states.player == "Idle" and not load_visible("player") and held(KINDS[index]))
		observations.append({"kind":KINDS[index],"state":view._states.player,"tool_id":view._held_ids.player,"pack":runtime.actor("player").pack})
	for item: String in Cargo.BULK:
		patch_actor("player",{"pack":{item:2.0},"pending_delivery":{}}); sync_views()
		expect("ordinary player bulk does not mean two-hand holding " + item,not load_visible("player") and held("hand_saw") and view._states.player == "Idle")
	runtime.set_hand({"slots":[],"selected":0}); sync_views()
	expect("ordinary bulk without selected tool leaves neutral empty hands",not load_visible("player") and not view._props.has("player") and view._states.player == "Idle")
	for id: String in ["fixture:broken","fixture:foreign","missing"]:
		runtime.set_hand({"slots":[{"kind":"tool","id":id}],"selected":0}); sync_views()
		expect("ownership and durability still reject invalid tool " + id,not view._props.has("player") and not load_visible("player"))
	runtime.set_hand({"slots":slots,"selected":0})
	patch_actor("player",{"pack":{"soil_m3":2.0,"food":2.0},"pending_delivery":{"phase":"collect","items":{"food":1.0}}}); sync_views()
	expect("not-yet-collected delivery does not turn unrelated pack into Carry",held("salvaged_axe") and not load_visible("player"))
	patch_actor("player",{"pending_delivery":{"phase":"deliver","items":{"food":1.0}},"intent":null}); sync_views()
	expect("real small delivery carries its actual food not unrelated soil",view._states.player == "Carry" and load_visible("player") and not view._props.has("player") and view._carried.player.get_meta("item_id") == "food" and view._carried.player.get_meta("actual_items") == {"food":2.0})
	patch_actor("player",{"intent":null}); sync_views()
	expect("stopped real delivery remains held while pending and actual goods remain",view._states.player == "Carry" and load_visible("player"))
	patch_actor("player",{"pack":{"soil_m3":2.0},"pending_delivery":{"phase":"deliver","items":{"food":100.0}}}); sync_views()
	expect("promised absent food cannot hold unrelated soil or hide selected tool",not load_visible("player") and held("salvaged_axe"))
	patch_actor("player",{"pack":{"soil_m3":2.0,"log":1.0},"pending_delivery":{"phase":"deliver","items":{"log":1.0}},"intent":{"schema_version":1,"id":"fixture:work","owner":"actions","kind":"harvest","order_id":"fixture:order","tool_id":"fixture:salvaged_axe","held":true,"elapsed":0.2,"duration":2.0,"request":{"actor_id":"player","command_id":"fixture:work","kind":"harvest","target_id":"fixture:tree","payload":{}}}}); sync_views()
	expect("accepted work-intent fixture retains existing Use and owned labor tool override",view._states.player == "Use" and held("salvaged_axe") and not load_visible("player"))
	patch_actor("player",{"intent":null}); sync_views()
	expect("work interrupted with genuine pending load resumes existing Carry",view._states.player == "Carry" and load_visible("player") and not view._props.has("player"))
	patch_actor("player",{"pending_delivery":{},"intent":null}); sync_views()
	expect("ordinary pack after work interruption immediately restores selected tool",view._states.player == "Idle" and held("salvaged_axe") and not load_visible("player"))
	for id: String in ["village-resident","repair-resident"]:
		for item: String in Cargo.BULK:
			patch_actor(id,{"pack":{item:1.0},"pending_delivery":{},"intent":null}); sync_views()
			expect("original NPC interrupted bulk presentation unchanged " + id + " " + item,npc_same(id) and load_visible(id))
		patch_actor(id,{"pack":{"food":2.0},"pending_delivery":{"phase":"deliver","items":{"food":4.0}}}); sync_views()
		expect("original NPC small actual cargo unchanged " + id,npc_same(id) and load_visible(id))
	patch_actor("player",{"hp":0.0}); sync_views()
	expect("incapacitation still hides owned tool and load",not load_visible("player") and not view._props.has("player") and view._states.player == "RestLying")
	var invalid := {"id":"player","pack":{"soil_m3":NAN,"timber":-1.0,"food":"4"},"pending_delivery":{"phase":"deliver","items":{"soil_m3":1.0,"timber":1.0,"food":1.0}}}
	expect("invalid and nonpositive items cannot become hand cargo",Cargo.hand_items(invalid).is_empty())
	view.free(); await process_frame
	var file := FileAccess.open(output.path_join("results.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope":"current presentation over real runtime and rigs; explicit finite body/tool/delivery fixtures, no real route or settlement, OS or VA qualification","checks":checks,"failures":failures,"observations":observations},"\t")+"\n"); file.close()
	print("DDD_PLAYER_HANDS ",JSON.stringify({"checks":checks.size(),"failed":failures.size()})); quit(0 if failures.is_empty() else 1)
