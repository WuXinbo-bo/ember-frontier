extends "res://tests/world/local_apron.gd"
const Contract=preload("res://scripts/world/generation_contract.gd")
func model_world(seed:int,profiles:Array,model:String)->Dictionary:
	var input:Dictionary=Contract.fresh(profiles);input.contract.landscape_model=model
	return Landscape.generate(seed,profiles,input.contract)
func road_cells(w:RefCounted)->int:
	var count:int=0
	for region:String in ["RH-HOME","RH-VILLAGE"]:
		var bounds:Dictionary=w.region(region).bounds
		for z in range(roundi(bounds.min.z*2),roundi(bounds.max.z*2)):
			for x in 128:
				var y:int=roundi(float(w.surface_height((x+0.5)*0.5,(z+0.5)*0.5))*2)-1
				if w.cell_at(x,y,z)==4:count+=1
	return count
func region_risers(w:RefCounted,region:String,common_mask:Dictionary={})->Dictionary:
	# Same axis/run/exclusion definition as local_apron; translate the queried
	# voxel columns, not the source plan, to cover the actual Village screenshot.
	var plan:Dictionary=w.extension("generation:"+region) if common_mask.is_empty() else common_mask
	var oz:float=w.region(region).bounds.min.z
	var heights:Dictionary={}
	for z in 128:
		for x in 128:heights[Vector2i(x,z)]=roundi(float(w.surface_height((x+0.5)*0.5,oz+(z+0.5)*0.5))*2)
	var longest:int=0;var total:int=0
	for axis in 2:
		for cross in range(1,128):
			var last:Variant=null;var count:int=0
			for along in 129:
				var pair:Variant=null
				if along<128:
					var a:=Vector2i(cross-1,along) if axis==0 else Vector2i(along,cross-1)
					var b:=a+(Vector2i.RIGHT if axis==0 else Vector2i.DOWN)
					if not excluded(plan,(a.x+0.5)*0.5,oz+(a.y+0.5)*0.5) and not excluded(plan,(b.x+0.5)*0.5,oz+(b.y+0.5)*0.5) and heights[a]!=heights[b]:pair=Vector2i(heights[a],heights[b])
				if pair!=last:
					longest=maxi(longest,count)
					if count>=16:total+=count
					count=0;last=pair
				if pair!=null:count+=1
	return {"longest_m":longest*0.5,"total_risers_ge8m_m":total*0.5}
func run()->void:
	var profiles:Array=Building.generation_profiles()
	var samples:Array=[]
	for seed:int in [713,973339546,275196493]:
		var baseline:Dictionary=model_world(seed,profiles,"local-apron-v3")
		var revised:Dictionary=model_world(seed,profiles,"village-contours-v4")
		var old:=State.new();var world:=State.new()
		check("real paired model worlds load "+str(seed),old.load_snapshot(baseline).ok and world.load_snapshot(revised).ok)
		var old_metrics:Dictionary=risers(old);var new_metrics:Dictionary=risers(world)
		var village_mask:Dictionary=old.extension("generation:RH-VILLAGE")
		var sample:Dictionary={"seed":seed,"before":old_metrics,"after":new_metrics,"village_before":region_risers(old,"RH-VILLAGE",village_mask),"village_after":region_risers(world,"RH-VILLAGE",village_mask),"village_exclusion_scope":"exact same baseline pad/landform mask for both worlds; new plots are not used to hide contour edges","before_road_cells":road_cells(old),"after_road_cells":road_cells(world),"region_content":{}}
		for id:String in ["RH-HOME","RH-VILLAGE"]:
			var plan:Dictionary=world.extension("generation:"+id)
			sample.region_content[id]={"field_plots":plan.landforms.filter(func(l:Dictionary)->bool:return l.use=="field"),"trees":plan.resource_sites.size(),"grove_trees":plan.resource_sites.filter(func(s:Dictionary)->bool:return s.use=="courtyard-forest-edge").size(),"vegetation_patches":plan.ecology.patches.size()}
		samples.append(sample)
		var assembled:Dictionary=Assembly.prepare(revised)
		check("complete A/B actual buildings and body assembly "+str(seed),assembled.ok,assembled.get("reason"))
		if not assembled.ok:continue
		world=State.new();world.load_snapshot(assembled.capture.world)
		var runtime:=Runtime.new();var building:=Building.new()
		var configured:Dictionary=runtime.configure({"world":world,"facts":assembled.capture.facts,"services":{"buildings":building,"production":Production.new(),"actions":Actions.new()}})
		check("sole production runtime configures revised world "+str(seed),configured.ok)
		walk_paths(world,building,"village contours "+str(seed))
		if seed==973339546:
			check("actual eighth terrain baseline integer raster is retained",raster_digest(baseline)=="632b709acf1ee9b31117059fd39e3eb34d41f152881f0426f265b70536c78c40")
			check("same actual-seed Village long risers reduced at least original thirty percent",float(sample.village_after.total_risers_ge8m_m)<=float(sample.village_before.total_risers_ge8m_m)*0.7)
			check("same actual-seed Village longest riser also decreases",float(sample.village_after.longest_m)<float(sample.village_before.longest_m))
			check("same actual-seed genuine terrain height range remains",float(new_metrics.max_y)-float(new_metrics.min_y)>=1.5)
		var saved:Dictionary=Codec.encode_checkpoint(world.snapshot(),{"runtime":runtime.facts()},"test:contours:"+str(seed))
		var decoded:Dictionary=Codec.decode_checkpoint(saved.envelope) if saved.ok else saved
		var restored:=State.new();var loaded:Dictionary=restored.load_snapshot(decoded.state) if decoded.ok else decoded
		check("real native checkpoint preserves exact cells and saved model "+str(seed),loaded.ok and raster_digest(restored.snapshot())==raster_digest(world.snapshot()) and restored.extension("generation:rural2").landscape_model=="village-contours-v4")
	var args:Array=Array(OS.get_cmdline_user_args())
	if args.has("matrix"):
		for seed:int in [0,1,2147483646,2147483647,1034690049,2080267707,553890622]:
			var source:Dictionary=model_world(seed,profiles,"village-contours-v4")
			check("full v4 world deterministic repeat "+str(seed),source==model_world(seed,profiles,"village-contours-v4"))
			var assembled:Dictionary=Assembly.prepare(source)
			check("full actual assembly endpoint/random seed "+str(seed),assembled.ok,assembled.get("reason"))
			if not assembled.ok:continue
			var world:=State.new();world.load_snapshot(assembled.capture.world)
			var runtime:=Runtime.new();var building:=Building.new()
			check("real runtime endpoint/random seed "+str(seed),runtime.configure({"world":world,"facts":assembled.capture.facts,"services":{"buildings":building,"production":Production.new(),"actions":Actions.new()}}).ok)
			walk_paths(world,building,"v4 endpoint/random "+str(seed))
	costs.pairs=samples
	costs.scope="New-world C geometry candidate. Original >=30% criterion not silently changed; these measurements are not VA, OS or performance qualification."
	finish()
func raster_digest(snapshot:Dictionary)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256)
	var keys:Array=snapshot.chunks.keys();keys.sort()
	for key:String in keys:
		h.update(key.to_utf8_buffer());h.update(PackedInt32Array(snapshot.chunks[key].cells).to_byte_array())
	return h.finish().hex_encode()
