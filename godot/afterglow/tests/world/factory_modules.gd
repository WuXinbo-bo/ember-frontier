extends "res://tests/world/factory_country.gd"
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const Mesher=preload("res://scripts/terrain/terrain_mesher.gd")

func run()->void:
	var profiles:Array=Catalog.profiles()
	check("actual B catalogue spatial profiles resolve",Catalog.validate().ok and Contract.fresh(profiles).ok)
	var world:RefCounted;var signatures:Array=[]
	for seed:int in [713,2026]:
		var start:int=Time.get_ticks_usec();var source:Dictionary=Factory.generate(seed,profiles)
		check("real B profiles create complete initial C world "+str(seed),source.has("chunks"),source.get("reason"))
		if not source.has("chunks"):return finish()
		world=State.new();check("real module-aware terrain enters sole authority "+str(seed),world.load_snapshot(source).ok)
		var query:=Space.new();query.configure(world,{"instances":[]},Geometry.new(),func(_a:Variant,_b:Variant,_c:Variant,_d:Variant)->Variant:return null)
		var total_seeds:Array=[];var all_ports:bool=true;var all_anchors:bool=true
		var module_definitions:Dictionary={};var bad:Array=[]
		for region:String in ["RH-HOME","RH-VILLAGE"]:
			var plan:Dictionary=world.extension("generation:"+region)
			total_seeds.append_array(plan.module_seeds)
			for p:Dictionary in plan.parcels:
				module_definitions[p.definition_id]=true
				for port:Dictionary in p.entrance_ports:
					for at:Dictionary in port.use_points:
						var location:Dictionary=at.duplicate(true);location.regionId=region;location.buildingId=null;location.storeyId=null
						var feet:Dictionary=query.standing_point(location)
						if feet.is_empty() or absf(feet.y-p.pad.height)>0.001:all_ports=false;bad.append({"parcel":p.id,"port":port.id,"location":location})
			for key:String in plan.anchors:
				if query.standing_point(plan.anchors[key]).is_empty():all_anchors=false;bad.append({"anchor":key,"position":plan.anchors[key]})
		check("complete real B use points stand on fitted pads "+str(seed),all_ports,bad)
		check("arrival story defence anchors use actual body support "+str(seed),all_anchors,bad)
		check("four initial module sources exclude free fuel machine "+str(seed),total_seeds.size()==4 and module_definitions.has("r34.module.hand_workshop") and not module_definitions.has("r34.module.fuel_woodshop"),total_seeds)
		var stocks:Array=Factory.initial_resource_stocks(world)
		check("snapshot and world produce identical sole empty tree stock input "+str(seed),Data.json_equal(stocks,Factory.initial_resource_stocks(source)) and stocks.size()>0 and stocks.all(func(s:Dictionary)->bool:return s.items.is_empty()))
		var profile_input:Dictionary=Factory.region_generation_input(world,profiles)
		check("captured generation input is detached pure JSON "+str(seed),profile_input.ok and Data.json_value(profile_input))
		var positive:Dictionary=Factory.draft_region_request(profile_input,Vector2i(1,0))
		var negative:Dictionary=Factory.draft_region_request(profile_input,Vector2i(-1,-1))
		check("both actual positive negative workers prepare "+str(seed),positive.ok and negative.ok)
		if not positive.ok or not negative.ok:return finish()
		var committed:Dictionary={}
		for draft:Dictionary in [negative,positive]:
			var ready:Dictionary=Factory.prepare_region_draft(world,draft,world.get_revision())
			var tx:Dictionary=world.prepare_changes(ready.world_changes,world.get_revision()) if ready.ok else ready
			check("unrelated commit permits same pinned worker with current CAS "+str(seed)+draft.region.id,tx.ok,tx.get("reason"))
			if not tx.ok:return finish()
			committed=world.commit_prepared(tx.capability)
		check("worker does not replenish prior source or module contents "+str(seed),committed.ok and Factory.prepare_region_draft(world,positive,world.get_revision()).initial_stocks.is_empty())
		var wrong:Dictionary=positive.duplicate(true);wrong.input_dependency.world_id="r34:foreign"
		check("foreign worker cannot enter same-seed world "+str(seed),Factory.prepare_region_draft(world,wrong,world.get_revision()).get("code")=="FOREIGN_GENERATION_REQUEST")
		check("old commit revision rejected "+str(seed),Factory.prepare_region_draft(world,positive,world.get_revision()-1).get("code")=="STALE_REVISION")
		var changed:Array=profiles.duplicate(true);changed[0].geometry_version="unsupported-next-version"
		check("catalogue change cannot reinterpret unexplored saved-world contract "+str(seed),Factory.region_generation_input(world,changed).get("code")=="MODULE_PROFILE_VERSION_MISMATCH")
		var raw:Dictionary=Factory.draft_region_request(Factory.region_generation_input(world,profiles),Vector2i(0,1))
		var missing:Dictionary=raw.duplicate(true);missing.chunks.erase(missing.chunks.keys()[0])
		check("incomplete voxel lattice refused before commit "+str(seed),Factory.prepare_region_draft(world,missing,world.get_revision()).get("code")=="INVALID_REGION_DRAFT")
		var bad_chunk:Dictionary=raw.duplicate(true);bad_chunk.chunks[bad_chunk.chunks.keys()[0]].cells[0]=12345
		var prepared:Dictionary=Factory.prepare_region_draft(world,bad_chunk,world.get_revision())
		var rejected:Dictionary=world.prepare_changes(prepared.world_changes,world.get_revision()) if prepared.ok else prepared
		check("final sole authority rejects unknown worker material "+str(seed),not rejected.ok)
		var frozen:Dictionary=world.snapshot();var encoded:Dictionary=Codec.encode_checkpoint(frozen,{},"r34:profiles:"+str(seed))
		var decoded:Dictionary=Codec.decode_checkpoint(encoded.envelope) if encoded.ok else encoded
		var cold:=State.new();var loaded:Dictionary=cold.load_snapshot(decoded.state) if decoded.ok else decoded
		check("native cold restore retains exact pinned profiles and cells "+str(seed),loaded.ok and Data.json_equal(cold.extension(Factory.CONFIG_KEY),world.extension(Factory.CONFIG_KEY)) and raster_digest(cold.snapshot())==raster_digest(frozen))
		costs[str(seed)]={"total_generate_and_checks_ms":(Time.get_ticks_usec()-start)/1000.0,"initial_regions":2,"expanded_regions":world.regions().size(),"module_sources":total_seeds,"raster_sha256":raster_digest(world.snapshot())}
		signatures.append(raster_digest(world.snapshot()))
		var args:=OS.get_cmdline_user_args()
		if not args.is_empty():FileAccess.open(args[0].get_base_dir()+"/seed%d-module-aware.var"%seed,FileAccess.WRITE).store_var(world.snapshot())
	check("real profile-world seeds vary",signatures.size()==2 and signatures[0]!=signatures[1])
	finish()
