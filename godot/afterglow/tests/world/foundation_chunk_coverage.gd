extends SceneTree
## Same public finite-world proof and original cell traversal as reference.
## No app/import/export/user slot; CPU timings are not frame/GPU qualification.
const Data=preload("res://scripts/world/world_data.gd")
const View=preload("res://scripts/world/world_view.gd")
const State=preload("res://scripts/world/world_state.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const Queries=preload("res://scripts/terrain/terrain_queries.gd")
class CellReference extends "res://scripts/world/world_view.gd":
	func _outdoor_coverage(a:Vector3,b:Vector3,resident:bool)->Dictionary:
		return TerrainQueries.coverage(self,a,b,resident)
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label+" "+str(detail))
func location(v:Vector3)->Dictionary:
	return {"x":v.x,"y":v.y,"z":v.z,"regionId":"RH-HOME" if v.z>=0 else "RH-VILLAGE","buildingId":null,"storeyId":null}
func compare(source:Dictionary,segments:Array,resident:bool)->Array:
	var current:=View.new(source);var previous:=CellReference.new(source)
	var differences:Array=[]
	for pair:Array in segments:
		var a:Dictionary=location(pair[0]);var b:Dictionary=location(pair[1])
		var actual:Dictionary=current.continuous_outdoor_segment(a,b,256,resident)
		var expected:Dictionary=previous.continuous_outdoor_segment(a,b,256,resident)
		if not Data.json_equal(actual,expected):differences.append({"a":a,"b":b,"actual":actual,"reference":expected})
	return differences
func median(values:Array)->float:
	var sorted:Array=values.duplicate();sorted.sort()
	return (float(sorted[sorted.size()/2-1])+float(sorted[sorted.size()/2]))/2.0
func elapsed(view:RefCounted,pairs:Array,repeats:int)->int:
	var start:int=Time.get_ticks_usec()
	for repeat_index in repeats:
		for pair:Array in pairs:view.continuous_outdoor_segment(location(pair[0]),location(pair[1]),256,true)
	return Time.get_ticks_usec()-start
func run()->void:
	var source:Dictionary=Rural.generate(713)
	source.generatorVersion="rural-2"
	for c:Dictionary in source.chunks.values():c.generatorVersion="rural-2"
	var world:=State.new();var loaded:Dictionary=world.load_snapshot(source)
	check("actual authority accepts generated finite rural source",loaded.ok)
	var cases:Array=[]
	# Negative coordinates, exact chunk/cell faces, zero length, closed endpoints,
	# coplanar and three-axis ties. Vertical partial chunks are not all valid.
	for y:float in [-4.0,-3.75,0.0,0.5,5.0,8.0,16.0,19.75,20.0]:
		for z:float in [-16.0,-8.0,-0.5,0.0,0.5,8.0,16.0]:
			cases.append([Vector3(8.0,y,z),Vector3(40.0,y,-z)])
			cases.append([Vector3(40.0,y,-z),Vector3(8.0,y,z)])
			cases.append([Vector3(8.0,y,z),Vector3(8.0,y,z)])
	for a:Vector3 in [Vector3(0.25,0.25,0.25),Vector3(8.0,8.0,0.0),Vector3(32.0,-4.0,-32.0)]:
		for b:Vector3 in [Vector3(31.75,15.75,-31.25),Vector3(32.0,-4.0,-32.0),Vector3(8.0,8.0,0.0)]:cases.append([a,b])
	var rng:=RandomNumberGenerator.new();rng.seed=2026111422
	for i in 180:
		cases.append([Vector3(rng.randf_range(0.25,63.75),rng.randf_range(-3.75,19.75),rng.randf_range(-63.75,63.75)),Vector3(rng.randf_range(0.25,63.75),rng.randf_range(-3.75,19.75),rng.randf_range(-63.75,63.75))])
	for resident:bool in [false,true]:
		var differences:=compare(source,cases,resident)
		check("all known exact boundaries and random segments match cell reference resident="+str(resident),differences.is_empty(),{"segments":cases.size(),"differences":differences.slice(0,4)})
	for key:String in ["1,0,-1","4,0,0","0,1,-1","1,-1,1"]:
		for mutation:String in ["missing","cold","ungenerated"]:
			var changed:Dictionary=source.duplicate(true)
			if mutation=="missing":changed.chunks.erase(key)
			elif mutation=="cold":changed.chunks[key].resident=false
			else:changed.chunks[key].generated=false
			for resident:bool in [false,true]:
				var differences:=compare(changed,cases,resident)
				check(mutation+" "+key+" exact nearest-cell result resident="+str(resident),differences.is_empty(),{"segments":cases.size(),"differences":differences.slice(0,4)})
	var a:=location(Vector3(8.25,5,3));var b:=location(Vector3(8.25,5,-9))
	check("actual live authority initially passes",world.continuous_outdoor_segment(a,b,12).ok)
	var p:Dictionary=world.prepare_changes([{"op":"chunk.residency","id":"1,0,-1","before":true,"after":false}],world.get_revision())
	if p.ok:world.commit_prepared(p.capability)
	check("live unload immediately rejects without stale memo",p.ok and world.continuous_outdoor_segment(a,b,12).get("code")=="UNLOADED_CELL")
	p=world.prepare_changes([{"op":"chunk.residency","id":"1,0,-1","before":false,"after":true}],world.get_revision())
	if p.ok:world.commit_prepared(p.capability)
	check("live reload immediately passes with current revision",p.ok and world.continuous_outdoor_segment(a,b,12).get("world_revision")==world.get_revision() and world.continuous_outdoor_segment(a,b,12).ok)
	var proof:Dictionary=world.continuous_outdoor_segment(a,b,12);proof.from_region_id="mutated"
	check("public proof is detached and source cells preserved",world.continuous_outdoor_segment(a,b,12).from_region_id=="RH-HOME" and Data.json_equal(world.chunk("1,0,-1").cells,source.chunks["1,0,-1"].cells))
	# Real public-path cost with same immutable finite map, 64 actual long lines,
	# alternating six rounds. No materials/entities/LOS or display policy skipped.
	var cost_cases:Array=[]
	for i in 64:cost_cases.append([Vector3(0.25+i*0.875,5,60.25),Vector3(63.75-i*0.875,5,-60.25)])
	var previous:=CellReference.new(source);var current:=View.new(source)
	elapsed(previous,cost_cases,1);elapsed(current,cost_cases,1)
	var before:Array=[];var after:Array=[]
	for round_index in 6:
		if round_index%2==0:
			before.append(elapsed(previous,cost_cases,2));after.append(elapsed(current,cost_cases,2))
		else:
			after.append(elapsed(current,cost_cases,2));before.append(elapsed(previous,cost_cases,2))
	check("positive long-line public results remain valid",cost_cases.all(func(pair:Array)->bool:return current.continuous_outdoor_segment(location(pair[0]),location(pair[1]),256,true).ok))
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"checks":checks,"failed":failed,"cost":{"unit":"microseconds per 128 public queries","pairs":64,"repeats":2,"rounds":6,"before":before,"after":after,"before_median":median(before),"after_median":median(after)},"scope":"same public path chunk metadata coverage vs cell traversal; headless CPU only, no B sight/policy/OS/VA/frame qualification"}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify(report));quit(1 if failed else 0)
