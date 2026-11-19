extends "res://tests/ui/run_controls15.gd"
## Current Native owners and real page consumers. Microtimings are CPU-only,
## not PCK/renderer/FPS or acceptance of the whole starting economy.
const KnownMap = preload("res://scripts/ui/factory_map.gd")
const Catalog = preload("res://scripts/ui/factory_catalog.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	host=ControlsHost.new();root.add_child(host)
	var profiles:Dictionary=Assembly.generation_profiles()
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles))
	check("current generated normal village prepares",prepared.get("ok",false),prepared.get("reason"))
	if not prepared.get("ok",false):return finish()
	prepared.capture=Opening.prepare_opening(prepared.capture,"normal")
	var made:Dictionary=host._assemble(prepared.capture)
	check("same Native authority assembles",made.get("ok",false),made.get("reason"))
	if not made.get("ok",false):return finish()
	runtime=made.runtime;router=RealRouter.new();router.controls_path=output+"/controls.json"
	host.add_child(router);router.configure(runtime,false,true)
	ui=Mount.mount(host,runtime,router);await flush()
	runtime.tick(0.1);ui.refresh();await flush()
	var checkpoint:Dictionary=runtime.capture_checkpoint()
	var baseline:Dictionary=runtime.factory_ui_snapshot()
	ui.open_panel("factory_catalog");await flush()
	var definitions:Array=F.build_definitions(ui.factory)
	var expected:Array=definitions.map(func(row:Dictionary):return str(row.id));expected.sort()
	var seen:Array=[];var totals:Array=[]
	for page_index:int in ceili(float(definitions.size())/Catalog.PAGE_SIZE):
		var cards:Array=[]
		for node:Node in ui._body.find_children("*","VBoxContainer",true,false):
			if node.has_meta("ui_catalog_definition"):cards.append(node)
		check("bounded actual native catalog cards page "+str(page_index),not cards.is_empty() and cards.size()<=Catalog.PAGE_SIZE,cards.size())
		totals.append(cards.size())
		for card:Node in cards:seen.append(str(card.get_meta("ui_catalog_definition")))
		if page_index+1<ceili(float(definitions.size())/Catalog.PAGE_SIZE):await click_key("factory:catalog:next")
	seen.sort()
	check("pagination exposes every owner definition once",seen==expected,{"seen":seen.size(),"expected":expected.size()})
	check("catalog receives only its requested factory detail",ui.factory.get("details_state")=="page:factory_catalog" and F.rows(ui.factory,"production","orders").is_empty() and F.rows(ui.factory,"workforce","members").is_empty())
	check("movable cabinet remains genuinely defined",not ui.snapshot.get("catalog",{}).get("buildings",[]).is_empty())
	var serial:int=ui._panel_render_serial
	ui.refresh();await flush();serial=ui._panel_render_serial
	ui.snapshot.actors[0].stamina=float(ui.snapshot.actors[0].get("stamina",100))-0.1
	check("catalog visible signature ignores unrelated actor needs",ui._visible_panel_signature()==ui._panel_signature)
	for page:String in ["factory","factory_inventory","factory_production","factory_logistics","factory_people","factory_alerts","factory_handbook","pause","settings"]:
		ui.close_panels();ui.open_panel(page);await flush()
		check("real demand page renders "+page,not text_in(ui._body).is_empty() and ui.factory.get("details_state")=="page:"+page,{"title":ui._title.text,"details":ui.factory.get("details_state")})
		for domain:String in ["modules","production","logistics","workforce"]:check("navigation capability matches original owner "+page+" "+domain,ui.factory[domain].available==baseline[domain].available,{"page":ui.factory[domain].available,"original":baseline[domain].available})
	ui.close_panels();ui.open_panel("map");await flush()
	var data:Dictionary=ui.factory.get("map",{})
	var map:=keyed("factory:map:canvas") as KnownMap
	check("map is actual 2D Control with known terrain",map!=null and not map.cartography.get("cells",[]).is_empty() and map._terrain_texture!=null,{"map":data,"region":map.region_id if map!=null else "none"})
	if map!=null:
		var repeat:=KnownMap.new();repeat.configure(data,{},map.region_id,1)
		check("same surveyed geography reuses cached raster",repeat.terrain_cache_hit)
		var changed:Dictionary=data.duplicate(true)
		for marker:Dictionary in changed.get("markers",[]):
			if marker.get("kind")=="player":marker.location.x=float(marker.location.x)+0.25
		var texture:Texture2D=map._terrain_texture
		map.update_markers(changed)
		check("live public marker movement retains base raster",map._terrain_texture==texture and map.markers!=repeat.markers)
		check("map has no secondary 3D render viewport",map.find_children("*","SubViewport",true,false).is_empty() and map.find_children("*","Camera3D",true,false).is_empty())
		repeat.free()
	var module_id:="r34:generated:RH-HOME:woodwork"
	ui.close_panels();ui.open_panel("factory_module",module_id);await flush()
	var module:Dictionary=F.instance(ui.factory,module_id)
	var station_id:=""
	for member:Dictionary in module.get("members",[]):
		if str(member.get("kind","")).contains("workbench") or str(member.get("id","")).contains("workbench"):station_id=str(member.id);break
	if station_id.is_empty():
		for target:Dictionary in runtime.work_targets():
			if str(target.get("kind",""))=="workbench":station_id=str(target.id);break
	check("real owner publishes a starting workbench",not station_id.is_empty(),module.get("members",[]))
	if not station_id.is_empty():
		ui.open_panel("workbench",station_id);await flush()
		var modern:=0;var legacy:=0
		for button:Node in ui._body.find_children("*","Button",true,false):
			var key:String=str(button.get_meta("ui_focus_key",""))
			if key.begins_with("craft:"+module_id+":"):modern+=1
			if key.begins_with("craft:"+station_id+":"):legacy+=1
		check("modern recipes use the owning module and legacy keeps station",modern>0 and legacy>0,{"modern":modern,"legacy":legacy,"station":station_id})
		var handle:Dictionary={}
		for row:Dictionary in P.records(ui.snapshot.get("catalog",{}).get("recipes",ui.snapshot.get("catalog",{}).get("production_recipes",[]))):
			if row.get("id")=="make_handle":handle=row;break
		check("workbench keeps actual legacy handle recipe",not handle.is_empty() and text_in(ui._body).contains(str(handle.get("name","make_handle"))),handle)
	check("reading and rendering all pages preserves authority",Data.json_equal(checkpoint,runtime.capture_checkpoint()))
	observed.append({"catalog_definitions":definitions.size(),"cards_per_page":totals,"source_scope":"real Native/display owners; headless UI and CPU only"})
	finish()
