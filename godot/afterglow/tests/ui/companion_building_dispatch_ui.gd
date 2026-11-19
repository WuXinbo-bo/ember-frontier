extends "res://tests/planning/zone_pointer.gd"

const Draft=preload("res://scripts/actions/domain_draft.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const F=preload("res://scripts/ui/factory_projection.gd")
const WORKER="village-resident"
const WAREHOUSE="r34:generated:RH-HOME:village-warehouse"

func button(key:String)->Button:
	for node:Node in ui.find_children("*","Button",true,false):
		if node.get_meta("ui_focus_key","")==key:return node as Button
	return null

func press(key:String)->bool:
	var control:=button(key)
	if control==null or control.disabled or not control.is_visible_in_tree():return false
	control.pressed.emit()
	await idle()
	return true

func aim(camera:Camera3D,point:Vector3)->Vector2:
	camera.position=point+Vector3(.2,24,.2)
	camera.look_at(point)
	return camera.unproject_position(point)

func tap_key(code:int)->void:
	for down:bool in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=down
		root.push_input(event,true);await idle()

func fixture(capture:Dictionary)->void:
	# Isolate placement on the same clear, supported terrain as the blueprint supply suite.
	for key:String in capture.world.chunks:
		var c:Vector3i=Data.coord(key)
		if c.x not in [3,4,5,6] or c.z not in [3,4,5,6]:continue
		var cells:PackedInt32Array=capture.world.chunks[key].cells.duplicate()
		for y:int in 16:
			for z:int in 16:
				for x:int in 16:cells[x+16*(z+16*y)]=2 if c.y*16+y<0 else 0
		capture.world.chunks[key].cells=cells
	for id:String in capture.world.entities.keys():
		if G.aabb(capture.world.entities[id].bounds).intersects(AABB(Vector3(24,-1,24),Vector3(32,20,32))):capture.world.entities.erase(id)
	for id:String in ["player",WORKER]:
		var actor:Dictionary=Draft.find(capture.facts.actors,id)
		actor.x=33 if id=="player" else 35;actor.y=0;actor.z=51;actor.intent=null

func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	var profiles:Dictionary=Assembly.generation_profiles()
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.get("profiles",[])))
	check("seeded village prepares",prepared.get("ok",false),prepared.get("reason"))
	if not prepared.get("ok",false):return finish()
	fixture(prepared.capture)
	host=TestHost.new();root.add_child(host)
	var built:Dictionary=host._assemble(prepared.capture)
	check("real owner domains assemble",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	var rt:RefCounted=built.runtime;var world:RefCounted=built.world
	router=TestRouter.new();router.controls_path=output.path_join("isolated-controls.json")
	host.add_child(router);router.configure(rt);router.set_process(false)
	ui=Mount.mount(host,rt,router);await idle();await idle()
	var terrain:=Terrain.new();terrain.world=world;host.add_child(terrain);terrain.set_process(false)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=16;host.add_child(camera)
	var warehouse:Dictionary=world.entity(WAREHOUSE)
	check("generated warehouse provides a real pick target",not warehouse.is_empty())
	if warehouse.is_empty():return finish()
	var screen:=aim(camera,G.aabb(warehouse.bounds).get_center());camera.make_current()
	var interaction:=Interaction.new();host.add_child(interaction);interaction.set_process(false)
	interaction.configure({"runtime":rt,"world":world,"router":router,"camera":camera,"buildings":built.services.buildings,"modules":built.services.modules,"terrain":terrain,"ui":ui})
	for pressed:bool in [true,false]:
		var right:=InputEventMouseButton.new()
		right.position=screen
		right.global_position=screen
		right.button_index=MOUSE_BUTTON_RIGHT
		right.pressed=pressed
		right.button_mask=MOUSE_BUTTON_MASK_RIGHT if pressed else 0
		root.push_input(right,true)
		await idle()
	check("right click opens the use page of the physical warehouse",not ui.pages.is_empty() and ui.pages.back().page=="factory_module" and ui.pages.back().subject==WAREHOUSE and button("building:worker:auto:"+WAREHOUSE)!=null,ui.pages)
	var self_restore := button("factory:command:module.restore:"+WAREHOUSE)
	var queue_restore := button("building:worker:auto:"+WAREHOUSE)
	check("ruined warehouse exposes both main restoration actions",self_restore!=null and self_restore.text=="亲自修缮" and queue_restore!=null and queue_restore.text=="安排修缮")
	check("normal building button queues the village order",await press("building:worker:auto:"+WAREHOUSE) and world.extension("r34:workforce").get("building_queue",[]).has(WAREHOUSE))
	ui.open_panel("factory_module",WAREHOUSE)
	await idle()
	check("player can cancel a queued order from the same building",await press("building:worker:cancel:"+WAREHOUSE) and not world.extension("r34:workforce").get("building_queue",[]).has(WAREHOUSE))
	ui.close_panels()
	await idle()
	await send(screen,true);await send(screen,false)
	check("left click selects the physical warehouse without opening or starting work",ui.pages.is_empty() and ui.world_view_selection().get("id")==WAREHOUSE and rt.actor("player").intent==null)
	await tap_key(KEY_E)
	check("E opens the same physical warehouse",not ui.pages.is_empty() and ui.pages.back().page=="factory_module" and ui.pages.back().subject==WAREHOUSE,ui.pages)
	await tap_key(KEY_E)
	check("E closes the open interaction panel",ui.pages.is_empty(),ui.pages)
	await send(screen,true);await send(screen,false)
	await tap_key(KEY_ESCAPE)
	check("first Escape clears selection without opening pause",ui.pages.is_empty() and ui.world_view_selection().is_empty(),ui.pages)
	await tap_key(KEY_ESCAPE)
	check("next Escape reaches real pause",not ui.pages.is_empty() and ui.pages.back().page=="pause" and router.world_is_paused(),ui.pages)
	ui.close_panels();await idle()
	check("village stock opens separately from personal inventory",await press("hud:factory_stock") and ui.pages.back().page=="factory_stock" and ui._title.text=="村庄库存",ui.pages)
	check("village stock does not expose personal or physical transfer controls",not ui._modal_hotbar.visible and button("factory:inventory:take-all")==null)
	ui.close_panels();await idle()
	await tap_key(KEY_TAB)
	check("Tab still opens the personal pack",not ui.pages.is_empty() and ui.pages.back().page=="factory_inventory" and str(ui.pages.back().subject).is_empty() and ui._title.text=="随身背包",ui.pages)
	ui.close_panels();await idle()
	ui.open_panel("factory_catalog");await idle()
	var presets: Array[String] = []
	for candidate: Node in ui._body.find_children("*", "Button", true, false):
		var key := str(candidate.get_meta("ui_focus_key", ""))
		if key.begins_with("factory:preset:"): presets.append(key.trim_prefix("factory:preset:"))
	var buildable_ids: Array = F.build_definitions(ui.factory).map(func(definition: Dictionary) -> String: return str(definition.id))
	check("quick presets select current owner choices",not presets.is_empty() and presets.all(func(id: String) -> bool: return buildable_ids.has(id)),presets)
	if presets.is_empty():return finish()
	check("quick preset enters the same placement preview",await press("factory:preset:"+presets[0]) and router.state().mode=="module_place" and router.state().module_definition_id==presets[0],router.state())
	await tap_key(KEY_ESCAPE)
	ui.close_panels();await idle()
	ui.open_panel("factory_catalog");await idle()
	var pack_before: Dictionary = rt.actor("player").pack.duplicate(true)
	var has_wall := await press("factory:wall:preview")
	check("normal catalogue opens the original structure preview for a whole wall",has_wall and router.is_placement() and router.held_reference().get("id")=="wall")
	if has_wall:
		var wall_screen := aim(camera, Vector3(33, 0, 49))
		await send(wall_screen,true);await send(wall_screen,false)
		var wall_plan: Dictionary = interaction._preview.get("instance", {})
		var full_wall: bool = not wall_plan.is_empty() and built.services.buildings.geometry.definition(wall_plan).get("id")=="wall" and is_equal_approx(built.services.buildings.geometry.bounds(wall_plan).size.x,2.0)
		check("fixing the wall previews its full two-metre segment without spending material",full_wall and interaction._placement_locked() and Data.json_equal(rt.actor("player").pack,pack_before),wall_plan)
		await tap_key(KEY_ESCAPE)
		await tap_key(KEY_ESCAPE)
	check("actual companion portrait opens dispatch",await press("hud:portrait:"+WORKER) and ui.world_view_selection().get("id")==WORKER,ui.pages)
	check("companion can start building pick",await press("npc:building") and await press("npc:building:pick") and ui.is_companion_building_pick() and not router.world_is_paused())
	screen=aim(camera,G.aabb(warehouse.bounds).get_center())
	await send(screen,true);await send(screen,false)
	check("physical building ray retains the selected worker",ui.world_view_selection().get("id")==WAREHOUSE and ui.building_dispatch_actor()==WORKER and button("building:worker:"+WORKER+":"+WAREHOUSE)!=null,ui.pages)
	ui.close_panels();await idle()
	await press("hud:portrait:"+WORKER)
	if button("npc:home:blueprint")==null:await press("npc:building")
	check("companion opens the themed housing catalogue",await press("npc:home:blueprint") and ui.building_dispatch_actor()==WORKER,ui.pages)
	var choices:Array=[]
	for item:Node in ui._body.find_children("*","Button",true,false):
		var key:String=str(item.get_meta("ui_focus_key",""))
		if key.begins_with("factory:preview:"):choices.append(key.trim_prefix("factory:preview:"))
	var buildable_homes:Array=F.build_definitions(ui.factory).filter(func(definition:Dictionary)->bool:return definition.get("shape")=="home").map(func(definition:Dictionary)->String:return str(definition.id))
	check("only the current opening's buildable housing can be selected",not choices.is_empty() and choices==buildable_homes,choices)
	if choices.is_empty() or choices!=buildable_homes:return finish()
	var home_id:String=choices[0]
	var place_key:="factory:preview:"+home_id
	check("housing CTA retains the worker in actual placement",await press(place_key) and router.state().mode=="module_place" and router.state().module_worker_id==WORKER,router.state())
	await tap_key(KEY_ESCAPE)
	check("Escape cancels placement and clears the worker from the router",router.state().mode=="tool" and router.state().module_worker_id=="",router.state())
	await press(place_key)
	ui.open_panel("factory_inventory");await idle()
	check("switching panels cannot leave an accidental placement behind",router.state().mode=="tool" and router.state().module_worker_id=="",router.state())
	ui.cancel_ui();await idle()
	if not await press(place_key):check("placement can resume from the housing page",false,ui.pages);return finish()
	screen=aim(camera,Vector3(40,0,40));await idle()
	var before:Dictionary=rt.actor("player")
	await send(screen,true);await send(screen,false)
	await tap_key(KEY_ENTER)
	var state:Variant=world.extension("r34:workforce")
	var assigned:Dictionary=F.find(state.get("assignments",[]),WORKER,"actor_id") if state is Dictionary else {}
	var planned:Dictionary=built.services.modules.instance(str(assigned.get("module_id","")))
	check("left click and Enter create an unpaid blueprint assigned to the named companion",planned.get("status")=="planned" and planned.get("definition_id")==home_id and assigned.get("candidate_id")=="building-order:"+str(planned.get("id","")) and Data.json_equal(before.pack,rt.actor("player").pack) and rt.actor("player").intent==null and ui.pages.is_empty(),[assigned,planned,ui.pages])
	var cleared:Dictionary=rt.command({"kind":"workforce.clear","actor_id":WORKER,"command_id":"ui-test:clear-blueprint-order","target_id":"","payload":{}})
	var damage:=Draft.new(built.services.modules.context)
	var shed:Dictionary=built.services.modules.instance(WAREHOUSE)
	var destroyed:Dictionary=built.services.modules.damage_in(damage,WAREHOUSE,shed.hp,"ui-test:destroy-shed")
	if not destroyed.ok or not rt._commit(damage.result()).ok or not cleared.ok:
		check("warehouse damage and blueprint release prepare the rebuild UI fixture",false,[destroyed,cleared])
		return finish()
	ui.open_panel("factory_module",WAREHOUSE);await idle()
	var self_rebuild:=button("factory:command:module.repair:"+WAREHOUSE)
	var queue_rebuild:=button("building:worker:auto:"+WAREHOUSE)
	check("destroyed warehouse offers personal rebuild and village dispatch",self_rebuild!=null and self_rebuild.text=="亲自原地重建" and queue_rebuild!=null and queue_rebuild.text=="安排原地重建")
	var rebuild_queued:bool=await press("building:worker:auto:"+WAREHOUSE) and world.extension("r34:workforce").get("building_queue",[]).has(WAREHOUSE)
	ui.open_panel("factory_module",WAREHOUSE);await idle()
	check("rebuild can be queued and withdrawn from the building",rebuild_queued and await press("building:worker:cancel:"+WAREHOUSE) and not world.extension("r34:workforce").get("building_queue",[]).has(WAREHOUSE))
	ui.open_panel("factory_module",WAREHOUSE,WORKER);await idle()
	var stock_before:Dictionary=rt.actor(WORKER).pack
	var rebuild_assigned:=await press("building:worker:"+WORKER+":"+WAREHOUSE)
	var rebuild_order:=F.find(world.extension("r34:workforce").get("assignments",[]),WORKER,"actor_id")
	var still_ruined:Dictionary=built.services.modules.instance(WAREHOUSE)
	check("named companion accepts rebuild without spending materials remotely",rebuild_assigned and rebuild_order.get("candidate_id")=="building-order:"+WAREHOUSE and still_ruined.get("status")=="ruined" and Data.json_equal(stock_before,rt.actor(WORKER).pack),rebuild_order)
	finish()
