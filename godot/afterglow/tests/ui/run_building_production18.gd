extends "res://tests/ui/run_controls15.gd"
## Historical finite checkpoint, actual walking, new building button and original craft settlement.
const RecipeActions18=preload("res://scripts/ui/building_recipe_actions.gd")
const MODULE18:="r34:generated:RH-HOME:woodwork"
var input_path18:String=""
var original18:String=""
func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	if args.size()<2:check("explicit finite checkpoint argument provided",false);return finish()
	input_path18=args[1];original18=FileAccess.get_file_as_string(input_path18)
	var decoded:Dictionary=Store.decode(original18)
	check("finite natural-opening checkpoint decodes read-only",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish()
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	host=ControlsHost.new();root.add_child(host)
	var made:Dictionary=host._assemble(decoded.capture)
	check("checkpoint assembles through actual Native owners",made.get("ok",false),made.get("reason"))
	if not made.get("ok",false):return finish()
	runtime=made.runtime;router=RealRouter.new();router.controls_path=output+"/controls.json";host.add_child(router);router.configure(runtime)
	ui=Mount.mount(host,runtime,router);await flush()
	ui.open_panel("factory_module",MODULE18);await flush()
	var module:Dictionary=F.instance(ui.factory,MODULE18)
	var definition:Dictionary=F.definition(ui.factory,str(module.get("definition_id","")))
	check("actual discovered workshop has published board recipe",RecipeActions18.choices(module,definition,ui.factory,ui.snapshot).any(func(row:Dictionary)->bool:return row.recipe.id=="r34:saw_timber_v2"))
	if module.is_empty():return finish()
	var provider:Dictionary=ui.read_service_approaches(MODULE18,true)
	var near:bool=Access.rows(provider,module).any(func(row:Dictionary)->bool:return row.get("at_service",false))
	if not near:
		var walk:Dictionary={}
		for row:Dictionary in Access.rows(provider,module):
			if not Access.access_reason(provider,row).is_empty():continue
			walk=Access.walk_command(row)
			if not walk.is_empty():break
		check("workshop offers an actual publicly proven walk",not walk.is_empty(),provider)
		if walk.is_empty():return finish()
		ui.close_panels();runtime.set_paused(false)
		walk.merge({"command_id":"production18:walk","actor_id":"player"},true)
		var walking:Dictionary=runtime.command(walk)
		check("walk is admitted by original action authority",walking.get("ok",false),walking)
		if not walking.get("ok",false):return finish()
		var max_step:float=0;var start:Vector3=G.point(G.location(runtime.actor("player")))
		for tick:int in 600:
			if runtime.actor("player").get("intent")==null:break
			var before:Vector3=G.point(G.location(runtime.actor("player")));runtime.tick(.1)
			max_step=maxf(max_step,before.distance_to(G.point(G.location(runtime.actor("player")))))
		check("actual workshop walk finishes without teleport",runtime.actor("player").get("intent")==null and max_step>0 and max_step<1 and start.distance_to(G.point(G.location(runtime.actor("player"))))>1,{"max_step":max_step})
		ui.open_panel("factory_module",MODULE18);await flush()
		provider=ui.read_service_approaches(MODULE18,true)
	check("real player has arrived within building reach",Access.rows(provider,module).any(func(row:Dictionary)->bool:return row.get("at_service",false)),provider)
	ui.factory_view["building-recipe:"+MODULE18]="craft:r34:saw_timber_v2";ui.queue_refresh();await flush()
	var recipe:Dictionary={}
	module=F.instance(ui.factory,MODULE18)
	for choice:Dictionary in RecipeActions18.choices(module,definition,ui.factory,ui.snapshot):
		if choice.recipe.id=="r34:saw_timber_v2":recipe=choice.recipe;break
	if recipe.is_empty():check("actual selected recipe remains published",false);return finish()
	var payload:Dictionary=RecipeActions18.craft_payload(ui.snapshot,recipe)
	var can_craft:Dictionary=runtime.availability(ui.request("craft",MODULE18,payload))
	check("unmodified finite materials tools knowledge permit selected craft",can_craft.get("ok",false),can_craft)
	if not can_craft.get("ok",false):return finish()
	var pack_before:Dictionary=runtime.actor("player").pack.duplicate(true)
	var tools_before:Dictionary={}
	for id:Variant in payload.tool_ids:tools_before[str(id)]=float(runtime.tool(str(id)).durability)
	var previous_ids:Array=runtime.world.extension("r3:production").orders.map(func(order:Dictionary):return order.id)
	var begin_clock:float=runtime.clock()
	if not await click_key("building:craft:"+MODULE18+":"+str(recipe.id)):return finish()
	check("actual native recipe click closes page and starts real work",ui.pages.is_empty() and runtime.actor("player").get("intent")!=null)
	check("production has not awarded output at button click",runtime.actor("player").pack.get("timber",0)==pack_before.get("timber",0))
	var settled:Dictionary={}
	for tick:int in 400:
		runtime.tick(.1)
		for order:Dictionary in runtime.world.extension("r3:production").orders:
			if not previous_ids.has(order.id) and order.kind=="craft" and order.targetId==recipe.id:settled=order
		if settled.get("status")=="completed":break
		if runtime.actor("player").get("intent")==null:break
	check("original production ledger completes clicked recipe",settled.get("status")=="completed",settled)
	check("original craft duration elapses before completion",settled.get("status")=="completed" and is_equal_approx(float(settled.get("elapsed",0)),float(settled.get("duration",0))) and runtime.clock()-begin_clock>=float(settled.get("duration",0))-.11)
	var expected:Dictionary=pack_before.duplicate(true)
	for item:String in recipe.inputs:expected[item]=float(expected.get(item,0))-float(recipe.inputs[item])
	for item:String in recipe.outputs:expected[item]=float(expected.get(item,0))+float(recipe.outputs[item])
	var resources_match:bool=true
	for item:String in expected:
		if not is_equal_approx(float(expected[item]),float(runtime.actor("player").pack.get(item,0))):resources_match=false
	check("exact original inputs consumed and output granted once",resources_match,{"before":pack_before,"expected":expected,"after":runtime.actor("player").pack})
	# UI supplies candidate tools. The original production allocator chooses
	# the required subset and records that subset on this settled order.
	var allocated:Array=settled.get("toolIds",[])
	var wear_match:bool=allocated.size()==1 and allocated.all(func(id:Variant)->bool:return tools_before.has(str(id)) and runtime.tool(str(id)).get("kind")=="hand_saw")
	var tools_after:Dictionary={}
	for id:String in tools_before:
		tools_after[id]=float(runtime.tool(id).durability)
		var expected_wear:float=float(recipe.get("toolWear",0)) if allocated.has(id) else 0.0
		if not is_equal_approx(float(tools_after[id]),float(tools_before[id])-expected_wear):wear_match=false
	check("original allocated saw pays wear while unallocated tools remain unchanged",wear_match,{"before":tools_before,"after":tools_after,"allocated":allocated,"wear":recipe.get("toolWear",0)})
	check("historical source checkpoint bytes unchanged",FileAccess.get_file_as_string(input_path18)==original18)
	observed.append({"source_checkpoint":input_path18,"recipe_id":recipe.id,"settled_order":settled,"input":recipe.inputs,"output":recipe.outputs,"tool_wear":recipe.get("toolWear",0),"scope":"Read-only finite checkpoint; real original walk, actual native Viewport recipe button, real Runtime.tick and original production ledger; no resource or position injection."})
	finish()
func finish()->void:
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	if not output.is_empty():
		var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failed":failed,"observed":observed,"scope":"Actual Native authority and real UI button from finite normal-opening checkpoint; no injected materials, position, knowledge or simulated output. Headless/source unless invocation records exact PCK; not GUI/FPS qualification."},"\t",true,true));file.close()
	if runtime!=null:runtime.retire()
	if is_instance_valid(host):host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
