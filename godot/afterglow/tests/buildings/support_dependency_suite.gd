extends "res://tests/buildings/support_baseline_transaction_suite.gd"
## Exact dependency boundary for the support-only proof. These forged plans
## are classification adversaries, not permission to commit invalid changes.

func mutate(changes:Array,kind:String,b:RefCounted)->Array:
	var altered:Array=changes.duplicate(true)
	var structure:Dictionary=altered[0]
	var index:=0
	for i in structure.after.instances.size():
		if structure.after.instances[i].id!=DOOR:index=i;break
	var piece:Dictionary=structure.after.instances[index]
	if kind=="piece HP":piece.hp-=1
	elif kind=="piece rotation":piece.quarterTurn=(int(piece.quarterTurn)+1)%4
	elif kind=="piece position":piece.position.x+=0.5
	elif kind=="piece version":piece.version+=1
	elif kind=="geometry version":piece.geometryVersion=2
	elif kind=="definition":piece.definitionId="unresolved-definition"
	elif kind=="owner":piece.owner="different-household"
	elif kind=="storey":structure.after.storeys[0].elevation+=0.5
	elif kind=="structure metadata":structure.after.future_geometry={"version":2}
	elif kind=="door HP":
		for p:Dictionary in structure.after.instances:
			if p.id==DOOR:p.hp-=1
	elif kind=="entity payload":altered[1].before.data.structure.hp-=1
	elif kind=="entity after geometry":altered[1].after.bounds.min.x-=0.25
	elif kind=="unpaired ID":altered[1].id="different-entity"
	elif kind=="missing entity":altered.resize(1)
	elif kind=="missing structure":altered.remove_at(0)
	elif kind=="duplicate entity":altered.append(altered[1].duplicate(true))
	elif kind=="voxel":altered.append({"op":"voxel.set","cell":{"x":1,"y":0,"z":1},"before":1,"after":0})
	elif kind=="chunk":altered.append({"op":"chunk.put","id":"0:0:0","before_exists":true,"before":{},"after":{}})
	elif kind=="residency":altered.append({"op":"chunk.residency","id":"0:0:0","before":true,"after":false})
	elif kind=="region":altered.append({"op":"region.put","id":"region:0:0","before_exists":true,"before":{},"after":{}})
	elif kind=="generation":altered.append(b.extension_change("generation:region:0:0",{}))
	elif kind=="unrelated entity":altered.append({"op":"entity.put","id":"different-entity","before_exists":false,"before":null,"after":{}})
	elif kind=="unknown":altered.append({"op":"future-geometry-change"})
	return altered

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var raw:=FileAccess.get_file_as_string(args[0]);var decoded:=Codec.decode_checkpoint(raw)
	var imported:=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	var c:=configure_case(imported,0,false);var b:RefCounted=c.building
	var before:Dictionary=c.runtime.capture_checkpoint()
	var full:Dictionary=b.validate_structures(c.world,b.structures(),c.runtime.facts())
	expect("real current city has complete startup support proof",full.ok and b._support_roots.size()==971,full)
	var request:Dictionary={"kind":"door","actor_id":"player","target_id":DOOR,"payload":{"operation":"close" if b.instance(DOOR).door.open else "open"}}
	var plan:Dictionary=b.prepare_door(request)
	expect("real single-door plan has exact reusable support dependencies",plan.ok and b._support_only_door_commit(plan.world_changes),plan.get("reason"))
	var changes:Array=plan.world_changes
	for kind:String in ["piece HP","piece rotation","piece position","piece version","geometry version","definition","owner","storey","structure metadata","door HP","entity payload","entity after geometry","unpaired ID","missing entity","missing structure","duplicate entity","voxel","chunk","residency","region","generation","unrelated entity","unknown"]:
		expect("support-only continuation rejects actual dependency "+kind,not b._support_only_door_commit(mutate(changes,kind,b)))
	var metadata:Array=changes.duplicate(true);metadata.append(b.extension_change("fixture:nonspatial-proof",{"value":1}))
	expect("exact typed metadata plus paired door may preserve static support only",b._support_only_door_commit(metadata))
	expect("classification and preflight do not mutate authority",c.runtime.capture_checkpoint()==before)
	# Returned/staged state is not the service's saved proof, and a modified
	# proof destination cannot alter a future exact-root result.
	var saved:Dictionary=b._support_roots.duplicate(false)
	var query:RefCounted=b.space(c.world,b._support_state)
	b._reuse_support_proof(query,c.world,b._support_state)
	query.support_roots.clear();query.state.instances[0].hp=0
	expect("query root map/state cannot mutate saved immutable proof",b._support_roots==saved and b._support_state.instances[0].hp>0)
	expect("original input bytes preserved",FileAccess.get_file_as_string(args[0])==raw)
	print(JSON.stringify({"ok":not failed,"checks":checks,"scope":"B support-only exact dependency classification plus actual city startup/door; production final safety and CAS unchanged; not OS/P0 qualification"}))
	quit(1 if failed else 0)
