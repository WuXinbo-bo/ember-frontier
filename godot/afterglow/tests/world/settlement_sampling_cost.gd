extends SceneTree
const Generator=preload("res://scripts/world/settlement_generator.gd")
const Building=preload("res://scripts/buildings/building_service.gd")
var checks: Array=[]
func _initialize() -> void: call_deferred("run")
func sample(plan: Dictionary,noise: FastNoiseLite,index: Dictionary) -> Dictionary:
	var output := PackedInt32Array();output.resize(128*128*2)
	var start:=Time.get_ticks_usec()
	for z in 128:
		for x in 128:
			var p:=Generator._sample(plan,noise,(x+0.5)*0.5,(z+0.5)*0.5,true,index)
			output[(x+128*z)*2]=roundi(p.height*2);output[(x+128*z)*2+1]=p.material
	return {"ms":(Time.get_ticks_usec()-start)/1000.0,"cells":output}
func run() -> void:
	var plan: Dictionary=Generator.plan_region(713,Vector2i.ZERO,Building.generation_profiles()).plan
	var noise:=Generator._noise(713)
	var indexed:=Generator._road_index(plan)
	# Exact exhaustive reference in original path order. No production switch,
	# stored cache, different world, quality reduction or approximate sampling.
	var segments: Array=[]
	for path in plan.paths:
		for i in path.points.size()-1:segments.append({"a":path.points[i],"b":path.points[i+1],"half":float(path.width)*0.5})
	var exhaustive := {}
	for z in 8:
		for x in 8:exhaustive[Vector2i(x,z)]=segments
	var outputs := {};var times := {"indexed":[],"exhaustive":[]}
	for warmup in 2:
		sample(plan,noise,indexed);sample(plan,noise,exhaustive)
	for iteration in 4:
		for side in (["indexed","exhaustive"] if iteration%2==0 else ["exhaustive","indexed"]):
			var result:=sample(plan,noise,indexed if side=="indexed" else exhaustive)
			times[side].append(result.ms);outputs[side]=result.cells
	checks.append({"label":"all 16384 XZ height/material columns exactly equal exhaustive segment reference","ok":outputs.indexed==outputs.exhaustive})
	checks.append({"label":"repeated output is independent of alternating execution order","ok":sample(plan,noise,indexed).cells==outputs.exhaustive})
	var summaries := {}
	for side in times:
		var sorted: Array=times[side].duplicate();sorted.sort()
		summaries[side]={"median_ms":(float(sorted[1])+float(sorted[2]))/2,"max_ms":sorted[-1],"samples_ms":times[side]}
	var failed:=checks.filter(func(c: Dictionary)->bool:return not c.ok).size()
	var result: Dictionary={"scope":"same current mapgen input, exact exhaustive candidate reference versus spatial segment index; CPU only, no formal app/FPS/Metal qualification","seed":713,"coord":{"x":0,"z":0},"checks":checks,"failed":failed,"costs":summaries,"segment_count":segments.size(),"column_count":16384,"height_material_sha256":outputs.indexed.to_byte_array().hex_encode().sha256_text()}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true)+"\n")
	print(JSON.stringify({"failed":failed,"costs":summaries}));quit(1 if failed else 0)
