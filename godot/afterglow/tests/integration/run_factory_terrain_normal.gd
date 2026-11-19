extends "res://tests/integration/run_direct_playability.gd"
## Continue actual normal53: no placed actor, granted tool, flat patch or edit fixture.
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
var output:String
var source_path:String
var source_sha:String
var observations:Dictionary={}
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=2:quit(2);return
	output=args[0];source_path=args[1];source_sha=FileAccess.get_sha256(source_path)
	DirAccess.make_dir_recursive_absolute(output);root.size=Vector2i(1280,800)
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(source_path))
	check("original normal53 Native input decodes without mutation",decoded.get("ok",false))
	if not decoded.get("ok",false):finish();return
	var client:=Client.new();var built:Dictionary=client._assemble(decoded.capture);client.free()
	check("actual Native services retain canonical normal source",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):finish();return
	runtime=built.runtime;world=built.world;building=built.services.buildings
	check("real normal content4 story1 is retained",runtime.snapshot().opening_profile=="normal" and world.extension("generation:factory-r34").content_version==4 and world.extension("generation:factory-r34").story_clue_version==1)
	var shovel:String="";var axe:String=""
	for tool:Dictionary in world.extension("r3:production").tools:
		if tool.holderId!="pack:player" or float(tool.durability)<=0:continue
		if tool.kind=="shovel":shovel=tool.id
		if tool.kind=="salvaged_axe":axe=tool.id
	check("both original legitimately collected shovel and axe exist",not shovel.is_empty() and not axe.is_empty())
	if shovel.is_empty() or axe.is_empty():finish();return
	root.add_child(scene);scene.add_child(camera);scene.add_child(ground);root.add_child(feedback)
	router.controls_path=output+"/isolated-controls.json";root.add_child(router)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=24;camera.current=true
	ground.world=world;router.configure(runtime);router.set_physics_process(false)
	root.add_child(direct);direct.configure({"runtime":runtime,"world":world,"router":router,"camera":camera,"buildings":building,"modules":built.services.modules,"terrain":ground,"ui":feedback});direct.set_process(false)
	check("real tool selection uses original tool references",router.assign_slot(0,{"kind":"tool","id":shovel}).ok and router.assign_slot(1,{"kind":"tool","id":axe}).ok and router.select_slot(0).ok)
	check("single-cell direct dig mode is accepted",router.set_terrain_brush("dig",2,0,1).ok)
	await process_frame
	var original_actor:Dictionary=runtime.actor("player")
	var chosen:Dictionary={};var attempts:Array=[]
	for dz:int in range(-4,5):
		for dx:int in range(-4,5):
			var x:float=(floori(float(original_actor.x)*2)+dx+0.5)*0.5
			var z:float=(floori(float(original_actor.z)*2)+dz+0.5)*0.5
			var y:Variant=world.surface_height(x,z)
			if y==null:continue
			aim(Vector3(x,float(y)+0.001,z))
			if direct._target.get("primary")!="terrain":continue
			var cell:Dictionary=direct._point.get("cell",{})
			if cell.is_empty() or world.cell_at(cell.x,cell.y,cell.z) not in [1,2]:continue
			if direct._target.get("enabled",false):chosen=direct._target.duplicate(true);break
			if attempts.size()<12:attempts.append(direct._target.duplicate(true))
		if not chosen.is_empty():break
	check("actual original feet can select supported visible soil without relocation",not chosen.is_empty(),attempts)
	if chosen.is_empty():finish();return
	var cell:Dictionary=chosen.cell
	var selected_payload:Dictionary=direct._terrain_payload.duplicate(true)
	check("ray cell highlight and submitted edit are identical",cell==direct._point.cell and chosen.edit==selected_payload.edit and selected_payload.edit.cells==[cell] and chosen.world_revision==world.get_revision(),chosen)
	var quantity:float=float(runtime.actor("player").pack.get("soil_m3",0))
	var wear:float=float(runtime.tool(shovel).durability)
	var before_cell:int=world.cell_at(cell.x,cell.y,cell.z)
	router.primary_requested.emit(true);ticks(1)
	var intent:Variant=runtime.actor("player").intent
	check("primary begins exact original terrain work without menu or early award",intent is Dictionary and intent.owner=="terrain" and intent.request.payload.edit==selected_payload.edit and feedback.panels.is_empty() and world.cell_at(cell.x,cell.y,cell.z)==before_cell and runtime.actor("player").pack.get("soil_m3",0)==quantity)
	if not intent is Dictionary:finish();return
	router.primary_requested.emit(false)
	var paused_elapsed:float=runtime.actor("player").intent.elapsed
	ticks(12)
	check("release retains paused work with no cell item or tool mutation",not direct._holding_primary and runtime.actor("player").intent.elapsed==paused_elapsed and world.cell_at(cell.x,cell.y,cell.z)==before_cell and runtime.actor("player").pack.get("soil_m3",0)==quantity and runtime.tool(shovel).durability==wear)
	router.primary_requested.emit(true);ticks(1);router.set_window_focus(false)
	var focus_clock:float=runtime.clock();var focus_elapsed:float=runtime.actor("player").intent.elapsed
	ticks(10)
	check("focus loss releases hold and pauses the only clock",not direct._holding_primary and not runtime.actor("player").intent.held and runtime.clock()==focus_clock and runtime.actor("player").intent.elapsed==focus_elapsed)
	router.set_window_focus(true);ticks(3)
	check("focus return does not silently resume terrain labor",runtime.actor("player").intent.elapsed==focus_elapsed and not direct._holding_primary)
	router.primary_requested.emit(true);ticks(1);router.select_slot(1)
	var switched_elapsed:float=runtime.actor("player").intent.elapsed
	ticks(5)
	check("actual axe selection releases original shovel labor",not direct._holding_primary and not runtime.actor("player").intent.held and runtime.actor("player").intent.elapsed==switched_elapsed and runtime.tool(shovel).durability==wear)
	router.select_slot(0);direct._refresh()
	router.primary_requested.emit(true)
	for i:int in 30:
		ticks(1)
		if world.cell_at(cell.x,cell.y,cell.z)==0:break
	router.primary_requested.emit(false)
	check("actual completion edits only highlighted cell and pays exact cubic volume",world.cell_at(cell.x,cell.y,cell.z)==0 and runtime.actor("player").pack.get("soil_m3",0)==quantity+0.125 and is_equal_approx(runtime.tool(shovel).durability,wear-0.1),{"cell":cell,"pack":runtime.actor("player").pack,"tool":runtime.tool(shovel)})
	check("real feet and terrain ownership are never test-repositioned",Geometry.location(original_actor)==Geometry.location(runtime.actor("player")) and runtime.actor("player").intent==null)
	var after_pack:Dictionary=runtime.actor("player").pack.duplicate(true);var after_wear:float=runtime.tool(shovel).durability
	ticks(20)
	check("release after completion cannot repeat next cell or award",runtime.actor("player").pack==after_pack and runtime.tool(shovel).durability==after_wear and feedback.panels.is_empty())
	var exported:Dictionary=Store.new().export_file(output+"/actual-normal-dig.native.json",runtime.capture_checkpoint())
	var cold:Dictionary=Store.decode(FileAccess.get_file_as_string(output+"/actual-normal-dig.native.json")) if exported.get("ok",false) else exported
	var native:=Client.new();var restored:Dictionary=native._assemble(cold.capture) if cold.get("ok",false) else cold;native.free()
	check("actual edited cell tool material and original identities cold restore",restored.get("ok",false) and Data.json_equal(cold.capture.facts,restored.runtime.facts()) and restored.world.cell_at(cell.x,cell.y,cell.z)==0 and restored.runtime.tool(shovel).durability==after_wear,restored.get("reason"))
	check("normal53 source and user controls remain untouched",FileAccess.get_sha256(source_path)==source_sha and not FileAccess.file_exists(router.controls_path))
	observations={"original_feet":Geometry.location(original_actor),"actual_target":chosen,"held_payload":selected_payload,"source_soil":quantity,"actual_soil":runtime.actor("player").pack.get("soil_m3",0),"original_shovel":shovel,"initial_durability":wear,"actual_durability":after_wear,"command_receipts":feedback.receipts}
	finish()
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"scope":"Actual content4 normal53 collected tools/untouched feet, real orthographic ray and production input signals, single cell dig and hold/focus/tool transition; no OS physical mouse, renderer VA, fill/level multi-cell or full R34-17 qualification.","checks":checks,"failed":failed,"input":{"path":source_path,"sha256":source_sha},"observations":observations},"\t",true,true))
	direct.free();router.free();feedback.free();scene.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
