extends "res://tests/world/local_hills_candidate.gd"
const Layout=preload("res://scripts/world/bounded_layout.gd")

func run()->void:
	var profiles:Array=Building.generation_profiles();var rows:Array=[]
	for seed:int in [0,2026,2147483647]:
		var contract:Dictionary=Contract.fresh(profiles).contract;contract.landscape_model=Hills.MODEL;contract.layout_policy=Layout.POLICY.duplicate(true)
		var source:Dictionary=Landscape.generate(seed,profiles,contract)
		check("v6 existing bounded placement contract generates endpoint seed "+str(seed),source.has("chunks"),source.get("reason"))
		if not source.has("chunks"):continue
		var world:=State.new();world.load_snapshot(source)
		var row:Dictionary={"seed":seed,"raster_sha256":raster_digest(source),"regions":{}}
		for id:String in ["RH-HOME","RH-VILLAGE"]:
			var plan:Dictionary=world.extension("generation:"+id);var m:Dictionary=metrics(world,id);m.erase("heights")
			row.regions[id]={"metrics":m,"content":content(plan),"layout_choices":plan.parcels.map(func(p:Dictionary)->Dictionary:return {"id":p.id,"choice":p.layout_choice})}
			check("existing bounded pads do not break wide half-metre terrain "+str(seed)+id,m.axis_treads_lt2m==0 and m.single_columns==0 and m.max_axis_neighbor_step_m<=0.5 and m.max_y-m.min_y>=1.5,m)
		var assembled:Dictionary=Assembly.prepare(source)
		check("complete actual A B assembly with bounded placement "+str(seed),assembled.ok,assembled.get("reason"))
		if not assembled.ok:rows.append(row);continue
		var native:=Native.new();var built:Dictionary=native._assemble(assembled.capture);native.free()
		check("same formal Native complete offline safety with bounded placement "+str(seed),built.ok,built.get("reason"))
		if built.ok:walk_paths(built.world,built.services.buildings,"v6 existing bounded policy "+str(seed))
		rows.append(row)
	costs.rows=rows;costs.scope="Only existing opt-in bounded placement/v6 interoperability at endpoint and ordinary seeds, complete current A B/Native safety and body paths. No new policy/default/build/app/VA or broad all-seeds claim."
	finish()
