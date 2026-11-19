extends "res://tests/modules/factory_boundary_fixture.gd"
## Explicit finite negative fixtures, not the normal acquisition/combat journey.
const Generator=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Restoration=preload("res://scripts/modules/module_restoration.gd")
const Store=preload("res://scripts/storage/native_store.gd")
func save_state(rt:RefCounted,label:String)->void:
	var encoded:Dictionary=Store.encode(rt.capture_checkpoint())
	check(label+" serializes through original Native Store",encoded.ok,encoded.get("reason"))
	if encoded.ok:
		var file:=FileAccess.open(OS.get_cmdline_user_args()[0]+"/"+label+".native.json",FileAccess.WRITE)
		file.store_string(encoded.text);file.close()
func run()->void:
	var profiles:Array=Modules.generation_profiles();var contract:Dictionary=Contract.fresh(profiles,7,1)
	var prepared:Dictionary=Assembly.prepare(Generator.generate(713,profiles,contract.contract))
	check("actual content7 prepares for negative fixtures",prepared.ok,prepared.get("reason"))
	if not prepared.ok:finish();return
	var base:Dictionary=prepared.capture;var frame:Dictionary=base.world.extensions[Modules.KEY].instances.filter(func(v:Dictionary)->bool:return v.has("restoration"))[0]
	var id:String=frame.id;var hammer:String=""
	put_actor(base,port(frame,"work"));Draft.find(base.facts.actors,"player").pack=Restoration.COST.duplicate(true)
	for tool:Dictionary in base.world.extensions["r3:production"].tools:
		if tool.kind=="hammer":tool.holderId="pack:player";hammer=tool.id;break
	var missing:Dictionary=base.duplicate(true);Draft.find(missing.facts.actors,"player").pack.erase("r34:salvaged_drive_unit")
	var mm:=mount(missing,"missing-drive finite fixture");if not mm.ok:finish();return
	var mr:RefCounted=mm.runtime;var ms:RefCounted=mm.services.modules
	var request:Dictionary={"source_id":"pack:player","tool_ids":[hammer]}
	check("missing drive may only create original blocked project",command(mr,"module.restore",id,request).ok)
	var prior:Dictionary=mr.actor("player").pack;var hammer_durability:float=Draft.find(mm.services.production.state().tools,hammer).durability
	tick(mr,15);var mp:=Draft.find(ms.state().projects,ms.instance(id).project_id)
	check("missing drive blocks labor without material or tool charge",mp.status=="blocked" and mp.paused_reason=="missing_input" and mp.progress_seconds==0 and mp.effective_work==0 and mr.actor("player").pack==prior and Draft.find(mm.services.production.state().tools,hammer).durability==hammer_durability,mp)
	check("blocked project cannot install motor or full recovery basis",not ms.instance(id).restoration.completed and mr.world.entity(id+":part:fixed-power-housing").is_empty() and Restoration.basis(ms.instance(id))==Restoration.HISTORY)
	check("missing-drive cancel releases only original reservations",command(mr,"module.cancel",id).ok and mr.actor("player").pack==prior and not ms.hold_descriptors(mr.facts()).any(func(h:Dictionary)->bool:return h.intent_id==mp.id))
	var mounted:=mount(base,"finite complete costs for interrupted restoration");if not mounted.ok:finish();return
	var rt:RefCounted=mounted.runtime;var svc:RefCounted=mounted.services.modules
	var before:Dictionary=rt.capture_checkpoint()
	for payload:Dictionary in [{"source_id":"pack:player","tool_ids":[]},{"source_id":"pack:player","tool_ids":[hammer,hammer]},{"source_id":"pack:player","tool_id":hammer,"tool_ids":[hammer]}]:
		var result:=command(rt,"module.restore",id,payload)
		check("ambiguous restoration hammer rejected without mutation "+str(payload),not result.ok and Data.json_equal(before,rt.capture_checkpoint()),result)
	check("original valid restore starts for interrupted-damage proof",command(rt,"module.restore",id,request).ok)
	var pid:String=svc.instance(id).project_id;tick(rt,21)
	var active:Dictionary=rt.capture_checkpoint();var p:=Draft.find(svc.state().projects,pid)
	check("partial project has real labor but still unspent one drive",p.progress_seconds>2 and p.progress_seconds<40 and Data.json_equal(rt.actor("player").pack,Restoration.COST) and svc.instance(id).hp==120,p)
	save_state(rt,"interrupted-restoration-active")
	for field:String in ["cost","duration_seconds","geometry_version","historical_cost","origin"]:
		var forged:Dictionary=active.duplicate(true);var st:Dictionary=forged.world.extensions[Modules.KEY];var fp:=Draft.find(st.projects,pid);var fv:=Draft.find(st.instances,id)
		if field=="cost":fp.cost["r34:salvaged_drive_unit"]=0
		elif field=="duration_seconds":fp.duration_seconds=39
		elif field=="geometry_version":fp.geometry_version="r34.module.fuel_woodshop.geometry-unknown"
		elif field=="historical_cost":fv.restoration.historical_cost.timber=20
		else:fv.position.x+=1
		var host:=Native.new();hosts.append(host);var rejected:Dictionary=host._assemble(forged)
		check("forged restoration "+field+" cold rejects",not rejected.ok,rejected.get("reason",rejected.get("code")))
	var tx:=Draft.new(svc.context);var hit:Dictionary=svc.damage_in(tx,id,300,"B:S01:pending-explicit-damage-fixture")
	check("pending damage uses existing damage_in and original single commit",hit.ok and rt._commit(tx.result()).ok,hit)
	var ruined:Dictionary=svc.instance(id);var interrupted:=Draft.find(svc.state().projects,pid)
	check("unfinished damage freezes only historical6/2 without drive",ruined.status=="ruined" and ruined.recovery.items=={"timber":6.0,"scrap":2.0} and not ruined.restoration.completed and rt.world.entity(id+":part:fixed-power-housing").is_empty())
	check("damage cancels original project and releases holds without debit",interrupted.status=="cancelled" and rt.actor("player").intent==null and Data.json_equal(rt.actor("player").pack,Restoration.COST) and not svc.hold_descriptors(rt.facts()).any(func(h:Dictionary)->bool:return h.intent_id==pid),interrupted)
	save_state(rt,"interrupted-restoration-ruin")
	var cold:=mount(rt.capture_checkpoint(),"unfinished ruined frame cold")
	check("cold preserves cancelled labor history and unique original drive",cold.ok and Data.json_equal(svc.state(),cold.services.modules.state()) and Data.json_equal(rt.actor("player").pack,cold.runtime.actor("player").pack))
	before=rt.capture_checkpoint();var again:=command(rt,"module.restore",id,request)
	check("ruined pending source cannot be restored or multiply history",not again.ok and Data.json_equal(before,rt.capture_checkpoint()),again)
	evidence.append({"scope":"Actual C7 generated identity/terrain, explicit initial finite pack/hammer/standing fixture; missing-drive, forged-save and partial-project damage fixtures only. damage_in is isolated, not natural hostile combat; no claim of normal material acquisition.","module_id":id,"project_id":pid})
	finish()
