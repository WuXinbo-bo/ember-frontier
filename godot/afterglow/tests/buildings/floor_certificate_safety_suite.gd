extends "res://tests/buildings/legacy_suite.gd"
## Warm a REAL elevated floor, then use A's actual commit and C's entity/voxel
## capability. A prior clear superset must not survive a physical revision.
const Space=preload("res://scripts/buildings/building_space.gd")
const Reference=preload("res://tests/buildings/floor_reference/building_service.gd")
const Data=preload("res://scripts/world/world_data.gd")

func run()->void:
	var started:=Time.get_ticks_msec()
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var decoded:=Codec.decode_checkpoint(FileAccess.get_file_as_string(args[0]))
	var imported:=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	var fixture_world:=World.new();fixture_world.load_snapshot(imported.world)
	var fixture_runtime:=Runtime.new();var fixture_building:=Building.new()
	expect("unchanged city fixture loads",fixture_runtime.configure({"world":fixture_world,"facts":imported.facts,"services":{"buildings":fixture_building}}).ok)
	var fixture:RefCounted=fixture_building.current_space();var selected:Dictionary={}
	for piece:Dictionary in fixture.surfaces:
		if fixture_building.geometry.definition(piece).kind!="floor" or float(piece.position.y)<2.0:continue
		var p:Dictionary=Geometry.location(piece)
		if imported.facts.actors.any(func(a:Dictionary)->bool:return a.regionId==p.regionId and Geometry.point(Geometry.location(a)).distance_to(Geometry.point(p))<1.5):continue
		var sample:Dictionary=fixture.floor_sample(p.regionId,p.x,p.z,p.y)
		if sample.get("piece",{}).get("id")==piece.id and fixture.floor_clearances.get(piece.id,{}).get("clear",false):selected=piece;break
	expect("real unoccupied elevated floor has a positive enclosing terrain proof",not selected.is_empty(),selected.get("id"))
	if selected.is_empty():quit(1);return
	var at:=Geometry.location(selected)
	var outcomes:Dictionary={}
	for kind:String in ["thin entity","voxel"]:
		outcomes[kind]={}
		for name:String in ["reference","production"]:
			var w:=World.new();w.load_snapshot(imported.world)
			var r:=Runtime.new();var b:RefCounted=Reference.new() if name=="reference" else Building.new()
			expect("same complete actual runtime configures "+kind+name,r.configure({"world":w,"facts":imported.facts,"services":{"buildings":b,"actions":Actions.new(),"production":Production.new()}}).ok)
			var q:RefCounted=b.current_space()
			var initial:Dictionary=q.point_location(at.regionId,at.x,at.z,at.y)
			expect("original actual elevated foot is supported "+kind+name,initial.get("y")==at.y)
			if name=="production":expect("actual current query is positively warmed "+kind,q.floor_clearances.get(selected.id,{}).get("clear",false))
			var before:Dictionary=r.capture_checkpoint()
			var before_clock:float=r.clock()
			var changes:Array=[];var remove:Array=[]
			if kind=="thin entity":
				var e:Dictionary={"id":"fixture:floor-thin-solid","kind":"prop","regionId":at.regionId,"position":Geometry.json_point(Geometry.point(at)),"bounds":Geometry.json_box(AABB(Geometry.point(at)+Vector3(-0.03,0.012,-0.03),Vector3(0.06,0.006,0.06))),"revision":0,"data":{"solid":true}}
				changes.append({"op":"entity.put","id":e.id,"before_exists":false,"before":null,"after":e})
				remove.append({"op":"entity.remove","id":e.id,"before":e})
			else:
				var size:float=w.config().cellSize
				var cell:=Vector3i(floori(float(at.x)/size),floori((float(at.y)+0.01)/size),floori(float(at.z)/size))
				var material:int=w.cell_at(cell.x,cell.y,cell.z)
				expect("actual floor foot voxel begins as air "+name,material==0)
				changes.append({"op":"voxel.set","cell":{"x":cell.x,"y":cell.y,"z":cell.z},"before":material,"after":3})
				remove.append({"op":"voxel.set","cell":{"x":cell.x,"y":cell.y,"z":cell.z},"before":3,"after":material})
			changes.append(b.extension_change("fixture:mixed-physical",kind))
			var result:Dictionary=r._commit({"world_changes":changes,"fact_changes":[]})
			expect("physical proof counterexample is accepted by original full safety "+kind+name,result.ok,result.get("reason"))
			if not result.ok:
				expect("rejected physical attempt preserves complete authority "+kind+name,Data.json_equal(before,r.capture_checkpoint()))
				outcomes[kind][name]={"result":result,"capture":r.capture_checkpoint()}
				continue
			expect("physical revision discards both previous queries "+kind+name,b._space==null and b._validation_space==null)
			var fresh:RefCounted=b.current_space()
			var changed:Dictionary=fresh.point_location(at.regionId,at.x,at.z,at.y)
			# A new 0.5m voxel can create a legal original terrain step (here 0.2m
			# above the 3.8m slab). It must resolve that NEW terrain, not be forced
			# into a rejection that the frozen original never required.
			var exact_new_foot:bool=changed.is_empty() if kind=="thin entity" else not changed.is_empty() and changed.get("buildingId")==null and changed.get("storeyId")==null and float(changed.y)==(floori((float(at.y)+0.01)/float(w.config().cellSize))+1)*float(w.config().cellSize)
			expect("new precise foot cannot reuse old clear result "+kind+name,fresh!=q and changed!=initial and exact_new_foot,changed)
			if name=="production":expect("new floor superset is actually blocked "+kind,not fresh.floor_clearances.get(selected.id,{"clear":true}).clear)
			if kind=="thin entity":
				var adjacent:Dictionary=fresh.point_location(at.regionId,float(at.x)+0.35,float(at.z)+0.35,at.y)
				expect("blocked floor superset retains exact clear adjacent foot fallback "+name,adjacent.get("y")==at.y,adjacent)
			# C assigns the true entity revision; remove its actual committed value,
			# never the pre-CAS request copy which still has revision zero.
			if kind=="thin entity":remove[0].before=w.entity(str(remove[0].id))
			var restored:Dictionary=r._commit({"world_changes":remove,"fact_changes":[]})
			expect("real removal restores original supported foot "+kind+name,restored.ok and b.current_space()!=fresh and b.current_space().point_location(at.regionId,at.x,at.z,at.y)==initial,restored.get("reason"))
			# A normalizes explicit appearance/body profiles during configure.
			# Compare the complete normalized authority, retaining every field,
			# rather than the intentionally unnormalized source fixture.
			expect("physical checks never change people inventory tools clock "+kind+name,r.facts()==before.facts and r.clock()==before_clock)
			outcomes[kind][name]={"result":result,"changed":changed,"capture":r.capture_checkpoint()}
		expect("complete result and final authority equal frozen original "+kind,Data.json_equal(outcomes[kind].reference,outcomes[kind].production))
	print(JSON.stringify({"ok":not failed,"checks":checks,"elapsed_ms":Time.get_ticks_msec()-started,"scope":"real physical commit after warm actual floor certificate vs frozen original; not OS/PCK/FPS/VA"}))
	quit(1 if failed else 0)
