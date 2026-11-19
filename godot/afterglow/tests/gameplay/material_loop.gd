extends "res://tests/gameplay/generated_cooperation.gd"
## Continue the saved original-NPC harvested/physically-delivered log route.
## Real player commands close log -> sawn timber -> built usable storage.

func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	output_dir=args[0];DirAccess.make_dir_recursive_absolute(output_dir)
	command_prefix="E-material:"
	evidence_kind="recorded-harvested-route-material-continuation"
	host=Client.new()
	if args.size()!=2:check("real harvested route capture explicitly supplied",false);finish();return
	var capture:Variant=JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if not capture is Dictionary or not mount(capture):finish();return
	check("original NPC physically delivered three logs before this continuation",float(runtime.stock(str(runtime.world.extension(Gameplay.KEY).layout.home_building)+":storage").items.get("log",0))==3)
	material_route()
	finish()

func material_route()->void:
	var home:String=runtime.world.extension(Gameplay.KEY).layout.home_building
	var stock:String=home+":storage"
	if not stock_at(stock):return
	if not perform("take one actually harvested and delivered log","take",stock,{"items":{"log":1}}):return
	if not approach("repair-resident"):return
	var tool_ids:Array=[];var saw:="";var hammer:=""
	for t:Dictionary in runtime.world.extension("r3:production").tools:
		if t.holderId!="pack:repair-resident":continue
		if t.kind=="hand_saw":saw=t.id;tool_ids.append(t.id)
		if t.kind=="hammer":hammer=t.id;tool_ids.append(t.id)
	check("consenting original craft resident holds actual reusable tools",not saw.is_empty() and not hammer.is_empty())
	if saw.is_empty() or hammer.is_empty():return
	if not perform("physical consensual handoff of manual and tools","take","pack:repair-resident",{"items":{"book_woodwork":1},"tool_ids":tool_ids}):return
	var records:Array=runtime.world.extension("r3:production").records.filter(func(r:Dictionary)->bool:return r.holderId=="pack:player" and r.itemId=="book_woodwork")
	check("one same physical manual follows handoff",records.size()==1,records)
	if records.size()!=1:return
	if not perform("player learns from same finite physical manual","study",records[0].id,{"record_id":records[0].id}):return
	var benches:Array=runtime.work_targets().filter(func(t:Dictionary)->bool:return t.work_payload.get("recipe_id")=="saw_timber" and runtime.world.entity(t.actual_target_id).regionId=="RH-HOME")
	check("actually built home workbench exposes timber recipe",benches.size()==1,benches)
	if benches.size()!=1:return
	var bench:String=benches[0].actual_target_id
	var points:Array=runtime._services.buildings.use_points(bench)
	if points.is_empty():check("built workbench has real use points",false);return
	if not walk(points[0],"physically reach real saw workstation"):return
	var before:Dictionary=runtime.actor("player").pack.duplicate(true)
	if not perform("saw harvested log into actual building timber","craft",bench,{"recipe_id":"saw_timber","source_id":"pack:player","output_id":"pack:player","tool_ids":[saw]}):return
	check("one log creates exactly four timber through paid recipe",float(runtime.actor("player").pack.log)==float(before.log)-1 and float(runtime.actor("player").pack.timber)==float(before.timber)+4)
	var building:RefCounted=runtime._services.buildings
	var query:RefCounted=building.current_space()
	var centre:Dictionary=Geometry.location(building.instance(bench))
	var cabinet:Dictionary={};var use:Dictionary={};var attempts:Array=[]
	for offset:Vector3 in [Vector3(0,0,3),Vector3(0,0,-3),Vector3(3,0,0),Vector3(-3,0,0),Vector3(3,0,3),Vector3(-3,0,3),Vector3(3,0,-3),Vector3(-3,0,-3)]:
		var at:=centre.duplicate(true);at.x+=offset.x;at.z+=offset.z
		var feet:Dictionary=query.standing_point(at)
		if feet.is_empty():continue
		var piece:Dictionary=building.make_instance("cabinet","E-material:real-log-cabinet",feet)
		var safe:Dictionary=building.prepare_edit([],[piece],runtime.facts())
		if not safe.ok:attempts.append(safe.get("reason"));continue
		for point:Dictionary in query.use_points(piece):
			var ready:Dictionary=query.standing_point(point)
			if ready.is_empty():continue
			cabinet=piece;use=ready;break
		if not cabinet.is_empty():break
	check("existing B placement safety finds a real supported new storage site",not cabinet.is_empty(),attempts)
	if cabinet.is_empty() or not walk(use,"physically reach validated new storage site"):return
	before=runtime.actor("player").pack.duplicate(true)
	if not perform("construct storage from real sawn timber and carried scrap","structure",cabinet.id,{"kind":"place","instance":cabinet,"source_id":"pack:player","output_id":"pack:player","tool_id":hammer}):return
	check("actual new storage costs exactly three timber and one scrap",float(runtime.actor("player").pack.timber)==float(before.timber)-3 and float(runtime.actor("player").pack.scrap)==float(before.scrap)-1 and not runtime.world.entity(cabinet.id).is_empty())
	var actual:Dictionary=runtime.stock(cabinet.id)
	check("newly built storage is real empty finite stock",not actual.is_empty() and actual.items.is_empty(),actual)
	if not perform("use newly built stock through canonical inventory transfer","deposit",cabinet.id,{"items":{"timber":1}}):return
	check("built storage contains only explicitly deposited timber",runtime.stock(cabinet.id).items=={"timber":1.0} and float(runtime.stock(stock).items.log)==2)
	roundtrip("actual harvested-log crafting and storage construction")
