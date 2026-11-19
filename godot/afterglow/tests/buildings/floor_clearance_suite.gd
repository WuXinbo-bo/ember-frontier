extends "res://tests/buildings/candidate_tokens_suite.gd"
const OriginalSpace=preload("res://tests/buildings/floor_reference/building_space.gd")

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var raw:=FileAccess.get_file_as_string(args[0]);var decoded:=Codec.decode_checkpoint(raw)
	var imported:=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	var w:=World.new();w.load_snapshot(imported.world)
	var r:=Runtime.new();var b:=Building.new()
	expect("same unchanged actual city source configures",r.configure({"world":w,"facts":imported.facts,"services":{"buildings":b}}).ok)
	var before:=w.snapshot();var rows:Array=[]
	for n in 4:
		var variants:Dictionary={}
		for name in (["original","candidate"] if n%2==0 else ["candidate","original"]):
			var q:RefCounted=OriginalSpace.new() if name=="original" else Space.new()
			q.configure(w,b.structures(),b.geometry,b.permission)
			variants[name]=measured(q,b,w,imported.facts)
			if name=="candidate":variants[name].proofs={"floor_certificates":q.floor_clearances.size()}
		expect("all complete four-resident exit routes identical iteration "+str(n),variants.original.routes==variants.candidate.routes and variants.candidate.rows.size()==4 and variants.candidate.rows.all(func(row:Dictionary)->bool:return row.ok))
		rows.append({"iteration":n,"first":"original" if n%2==0 else "candidate","original":variants.original.rows,"candidate":variants.candidate.rows,"proofs":variants.candidate.proofs})
	var old:=OriginalSpace.new();old.configure(w,b.structures(),b.geometry,b.permission)
	var next:=Space.new();next.configure(w,b.structures(),b.geometry,b.permission)
	var count:=0;var differences:Array=[]
	for piece:Dictionary in next.surfaces:
		var box:AABB=next.bounds(piece)
		for x:float in [box.position.x-0.00101,box.position.x-0.001,box.position.x,box.get_center().x,box.end.x,box.end.x+0.001,box.end.x+0.00101]:
			for z:float in [box.position.z-0.001,box.position.z,box.get_center().z,box.end.z,box.end.z+0.001]:
				for dy:float in [-0.55001,-0.55,0.0,0.55,0.55001]:
					count+=1
					var a:Dictionary=old.point_location(piece.regionId,x,z,float(piece.position.y)+dy)
					var c:Dictionary=next.point_location(piece.regionId,x,z,float(piece.position.y)+dy)
					if a!=c and differences.size()<10:differences.append({"piece":piece.id,"x":x,"z":z,"dy":dy,"original":a,"candidate":c})
	expect("all floor edge epsilon height and roof-exclusion points remain exact",count>50000 and differences.is_empty(),{"count":count,"differences":differences})
	# A partial solid entity anywhere in the superset must disable that proof.
	# An independently clear foot rectangle still succeeds via the old predicate.
	var region:="fixture:floor-certificate"
	var floor_piece:Dictionary={"id":"fixture:floor","position":{"x":0,"y":19.0,"z":0}}
	var surface:Dictionary={"piece":floor_piece,"bounds":AABB(Vector3(-0.5,18.8,-0.5),Vector3(1,0.2,1)),"elevation":19.0}
	var entity:Dictionary={"id":"fixture:thin-foot-obstacle","bounds":Geometry.json_box(AABB(Vector3(0.1,19.011,0.1),Vector3(0.15,0.008,0.15)))}
	for q:RefCounted in [old,next]:
		q.entity_buckets[region]={Vector2i.ZERO:[entity]}
	var hit:=AABB(Vector3(0.14,19.01,0.14),Vector3(0.02,0.01,0.02))
	var clear:=AABB(Vector3(0.3,19.01,0.3),Vector3(0.02,0.01,0.02))
	expect("partial solid thin entity disables whole floor proof but not a clear foot",not next.floor_terrain_clear(region,surface,hit) and next.floor_terrain_clear(region,surface,clear) and not next.floor_clearances[floor_piece.id].clear and not old.terrain_clear(region,hit) and old.terrain_clear(region,clear))
	expect("original entity exclusion remains per exact foot volume",old.terrain_clear(region,hit,entity.id) and next.terrain_clear(region,hit,entity.id) and not next.floor_terrain_clear(region,surface,hit))
	var enclosure_region:="fixture:floor-enclosure"
	var outside:Dictionary={"id":"fixture:outside-strip","bounds":Geometry.json_box(AABB(Vector3(0.78,19.011,0.1),Vector3(0.06,0.008,0.06)))}
	for q:RefCounted in [old,next]:q.entity_buckets[enclosure_region]={Vector2i.ZERO:[outside]}
	var enclosure_surface:Dictionary=surface.duplicate(true);enclosure_surface.piece.id="fixture:enclosure-floor"
	var beyond:=AABB(Vector3(0.79,19.01,0.11),Vector3(0.02,0.01,0.02))
	expect("native enclosure prevents a positive strip from covering an outside obstacle",next.floor_terrain_clear(enclosure_region,enclosure_surface,clear) and next.floor_clearances[enclosure_surface.piece.id].clear and not next.floor_terrain_clear(enclosure_region,enclosure_surface,beyond) and not old.terrain_clear(enclosure_region,beyond))
	var large_surface:Dictionary=surface.duplicate(true);large_surface.piece.id="fixture:oversized-floor";large_surface.bounds=AABB(Vector3(-64,18.8,-64),Vector3(128,0.2,128))
	expect("oversized or unknown broad strip never rejects a precise clear foot",next.floor_terrain_clear("fixture:large-floor",large_surface,clear) and not next.floor_clearances[large_surface.piece.id].clear and old.terrain_clear("fixture:large-floor",clear))
	var bounded:=Space.new();bounded.configure(w,b.structures(),b.geometry,b.permission)
	for n:int in 8193:
		var repeated:Dictionary=surface.duplicate(true);repeated.piece.id="fixture:bounded-floor:"+str(n)
		bounded.floor_terrain_clear("fixture:bounded",repeated,clear)
	expect("derived floor cache stays bounded and eviction preserves exact result",bounded.floor_clearances.size()<=8192 and bounded.floor_terrain_clear("fixture:bounded",surface,clear)==old.terrain_clear("fixture:bounded",clear),bounded.floor_clearances.size())
	expect("all floor proofs remain derived and preserve entire source authority",w.snapshot()==before and r.facts()==imported.facts)
	print(JSON.stringify({"ok":not failed,"checks":checks,"measurements":rows,"scope":"production floor-superset clearance vs raw frozen original; exact fallback and complete route identity; alternating source CPU diagnostic, not official door/PCK/FPS/VA"}))
	quit(1 if failed else 0)
