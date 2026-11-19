extends "res://tests/buildings/legacy_suite.gd"
## Independent full Space.configure oracle, exact ordered static/dynamic
## projections, and adversarial gates. No frame-rate or application claim.
const DoorProjection=preload("res://scripts/buildings/building_door_projection.gd")
const DOOR="world:713:region:0:0:convenience-store:piece:34"

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var raw:=FileAccess.get_file_as_string(args[0]);var decoded:Dictionary=Codec.decode_checkpoint(raw)
	var imported:Dictionary=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	var world:=World.new();expect("exact preserved city loads",world.load_snapshot(imported.world).ok)
	var b:=Building.new();var runtime:=Runtime.new()
	expect("all original source actors configure",runtime.configure({"world":world,"facts":imported.facts,"services":{"buildings":b,"actions":Actions.new(),"production":Production.new()}}).ok)
	var base:RefCounted=b.current_space();var old:Dictionary=base.state.duplicate(true)
	var door:Dictionary=base.by_id[DOOR]
	var witness:Dictionary={}
	for piece:Dictionary in base.pieces:b.supported(base,piece,{},witness)
	var original_world:=world.snapshot();var original_facts:=runtime.facts()
	var source_colliders:Array=base.colliders.duplicate(true);var source_buckets:Dictionary=base.buckets.duplicate(true)
	var source_support:Dictionary=base.support_wall_index.duplicate(true)
	for opened:bool in [false,true]:
		for swing in [-1,1]:
			for lock:bool in [false,true]:
				var data:=old.duplicate(true);var next:=door.duplicate(true)
				next.version+=1;next.door.open=opened;next.door.swing=swing;next.door.locked=lock;next.door.blocked=lock
				for i in data.instances.size():
					if data.instances[i].id==DOOR:data.instances[i]=next;break
				var changed:Dictionary=DoorProjection.changed_door(old,data)
				expect("single door recognized "+str([opened,swing,lock]),changed==next)
				var a:RefCounted=DoorProjection.project(base,data,changed,base.permission)
				var full:RefCounted=b.space(world,data)
				var mismatch:Array=[]
				for field:String in ["state","pieces","stair_pieces","by_id","colliders","buckets","piece_buckets","surface_buckets","walk_surfaces","piece_bounds","sight_boxes","solid_entities","surfaces","entity_buckets","support_wall_index","support_slab_index"]:
					if a.get(field)!=full.get(field):mismatch.append(field)
				expect("complete ordered indices equal full configure "+str([opened,swing,lock]),mismatch.is_empty(),mismatch)
				var support_errors:Array=[];var query_errors:Array=[]
				for piece:Dictionary in a.pieces:
					if b.supported(a,piece)!=b.supported(full,full.by_id[piece.id]):support_errors.append(piece.id)
					if a.support_neighbors(piece)!=full.support_neighbors(full.by_id[piece.id]):query_errors.append(piece.id)
				expect("all971 real supports and ordered neighbors equal full oracle",support_errors.is_empty() and query_errors.is_empty(),{"supports":support_errors,"neighbors":query_errors})
				var paths:Array=[]
				for actor:Dictionary in imported.facts.actors:
					var at:=Geometry.location(actor)
					if a.standing_point(at)!=full.standing_point(at):paths.append({"actor":actor.id,"kind":"standing"})
					if a.blockers(at,at,actor.id)!=full.blockers(at,at,actor.id):paths.append({"actor":actor.id,"kind":"body"})
				for point:Dictionary in a.use_points(next):
					for offset:Vector2 in [Vector2.ZERO,Vector2(0.6,0),Vector2(0,0.6),Vector2(-0.6,-0.6)]:
						var to:=point.duplicate(true);to.x+=offset.x;to.z+=offset.y
						if a.blockers(point,to,"player",true)!=full.blockers(point,to,"player",true) or a.line_clear(point,to)!=full.line_clear(point,to):paths.append({"kind":"door proximity","point":to})
				expect("all source residents and exact door LOS/body predicates equal full",paths.is_empty(),paths)
				expect("copy-on-write overlay never changes its original static projection",base.state==old and base.colliders==source_colliders and base.buckets==source_buckets and base.support_wall_index==source_support)
	# Every non-door mutation must reject the optimized eligibility gate.
	var variants:Array=[]
	for field:String in ["hp","definitionId","position","quarterTurn","owner","buildingId","storeyId"]:
		var data:=old.duplicate(true)
		for piece:Dictionary in data.instances:
			if piece.id!=DOOR:continue
			match field:
				"hp":piece.hp-=1
				"definitionId":piece.definitionId="wall"
				"position":piece.position.x+=0.5
				"quarterTurn":piece.quarterTurn=posmod(int(piece.quarterTurn)+1,4)
				"owner":piece.owner="unrelated-household"
				"buildingId":piece.buildingId="different"
				"storeyId":piece.storeyId="different"
		variants.append({"label":field,"data":data})
	var floor_data:=old.duplicate(true);floor_data.storeys[0].elevation+=0.5;variants.append({"label":"storey elevation","data":floor_data})
	var many:=old.duplicate(true);many.instances[0].version+=1;many.instances[1].version+=1;variants.append({"label":"two changed pieces","data":many})
	var removed:=old.duplicate(true);removed.instances.pop_back();variants.append({"label":"removal","data":removed})
	for variant:Dictionary in variants:expect("non-door/static edit retains full projection "+variant.label,DoorProjection.changed_door(old,variant.data).is_empty())
	expect("all tests leave original world and five actor facts unchanged",world.snapshot()==original_world and runtime.facts()==original_facts)
	print(JSON.stringify({"ok":not failed,"checks":checks,"scope":"B single-door projection vs independent full configure; all971 supports/ordered indices/5 source actors, explicit door-state fixtures; not app/FPS acceptance"}))
	quit(1 if failed else 0)
