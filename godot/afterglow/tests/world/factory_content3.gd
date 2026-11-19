extends "res://tests/world/factory_environment.gd"
## Actual B7 profiles through the one A assembly/runtime/scheduler/native path.
## Explicit C edit/residency transactions test derivation, not normal input/OS.

func first_difference(a:Variant,b:Variant,path:String="")->Dictionary:
	if Data.json_equal(a,b):return {}
	if a is Dictionary and b is Dictionary:
		for key:Variant in a:
			if not b.has(key):return {"path":path+"/"+str(key),"missing":true}
			var delta:Dictionary=first_difference(a[key],b[key],path+"/"+str(key))
			if not delta.is_empty():return delta
	if a is Array and b is Array and a.size()==b.size():
		for i:int in a.size():
			var delta:Dictionary=first_difference(a[i],b[i],path+"/"+str(i))
			if not delta.is_empty():return delta
	return {"path":path,"before":a,"after":b}

func run()->void:
	var profiles:Array=Modules.generation_profiles();var policy:Dictionary=Contract.fresh(profiles,3)
	check("actual seven independent designs enter explicit content3 lock",policy.ok and profiles.filter(func(p:Dictionary)->bool:return p.has("design_id")).size()==7)
	if not policy.ok:return finish()
	var families:Dictionary={};var signatures:Array=[]
	# Pure plans exercise deterministic finite designs beyond the opening two
	# parcels. No free machine, module inventory or population is fabricated.
	for seed:int in [713,2026,17,999]:
		for z:int in range(-2,2):
			for x:int in range(-2,2):
				var planned:Dictionary=Factory.plan_region(seed,Vector2i(x,z),profiles,policy.contract)
				if not planned.ok:check("all actual design plans fit finite purpose slots",false,planned);return finish()
				for parcel:Dictionary in planned.plan.parcels:
					var definition:Dictionary=Catalog.definition(parcel.definition_id)
					var family:String=definition.get("visual_family","")
					if not families.has(family):families[family]={}
					families[family][definition.get("design_id","")]=true
	check("six real opening and peripheral designs cover three families",families.size()==3 and families.get("home",{}).size()==2 and families.get("warehouse",{}).size()==2 and families.get("roadside",{}).size()==2,families)
	for seed:int in [713,2026]:
		var generated:Dictionary=Factory.generate(seed,profiles,policy.contract)
		var opening:Dictionary=Assembly.prepare(generated)
		check("real content3 cells and module sources assemble "+str(seed),opening.ok,opening.get("reason"))
		if not opening.ok:return finish()
		var host:=Native.new();var built:Dictionary=host._assemble(opening.capture);host.free()
		check("same Native configures actual new world services "+str(seed),built.ok,built.get("reason"))
		if not built.ok:return finish()
		world=built.world
		var homes:Array=[];var spaces_ok:bool=true;var layouts:Dictionary={}
		for region:String in ["RH-HOME","RH-VILLAGE"]:
			var plan:Dictionary=world.extension("generation:"+region);var spaces:Dictionary={}
			for space:Dictionary in plan.spaces:spaces[space.type]=true
			spaces_ok=spaces_ok and spaces.size()==6 and plan.generation_content_version==3 and plan.ecology.layout_policy=="land-use-clusters-v3"
			for parcel:Dictionary in plan.parcels:
				var definition:Dictionary=Catalog.definition(parcel.definition_id)
				if definition.generation_role=="home":homes.append(definition.design_id)
			layouts[region]=plan
		check("both regions retain six spaces and different home designs "+str(seed),spaces_ok and homes.size()==2 and homes[0]!=homes[1],homes)
		var modules:Array=world.extension("r34:modules").instances
		var ports_ok:bool=true;var ids:Dictionary={};var no_machine:bool=true
		for module:Dictionary in modules:
			ids[module.id]=true
			no_machine=no_machine and Catalog.definition(module.definition_id).generation_role!="machine"
			for port:Dictionary in preload("res://scripts/modules/module_geometry.gd").ports(module,Catalog.definition(module.definition_id)):
				for at:Dictionary in port.use_points:ports_ok=ports_ok and not built.services.buildings.current_space().standing_point(at).is_empty()
		check("actual complete modules have unique IDs full service clearance and no gifted machine "+str(seed),ports_ok and ids.size()==modules.size() and no_machine)
		var jobs:=Scheduler.new();jobs.attach(built.runtime,built.services.buildings,34,built.services.modules)
		var peripherals_ok:bool=true
		for coord:Vector2i in [Vector2i(-1,0),Vector2i(1,0)]:
			var added:Dictionary=await peripheral(jobs,coord);peripherals_ok=peripherals_ok and added.get("ok",false)
			if not added.get("ok",false):check("actual content3 peripheral source registration",false,added)
		jobs.shutdown()
		check("actual scheduler registers positive negative regions with same content3 lock "+str(seed),peripherals_ok and world.regions().size()==4 and world.extension(Factory.CONFIG_KEY).content_version==3)
		if not peripherals_ok:return finish()
		terrain=TerrainView.new();root.add_child(terrain);terrain.set_process(false)
		terrain.configure({"world":world,"stream_updates":true,"budgeted_edits":true});terrain.cancel_pending()
		var selected:Array=[]
		for region:String in ["RH-HOME","RH-VILLAGE"]:
			var plan:Dictionary=world.extension("generation:"+region)
			var limit:int=2 if region=="RH-HOME" else 4
			for key:String in plan.field_surfaces.chunks:
				selected.append(key)
				if selected.size()>=limit:break
		for key:String in selected:terrain._rebuild(key)
		await physics_frame
		var stats:Dictionary=terrain.environment.statistics();var hot:String=derived_signature();var before:String=raster_digest(world.snapshot())
		check("real new plants fields native meshes collision and image bindings mount "+str(seed),stats.tree_roots>0 and stats.ecology_patches>0 and stats.field_surface_chunks>0 and stats.missing_materials.is_empty() and stats.missing_models.is_empty() and stats.missing_quality_images.is_empty() and terrain.readiness(selected).ready,stats)
		var cold_prep:Dictionary=world.prepare_region_residency("RH-VILLAGE",false,world.get_revision())
		var cooled:Dictionary=apply(cold_prep.world_changes) if cold_prep.ok else cold_prep
		check("new plan plants and cached factual boundaries release on cold "+str(seed),cooled.ok and cached_bytes(world.region_chunk_keys("RH-VILLAGE"))==0 and not world.region_is_resident("RH-VILLAGE"))
		var saved:Dictionary=Store.encode(built.runtime.capture_checkpoint());var decoded:Dictionary=Store.decode(saved.text) if saved.ok else saved
		var restored:Dictionary={}
		if decoded.ok:
			host=Native.new();restored=host._assemble(decoded.capture);host.free()
		check("same runtime native save restores real content3 and cold pages "+str(seed),restored.get("ok",false) and Data.json_equal(restored.world.extension(Factory.CONFIG_KEY),world.extension(Factory.CONFIG_KEY)) and Data.json_equal(restored.world.extension("r34:modules"),world.extension("r34:modules")),restored.get("reason"))
		var plans_same:bool=restored.get("ok",false)
		var restore_detail:Dictionary={"plans_same":plans_same}
		if plans_same:
			for region:Dictionary in world.regions():
				var delta:Dictionary=first_difference(world.extension("generation:"+str(region.id)),restored.world.extension("generation:"+str(region.id)),str(region.id))
				if not delta.is_empty() and not restore_detail.has("difference"):restore_detail.difference=delta
				plans_same=plans_same and delta.is_empty()
			restore_detail.plans_same=plans_same
			var rewarm:Dictionary=restored.world.prepare_region_residency("RH-VILLAGE",true,restored.world.get_revision())
			var tx:Dictionary=restored.world.prepare_changes(rewarm.world_changes,restored.world.get_revision()) if rewarm.ok else rewarm
			restore_detail.warm=tx.get("code");restore_detail.warm_reason=tx.get("reason")
			if tx.ok:restore_detail.commit=restored.world.commit_prepared(tx.capability).get("code")
			restore_detail.raster_same=raster_digest(restored.world.snapshot())==before
			plans_same=plans_same and tx.ok and raster_digest(restored.world.snapshot())==before
		check("all actual saved plans and modified-free raster survive cold reload exactly "+str(seed),plans_same,restore_detail)
		var warm_prep:Dictionary=world.prepare_region_residency("RH-VILLAGE",true,world.get_revision())
		var warmed:Dictionary=apply(warm_prep.world_changes) if warm_prep.ok else warm_prep
		terrain.cancel_pending()
		for key:String in selected:terrain._rebuild(key)
		await physics_frame
		check("actual cold warm restores identical native geometry and plant transforms "+str(seed),warmed.ok and derived_signature()==hot and raster_digest(world.snapshot())==before)
		var request:Dictionary=Factory.draft_region_request(Factory.region_generation_input(world,profiles),Vector2i(-1,0))
		var revisit:Dictionary=Factory.prepare_region_draft(world,request,world.get_revision())
		check("generated new design revisit never rerolls or replenishes sources "+str(seed),revisit.ok and revisit.already_generated and revisit.world_changes.is_empty() and revisit.initial_stocks.is_empty())
		costs[str(seed)]={"environment":stats,"module_ids":ids.keys(),"raster_sha256":before,"native_bytes":saved.text.length() if saved.ok else 0}
		signatures.append(before);terrain.free()
	check("real content3 playable seed terrain varies",signatures.size()==2 and signatures[0]!=signatures[1])
	costs.families=families;costs.scope="actual C/B profiles and A assembly/scheduler/runtime native source; C residency transactions explicit. Default remains2; not package, normal tools journey, OS, VA, GPU or whole-game performance qualification"
	finish()
