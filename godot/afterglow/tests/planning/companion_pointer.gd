extends "res://tests/planning/zone_pointer.gd"
## Old-village authority and viewport test. Ground quantity is seeded as a
## post-felling fixture; transport and resident movement use normal ticks.
const Draft=preload("res://scripts/actions/domain_draft.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const WORKER="village-resident"
const OTHER="repair-resident"

func receiver_control(node:Node)->OptionButton:
	if node is OptionButton and node.get_meta("ui_focus_key","")=="zone:stock:target_stock_id":return node
	for child:Node in node.get_children():
		var found:=receiver_control(child)
		if found!=null:return found
	return null

func keyed_button(node:Node,key:String)->Button:
	if node is Button and node.get_meta("ui_focus_key","")==key:return node
	for child:Node in node.get_children():
		var found:=keyed_button(child,key)
		if found!=null:return found
	return null

func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	var profiles:Dictionary=Assembly.generation_profiles()
	var opening:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.get("profiles",[])))
	check("real village prepares",opening.get("ok",false),opening.get("reason"))
	if not opening.get("ok",false):return finish()
	var capture:Dictionary=opening.capture
	var player:Dictionary=Draft.find(capture.facts.actors,"player")
	var drops:Array=capture.world.entities.values().filter(func(e:Dictionary)->bool:return e.regionId==player.regionId and e.get("data",{}).get("dropped",false) and not Draft.find(capture.facts.stocks,str(e.id)).is_empty())
	drops.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return G.point(a.position).distance_squared_to(G.point(player))<G.point(b.position).distance_squared_to(G.point(player)))
	check("real generated ground drops exist",drops.size()>2)
	if drops.size()<3:return finish()
	var drop:Dictionary=drops[0];var outside:Dictionary=drops[2]
	var source_id:=str(drop.id);var outside_id:=str(outside.id)
	Draft.find(capture.facts.stocks,source_id).items={"log":3}
	Draft.find(capture.facts.stocks,outside_id).items={"log":2}
	var dest:Dictionary=Draft.find(capture.facts.stocks,"r34:generated:RH-HOME:woodwork:stock:input")
	check("real workshop input exists",not dest.is_empty())
	if dest.is_empty():return finish()
	dest.searched=true
	var dest_id:=str(dest.id);var base:float=float(dest.items.get("log",0))
	host=TestHost.new();root.add_child(host)
	var built:Dictionary=host._assemble(capture)
	check("native authority assembles",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	var rt:RefCounted=built.runtime;var world:RefCounted=built.world
	var starts:Dictionary={WORKER:G.point(rt.actor(WORKER)),OTHER:G.point(rt.actor(OTHER))}
	var moved:Dictionary={}
	for i:int in 100:
		rt.tick(.1)
		for id:String in starts:
			if G.point(rt.actor(id)).distance_to(starts[id])>.3:moved[id]=true
		if moved.size()==2:break
	check("both companions move with no player order",moved.size()==2,[rt.actor(WORKER).activity,rt.actor(OTHER).activity])
	router=TestRouter.new();router.controls_path=output.path_join("isolated-controls.json");host.add_child(router);router.configure(rt);router.set_process(false)
	router.primary_requested.connect(func(down:bool):if down:primary_count+=1)
	ui=Mount.mount(host,rt,router);await idle();await idle()
	var portrait:=keyed_button(ui,"hud:portrait:"+WORKER)
	if portrait!=null:
		var spot:=portrait.get_global_rect().get_center()
		await send(spot,true);await send(spot,false)
	check("HUD portrait click opens the actual dispatch page",not ui.pages.is_empty() and ui.pages.back().page=="npc_quick" and keyed_button(ui,"npc:work")!=null and keyed_button(ui,"npc:building")!=null,ui.pages)
	ui.close_panels();await idle()
	var terrain:=Terrain.new();terrain.world=world;host.add_child(terrain);terrain.set_process(false)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=16;host.add_child(camera)
	var focus:Vector3=G.point(rt.actor(WORKER))+Vector3(0,.9,0)
	camera.position=focus+Vector3(1,24,1);camera.look_at(focus);camera.make_current()
	var interaction:=Interaction.new();host.add_child(interaction);interaction.set_process(false)
	interaction.configure({"runtime":rt,"world":world,"router":router,"camera":camera,"buildings":built.services.buildings,"modules":built.services.modules,"terrain":terrain,"ui":ui})
	var screen:=camera.unproject_position(focus)
	await send(screen,true);await send(screen,false)
	check("visible companion opens from exact viewport click and the world keeps running",ui.world_view_selection().get("id")==WORKER and rt.actor("player").get("intent")==null and not router.world_is_paused(),[ui.pages,rt.actor_presentation().visible_actor_ids])
	if ui.world_view_selection().get("id")!=WORKER:return finish()
	ui.start_companion_area(WORKER,"haul")
	ui.observe_companion_selection([])
	check("leaving camera view does not discard the dispatch draft",ui.is_zone_planning() and ui.zone_planning.companion_id==WORKER,ui.pages)
	focus=G.point(drop.position);camera.position=focus+Vector3(.2,24,.2);camera.look_at(focus)
	await idle()
	var size:float=world.config().cellSize
	var cell_center:=Vector3((floorf(focus.x/size)+.5)*size,focus.y,(floorf(focus.z/size)+.5)*size)
	screen=camera.unproject_position(cell_center)
	await send(screen,true);await send(screen,false);await create_timer(.12).timeout;await idle()
	check("ground pointer queues a draft without committing",ui.zone_planning.preview.get("ok",false) and world.extension("r34:zones")==null,ui.zone_planning.preview)
	var select:=receiver_control(ui)
	var index:=-1
	if select!=null:
		for i:int in select.item_count:
			if select.get_item_metadata(i)==dest_id:index=i;break
	check("discovered outside workshop appears in the actual destination selector",index>=0)
	if index<0:return finish()
	select.select(index);select.item_selected.emit(index)
	await create_timer(.12).timeout;await idle()
	var spec:Dictionary=ui.zone_planning.make_spec()
	var first:Dictionary=ui.zone_planning.submit(ui)
	check("confirm creates named worker's ground collection plan",first.get("ok",false),first.get("reason"))
	if not first.get("ok",false):return finish()
	var stop:Dictionary=rt.command({"command_id":"companion-test:stop-before","actor_id":"player","kind":"zone.cancel","target_id":ui.zone_planning.selected_id,"payload":{}})
	ui.close_panels()
	for i:int in 20:rt.tick(.1)
	check("stopping before pickup leaves all ground logs in place",stop.get("ok",false) and rt.stock(source_id).items.get("log",0)==3, stop.get("reason"))
	var second:Dictionary=rt.command({"command_id":"companion-test:second","actor_id":"player","kind":"zone.create","target_id":"companion-test:collect","payload":{"spec":spec}})
	check("cancelled collection area can be arranged again",second.get("ok",false),second.get("reason"))
	if not second.get("ok",false):return finish()
	var seen_pickup:=false
	var stopped_after_pickup:=false
	for i:int in 450:
		rt.tick(.1)
		if not seen_pickup and float(rt.actor(WORKER).pack.get("log",0))==3:
			seen_pickup=true
			stop=rt.command({"command_id":"companion-test:stop-after","actor_id":"player","kind":"zone.cancel","target_id":"companion-test:collect","payload":{}})
			stopped_after_pickup=stop.get("ok",false)
		if float(rt.stock(dest_id).items.get("log",0))==base+3:break
	var tasks:Array=world.extension("r34:logistics").get("tasks",[])
	check("designated companion physically carries the logs",seen_pickup,tasks)
	check("stopping after pickup still lets the carried batch arrive",stopped_after_pickup and rt.stock(dest_id).items.get("log",0)==base+3 and rt.actor(WORKER).pack.get("log",0)==0,stop.get("reason"))
	check("only the framed drop arrives in the selected outside stock",float(rt.stock(dest_id).items.get("log",0))==base+3 and rt.stock(source_id).items.get("log",0)==0 and rt.stock(outside_id).items.get("log",0)==2 and rt.actor(OTHER).pack.get("log",0)==0,[rt.actor(WORKER).activity,tasks])
	var encoded:Dictionary=Store.encode(rt.capture_checkpoint());var decoded:Dictionary=Store.decode(encoded.get("text",""))
	var cold:Dictionary=host._assemble(decoded.capture) if decoded.ok else decoded
	check("cold save preserves the plan and does not recreate ground stock",cold.get("ok",false) and cold.runtime.stock(source_id).items.get("log",0)==0 and cold.runtime.stock(dest_id).items.get("log",0)==base+3 and Data.json_equal(cold.world.extension("r34:zones"),world.extension("r34:zones")),cold.get("code"))
	if cold.get("ok",false):cold.runtime.retire()
	var warehouse:="r34:generated:RH-HOME:village-warehouse"
	ui.open_panel("factory_module",warehouse);await idle()
	var picker := keyed_button(ui, "fold:repair-workers:" + warehouse)
	var had_picker := picker != null
	if had_picker:
		picker.pressed.emit()
		await idle()
	var delegate:=keyed_button(ui,"building:worker:"+OTHER+":"+warehouse)
	check("opening the warehouse worker picker reveals an enabled action for the named companion",had_picker and delegate!=null and not delegate.disabled,{"pages":ui.pages,"picker":had_picker,"open":ui.factory_view.get("fold:repair-workers:"+warehouse,false),"delegate":delegate.text if delegate!=null else "missing","tooltip":delegate.tooltip_text if delegate!=null else ""})
	if delegate!=null and not delegate.disabled:
		delegate.pressed.emit();await idle()
		var orders:Variant=world.extension("r34:workforce")
		var engineering:Array=orders.assignments.filter(func(row:Dictionary)->bool:return row.get("module_id")==warehouse and row.actor_id==OTHER) if orders is Dictionary else []
		check("real building button submits a pending order for named companion",engineering.size()==1,orders)
		var hud:=keyed_button(ui,"hud:person:"+OTHER)
		check("accepting the order returns to the running village with the engineering status on the HUD",ui.pages.is_empty() and not router.world_is_paused() and hud!=null and hud.tooltip_text.contains("建筑工程"),ui.pages)
		ui.open_panel("factory_module",warehouse);await idle()
		var labels:Array[Node]=ui._body.find_children("*","Label",true,false)
		check("the original engineering order is shown when reopening the building page",engineering.size()==1 and labels.any(func(label:Node)->bool:return label.get_meta("ui_building_order","")==engineering[0].id) and keyed_button(ui,"building:worker:clear:"+warehouse)!=null,ui.pages)
	finish()
