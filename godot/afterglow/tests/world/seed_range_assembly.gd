extends "res://tests/world/settlement_joint.gd"
## Bounded 31-bit endpoint/random sample qualification of the actual fresh path.
## Random sample: Python random.Random(20261114).randrange(2**31), four draws.
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
const Terrain=preload("res://scripts/terrain/terrain_service.gd")
const Data=preload("res://scripts/world/world_data.gd")
const SEEDS=[0,1,2147483646,2147483647,275196493,1034690049,2080267707,553890622]
func raster_digest(snapshot:Dictionary)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
	var keys:Array=snapshot.chunks.keys();keys.sort()
	for key:String in keys:
		hash.update(key.to_utf8_buffer());hash.update(PackedInt32Array(snapshot.chunks[key].cells).to_byte_array())
	return hash.finish().hex_encode()
func differences(a:Variant,b:Variant,path:String="",out:Array=[])->Array:
	if out.size()>=6:return out
	if a is Dictionary and b is Dictionary:
		for key:Variant in a:
			if b.has(key):differences(a[key],b[key],path+"/"+str(key),out)
			elif out.size()<6:out.append({"path":path+"/"+str(key),"missing":true})
	elif a is Array and b is Array and a.size()==b.size():
		for i in a.size():differences(a[i],b[i],path+"/"+str(i),out)
	elif not Data.json_equal(a,b):out.append({"path":path,"before":a,"after":b,"number_delta":float(b)-float(a) if (a is float or a is int) and (b is float or b is int) else null})
	return out
func run()->void:
	var profiles:Array=Building.generation_profiles();var rasters:Array=[];var samples:Array=[]
	for value:int in SEEDS:
		var started:=Time.get_ticks_usec()
		var source:Dictionary=Assembly.generate(value,profiles)
		var sample:Dictionary={"seed":value,"generation_ms":(Time.get_ticks_usec()-started)/1000.0}
		samples.append(sample)
		var generated:bool=source.get("seed")==value and source.get("worldId")=="rural:v3:"+str(value) and source.get("generatorVersion")=="rural-3" and source.get("regions",{}).size()==2 and source.get("chunks",{}).size()==512
		check("actual fresh dual-region generation preserves exact 31-bit seed "+str(value),generated,source.get("reason"))
		if not generated:sample.error=source;continue # Never substitute a seed.
		sample.raster_sha256=raster_digest(source);rasters.append(sample.raster_sha256)
		check("complete world reproduces same seed and saved model "+str(value),source==Assembly.generate(value,profiles) and source.extensions["generation:rural2"].landscape_model=="village-contours-v4")
		started=Time.get_ticks_usec()
		var assembled:Dictionary=Assembly.prepare(source)
		sample.assembly_ms=(Time.get_ticks_usec()-started)/1000.0
		check("complete formal A/B structures actors stocks and safety assembly "+str(value),assembled.ok,assembled.get("reason"))
		if not assembled.ok:sample.error=assembled;continue
		var world:=State.new();var loaded:Dictionary=world.load_snapshot(assembled.capture.world)
		var runtime:=Runtime.new();var building:=Building.new()
		var configured:Dictionary=runtime.configure({"world":world,"facts":assembled.capture.facts,"services":{"buildings":building,"terrain":Terrain.new(),"actions":Actions.new(),"production":Production.new()}}) if loaded.ok else loaded
		check("sole real runtime accepts complete assembled seed "+str(value),configured.ok and world.identity().seed==value,configured.get("reason"))
		if not configured.ok:continue
		var arrival:Dictionary=world.extension("generation:RH-HOME").anchors.arrival.duplicate()
		arrival.merge({"regionId":"RH-HOME","buildingId":null,"storeyId":null})
		var feet:Dictionary=building.current_space().standing_point(arrival)
		check("actual nine-foot arrival support remains legal "+str(value),not feet.is_empty() and is_equal_approx(feet.y,arrival.y),{"anchor":arrival,"standing":feet})
		walk_paths(world,building,"31bit seed "+str(value)+" full actual assembly")
		if value==275196493:
			var plan:Dictionary=world.extension("generation:RH-VILLAGE");var noise:=Generator._noise(value)
			var grid:Array=[]
			for z in range(-70,-59):
				var row:Array=[]
				for x in range(40,44):row.append({"x":(x+0.5)*0.5,"z":(z+0.5)*0.5,"actual":world.surface_height((x+0.5)*0.5,(z+0.5)*0.5),"road_grade":Generator._road_grade(plan,noise,(x+0.5)*0.5,(z+0.5)*0.5)})
				grid.append(row)
			sample.failed_seed_diagnostic={"grade_controls":plan.grade_controls,"nearby_actual_columns":grid,"access":plan.paths.filter(func(path:Dictionary)->bool:return path.id=="access:RH-VILLAGE:neighbor:yard-gate")}
		sample.home_arrival=arrival;sample.player=runtime.actor("player")
		if value in [2147483647,275196493]:
			var encoded:Dictionary=Codec.encode_checkpoint(world.snapshot(),{"runtime":runtime.facts()},"test:31bit:"+str(value))
			var decoded:Dictionary=Codec.decode_checkpoint(encoded.envelope) if encoded.ok else encoded
			var restored:=State.new();var readback:Dictionary=restored.load_snapshot(decoded.state) if decoded.ok else decoded
			# Compare against the exact native JSON representation. Godot's JSON
			# parser can round a decorative fractional bound by 1-2 ULP; seed,
			# integer cells and every stored field still require exact readback.
			var persisted:Variant=JSON.parse_string(JSON.stringify(world.extension("generation:RH-HOME"),"",true,true))
			var plan_equal:bool=readback.ok and Data.json_equal(restored.extension("generation:RH-HOME"),persisted)
			var facts_equal:bool=decoded.ok and Data.json_equal(decoded.extensions.runtime,runtime.facts())
			var cells_equal:bool=readback.ok and raster_digest(restored.snapshot())==raster_digest(world.snapshot())
			check("native checkpoint keeps exact extreme or random seed and persistent plan "+str(value),readback.ok and restored.identity().seed==value and plan_equal and facts_equal and cells_equal,{"load":readback.get("code"),"seed":restored.identity().get("seed"),"plan_equal_to_exact_native_JSON":plan_equal,"runtime_facts_equal":facts_equal,"voxel_sha_equal":cells_equal,"original_plan_JSON_roundoff":differences(world.extension("generation:RH-HOME"),restored.extension("generation:RH-HOME"),"",[]) if readback.ok else []})
	check("all eight chosen seeds produce distinct authoritative terrain",rasters.size()==SEEDS.size() and rasters.all(func(d:String)->bool:return rasters.count(d)==1))
	costs.seed_samples=samples;costs.sample_scope="four endpoints and four fixed random draws; not exhaustive proof of 2^31 worlds; no seed replacement, app, OS, Metal or VA qualification"
	finish()
