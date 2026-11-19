extends "res://tests/buildings/domain_suite.gd"
## Derived room/visible pick geometry only; not an OS or VA route.
const Policy=preload("res://scripts/presentation/interior_view_policy.gd")
const Data=preload("res://scripts/world/world_data.gd")

func run()->void:
	var started:int=Time.get_ticks_msec()
	expect("retained real rural fixture loads",world.load_snapshot(Generator.generate(713)).ok)
	initialize_at({"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var seeded:Dictionary=building.seed_rural(world)
	var draft:Dictionary=world.prepare_changes(seeded.world_changes,world.get_revision())
	expect("actual B home commits",draft.ok and world.commit_prepared(draft.capability).ok)
	var q:RefCounted=building.current_space();var p:=Policy.new();p.configure(q)
	var groups:Dictionary={}
	for roof:Dictionary in p._rooms.roofs:
		var feet:Dictionary=q.standing_point(p._rooms.room_point(roof))
		if feet.is_empty() or feet.get("buildingId")!="rural:v1:RH-HOME:old-house":continue
		var id:int=p._rooms.component_at(feet)
		if not groups.has(id):groups[id]=[]
		groups[id].append(feet)
	expect("actual home has distinct closed structural rooms",groups.size()>1)
	if groups.size()<2:finish_local(started);return
	var first:Dictionary=groups.values()[0][0];var other:Dictionary=groups.values()[1][0]
	p.sample(first,0)
	var baseline:Dictionary=runtime.capture_checkpoint();var wrong:Array=[];var door_count:int=0
	for v:Dictionary in q.pieces:
		if v.get("buildingId")!=first.buildingId or v.get("storeyId")!=first.storeyId:continue
		if p.base_visible(v,"cap"):wrong.append(v.id)
		if not p.cut_wall(v):continue
		var kind:String=q.geometry.definition(v).kind
		var boxes:Array=p.pick_boxes(v)
		if kind!="door":
			if not boxes.is_empty():wrong.append("hidden pick "+v.id)
		else:
			door_count+=1
			if boxes.size()!=3:wrong.append("door count "+v.id);continue
			var center:Vector3=Geometry.transform(Vector3(0,1.1,0),v)
			if boxes.any(func(box:AABB)->bool:return box.has_point(center)):wrong.append("invisible leaf still pickable "+v.id)
	expect("all near walls vanish without residual cap or invisible leaf picking",wrong.is_empty(),wrong)
	expect("actual cut doorway exercises its three visible frame boxes",door_count>0,door_count)
	var shell:Dictionary={"id":"fixture:shell","position":first.duplicate(true),"regionId":first.regionId,"buildingId":first.buildingId,"storeyId":first.storeyId}
	expect("same structural-room shell has stable presentation scope",p.can_observe_geometry(shell,first))
	var unknown:Dictionary=shell.duplicate(true);unknown.position=other.duplicate(true)
	if not q.line_clear(first,other):expect("closed unknown room shell is not granted by open roof",not p.can_observe_geometry(unknown,first))
	var pending_location:Dictionary=other.duplicate(true)
	# Explicit close threshold observation: bypass the >3m teleport reset.
	p._observed=pending_location.duplicate(true)
	p.sample(pending_location,100)
	expect("real other structural room enters pending confirmation",p.statistics().pending)
	var signature:String=p.signature();var version:int=p.statistics().topology_rebuilds
	var rebound:RefCounted=building.space()
	p.configure(rebound)
	expect("new equal immutable query preserves pending room and cut signature",p.statistics().pending and p.signature()==signature and p.statistics().topology_rebuilds==version)
	p.sample(pending_location,200)
	expect("query rebind does not prematurely activate threshold room",p.statistics().pending)
	p.sample(pending_location,250)
	expect("original confirmation interval still completes without extension",not p.statistics().pending and p.statistics().room_id!=p._scope(first).room_id)
	var state:Dictionary=rebound.state.duplicate(true)
	var found:=false
	for v:Dictionary in state.instances:
		if v.has("door"):
			v.door.open=not v.door.open;v.hp=maxf(1.0,float(v.hp)-0.1);found=true;break
	expect("real door supplies open/nonzero-HP projection fixture",found)
	signature=p.signature();version=p.statistics().topology_rebuilds
	var changed:RefCounted=building.space(null,state)
	p.configure(changed)
	expect("actual door leaf state/nonzero HP keeps structural room partition",p.signature()==signature and p.statistics().topology_rebuilds==version and p._query==changed)
	for v:Dictionary in state.instances:
		if changed.geometry.definition(v).kind=="roof":v.hp=0;break
	p.configure(building.space(null,state))
	expect("real removed roof still invalidates structural projection",p.statistics().topology_rebuilds>version)
	expect("room presentation leaves every authority field unchanged",Data.json_equal(baseline,runtime.capture_checkpoint()))
	finish_local(started)

func finish_local(started:int)->void:
	var result:Dictionary={"scope":"real B room/door geometry, explicit query/pose fixtures; no OS/VA proof","checks":checks,"failures":failures,"elapsed_ms":Time.get_ticks_msec()-started}
	var file:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("DDD_SHELL "+JSON.stringify({"checks":checks.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
