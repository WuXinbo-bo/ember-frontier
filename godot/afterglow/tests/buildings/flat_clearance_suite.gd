extends "res://tests/buildings/legacy_suite.gd"
const ReferenceSpace=preload("res://tests/buildings/flat_reference.gd")
class CountedSpace extends "res://scripts/buildings/building_space.gd":
	var proofs:=0
	func flat_walk_clearance(a:Dictionary,b:Dictionary)->bool:
		var result:=super.flat_walk_clearance(a,b)
		if result:proofs+=1
		return result

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var decoded:=Codec.decode_checkpoint(FileAccess.get_file_as_string(args[0]))
	var imported:=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	var w:=World.new();expect("actual unchanged city loads",w.load_snapshot(imported.world).ok)
	var b:=Building.new();var r:=Runtime.new()
	expect("actual runtime configures",r.configure({"world":w,"facts":imported.facts,"services":{"buildings":b}}).ok)
	var q:=CountedSpace.new();var ref:=ReferenceSpace.new()
	var access:Callable=func(id:String,t:String,k:String,p:Dictionary)->Variant:return b.permission(id,t,k,p)
	q.configure(w,b.structures(),b.geometry,access);ref.configure(w,b.structures(),b.geometry,access)
	var before:=r.capture_checkpoint();var starts:Array=[]
	for a:Dictionary in r.facts().actors:starts.append(Geometry.location(a))
	for p:Dictionary in q.pieces:
		if p.has("door") or p.has("stairs"):starts.append_array(q.use_points(p))
	var mismatch:Array=[];var samples:=0;var clear_path:Dictionary={}
	for start:Dictionary in starts:
		for direction in 8:
			var angle:=TAU*direction/8.0
			for length:float in [0.2,0.5,1.0,2.0,5.0]:
				var to:=start.duplicate(true);to.x=float(to.x)+cos(angle)*length;to.z=float(to.z)+sin(angle)*length
				for allow:bool in [false,true]:
					samples+=1
					var actual:=q.walk("player",start,to,allow);var expected:Dictionary=ref.walk("player",start,to,allow)
					if actual!=expected and mismatch.size()<10:mismatch.append({"start":start,"to":to,"allow":allow,"actual":actual,"expected":expected})
					if clear_path.is_empty() and length>=1.0 and actual.ok and q.flat_walk_clearance(start,to):clear_path={"from":start,"to":to}
	expect("all city/door/stair axes diagonals and permission modes equal exact old walk",mismatch.is_empty(),{"samples":samples,"mismatches":mismatch})
	expect("positive enclosure is actually exercised",q.proofs>0,{"proofs":q.proofs})
	# Existing OPEN/HP0 leaves may correctly be clear; only physical blocking
	# leaves require fallback. Do not invent a rule that every door label blocks.
	var doorway_proofs:Array=[]
	for v:Dictionary in q.pieces:
		if not v.has("door"):continue
		var ends:Array=[]
		for sign in [-1,1]:
			var p:=Geometry.json_point(Geometry.transform(Vector3(0,0,sign*0.7),v));p.merge({"regionId":v.regionId})
			ends.append(p)
		if q.flat_walk_clearance(ends[0],ends[1]) and not ref.blockers(ends[0],ends[1],"player",false).ok:doorway_proofs.append(v.id)
	expect("every physically blocking real leaf/frame forces exact fallback",doorway_proofs.is_empty(),doorway_proofs)
	expect("a real supported success has an enclosing proof",not clear_path.is_empty(),clear_path)
	if not clear_path.is_empty():
		var a:Dictionary=clear_path.from;var end:Dictionary=clear_path.to
		var midpoint:=Geometry.point(a).lerp(Geometry.point(end),0.5)+Vector3(0,0.8,0)
		for solid:bool in [false,true]:
			var entity:Dictionary={"id":"fixture:flat-thin-entity","kind":"prop","regionId":a.regionId,"position":Geometry.json_point(midpoint),"bounds":Geometry.json_box(AABB(midpoint-Vector3(0.005,0.1,0.005),Vector3(0.01,0.2,0.01))),"revision":0,"data":{"solid":solid,"opaque":false}}
			var original:=w.snapshot();var e:Dictionary=w.entity(entity.id)
			var transaction:=w.prepare_changes([{"op":"entity.put","id":entity.id,"before_exists":not e.is_empty(),"before":e if not e.is_empty() else null,"after":entity}],w.get_revision())
			expect("actual thin entity capability commits "+str(solid),transaction.ok and w.commit_prepared(transaction.capability).ok)
			var next:=CountedSpace.new();var old:=ReferenceSpace.new()
			for query:RefCounted in [next,old]:query.configure(w,b.structures(),b.geometry,access)
			var actual:=next.walk("player",a,end,false);var expected:Dictionary=old.walk("player",a,end,false)
			expect("thin transparent solid changes body proof with exact old result "+str(solid),actual==expected and actual.ok!=solid and next.flat_walk_clearance(a,end)!=solid,{"actual":actual,"expected":expected})
			# Low-level fixture restoration is explicit; no live slot/app/world.
			expect("isolated original world snapshot restores",w.load_snapshot(original).ok)
	expect("query/proof never changes actors stocks clock or world",r.capture_checkpoint()==before)
	print(JSON.stringify({"ok":not failed,"checks":checks,"scope":"full old/new walk return equality; positive empty superset proof; not formal application or FPS"}))
	quit(1 if failed else 0)
