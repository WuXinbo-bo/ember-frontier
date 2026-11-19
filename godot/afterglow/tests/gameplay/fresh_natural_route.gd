extends "res://tests/gameplay/rural_completion.gd"
## One continuous fresh finite opening. No input capture or Playtest grants.
## Production resolves exclusively from the explicitly selected candidate PCK.
var opening_totals:Dictionary={}
var phases:Array=[]

func phase(label:String)->void:
	var capture:Dictionary=runtime.capture_checkpoint()
	var file:String="fresh-"+label+"-capture.json"
	write_json(file,capture)
	phases.append({"phase":label,"path":output_dir+"/"+file,"clock":runtime.clock(),"player":runtime.actor("player"),"totals":totals(),"layout":game().layout})
	write_json("fresh-route-evidence.json",{"scope":evidence_kind,"seed":713,"historical_capture_input":false,"playtest_supplies_applied":false,"opening_totals":opening_totals,"phases":phases,"commands":route_steps})

func has_failure()->bool:return checks.any(func(c:Dictionary)->bool:return not c.ok)

func run()->void:
	output_dir=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output_dir)
	command_prefix="E-fresh-natural:"+output_dir.get_base_dir().get_file()+":"
	evidence_kind="actual-PCK-fresh713-base-three-original-actors-finite-opening-no-playtest-grants-no-historical-input"
	host=Client.new()
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,Building.generation_profiles()))
	check("fresh current PCK generated finite world prepares",prepared.ok,prepared.get("reason"))
	if not prepared.ok or not mount(prepared.capture):finish();return
	check("fresh route starts at clock zero original three people and original one food one water",runtime.clock()==0 and runtime.facts().actors.size()==3 and runtime.actor("player").pack=={"food":1,"water":1})
	check("no extra ready-to-test items or duplicate tools applied",prepared.capture.source.get("playtest",{}).is_empty() and runtime.world.extension("r3:production").tools.all(func(t:Dictionary)->bool:return not str(t.id).begins_with("playtest:")))
	opening_totals=totals()
	for t:Dictionary in runtime.world.extension("r3:production").tools:original_tool_ids.append(str(t.id))
	original_tool_ids.sort();phase("opening")
	cooperation_route()
	if has_failure():phase("blocked-cooperation");finish();return
	check("fresh same continuous world physically harvested three finite logs",float(runtime.stock(str(game().layout.home_building)+":storage").items.get("log",0))==3)
	phase("cooperative-harvest")
	fresh_material_route()
	if has_failure():phase("blocked-material");finish();return
	check("fresh harvested timber became actual built stocked cabinet",not runtime.stock("E-material:real-log-cabinet").is_empty() and runtime.stock("E-material:real-log-cabinet").items=={"timber":1.0})
	phase("material-storage")
	# The inherited RH audit deliberately starts its cost ledger here; the
	# opening-to-this-point ledger above remains separate and fully preserved.
	original_totals=totals()
	if not equip():phase("blocked-preparation");finish();return
	phase("legal-expedition-inputs")
	if not expedition():phase("blocked-exploration");finish();return
	phase("exploration")
	if not defend():phase("blocked-defense");finish();return
	phase("defense")
	# Fresh travel/combat has a real stamina cost absent from a short retained
	# material continuation. Pay canonical recovery before the 20s+30s radio.
	if not perform("actual post-combat recovery before radio labor","rest"):phase("blocked-radio-rest");finish();return
	phase("radio-rested")
	if not communicate():phase("blocked-radio");finish();return
	phase("radio")
	if not home_goals():phase("blocked-home-goals");finish();return
	audit();phase("complete")
	finish()

func fresh_material_route()->void:
	var home:String=runtime.world.extension(Gameplay.KEY).layout.home_building
	var stock:String=home+":storage"
	if not stock_at(stock):return
	if not perform("take one actually harvested and delivered log","take",stock,{"items":{"log":1}}):return
	if not approach("repair-resident"):return
	var tool_ids:Array=[];var material_saw:="";var material_hammer:=""
	for t:Dictionary in runtime.world.extension("r3:production").tools:
		if t.holderId!="pack:repair-resident":continue
		if t.kind=="hand_saw":material_saw=t.id;tool_ids.append(t.id)
		if t.kind=="hammer":material_hammer=t.id;tool_ids.append(t.id)
	check("consenting original craft resident holds actual reusable tools",not material_saw.is_empty() and not material_hammer.is_empty())
	if material_saw.is_empty() or material_hammer.is_empty():return
	if not perform("physical consensual handoff of manual and tools","take","pack:repair-resident",{"items":{"book_woodwork":1},"tool_ids":tool_ids}):return
	var records:Array=runtime.world.extension("r3:production").records.filter(func(r:Dictionary)->bool:return r.holderId=="pack:player" and r.itemId=="book_woodwork")
	check("one same physical manual follows handoff",records.size()==1,records)
	if records.size()!=1 or not perform("player learns from same finite physical manual","study",records[0].id,{"record_id":records[0].id}):return
	var benches:Array=runtime.work_targets().filter(func(t:Dictionary)->bool:return t.work_payload.get("recipe_id")=="saw_timber" and runtime.world.entity(t.actual_target_id).regionId=="RH-HOME")
	check("actually built home workbench exposes timber recipe",benches.size()==1,benches)
	if benches.size()!=1:return
	var material_bench:String=benches[0].actual_target_id
	var points:Array=runtime._services.buildings.use_points(material_bench)
	if points.is_empty():check("built workbench has real use points",false);return
	if not walk(points[0],"physically reach real saw workstation"):return
	var before:Dictionary=runtime.actor("player").pack.duplicate(true)
	if not perform("saw harvested log into actual building timber","craft",material_bench,{"recipe_id":"saw_timber","source_id":"pack:player","output_id":"pack:player","tool_ids":[material_saw]}):return
	check("one log creates exactly four timber through paid recipe",float(runtime.actor("player").pack.log)==float(before.log)-1 and float(runtime.actor("player").pack.timber)==float(before.timber)+4)
	var building:RefCounted=runtime._services.buildings
	var query:RefCounted=building.current_space()
	var centre:Dictionary=Geometry.location(building.instance(material_bench))
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
	if not perform("construct storage from real sawn timber and carried scrap","structure",cabinet.id,{"kind":"place","instance":cabinet,"source_id":"pack:player","output_id":"pack:player","tool_id":material_hammer}):return
	check("actual new storage costs exactly three timber and one scrap",float(runtime.actor("player").pack.timber)==float(before.timber)-3 and float(runtime.actor("player").pack.scrap)==float(before.scrap)-1 and not runtime.world.entity(cabinet.id).is_empty())
	var actual:Dictionary=runtime.stock(cabinet.id)
	check("newly built storage is real empty finite stock",not actual.is_empty() and actual.items.is_empty(),actual)
	if not perform("use newly built stock through canonical inventory transfer","deposit",cabinet.id,{"items":{"timber":1}}):return
	check("built storage contains only explicitly deposited timber",runtime.stock(cabinet.id).items=={"timber":1.0} and float(runtime.stock(stock).items.log)==2)
	roundtrip("actual harvested-log crafting and storage construction")
