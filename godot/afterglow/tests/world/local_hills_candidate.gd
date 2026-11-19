extends "res://tests/world/broad_terraces_candidate.gd"
const Hills=preload("res://scripts/world/local_hills.gd")

func content(plan:Dictionary)->Dictionary:
	var species:Dictionary={}
	for tree:Dictionary in plan.resource_sites:
		var key:String=str(tree.appearance.model)
		species[key]=int(species.get(key,0))+1
	return {"trees":plan.resource_sites.size(),"species":species,"patches":plan.ecology.patches.size(),"fields":plan.landforms.filter(func(l:Dictionary)->bool:return l.use=="field").size(),"dressing":plan.dressing.size()}

func run()->void:
	var args:=OS.get_cmdline_user_args();var folder:String=args[0].get_base_dir()
	var profiles:Array=Building.generation_profiles()
	var input:Dictionary=Contract.fresh(profiles);input.contract.landscape_model=Hills.MODEL
	check("explicit v6 only and unchanged fresh default",Contract.resolve(input.contract,profiles).ok and Contract.fresh(profiles).contract.landscape_model=="village-contours-v4")
	var rows:Array=[]
	for seed:int in [12,713]:
		var started:=Time.get_ticks_usec();var source:Dictionary=Landscape.generate(seed,profiles,input.contract)
		var row:Dictionary={"seed":seed,"generate_ms":(Time.get_ticks_usec()-started)/1000.0,"regions":{}}
		check("actual complete v6 world generates "+str(seed),source.has("chunks"),source.get("reason"))
		if not source.has("chunks"):rows.append(row);continue
		FileAccess.open(folder+"/seed%d-v6-source.var"%seed,FileAccess.WRITE).store_var(source)
		row.raster_sha256=raster_digest(source)
		var world:=State.new();check("v6 sole authority accepts source "+str(seed),world.load_snapshot(source).ok)
		for id:String in ["RH-HOME","RH-VILLAGE"]:
			var m:Dictionary=metrics(world,id);m.erase("heights")
			var plan:Dictionary=world.extension("generation:"+id)
			row.regions[id]={"metrics":m,"content":content(plan),"natural_surface":plan.height.natural_surface.duplicate(true),"pads":plan.parcels.map(func(p:Dictionary)->Dictionary:return {"id":p.id,"pad":p.pad,"entrance_ports":p.entrance_ports})}
			row.regions[id].natural_surface.erase("height_half_metres")
			check("real v6 remains nonflat wide and safe "+str(seed)+id,m.max_y-m.min_y>=1.5 and m.single_columns==0 and m.axis_treads_lt2m==0 and m.max_axis_neighbor_step_m<=0.5,m)
			check("pad intervention is strictly finite "+str(seed)+id,plan.height.natural_surface.pad_altered_beyond_limit==0)
			var roots_ok:=true;var cards_ok:=true
			for tree:Dictionary in plan.resource_sites:
				for dx:float in [-0.35,0,0.35]:
					for dz:float in [-0.35,0,0.35]:roots_ok=roots_ok and world.surface_height(tree.position.x+dx,tree.position.z+dz)==tree.position.y
			for patch:Dictionary in plan.ecology.patches:
				for dx:float in [-float(patch.footprint[0])*0.5,float(patch.footprint[0])*0.5]:
					for dz:float in [-float(patch.footprint[1])*0.5,float(patch.footprint[1])*0.5]:cards_ok=cards_ok and world.surface_height(patch.position.x+dx,patch.position.z+dz)==patch.position.y
			check("real resource roots and full ground cards touch actual cells "+str(seed)+id,roots_ok and cards_ok,{"roots":roots_ok,"cards":cards_ok})
		started=Time.get_ticks_usec();var assembled:Dictionary=Assembly.prepare(source)
		row.assembly_ms=(Time.get_ticks_usec()-started)/1000.0
		check("complete production A B assembly accepts v6 "+str(seed),assembled.ok,assembled.get("reason"))
		if not assembled.ok:rows.append(row);continue
		world=State.new();world.load_snapshot(assembled.capture.world)
		var runtime:=Runtime.new();var building:=Building.new()
		var configured:Dictionary=runtime.configure({"world":world,"facts":assembled.capture.facts,"source":assembled.capture.source,"services":{"buildings":building,"production":Production.new(),"actions":Actions.new(),"terrain":Terrain.new()}})
		check("production runtime accepts true opening actors "+str(seed),configured.ok,configured)
		if not configured.ok:rows.append(row);continue
		var encoded:Dictionary=Store.encode(runtime.capture_checkpoint())
		check("native capture encodes without a live slot "+str(seed),encoded.ok,encoded.get("reason"))
		if encoded.ok:
			FileAccess.open(folder+"/seed%d-v6.native.json"%seed,FileAccess.WRITE).store_string(encoded.text)
			var decoded:Dictionary=Store.decode(encoded.text);var native:=Native.new()
			var restored:Dictionary=native._assemble(decoded.capture) if decoded.ok else decoded
			check("actual Native offline standing and structure safety "+str(seed),restored.ok,restored.get("reason"))
			native.free()
		walk_paths(world,building,"v6 "+str(seed))
		# Only this separate bounded route fixture moves the actor to arrival.
		# Captures above preserve original opening facts/time/inventory.
		var facts:Dictionary=assembled.capture.facts.duplicate(true)
		var at:Dictionary=actor_at(world.extension("generation:RH-HOME").anchors.arrival)
		for a:Dictionary in facts.actors:
			if a.id=="player":a.merge({"x":at.x,"y":at.y,"z":at.z,"regionId":"RH-HOME","buildingId":null,"storeyId":null},true)
		runtime=Runtime.new();building=Building.new()
		check("isolated arrival route fixture configures "+str(seed),runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"production":Production.new(),"actions":Actions.new()}}).ok)
		row.route=walk_home_to_village(runtime,world)
		check("real runtime home village traversal "+str(seed),row.route.ok,row.route)
		rows.append(row)
	costs.rows=rows
	costs.scope="v6 new-world-only generation and production assembly candidate; no formal app/Metal/VA/performance qualification. Captures precede isolated route fixtures."
	finish()
