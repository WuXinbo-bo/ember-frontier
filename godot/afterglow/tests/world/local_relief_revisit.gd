extends "res://tests/world/local_relief_candidate.gd"

func run()->void:
	var args:=OS.get_cmdline_user_args();var profiles:Array=Building.generation_profiles()
	var source:Dictionary=FileAccess.open(args[1]+"/seed12-v7-source.var",FileAccess.READ).get_var()
	for seed:int in [12,713]:
		var original:Dictionary=FileAccess.open(args[1]+"/seed%d-v7-source.var"%seed,FileAccess.READ).get_var()
		check("same seed version exact full source repeat "+str(seed),var_to_bytes(original)==var_to_bytes(model_world(seed,profiles,Relief.MODEL)))
	var world:=State.new();world.load_snapshot(source)
	var east:Dictionary=add_region(world,Vector2i(1,0),profiles)
	var west:Dictionary=add_region(world,Vector2i(-1,0),profiles)
	check("actual detached worker and current CAS commit positive negative peripheral regions",east.ok and west.ok,east.get("reason",west.get("reason")))
	if not east.ok or not west.ok:return finish()
	var reverse:=State.new();reverse.load_snapshot(source)
	var first:Dictionary=add_region(reverse,Vector2i(-1,0),profiles)
	var second:Dictionary=add_region(reverse,Vector2i(1,0),profiles)
	check("opposite request order exact plans cells and resource IDs",first.ok and second.ok and signature(world,"R2:1:0")==signature(reverse,"R2:1:0") and signature(world,"R2:-1:0")==signature(reverse,"R2:-1:0"))
	var seam:=0.0;var diagonal:=0.0
	for edge:float in [0,64]:
		for z in 128:
			var wz:float=(z+0.5)*0.5
			seam=maxf(seam,absf(world.surface_height(edge-0.25,wz)-world.surface_height(edge+0.25,wz)))
	for x in 128:seam=maxf(seam,absf(world.surface_height((x+0.5)*0.5,-0.25)-world.surface_height((x+0.5)*0.5,0.25)))
	var rows:Array=[]
	for id:String in ["RH-HOME","RH-VILLAGE","R2:1:0","R2:-1:0"]:
		var region:Dictionary=world.region(id);var plan:Dictionary=world.extension("generation:"+id)
		for z in range(1,128):
			for x in range(1,128):
				var wx:float=region.bounds.min.x+x*0.5;var wz:float=region.bounds.min.z+z*0.5
				var hs:Array=[]
				for dx:float in [-0.25,0.25]:
					for dz:float in [-0.25,0.25]:hs.append(world.surface_height(wx+dx,wz+dz))
				diagonal=maxf(diagonal,float(hs.max())-float(hs.min()))
		var m:Dictionary=metrics(world,id);m.erase("heights")
		rows.append({"region":id,"metrics":m,"content":content(plan),"signature":signature(world,id)})
	check("all real seams and diagonal four-column corners at most half a metre",seam<=0.5 and diagonal<=0.5,{"max_seam_m":seam,"max_corner_m":diagonal})
	costs.regions=rows
	# Complete production A/B assembly of the actual expanded same world.
	var assembled:Dictionary=Assembly.prepare(world.snapshot())
	check("complete formal assembly accepts real four-region v7 world",assembled.ok,assembled.get("reason"))
	if not assembled.ok:return finish()
	world=State.new();world.load_snapshot(assembled.capture.world)
	var runtime:=Runtime.new();var building:=Building.new()
	check("expanded native world configures original facts and clock",runtime.configure({"world":world,"facts":assembled.capture.facts,"services":{"buildings":building,"actions":Actions.new(),"production":Production.new(),"terrain":Terrain.new()}}).ok)
	walk_paths(world,building,"actual expanded v7")
	await labor_and_restore(world,runtime.facts(),profiles)
	costs.scope="v7 exact reproduction, +/- peripheral worker/CAS and opposite-order identities, all four-region corners, production expanded assembly, real labor/edit/collision/codec. Labor inherits explicit isolated test tools; not natural survival, app, VA or performance qualification."
	finish()
