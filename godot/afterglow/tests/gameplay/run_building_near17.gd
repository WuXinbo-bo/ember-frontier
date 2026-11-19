extends "res://tests/gameplay/run_interaction16.gd"
const Contact=preload("res://scripts/modules/module_contact.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Projects=preload("res://scripts/modules/module_projects.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Recipes=preload("res://scripts/production/module_recipes.gd")
const Water=preload("res://scripts/modules/module_water.gd")
func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]));check("original finite16 input decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish()
	var built:=mount(decoded.capture);check("original finite16 fully mounts",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	runtime=built.runtime
	var m:Dictionary=runtime._services.modules.instance(WAREHOUSE);var q:RefCounted=runtime._services.buildings.current_space()
	var box:=Shape.transform_box(m,G.aabb(Catalog.definition_view(str(m.definition_id)).footprint));var ports:Array=Shape.ports(m,Catalog.definition_view(str(m.definition_id)))
	var candidates:Array=Contact.points(q,G.location(runtime.actor("player")),m);var sides:Dictionary={};var selected:Array=[]
	for foot:Dictionary in candidates:
		var old:bool=ports.any(func(port:Dictionary)->bool:return G.point(foot).distance_to(G.point(port.location))<=.9)
		if old:continue
		var side:String="west" if float(foot.x)<box.position.x else "east" if float(foot.x)>box.end.x else "north" if float(foot.z)<box.position.z else "south"
		if not sides.has(side):sides[side]=true;selected.append(foot)
	check("at least two safe sides differ from old fixed ports",selected.size()>=2,{"sides":sides.keys(),"points":candidates})
	if selected.size()<2:return finish()
	var before:Dictionary=runtime.facts()
	var started:=command("module.restore",WAREHOUSE);check("original paid restore starts",started.ok,started)
	if not started.ok:return finish()
	var p:Dictionary=project();var fact_basis:Dictionary=runtime.facts()
	for side_index:int in mini(2,selected.size()):
		var probe:=Draft.new(runtime._services.modules.context);probe.staged=fact_basis.duplicate(true);probe.initial=probe.staged.duplicate(true)
		var pa:Dictionary=probe.actor("player");pa.merge(selected[side_index],true);pa.intent={"owner":"modules","project_id":p.id,"held":true}
		var issue:=Projects.labor_problem(runtime._services.modules,probe,p,m)
		check("original labor admits safe non-port side "+str(side_index),issue.is_empty(),issue)
		var far:Dictionary=pa.duplicate(true);far.x=float(box.end.x)+8
		check("far location rejected "+str(side_index),not Contact.near(q,G.location(far),m))
		var cross:Dictionary=pa.duplicate(true);cross.regionId="RH-VILLAGE"
		check("cross region rejected "+str(side_index),not Contact.near(q,G.location(cross),m))
		cross=pa.duplicate(true);cross.y=float(pa.y)+3
		check("cross floor rejected "+str(side_index),not Contact.near(q,G.location(cross),m))
		var wrong:Dictionary=p.duplicate(true);wrong.tool_id="nonexistent-hammer"
		check("nearby still requires genuine hammer "+str(side_index),Projects.labor_problem(runtime._services.modules,probe,wrong,m)=="missing_tool")
		var saved_pack:Dictionary=pa.pack.duplicate(true);pa.pack={}
		check("nearby still requires real materials "+str(side_index),Projects.labor_problem(runtime._services.modules,probe,p,m)=="missing_input");pa.pack=saved_pack
		var buffer:String=str(m.stock_refs.values()[0])
		var stock_issue:Variant=runtime._services.production.reach("player",buffer,probe.stock(buffer),"search",probe)
		check("real production buffer search reach admits same non-port side "+str(side_index),stock_issue==null,{"issue":stock_issue,"buffer":probe.stock(buffer)})
		check("unsearched buffer still refuses inventory access "+str(side_index),runtime._services.production.reach("player",buffer,probe.stock(buffer),"stock",probe)!=null)
		var blocked:Dictionary=probe.staged.duplicate(true);blocked.actors[0].merge(G.json_point(box.get_center()),true)
		check("completion retains occupied footprint rejection "+str(side_index),Projects.footprint_check(runtime._services.modules,m,blocked,str(m.id)).get("code")=="MODULE_LIVE_ACTOR_OCCUPIED")
	check("isolated geometry guards cannot alter actual authority",Data.json_equal(runtime.facts(),fact_basis))
	var actual_work:bool=tick_until_work();check("real far restore walks normally then advances paid labor",actual_work,project())
	check("real approach ends inside shared building reach",Contact.near(q,G.location(runtime.actor("player")),m))
	check("real work has not prematurely spent completion material",runtime.actor("player").pack==before.actors.filter(func(a:Dictionary)->bool:return a.id=="player")[0].pack)
	command("module.cancel",WAREHOUSE)
	var storage:String=str(m.stock_refs.values()[0]);var searched:Dictionary=command("search",storage)
	check("actual nearby buffer search starts through action authority",searched.ok,searched)
	if searched.ok:
		for step:int in 100:
			if runtime.actor("player").get("intent")==null:break
			runtime.tick(.1)
		check("actual searched buffer enables original inventory reach",runtime._services.production.reach("player",storage,runtime.stock(storage),"stock")==null and runtime.stock(storage).get("searched",false))
	# A second actual walk chooses another non-port side through original path.
	var destination:Dictionary=selected[1]
	var walk:Dictionary=runtime.command({"command_id":"near17:walk-side","kind":"walk","actor_id":"player","target_id":"","payload":{},"destination":destination})
	check("second side uses real walk command",walk.ok,walk)
	if walk.ok:
		for step:int in 400:
			if runtime.actor("player").get("intent")==null:break
			runtime.tick(.1)
		check("actual second side reaches shared nearby area",Contact.near(q,G.location(runtime.actor("player")),m))
		var restart:=command("module.restore",WAREHOUSE);check("restore starts directly at second safe side",restart.ok and runtime.actor("player").get("intent",{}).get("owner")=="modules",restart)
		if restart.ok:
			var progress:float=float(project().progress_seconds);runtime.tick(.1);check("second side sustains actual original labor",float(project().progress_seconds)>progress,project())
	var modules:Dictionary=runtime.world.extension("r34:modules")
	var craft_checked:bool=false
	for station:Dictionary in modules.instances:
		var definition:Dictionary=Catalog.definition_view(str(station.definition_id));var recipes:Array=definition.get("mechanism",{}).get("recipes",[])
		if station.status!="operational" or recipes.is_empty():continue
		var feet:Array=Contact.points(q,G.location(runtime.actor("player")),station)
		if feet.is_empty():continue
		var probe:=Draft.new(runtime._services.production.context);probe.staged=runtime.facts();probe.initial=probe.staged.duplicate(true)
		var pa:Dictionary=probe.actor("player");pa.merge(feet[0],true)
		var recipe:Dictionary=runtime._services.production.recipes.get(recipes[0],{})
		check("actual module recipe admission uses shared building reach",Recipes.problem(runtime._services.production,probe,pa,{"stationId":station.id},recipe)==null)
		craft_checked=true;break
	check("real operational recipe fixture exists",craft_checked)
	for source:Dictionary in modules.get("water",{}).get("sources",[]):
		var e:Dictionary=runtime.world.entity(str(source.id));var feet:Array=Contact.entity_points(q,G.location(runtime.actor("player")),e)
		if feet.is_empty():continue
		var probe:=Draft.new(runtime._services.modules.context);probe.staged=runtime.facts();probe.initial=probe.staged.duplicate(true)
		var pa:Dictionary=probe.actor("player");pa.merge(feet[0],true);var s:Dictionary=source.duplicate(true);s.discovered=true
		var problem:String=Water.problem(runtime._services.modules,probe,{"actor_id":"player","id":"near17:water","operation":"draw","output_id":"pack:player"},s,false)
		check("actual water admission accepts any safe source side before resource rules",problem!="operator_not_at_water",problem);break
	finish()
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"suite":"building-near17","checks":checks,"failed":failed,"scope":"Actual16 paid restoration/walk/labor plus explicitly detached side/permission/resource/collision guards. No live actor teleport or resource grant. Source headless, not PCK/GUI/FPS."},"\t",true,true))
	if runtime!=null:runtime.retire()
	print(JSON.stringify({"suite":"building-near17","checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
