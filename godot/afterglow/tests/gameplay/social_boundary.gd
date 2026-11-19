extends "res://tests/gameplay/generated_cooperation.gd"
## Explicit supported actor/barrier fixtures on the real generated shared edge.
## Real social commands, finite carried water, C continuity, B LOS and codec.

func run()->void:
	output_dir=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output_dir)
	evidence_kind="real-generated-social-boundary-with-explicit-actor-barrier-fixtures"
	host=Client.new()
	var built:Dictionary=Assembly.prepare(Assembly.generate(713,Building.generation_profiles()))
	check("real generated social boundary prepares",built.ok,built.get("reason"))
	if not built.ok or not mount(built.capture):finish();return
	var baseline:Dictionary=runtime.capture_checkpoint()
	var pair:Dictionary=edge_pair()
	check("actual shared edge has two supported visible close feet",not pair.is_empty(),pair)
	if pair.is_empty():finish();return
	var fixture:Dictionary=baseline.duplicate(true)
	for a:Dictionary in fixture.facts.actors:
		if a.id=="player":a.merge(pair.from,true);a.intent=null
		elif a.id=="village-resident":a.merge(pair.to,true);a.intent=null
	if not mount(fixture):finish();return
	check("close social pair really has different region labels",runtime.actor("player").regionId!=runtime.actor("village-resident").regionId)
	var talk:Dictionary=send("talk","village-resident")
	check("actual talk crosses loaded continuous edge with true LOS",talk.ok and runtime.actor("village-resident").relationship.met,talk)
	var denied:Dictionary=send("invite","village-resident")
	check("nearby cross-edge invitation still requires paid help",not denied.ok and denied.code=="HELP_REQUIRED",denied)
	var water:float=float(runtime.actor("player").pack.water)
	var help:Dictionary=send("help","village-resident",{"items":{"water":1}})
	var request:Dictionary=route_steps[-1].request.duplicate(true)
	check("cross-edge help consumes exactly one original real water",help.ok and float(runtime.actor("player").pack.water)==water-1 and float(runtime.actor("village-resident").pack.get("water",0))==1,help)
	var before:Dictionary=runtime.facts()
	var replay:Dictionary=runtime.command(request)
	check("replayed successful help never duplicates stock or time",replay.ok and Data.json_equal(before,runtime.facts()),replay)
	var joined:Dictionary=send("invite","village-resident")
	check("real help enables voluntary cross-edge cooperation",joined.ok and runtime.actor("village-resident").relationship.member and runtime.actor("village-resident").relationship.consent,joined)
	denied=send("job","village-resident",{"job":"rest"})
	check("cross-edge cooperation never bypasses physical return-home gate",not denied.ok and denied.code=="RETURN_HOME_FIRST",denied)
	if not roundtrip("cross-edge paid help and voluntary joining"):finish();return
	if not mount(fixture):finish();return
	var middle:Vector3=(Geometry.point(pair.from)+Geometry.point(pair.to))*0.5
	var obstruction:Dictionary={"id":"E:social-barrier-fixture","kind":"prop","regionId":pair.from.regionId,"position":Geometry.json_point(middle),"bounds":Geometry.json_box(AABB(middle+Vector3(-0.15,0,-0.04),Vector3(0.3,1.8,0.08))),"revision":0,"data":{"solid":true,"opaque":true}}
	var change:Dictionary={"op":"entity.put","id":obstruction.id,"before_exists":false,"before":null,"after":obstruction}
	var committed:Dictionary=runtime._commit({"ok":true,"world_changes":[change],"fact_changes":[]})
	check("explicit actual occluder uses one validated world transaction",committed.ok,committed)
	if committed.ok:
		check("cross-edge actual ray sees barrier",not runtime._services.buildings.current_space().line_clear(pair.from,pair.to,""))
		var tx:=preload("res://scripts/actions/domain_draft.gd").new(runtime._services.residents.context)
		var threat:Dictionary=Initial.actor("infected:E-social-LOS-fixture","explicit blocked threat",pair.from,pair.from,{})
		threat.faction="infected";threat.appearance_id="infected_walker";tx.staged.actors.append(threat)
		check("resident does not perceive infected through real thin opaque barrier",runtime._services.residents._threat(tx.actor("village-resident"),tx).is_empty())
		before=runtime.facts()
		var blocked:Dictionary=send("help","village-resident",{"items":{"water":1}})
		check("opaque barrier rejects social help without free transfer or consent",not blocked.ok and blocked.code=="OUT_OF_REACH" and Data.json_equal(before,runtime.facts()),blocked)
	finish()

func edge_pair()->Dictionary:
	var home:Dictionary=runtime.world.region("RH-HOME")
	var village:Dictionary=runtime.world.region("RH-VILLAGE")
	var edge:float=float(home.bounds.min.z)
	if edge!=float(village.bounds.max.z):return {}
	var query:RefCounted=runtime._services.buildings.current_space()
	for x:int in range(ceili(maxf(home.bounds.min.x,village.bounds.min.x))+2,floori(minf(home.bounds.max.x,village.bounds.max.x))-2):
		var y:Variant=runtime.world.surface_height(float(x),edge+0.35)
		if y==null:continue
		var from:Dictionary=query.standing_point({"x":float(x),"y":float(y),"z":edge+0.35,"regionId":home.id,"buildingId":null,"storeyId":null})
		var to:Dictionary=query.standing_point({"x":float(x),"y":float(y),"z":edge-0.35,"regionId":village.id,"buildingId":null,"storeyId":null})
		if from.is_empty() or to.is_empty() or from.get("buildingId")!=null or to.get("buildingId")!=null:continue
		if absf(float(from.y)-float(to.y))>0.01:continue
		if runtime.world.continuous_outdoor_contact(from,to).ok and query.line_clear(from,to,""):return {"from":from,"to":to}
	return {}
