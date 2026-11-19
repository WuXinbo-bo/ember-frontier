extends SceneTree
## Exact before/after sampling cost; immutable fixture is never a world writer.
const Before=preload("res://tests/world/fixtures/local_apron_before_sampling_cost.gd")
const Current=preload("res://scripts/world/settlement_generator.gd")
const Landscape=preload("res://scripts/world/landscape_generator.gd")
const Contract=preload("res://scripts/world/generation_contract.gd")
const CATALOG="res://data/buildings/generation_profiles.json"
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func sample(generator:GDScript,plan:Dictionary)->Dictionary:
	var noise:=Current._noise(int(plan.seed));var index:=Current._road_index(plan)
	var values:=PackedInt32Array();values.resize(128*128*2)
	var start:=Time.get_ticks_usec()
	for z in 128:
		for x in 128:
			var wx:float=float(plan.region_coord.x)*64+(x+0.5)*0.5
			var wz:float=float(plan.region_coord.z)*64+(z+0.5)*0.5
			var p:Dictionary=generator._sample(plan,noise,wx,wz,true,index)
			values[(x+128*z)*2]=roundi(p.height*2);values[(x+128*z)*2+1]=p.material
	return {"values":values,"ms":(Time.get_ticks_usec()-start)/1000.0}
func run()->void:
	# Same delivered DTO; the sampler does not call building navigation/view.
	var profiles:Array=JSON.parse_string(FileAccess.get_file_as_string(CATALOG)).profiles
	# Keep this historical exact-output CPU pair on its original saved v2
	# input. A new road/grade model is a quality change, not this optimization.
	var pinned:Dictionary=Contract.fresh(profiles).contract;pinned.landscape_model="local-apron-v2"
	var plans:Array=[];var signatures:Array=[]
	for row:Dictionary in [{"seed":713,"coord":Vector2i.ZERO},{"seed":713,"coord":Vector2i(-1,0)},{"seed":2026,"coord":Vector2i(0,-1)}]:
		var result:Dictionary=Landscape.plan_region(row.seed,row.coord,profiles,pinned)
		if not result.ok:push_error(str(result));quit(1);return
		var plan:Dictionary=result.plan;plans.append(plan)
		var before:Dictionary=sample(Before,plan);var after:Dictionary=sample(Current,plan)
		checks.append({"label":"all 16384 true height/material columns exact "+str(row),"ok":before.values==after.values})
		signatures.append({"seed":row.seed,"coord":str(row.coord),"sha256":after.values.to_byte_array().hex_encode().sha256_text()})
	var plan:Dictionary=plans[0]
	for warmup in 2:sample(Before,plan);sample(Current,plan)
	var times:Dictionary={"before":[],"after":[]}
	for iteration in 4:
		for side:String in (["before","after"] if iteration%2==0 else ["after","before"]):
			var result:Dictionary=sample(Before if side=="before" else Current,plan)
			times[side].append(result.ms)
	var costs:Dictionary={}
	for side:String in times:
		var sorted:Array=times[side].duplicate();sorted.sort()
		costs[side]={"samples_ms":times[side],"median_ms":(float(sorted[1])+float(sorted[2]))*0.5,"max_ms":sorted[-1]}
	checks.append({"label":"paired cost is recorded without relaxing exact-output checks","ok":times.before.size()==4 and times.after.size()==4})
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"checks":checks,"failed":failed,"costs":costs,"signatures":signatures,"scope":"same local-apron-v2 inputs; only road-grade laziness and per-point trig hoist; two warmups and four alternating CPU samples; not frame/Metal/OS/VA"}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify(report));quit(1 if failed else 0)
