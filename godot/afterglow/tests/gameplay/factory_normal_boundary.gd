extends "res://tests/gameplay/factory_normal_preparation.gd"
## Same finite-source journey; vary only C's seed and real pre-commit exertion.
var sample_seed:int=713
var low_commitment:bool=false
var exhausted:bool=false

func normal_tools(generation_contract:Dictionary={},normal_seed:int=713)->Dictionary:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	sample_seed=int(args[1]) if args.size()>1 else normal_seed
	low_commitment=args.size()>2 and args[2]=="low"
	var contract:Dictionary=Contract.fresh(Modules.generation_profiles(),3).contract if generation_contract.is_empty() else generation_contract
	var opening:Dictionary=super.normal_tools(contract,sample_seed)
	costs.sample={"seed":sample_seed,"content_version":3,"low_commitment":low_commitment}
	check("boundary uses actual requested content3 seed",opening.get("ok",false) and opening.world.identity().seed==sample_seed and opening.world.extension(Factory.CONFIG_KEY).content_version==3)
	return opening

func send(runtime:RefCounted,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	if kind=="settlement.begin_route_work" and low_commitment and not exhausted:
		exhausted=true
		if not exert_at_site(runtime):return {"ok":false,"code":"TEST_EXERTION_FAILED"}
	return super.send(runtime,kind,target,payload,destination)

func exert_at_site(runtime:RefCounted)->bool:
	var query:RefCounted=runtime._services.buildings.current_space()
	var origin:Dictionary=Geometry.location(runtime.actor("player"));var endpoint:Dictionary={}
	for direction:Vector2 in [Vector2(1,0),Vector2(-1,0),Vector2(0,1),Vector2(0,-1)]:
		var raw:Dictionary=origin.duplicate(true);raw.x+=direction.x*2.0;raw.z+=direction.y*2.0
		var feet:Dictionary=query.standing_point(raw)
		if feet.is_empty() or Geometry.point(feet).distance_to(Geometry.point(origin))>2.05:continue
		var route:Dictionary=runtime._services.actions.route("player",origin,feet)
		if not route.ok:continue
		var length:float=0.0;var last:Vector3=Geometry.point(origin)
		for step:Dictionary in route.steps:
			if step.has("to"):length+=last.distance_to(Geometry.point(step.to));last=Geometry.point(step.to)
		if length<=2.1:endpoint=feet;break
	check("low commitment has a real supported local exertion route",not endpoint.is_empty())
	if endpoint.is_empty():return false
	var before:Dictionary=runtime.actor("player");var start:float=runtime.clock();var runs:int=0
	while float(runtime.actor("player").stamina)>20.0 and runs<40:
		var at:Dictionary=endpoint if runs%2==0 else origin
		var moved:Dictionary=super.send(runtime,"walk","",{"movement_mode":"run"},at)
		if not moved.ok or not progress(runtime).finished:break
		runs+=1
	var actor:Dictionary=runtime.actor("player")
	costs.low_commitment={"runs":runs,"seconds":runtime.clock()-start,"stamina_before":before.stamina,"stamina_at_commitment":actor.stamina,"location":Geometry.location(actor),"pack_before":before.pack,"pack_at_commitment":actor.pack,"hp":actor.hp}
	var okay:bool=float(actor.stamina)>=10.0 and float(actor.stamina)<=20.0 and actor.hp==before.hp and Data.json_equal(actor.pack,before.pack)
	check("risk commitment starts with low stamina caused by actual paid running",okay,costs.low_commitment)
	return okay

func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var result:Dictionary={"checks":checks,"failed":failed,"costs":costs,"scope":"Explicit content3 sampled seed and optional real running before risk acceptance; original finite tools, food, water, rest, combat and clearance. No actor, inventory or health injection. Headless source evidence only; no OS/VA/package or all-seed fairness qualification."}
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
