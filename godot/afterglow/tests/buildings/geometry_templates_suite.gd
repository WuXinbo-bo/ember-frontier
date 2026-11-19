extends "res://tests/buildings/legacy_suite.gd"
const OriginalGeometry=preload("res://tests/buildings/cold_reference/building_geometry.gd")

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var raw:=FileAccess.get_file_as_string(args[0]);var decoded:=Codec.decode_checkpoint(raw)
	var imported:=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	var w:=World.new();w.load_snapshot(imported.world)
	var b:=Building.new();var r:=Runtime.new()
	expect("actual whole city and facts configure",r.configure({"world":w,"facts":imported.facts,"services":{"buildings":b}}).ok)
	var old:=OriginalGeometry.new();old.configure(b.source_catalog)
	var original:=w.snapshot();var original_facts:=r.facts();var shapes:=0;var boxes:=0;var entity_checks:=0
	for turn in 4:
		var mismatch:Array=[]
		for original_piece:Dictionary in b.structures().instances:
			for offset:Vector3 in [Vector3.ZERO,Vector3(0.123456,0.014999,-0.987654),Vector3(10000,-17.25,-10000)]:
				for hp:float in [0,1,float(original_piece.hp)]:
					var v:=original_piece.duplicate(true);v.quarterTurn=turn;v.position=Geometry.json_point(Geometry.point(v.position)+offset);v.hp=hp
					shapes+=1
					if b.geometry.bounds(v)!=old.bounds(v) and mismatch.size()<10:mismatch.append({"id":v.id,"phase":"bounds","turn":turn,"offset":str(offset)})
					for mode in ["collision","sight","room"]:
						boxes+=1
						if b.geometry.boxes(v,mode)!=old.boxes(v,mode) and mismatch.size()<10:mismatch.append({"id":v.id,"phase":mode,"turn":turn,"offset":str(offset)})
					if v.has("door"):
						for opened:bool in [false,true]:
							for swing in [-1,1]:
								v.door.open=opened;v.door.swing=swing;entity_checks+=1
								if b.geometry.entity(v)!=old.entity(v) and mismatch.size()<10:mismatch.append({"id":v.id,"phase":"door entity","open":opened,"swing":swing})
		expect("all exact ordered collision/sight/room/bounds at quarter turn "+str(turn),mismatch.is_empty(),mismatch)
	expect("all 34956 piece poses and 104868 ordered volumes checked",shapes==34956 and boxes==104868,{"poses":shapes,"volume_arrays":boxes,"door_entities":entity_checks})
	# Configure is the catalog replacement boundary, not a second authority.
	var altered:=b.source_catalog.duplicate(true);var v:Dictionary=b.structures().instances[0]
	var definition:Dictionary=altered.structure_definitions[v.definitionId]
	definition.solids[0].max.x=float(definition.solids[0].max.x)+0.012345
	var retained_bounds:=b.geometry.bounds(v);var retained_boxes:=b.geometry.boxes(v)
	b.geometry.configure(altered);old.configure(altered)
	expect("catalog physical change cannot silently rewrite archived v1 geometry",b.geometry.bounds(v)==retained_bounds and b.geometry.boxes(v)==retained_boxes and b.geometry.bounds(v)!=old.bounds(v))
	expect("configure still clears derived template entries",b.geometry.box_templates.size()==1 and b.geometry.bound_templates.size()==1)
	expect("geometry preparation never modifies preserved city or normalized runtime facts",w.snapshot()==original and r.facts()==original_facts)
	print(JSON.stringify({"ok":not failed,"checks":checks,"scope":"frozen original geometry vs type/rotation endpoint templates; exact array equality, negative/large positions, four rotations, dead/live geometry and dynamic leaves"}))
	quit(1 if failed else 0)
