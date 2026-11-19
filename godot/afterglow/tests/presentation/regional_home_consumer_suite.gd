extends "res://tests/buildings/domain_suite.gd"
## Real catalog/Shape metadata and original BuildingView disclosure path.
## Finite geometric observations, not paid construction or player routes.
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Housing=preload("res://scripts/modules/module_housing.gd")
const View=preload("res://scripts/buildings/building_view.gd")
const Policy=preload("res://scripts/presentation/interior_view_policy.gd")
const Data=preload("res://scripts/world/world_data.gd")
var observations:Array=[]
func run()->void:
	expect("actual finite world loads",world.load_snapshot(Generator.generate(713)).ok)
	initialize_at({"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var view:=View.new();root.add_child(view);view.set_process(false);view.configure({"service":building,"runtime":runtime})
	var before:Dictionary=runtime.capture_checkpoint();var homes:int=0
	for d:Dictionary in Catalog.definitions():
		if not Housing.applies(d):continue
		homes+=1
		for q:int in 4:
			var instance:Dictionary={"id":"D:finite:"+str(d.id),"region":"RH-HOME","position":{"x":30,"y":0,"z":43},"quarter_turn":q,"geometry_version":d.geometry_version,"owner":"player"}
			var entities:Array=Shape.entities(instance,d);var room_map:Dictionary={};var bed_count:int=0
			for e:Dictionary in entities:
				if e.data.get("module_room") is Dictionary:room_map[e.data.module_room.room_id]=e.data.module_room
				if e.data.get("module_bed") is Dictionary:bed_count+=1
			expect("actual new house emits room metadata and real beds "+str([d.id,q]),not room_map.is_empty() and bed_count>0,{"rooms":room_map.size(),"beds":bed_count,"design_beds":d.mechanism.beds})
			for room:Dictionary in room_map.values():
				var center:Vector3=Geometry.aabb(room.bounds).get_center();center.y=Geometry.aabb(room.bounds).position.y
				var player:Dictionary=Geometry.json_point(center).merged({"regionId":"RH-HOME","buildingId":null,"storeyId":null})
				var policy:=Policy.new();policy.configure(building.current_space());policy.sample(player,0);view._view_policy=policy
				var roofs:int=0;var near_walls:int=0;var back_walls:int=0;var unexpected:Array=[];var disclosed_nonresident:Array=[]
				for e:Dictionary in entities:
					if not e.data.get("module_part") is Dictionary:continue
					var meta:Dictionary=e.data.get("module_room",{});var cut:bool=false
					if meta.get("room_id")==room.room_id:
						var n:=Vector2(float(meta.normal.x),float(meta.normal.z))
						cut=meta.role=="roof" or n.dot(Vector2(1,1).normalized())>.05
						if meta.role=="roof":roofs+=1
						elif meta.role=="wall":
							if cut:near_walls+=1
							else:back_walls+=1
					if view.visible_shell(e,player)==cut:unexpected.append(e.id)
					if not _denies_nonresident(view,e,player):disclosed_nonresident.append(e.id)
				expect("original consumer still denies every nonresident part "+str([d.id,q,room.room_id]),disclosed_nonresident.is_empty(),disclosed_nonresident)
				expect("actual B home cutaway reaches original consumer "+str([d.id,q,room.room_id]),unexpected.is_empty() and roofs>0 and near_walls>0 and back_walls>0,{"unexpected":unexpected,"roofs":roofs,"near_walls":near_walls,"back_walls":back_walls})
				# Leave ALL actual rooms. The first test's arbitrary +10m from a
				# U-wing landed inside its opposite wing in two orientations.
				var outside:Dictionary=player.duplicate(true)
				var old_candidate:Dictionary=outside.duplicate(true);old_candidate.x=float(room.bounds.max.x)+10
				var old_candidate_rooms:Array=[]
				for other:Dictionary in room_map.values():
					outside.x=maxf(float(outside.x),float(other.bounds.max.x)+1)
					if Data.contains(other.bounds,old_candidate):old_candidate_rooms.append(other.room_id)
				policy.sample(outside,10);policy.sample(outside,160)
				expect("stationary doorway exit restores actual home shell "+str([d.id,q,room.room_id]),entities.filter(func(e:Dictionary)->bool:return e.data.get("module_part") is Dictionary).all(func(e:Dictionary)->bool:return view.visible_shell(e,outside)))
				observations.append({"home":d.id,"q":q,"room":room.room_id,"roofs":roofs,"near_walls":near_walls,"back_walls":back_walls,"part_count":entities.size(),"bed_count":bed_count,"outside_all_rooms":outside,"old_candidate_inside_rooms":old_candidate_rooms})
	expect("all nine exact mechanism2 homes covered",homes==9,homes)
	expect("actual view and policy do not mutate world facts or inventory",Data.json_equal(before,runtime.capture_checkpoint()))
	view.free();runtime.retire();await process_frame
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify({"scope":"Nine current Catalog geometry-v2 homes x four orientations: actual Shape.entities metadata, actual BuildingView.visible_shell plus resident veto and stable doorway restore. Finite geometry observations; no paid build/player route, actual GPU, PCK/OS/VA/FPS.","checks":checks,"failures":failures,"observations":observations},"\t"))
	print("DDD_REGIONAL_HOME_CONSUMER ",JSON.stringify({"checks":checks.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
func _denies_nonresident(view:Node3D,e:Dictionary,player:Dictionary)->bool:
	view._residency["RH-HOME"]=false
	var denied:bool=not view.visible_shell(e,player)
	view._residency["RH-HOME"]=true
	return denied
