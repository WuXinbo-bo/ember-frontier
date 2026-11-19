extends "res://tests/buildings/legacy_suite.gd"
## Frozen whole-piece direct movement vs ordered stair-only candidates.
## Same world, body samples, collision/support/permission predicates and results.
const Space = preload("res://scripts/buildings/building_space.gd")
const Reference = preload("res://tests/buildings/movement_reference.gd")
const Generator = preload("res://scripts/world/rural_generator.gd")
const Assembly = preload("res://scripts/runtime/settlement_assembly.gd")
var measurements: Array = []

func compare_world(label: String, world: RefCounted, facts: Dictionary) -> void:
	var building := Building.new()
	var runtime := Runtime.new()
	expect(label + " uses actual complete services", runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":Actions.new(),"production":Production.new()}}).ok)
	var state := building.structures()
	var before := runtime.capture_checkpoint()
	var original := Reference.new()
	original.configure(world,state,building.geometry,building.permission)
	var current := Space.new()
	current.configure(world,state,building.geometry,building.permission)
	expect(label + " stair subset preserves complete original order and values", current.stair_pieces == current.pieces.filter(func(v:Dictionary)->bool:return v.has("stairs")))
	var mismatch: Array = []
	var pairs: Array = []
	var checked := 0
	for actor: Dictionary in facts.actors:
		var at := Geometry.location(actor)
		for distance: float in [0.0,0.0733333333,0.28,0.46,0.99,1.01]:
			for direction: Vector2 in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN,Vector2(-1,-1).normalized(),Vector2(1,1).normalized()]:
				var to := at.duplicate(true)
				to.x += distance*direction.x;to.z += distance*direction.y
				var a: Dictionary = original.direct_move(str(actor.id),at,to)
				var b: Dictionary = current.direct_move(str(actor.id),at,to)
				checked += 1
				if a != b and mismatch.size()<10:mismatch.append({"actor":actor.id,"from":at,"to":to,"before":a,"after":b})
				if a.ok and distance>=0.07 and distance<=0.46 and pairs.size()<12:pairs.append({"actor":actor.id,"from":at,"to":to})
	# Portal approaches and narrow margins use the real current leaf/frame.
	for piece: Dictionary in state.instances:
		if not piece.has("door"):continue
		for raw: Dictionary in original.use_points(piece):
			var at: Dictionary = original.standing_point(raw)
			if at.is_empty():continue
			for offset: Vector2 in [Vector2(0.46,0),Vector2(-0.46,0),Vector2(0,0.46),Vector2(0,-0.46)]:
				var to := at.duplicate(true);to.x+=offset.x;to.z+=offset.y
				var a: Dictionary = original.direct_move("player",at,to)
				var b: Dictionary = current.direct_move("player",at,to)
				checked+=1
				if a!=b and mismatch.size()<10:mismatch.append({"door":piece.id,"before":a,"after":b})
	expect(label + " actual actor input and door approaches are exactly unchanged", checked>100 and mismatch.is_empty(),{"samples":checked,"mismatches":mismatch})
	# An actual move pair, not stationary/no-op or geometry-free microbenchmark.
	expect(label + " has real supported movement for alternating CPU comparison",not pairs.is_empty())
	if not pairs.is_empty():
		for iteration in 3:
			var row: Dictionary = {"world":label,"iteration":iteration,"pieces":state.instances.size(),"stairs":current.stair_pieces.size(),"calls_per_variant":1200}
			for name: String in (["original","subset"] if iteration%2==0 else ["subset","original"]):
				var q: RefCounted = original if name=="original" else current
				var successful:=0;var t:=Time.get_ticks_usec()
				for n in 1200:
					var p: Dictionary=pairs[n%pairs.size()]
					var moved: Dictionary=q.direct_move(str(p.actor),p.from,p.to)
					if moved.ok:successful+=1
				row[name+"_ms"]=float(Time.get_ticks_usec()-t)/1000.0
				row[name+"_successes"]=successful
			expect(label + " alternating real movement returns identical acceptance " + str(iteration),row.original_successes==1200 and row.subset_successes==1200,row)
			measurements.append(row)
	expect(label + " never writes authority or time",runtime.capture_checkpoint()==before)

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var decoded:=Codec.decode_checkpoint(FileAccess.get_file_as_string(args[0]))
	var imported:=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	var old_world:=World.new()
	expect("preserved ordinary world loads unchanged",old_world.load_snapshot(imported.world).ok)
	compare_world("ordinary-713",old_world,imported.facts)
	for seed_value: int in [713,2026]:
		var prepared:Dictionary=Assembly.prepare(Generator.generate_settlement(seed_value,Building.generation_profiles()))
		expect("actual generated rural world prepares "+str(seed_value),prepared.ok,prepared.get("reason"))
		if not prepared.ok:continue
		var world:=World.new()
		expect("same rural snapshot loads "+str(seed_value),world.load_snapshot(prepared.capture.world).ok)
		compare_world("rural-"+str(seed_value),world,prepared.capture.facts)
	print(JSON.stringify({"ok":not failed,"scope":"BBB identical native direct-movement predicates and alternating warm command CPU, not cold door, OS/FPS or visual qualification","checks":checks,"measurements":measurements}))
	quit(1 if failed else 0)
