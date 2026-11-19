extends "res://tests/buildings/domain_suite.gd"
## Explicit isolated build-site fixtures: six recipes, four rotations, four
## actual voxel elevations. Real C world/validator/commit, not mapgen/VA claims.
const Data=preload("res://scripts/world/world_data.gd")

func site(profile:Dictionary,turn:int,elevation:float)->Dictionary:
	var source:Dictionary=Generator.generate(713)
	source.worldId="bbb-family-matrix:"+profile.id+":"+str(turn);source.generatorVersion="rural-2"
	source.entities={};source.extensions={}
	for key:String in source.chunks:
		var chunk:Dictionary=source.chunks[key];chunk.generatorVersion="rural-2"
		var cells:=PackedInt32Array();cells.resize(4096)
		for ly in 16:
			var height:float=(int(chunk.coord.y)*16+ly+1)*0.5
			if height>elevation:continue
			for z in 16:
				for x in 16:cells[x+16*(z+16*ly)]=2
		chunk.cells=cells
	var parcel:Dictionary={"id":"matrix:"+profile.id,"profile_id":profile.id,"recipe_id":profile.id,"origin":{"x":30.0,"y":elevation,"z":30.0},"quarter_turn":turn,"site_id":"home"}
	source.extensions["generation:RH-HOME"]={"schema":"afterglow-settlement-plan-v1","version":"rural-2","parcels":[parcel],"slots":[],"anchors":{}}
	return source

func rotated(p:Array,turn:int,elevation:float)->Dictionary:
	var at:=Vector3(30,elevation,30)+Geometry.rotate(Vector3(p[0],p[1],p[2]),turn)
	return {"x":at.x,"y":at.y,"z":at.z,"regionId":"RH-HOME","buildingId":null,"storeyId":null}

func profiles_to_check()->Array:
	return Building.generation_profiles()

func run()->void:
	var started:=Time.get_ticks_msec()
	for profile:Dictionary in profiles_to_check():
		for turn in 4:
			var elevation:float=[-0.5,0.5,2.0,4.5][turn]
			var label:String=profile.id+" q"+str(turn)+" y"+str(elevation)
			print("ACTUAL_FAMILY_START "+label)
			world=World.new();building=Building.new();actions=Actions.new();production=Production.new();runtime=Runtime.new()
			var loaded:Dictionary=world.load_snapshot(site(profile,turn,elevation))
			expect(label+" real isolated voxel site loads",loaded.ok,loaded.get("reason"))
			if not loaded.ok:continue
			initialize_at({"x":56,"y":elevation,"z":56,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
			var prepared:Dictionary=building.prepare_generation(world)
			expect(label+" real recipe preparation",prepared.ok,prepared.get("reason"))
			if not prepared.ok:continue
			var facts:=runtime.facts();facts.stocks=prepared.initial_stocks
			var state:Dictionary=Production.empty_state();state.tools=prepared.initial_tools;state.records=prepared.initial_records
			var changes:Array=prepared.world_changes.duplicate(true);changes.append(building.extension_change(Production.KEY,state))
			var draft:Dictionary=world.prepare_changes(changes,world.get_revision())
			expect(label+" authoritative C draft preparation",draft.ok,draft.get("reason"))
			if not draft.ok:continue
			# A resident in each physically distinct structural room exercises ALL
			# exits, not just support of an empty decorative shell.
			var query:RefCounted=building.space(draft.view)
			var rooms:=preload("res://scripts/presentation/interior_room_projection.gd").new();rooms.configure(query)
			var known:Dictionary={}
			for roof:Dictionary in rooms.roofs:
				var feet:Dictionary=query.standing_point(rooms.room_point(roof))
				if feet.is_empty() or feet.get("buildingId")==null:continue
				var component:int=rooms.component_at(feet)
				if known.has(component):continue
				known[component]=true;facts.actors.append(resident("room:"+str(component),feet))
			var safe:Dictionary=building.validate_world_draft(draft.view,facts,changes)
			expect(label+" every solid support resident and exit validates",safe.ok,{"reason":safe.get("reason"),"rooms":known.size(),"structures":query.pieces.size()})
			if not safe.ok:continue
			expect(label+" sole world commits exact accepted capability",world.commit_prepared(draft.capability).ok)
			expect(label+" actual runtime restores finite stocks and residents",runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
			var wrong:Array=[];var homes:=0
			for piece:Dictionary in building.structures().instances:
				if piece.get("buildingId")!=null:
					homes+=1
					var expected:float=elevation+(3.4 if building.geometry.definition(piece).kind=="roof" else 0.0)
					if absf(piece.position.y-expected)>0.00001:wrong.append(piece.id)
			expect(label+" all actual transformed solids retain real base height",wrong.is_empty() and homes>20,wrong)
			var door_errors:Array=[]
			for piece:Dictionary in building.structures().instances:
				if not piece.has("door"):continue
				var request:Dictionary={"actor_id":"player","target_id":piece.id,"payload":{"operation":"open"}}
				var d:Dictionary={"ok":false,"reason":"no physical use point"}
				# prepare_door also enforces actor reach; use exact real use point,
				# not a bypass or a different implementation of sweep validation.
				var opened:=false
				for point:Dictionary in building.use_points(piece.id):
					var feet:Dictionary=building.current_space().standing_point(point)
					if feet.is_empty():continue
					var staged:=runtime.facts();staged.actors=staged.actors.filter(func(a:Dictionary)->bool:return a.id!="player")
					staged.actors.append(resident("player",feet))
					runtime.configure({"world":world,"facts":staged,"services":{"buildings":building,"actions":actions,"production":production}})
					d=building.prepare_door(request,{},staged)
					if d.ok:opened=true;break
				if not opened:door_errors.append({"id":piece.id,"reason":d.get("reason")})
			expect(label+" every actual door retains safe reachable sweep",door_errors.is_empty(),door_errors)
			var original:=world.snapshot();var repeated:Dictionary=building.prepare_generation(world)
			expect(label+" repeat cannot regenerate or restock",not repeated.ok and repeated.code=="ALREADY_SEEDED" and Data.json_equal(original,world.snapshot()))
	finish(started)
