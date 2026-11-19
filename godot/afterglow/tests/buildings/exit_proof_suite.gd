extends "res://tests/buildings/legacy_suite.gd"
const Reference=preload("res://tests/buildings/exit_reference_service.gd")
const Space=preload("res://scripts/buildings/building_space.gd")
const DoorProjection=preload("res://scripts/buildings/building_door_projection.gd")
class CountedSpace extends "res://scripts/buildings/building_space.gd":
	var routes:=0
	func route(id:String,a:Dictionary,b:Dictionary)->Dictionary:
		routes+=1;return super.route(id,a,b)
var allowed:=true
var allowed_actor:=""

func newly_closed_gate_case()->void:
	var w:=World.new();w.load_snapshot(preload("res://scripts/world/rural_generator.gd").generate(713))
	var b:=Building.new();var old:=Reference.new();var r:=Runtime.new();var rr:=Runtime.new()
	var start:Dictionary={"x":29.2,"y":0.0,"z":40.0,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	var finish:=start.duplicate(true);finish.x=26.8
	var actor:Dictionary={"id":"player","name":"finite fixture","hp":100.0,"hunger":100.0,"thirst":100.0,"fatigue":0.0,"stamina":100.0,"pack":{},"intent":null};actor.merge(start,true)
	var facts:Dictionary={"actors":[actor],"stocks":[],"actions":[],"quests":[],"time":0.0,"status":"playing"}
	r.configure({"world":w,"facts":facts,"services":{"buildings":b}})
	var seed:Dictionary=b.seed_rural(w);var draft:Dictionary=w.prepare_changes(seed.world_changes,w.get_revision())
	expect("new closed gate fixture seeds actual geometry",draft.ok and w.commit_prepared(draft.capability).ok)
	# The original rural gate can legally be bypassed around an unfenced end.
	# Make the negative fixture an actual finite corridor, without changing the
	# gate/body aperture or permission policy. Both implementations see these
	# same real C solid entities; denied access must now have no alternate route.
	var walls:Array=[]
	for interval:Vector2 in [Vector2(0.0,39.1),Vector2(40.9,64.0)]:
		var box:=AABB(Vector3(27.9,0.0,interval.x),Vector3(0.2,2.0,interval.y-interval.x))
		var entity:Dictionary={"id":"fixture:gate-corridor:"+str(walls.size()),"kind":"prop","regionId":"RH-HOME","position":Geometry.json_point(box.get_center()),"bounds":Geometry.json_box(box),"revision":0,"data":{"solid":true,"opaque":true}}
		walls.append({"op":"entity.put","id":entity.id,"before_exists":false,"before":null,"after":entity})
	draft=w.prepare_changes(walls,w.get_revision())
	expect("finite corridor solid entities commit through real C capability",draft.ok and w.commit_prepared(draft.capability).ok)
	r.configure({"world":w,"facts":facts,"services":{"buildings":b}});rr.configure({"world":w,"facts":facts,"services":{"buildings":old}})
	var data:Dictionary=b.structures();var gate:="rural:v1:RH-HOME:old-house:yard-gate"
	for v:Dictionary in data.instances:
		if v.id==gate:v.door.open=true
	allowed=true
	var access:Callable=func(_id:String,_t:String,_k:String,_p:Dictionary)->Variant:return null if allowed else "explicit newly closed gate refusal"
	var q_open:=CountedSpace.new();var old_open:=Space.new()
	q_open.configure(w,data,b.geometry,access);old_open.configure(w,data,b.geometry,access)
	var open_ok:=b.exit_reachable(q_open,"player",start,finish);var old_ok:bool=old.exit_reachable(old_open,"player",start,finish)
	expect("actual open gate route has no opening step",open_ok and old_ok and b._exit_hints.values()[0].all(func(step:Dictionary)->bool:return step.kind!="open-door"),b._exit_hints.values())
	var q_closed:=CountedSpace.new();var old_closed:=Space.new()
	q_closed.configure(w,b.structures(),b.geometry,access);old_closed.configure(w,b.structures(),b.geometry,access)
	expect("old move hint is actually used for newly closed gate",b.exit_reachable(q_closed,"player",start,finish) and old.exit_reachable(old_closed,"player",start,finish) and q_closed.routes==0,{"routes":q_closed.routes})
	allowed=false
	var expected:bool=old.exit_reachable(old_closed,"player",start,finish)
	var actual:bool=b.exit_reachable(q_closed,"player",start,finish)
	var actual_route:Dictionary=q_closed.route("player",start,finish)
	var reference_route:Dictionary=old_closed.route("player",start,finish)
	expect("newly closed gate revocation cannot use old open-move proof",not expected and actual==expected,{"expected":expected,"actual":actual,"proofs":q_closed.exit_proofs.values(),"actual_route":actual_route,"reference_route":reference_route})
	allowed=true

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var decoded:=Codec.decode_checkpoint(FileAccess.get_file_as_string(args[0]))
	var imported:=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	var w:=World.new();expect("actual city loads",w.load_snapshot(imported.world).ok)
	var b:=Building.new();var old:=Reference.new();var r:=Runtime.new();var rr:=Runtime.new()
	expect("current services configure",r.configure({"world":w,"facts":imported.facts,"services":{"buildings":b}}).ok)
	expect("frozen original configures",rr.configure({"world":w,"facts":imported.facts,"services":{"buildings":old}}).ok)
	var before:=r.capture_checkpoint();var cases:=0;var doors:=0;var changed_hint_case:=false
	for a:Dictionary in r.facts().actors:
		var from:=Geometry.location(a)
		if from.buildingId==null:continue
		for slot:Dictionary in w.extension("generation:"+str(from.regionId)).get("slots",[]):
			if slot.get("kind")!="entrance" or slot.get("buildingId")!=from.buildingId:continue
			cases+=1;var to:=Geometry.location(slot);to.buildingId=null;to.storeyId=null
			var ground:Variant=w.surface_height(to.x,to.z)
			if ground!=null:to.y=float(ground)
			var q:=CountedSpace.new();var ref:=Space.new()
			allowed=true;allowed_actor=str(a.id)
			var access:Callable=func(id:String,_t:String,_k:String,_p:Dictionary)->Variant:return null if allowed and id==allowed_actor else "explicit current access refusal"
			q.configure(w,b.structures(),b.geometry,access);ref.configure(w,b.structures(),b.geometry,access)
			var actual:=b.exit_reachable(q,a.id,from,to);var expected:bool=old.exit_reachable(ref,a.id,from,to)
			var key:Array=[from.duplicate(true),to.duplicate(true)]
			expect("cold complete geometry route equals original "+a.id,actual and actual==expected and q.exit_proofs.has(key))
			if not q.exit_proofs.has(key):continue
			doors+=q.exit_proofs[key].size()
			var count:=q.routes
			expect("same start geometry proof avoids repeating route "+a.id,b.exit_reachable(q,a.id,from,to)==expected and q.routes==count)
			allowed=false
			expect("revoked permission matches full original search "+a.id,b.exit_reachable(q,a.id,from,to)==old.exit_reachable(ref,a.id,from,to))
			allowed=true
			expect("denial is not cached as geometry "+a.id,b.exit_reachable(q,a.id,from,to)==old.exit_reachable(ref,a.id,from,to))
			expect("geometry proof does not transfer actor authorization "+a.id,b.exit_reachable(q,"other-actor",from,to)==old.exit_reachable(ref,"other-actor",from,to))
			if not changed_hint_case and not q.exit_proofs[key].is_empty():
				changed_hint_case=true
				var open_data:Dictionary=b.structures()
				for piece:Dictionary in open_data.instances:
					if piece.has("door"):piece.door.open=true
				var open_q:=Space.new();var open_ref:=Space.new()
				open_q.configure(w,open_data,b.geometry,access);open_ref.configure(w,open_data,b.geometry,access)
				b._exit_hints.clear();old._exit_hints.clear()
				expect("fresh old all-open route supplies geometry hint",b.exit_reachable(open_q,a.id,from,to) and old.exit_reachable(open_ref,a.id,from,to))
				var closed_q:=Space.new();var closed_ref:=Space.new()
				closed_q.configure(w,b.structures(),b.geometry,access);closed_ref.configure(w,b.structures(),b.geometry,access)
				expect("old open hint revalidates against current closed geometry",b.exit_reachable(closed_q,a.id,from,to)==old.exit_reachable(closed_ref,a.id,from,to))
				allowed=false
				expect("closed doors newly discovered inside old move hints retain permission dependencies",b.exit_reachable(closed_q,a.id,from,to)==old.exit_reachable(closed_ref,a.id,from,to))
				allowed=true
			for delta:float in [0.007,-0.007]:
				var moved:=from.duplicate(true);moved.x=float(moved.x)+delta
				var feet:Dictionary=q.standing_point(moved)
				if feet.is_empty():continue
				actual=b.exit_reachable(q,a.id,feet,to);expected=old.exit_reachable(ref,a.id,feet,to)
				expect("exact moved feet has independent full result "+a.id+str(delta),actual==expected and (not actual or q.exit_proofs.has([feet.duplicate(true),to.duplicate(true)])))
			var door:Dictionary=q.pieces.filter(func(v:Dictionary)->bool:return v.has("door") and float(v.hp)>0)[0].duplicate(true)
			door.door.open=not door.door.open;door.version=int(door.version)+1
			var data:Dictionary=q.state.duplicate(true)
			for i in data.instances.size():
				if data.instances[i].id==door.id:data.instances[i]=door
			var child:=DoorProjection.project(q,data,door,access)
			expect("new physical door projection inherits NO exit proofs "+a.id,child.exit_proofs.is_empty())
			var other:=CountedSpace.new();other.configure(w,b.structures(),b.geometry,access)
			expect("new immutable query inherits no proof "+a.id,other.exit_proofs.is_empty())
	expect("all four actual indoor residents and permission doors exercised",cases==4 and doors>0,{"residents":cases,"closed_door_dependencies":doors})
	newly_closed_gate_case()
	# Capacity uses an isolated empty query and cannot authorize live movement.
	var isolated:=Space.new()
	for i in 1025:b.remember_exit(isolated,[{"id":i}],[])
	expect("exit geometry proof cache stays bounded",isolated.exit_proofs.size()==1024 and not isolated.exit_proofs.has([{"id":0}]))
	isolated.configure(w,b.structures(),b.geometry,func(_id:String,_t:String,_k:String,_p:Dictionary)->Variant:return null)
	expect("configure always clears prior exit certificates",isolated.exit_proofs.is_empty())
	expect("all query tests preserve actual authority",r.capture_checkpoint()==before)
	print(JSON.stringify({"ok":not failed,"checks":checks,"scope":"actual old city routes/closed permissions/exact feet against exact pre-proof B source; bounded derived geometry only, not app/FPS qualification"}))
	quit(1 if failed else 0)
