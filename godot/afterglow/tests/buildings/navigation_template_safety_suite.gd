extends "res://tests/buildings/exit_proof_suite.gd"
## Specific counterexamples for candidate-point reuse, against the unchanged
## navigation algorithm in the same real immutable city/permission projection.
const ActualSpace=preload("res://scripts/buildings/building_space.gd")
const Candidate=preload("res://scripts/buildings/building_navigation.gd")
const OriginalNav=preload("res://tests/buildings/pre_template_reference/building_navigation.gd")

func compare(q:RefCounted,id:String,from:Dictionary,to:Dictionary,label:String)->void:
	var candidate:Dictionary=Candidate.new().plan(q,id,from,to)
	var original:Dictionary=OriginalNav.new().plan(q,id,from,to)
	expect(label,candidate.ok==original.ok and candidate.get("steps",[])==original.get("steps",[]),{"candidate":candidate,"original":original,"template_count":q.navigation_templates.size()})

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var source:String=FileAccess.get_file_as_string(args[0]);var decoded:Dictionary=Codec.decode_checkpoint(source)
	var imported:Dictionary=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	var w:=World.new();w.load_snapshot(imported.world)
	var b:=Building.new();var r:=Runtime.new()
	expect("actual complete city and five actors configure",r.configure({"world":w,"facts":imported.facts,"services":{"buildings":b}}).ok)
	var before:Dictionary=r.capture_checkpoint();var total_hits:=0;var scenarios:=0
	for a:Dictionary in r.facts().actors:
		var from:=Geometry.location(a)
		if from.buildingId==null:continue
		for slot:Dictionary in w.extension("generation:"+str(from.regionId)).get("slots",[]):
			if slot.get("kind")!="entrance" or slot.get("buildingId")!=from.buildingId:continue
			var to:=Geometry.location(slot);to.buildingId=null;to.storeyId=null
			var ground:Variant=w.surface_height(to.x,to.z)
			if ground!=null:to.y=float(ground)
			var q:=ActualSpace.new()
			allowed=true
			q.configure(w,b.structures(),b.geometry,func(_id:String,_target:String,_kind:String,_piece:Dictionary)->Variant:return null if allowed else "explicit current permission withdrawal")
			compare(q,str(a.id),from,to,"cold exact original topology "+a.id)
			for delta:Vector2 in [Vector2(0.007,0),Vector2(0,-0.007)]:
				var moved:=from.duplicate(true);moved.x+=delta.x;moved.z+=delta.y
				var feet:Dictionary=q.standing_point(moved)
				if not feet.is_empty():compare(q,str(a.id),feet,to,"distinct start reuses no actor proof "+a.id+str(delta))
			allowed=false
			compare(q,"other-current-actor",from,to,"withdrawn other actor permission rechecked "+a.id)
			allowed=true
			var damaged:Dictionary=Candidate.new().plan(q,str(a.id),from,to)
			if not damaged.get("steps",[]).is_empty():
				for step:Dictionary in damaged.steps:
					if step.kind=="move":step.to.x+=100;break
			compare(q,str(a.id),from,to,"returned route cannot poison saved candidate points "+a.id)
			expect("no stateful or authorization object enters template "+a.id,q.navigation_templates.values().all(func(value:Dictionary)->bool:return value.has_all(["points","flights"]) and value.keys().size()==2))
			total_hits+=q.navigation_templates.size();scenarios+=1
			# Real door-state child must never inherit these candidate positions.
			var data:Dictionary=b.structures();var selected:Dictionary={}
			for piece:Dictionary in data.instances:
				if piece.has("door") and piece.get("buildingId")==from.buildingId:piece.door.open=not piece.door.open;piece.version+=1;selected=piece;break
			if not selected.is_empty():
				var child:RefCounted=DoorProjection.project(q,data,selected,q.permission)
				expect("door projection never copies navigation template "+a.id,not child.get_script().get_script_property_list().any(func(property:Dictionary)->bool:return property.name=="navigation_templates") or child.get("navigation_templates").is_empty())
			var fresh:=ActualSpace.new();fresh.configure(w,b.structures(),b.geometry,q.permission)
			expect("new terrain or geometry projection starts without template "+a.id,fresh.navigation_templates.is_empty())
	expect("all four real indoor actors exercised actual template hits",scenarios==4 and total_hits>=1,{"actors":scenarios,"hits":total_hits})
	expect("counterexamples preserve exact world facts and source bytes",r.capture_checkpoint()==before and FileAccess.get_file_as_string(args[0])==source)
	print(JSON.stringify({"ok":not failed,"checks":checks,"scope":"production candidate-point reuse; real city routes, moved starts, permission withdrawal, result mutation and child isolation; not production or P0 qualification"}))
	quit(1 if failed else 0)
