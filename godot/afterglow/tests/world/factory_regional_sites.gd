extends "res://tests/world/factory_joint.gd"

func run()->void:
	var profiles:Array=Modules.generation_profiles();var saved_sites:Array=[]
	var legacy:Dictionary=Contract.fresh(profiles,1)
	check("old content contract retains exact missing-field form",legacy.ok and not legacy.contract.has("content_version") and Contract.resolve(legacy.contract,profiles).ok)
	var old:Dictionary=Factory.generate(713,profiles,legacy.contract)
	check("old generated world remains without retroactive site or content fields",old.has("chunks") and not old.extensions["generation:RH-VILLAGE"].has("regional_sites") and not old.extensions["generation:RH-VILLAGE"].has("generation_content_version"))
	var legacy_state:=State.new();var valid:Dictionary=legacy_state.load_snapshot(old)
	var old_worker:Dictionary=Factory.draft_region_request(Factory.region_generation_input(legacy_state,profiles),Vector2i(1,-1))
	check("old unexplored request keeps its original pinned content policy",valid.ok and old_worker.ok and not old_worker.plan.has("regional_sites"))
	for seed:int in [713,2026,17,999]:
		var source:Dictionary=Factory.generate(seed,profiles)
		check("new actual world accepts finite regional site "+str(seed),source.has("chunks"),source.get("reason"))
		if not source.has("chunks"):return finish()
		var world:=State.new();valid=world.load_snapshot(source)
		check("sole authority accepts new site cells "+str(seed),valid.ok,valid)
		if not valid.ok:return finish()
		var plan:Dictionary=world.extension("generation:RH-VILLAGE")
		check("new content version2 stores only one actual event site "+str(seed),plan.generation_content_version==2 and plan.regional_sites.size()==1 and world.extension("generation:RH-HOME").regional_sites.is_empty())
		var site:Dictionary=plan.regional_sites[0];saved_sites.append(site)
		var query:=Space.new();query.configure(world,{"instances":[]},Geometry.new(),func(_a:Variant,_b:Variant,_c:Variant,_d:Variant)->Variant:return null)
		var references:bool=site.obstacle_cells.size()==24
		for cell:Dictionary in site.obstacle_cells:references=references and world.cell_at(cell.x,cell.y,cell.z)==3 and cell.clear_material==0
		for cell:Dictionary in site.goal_corridor.base_cells:references=references and world.cell_at(cell.x,cell.y,cell.z)==4
		check("persisted obstacle refs are actual stone above original road "+str(seed),references,{"cells":site.obstacle_cells.size(),"site":site.id})
		var points:Array=[site.survey_point,site.goal_corridor.approach_before,site.goal_corridor.approach_after]+site.encounter_positions
		var supported:bool=true
		for at:Dictionary in points:supported=supported and world.region_at(at).get("id")==site.region_id and not query.standing_point(at).is_empty()
		check("survey warning and three encounter points have real body support "+str(seed),supported and site.encounter_positions.size()==3,points)
		var before:Dictionary=site.goal_corridor.approach_before;var after:Dictionary=site.goal_corridor.approach_after
		var direct:Dictionary=query.walk("player",before,after)
		check("actual one-metre roadfall blocks straight loaded route "+str(seed),not direct.ok,direct)
		var bypass:Dictionary=query.route("player",before,after)
		check("actual terrain permits a walking bypass before clearing "+str(seed),bypass.ok,bypass.get("reason"))
		var changes:Array=[]
		for cell:Dictionary in site.obstacle_cells:changes.append({"op":"voxel.set","cell":{"x":cell.x,"y":cell.y,"z":cell.z},"before":3,"after":0})
		var tx:Dictionary=world.prepare_changes(changes,world.get_revision())
		if tx.ok:world.commit_prepared(tx.capability)
		query=Space.new();query.configure(world,{"instances":[]},Geometry.new(),func(_a:Variant,_b:Variant,_c:Variant,_d:Variant)->Variant:return null)
		check("actual cleared cells reopen original road without synthetic reward "+str(seed),tx.ok and query.walk("player",before,after).ok)
		var direction:Vector3=(Geometry.point(after)-Geometry.point(before)).normalized();var cross:=Vector3(-direction.z,0,direction.x)
		var width_ok:bool=true
		for side:float in [-0.6,0,0.6]:
			var a:Dictionary=before.duplicate(true);a.x+=cross.x*side;a.z+=cross.z*side
			var b:Dictionary=after.duplicate(true);b.x+=cross.x*side;b.z+=cross.z*side
			width_ok=width_ok and query.walk("player",a,b).ok
		check("cleared real corridor supports over one metre usable body width "+str(seed),width_ok)
		var encoded:Dictionary=Codec.encode_checkpoint(world.snapshot(),{},"r34:site:"+str(seed))
		var decoded:Dictionary=Codec.decode_checkpoint(encoded.envelope) if encoded.ok else encoded
		var cold:=State.new();valid=cold.load_snapshot(decoded.state) if decoded.ok else decoded
		check("cleared site and stable refs persist exactly after cold restore "+str(seed),valid.ok and raster_digest(cold.snapshot())==raster_digest(world.snapshot()) and Data.json_equal(cold.extension("generation:RH-VILLAGE").regional_sites,plan.regional_sites))
		var revisit:Dictionary=Factory.prepare_region_draft(cold,Factory.draft_region_request(Factory.region_generation_input(cold,profiles),Vector2i(0,-1)),cold.get_revision())
		check("site revisit never reinstates removed stones "+str(seed),revisit.ok and revisit.already_generated and revisit.world_changes.is_empty() and revisit.initial_stocks.is_empty())
		costs[str(seed)]={"site":site,"bypass_steps":bypass.get("steps",[]).size(),"removed_stone_m3":site.obstacle_cells.size()*0.125}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0].get_base_dir()+"/actual-regional-sites.json",FileAccess.WRITE).store_string(JSON.stringify(saved_sites,"\t",true,true))
	finish()
