extends "res://tests/modules/factory_boundary_fixture.gd"
const Generator=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Water=preload("res://scripts/modules/module_water.gd")
var site:Dictionary={}
var hammer_id:String=""
func request(rt:RefCounted,kind:String,payload:Dictionary={},identity:String="")->Dictionary:return command(rt,"module.water."+kind,site.id,payload,"player",identity)
func new_case(base:Dictionary,label:String)->Dictionary:return mount(base.duplicate(true),label+" explicit finite adversarial fixture")
func denied(rt:RefCounted,kind:String,payload:Dictionary,label:String)->void:
	var before:Dictionary=rt.capture_checkpoint();var result:=request(rt,kind,payload)
	check(label,not result.ok and Data.json_equal(before,rt.capture_checkpoint()),result)
func finish_work(rt:RefCounted,id:String,steps:int)->Dictionary:
	for i:int in steps:
		rt.tick(.1)
		var p:=Draft.find(rt.world.extension(Modules.KEY).water.projects,id)
		if p.get("status")=="completed":return p
	return Draft.find(rt.world.extension(Modules.KEY).water.projects,id)
func run()->void:
	var profiles:Array=Modules.generation_profiles();var prepared:Dictionary=Assembly.prepare(Generator.generate(713,profiles,Contract.fresh(profiles,6,1).contract))
	check("actual content6 generation and registration",prepared.ok)
	if not prepared.ok:finish();return
	var base:Dictionary=prepared.capture;site=base.world.extensions[Modules.KEY].water.sources[0].duplicate(true)
	put_actor(base,site.use_point);var a:=Draft.find(base.facts.actors,"player");a.pack["timber"]=2;a.pack["scrap"]=2
	var legacy:Dictionary=base.world.extensions["r3:production"];legacy.knowledge["player"]=["basic_tool_repair"]
	for t:Dictionary in legacy.tools:
		if t.kind=="hammer":t.holderId="pack:player";hammer_id=t.id;break
	base.world.extensions[Modules.KEY].water.sources[0].discovered=true
	var repair_payload:Dictionary={"source_id":"pack:player","tool_id":hammer_id}
	for variant:String in ["missing_material","missing_knowledge","broken_hammer","remote","dead"]:
		var bad:Dictionary=base.duplicate(true);var actor:=Draft.find(bad.facts.actors,"player")
		match variant:
			"missing_material":actor.pack.scrap=1
			"missing_knowledge":bad.world.extensions["r3:production"].knowledge["player"]=[]
			"broken_hammer":Draft.find(bad.world.extensions["r3:production"].tools,hammer_id).durability=0
			"remote":actor.x+=4
			"dead":actor.hp=0
		var m:=new_case(bad,variant)
		if m.ok:denied(m.runtime,"repair",repair_payload,variant+" cannot reserve or repair")
	var m:=new_case(base,"unrepaired");if not m.ok:finish();return
	var rt:RefCounted=m.runtime;var svc:RefCounted=m.services.modules
	denied(rt,"draw",{},"cannot take water before paying repair")
	var repaired:=request(rt,"repair",repair_payload,"B:water:safety:repair")
	check("repair starts for safety baseline",repaired.ok)
	if not repaired.ok:finish();return
	tick(rt,3)
	var pose:Dictionary=svc.actor_work_projection("player");var n:Vector3=G.point(site.use_point)-G.point(site.position);n.y=0;n=n.normalized()
	check("real repair work exposes original hammer and apparatus contact",pose.tool_id==hammer_id and G.point({"x":pose.contact.position[0],"y":pose.contact.position[1],"z":pose.contact.position[2]}).is_equal_approx(G.point(site.position)+n*.46+Vector3.UP*.73) and pose.contact.normal==[n.x,n.y,n.z])
	var tx:=Draft.new(svc.context);tx.actor("player").hp=0
	check("same Runtime transaction incapacitates actual operator",rt._commit(tx.result()).ok)
	check("lifecycle cancels project and releases source/tool/material holds",svc.state().water.projects[0].status=="cancelled" and svc.state().water.sources[0].project_id=="" and svc.hold_descriptors(rt.facts()).is_empty() and rt.actor("player").pack.scrap==2)
	var m2:=new_case(base,"paid ready baseline");if not m2.ok:finish();return
	rt=m2.runtime;svc=m2.services.modules
	check("second independent repair starts",request(rt,"repair",repair_payload,"B:water:safety:paid").ok)
	var done:=finish_work(rt,"B:water:safety:paid:water",180)
	check("ready baseline pays full labor and material once",done.status=="completed" and svc.state().water.sources[0].status=="ready" and rt.actor("player").pack.scrap==0)
	var ready:Dictionary=rt.capture_checkpoint()
	for variant:String in ["missing_entity","moved_entity","wall","remote_output"]:
		var bad:Dictionary=ready.duplicate(true)
		match variant:
			"missing_entity":bad.world.entities.erase(site.id)
			"moved_entity":bad.world.entities[site.id].position.x+=.1
			"wall":
				var at:=G.point(site.use_point);var center:=at+n*.4
				var operator:Dictionary=site.use_point.duplicate(true);operator.x+=n.x*.8;operator.z+=n.z*.8;put_actor(bad,operator)
				var bounds:=AABB(center-Vector3(.1,0,.1),Vector3(.2,2,.2))
				bad.world.entities["B:water:wall"]={"id":"B:water:wall","kind":"prop","regionId":site.region,"position":G.json_point(bounds.position),"bounds":G.json_box(bounds),"revision":0,"blocksTerrain":true,"data":{"solid":true,"opaque":true}}
		var b:=new_case(bad,variant)
		if b.ok:denied(b.runtime,"draw",{"output_id":"pack:village-resident"} if variant=="remote_output" else {},variant+" blocks original draw")
	# Only this last-unit counterexample seeds a matching completed ledger; it
	# is deliberately not evidence for a normal 47-draw survival journey.
	var last:Dictionary=ready.duplicate(true);var water:Dictionary=last.world.extensions[Modules.KEY].water
	water.sources[0].remaining=1
	for i:int in 47:
		water.projects.append({"id":"B:water:prior:"+str(i),"source_id":site.id,"actor_id":"player","operation":"draw","material_source_id":"","output_id":"pack:player","tool_id":"","cost":{},"progress_seconds":12.0,"duration_seconds":12.0,"status":"completed","effective_work":0.0,"paused_reason":""})
	var lm:=new_case(last,"one remaining unit with explicit matching ledger");if not lm.ok:finish();return
	rt=lm.runtime;svc=lm.services.modules;var prod:RefCounted=lm.services.production
	var r1:Dictionary=svc.prepare({"kind":"module.water.draw","actor_id":"player","target_id":site.id,"payload":{},"command_id":"B:water:last:A"})
	var r2:Dictionary=svc.prepare({"kind":"module.water.draw","actor_id":"player","target_id":site.id,"payload":{},"command_id":"B:water:last:B"})
	check("two same-revision pure preparations see same last unit",r1.ok and r2.ok)
	check("first last-unit CAS commits",rt._commit(r1).ok)
	var before:Dictionary=rt.capture_checkpoint();var stale:Dictionary=rt._commit(r2)
	check("second stale CAS cannot duplicate reservation",not stale.ok and Data.json_equal(before,rt.capture_checkpoint()),stale)
	check("one exact output promise and no duplicated debit",prod.capacity_reserved("pack:player","water")==1 and svc.water_projection().sources[0].remaining==1 and svc.water_projection().sources[0].reserved==1)
	tick(rt,1);pose=svc.actor_work_projection("player")
	var lever_angle:float=-.32-.08*sin(fposmod(float(pose.progress_seconds),1.0)*TAU)
	var lever_point:Vector3=G.point(site.position)+n*(.46-.24*sin(lever_angle))+Vector3.UP*(.86+.24*cos(lever_angle))
	check("draw work clears hammer and targets actual moving lever grip",pose.tool_id=="" and G.point({"x":pose.contact.position[0],"y":pose.contact.position[1],"z":pose.contact.position[2]}).is_equal_approx(lever_point))
	var prior_water:float=rt.actor("player").pack.get("water",0)
	done=finish_work(rt,"B:water:last:A:water",130)
	check("last unit settles once after twelve real seconds",done.status=="completed" and svc.water_projection().sources[0].remaining==0 and rt.actor("player").pack.get("water",0)==prior_water+1 and prod.capacity_reserved("pack:player","water")==0)
	denied(rt,"draw",{},"exhausted source cannot regenerate water")
	var final:Dictionary=rt.capture_checkpoint();var cold:=mount(final,"exhausted real transaction cold")
	check("exhausted cold preserves zero and the one real new output",cold.ok and Data.json_equal(svc.state(),cold.services.modules.state()))
	var malformed:Dictionary=svc.state();malformed.water.projects[0].duration_seconds="bad"
	check("malformed duration rejects without evaluator error",not svc.validate_extensions(rt.facts(),{Modules.KEY:malformed}).ok)
	evidence.append({"scope":"Explicit finite/material/knowledge/site/negative fixtures. Only last-unit setup seeds 47 matching historical draw entries; no claim these were actual survival draws.","last_cas_code":stale.get("code"),"finite_remaining":svc.water_projection().sources[0].remaining})
	finish()
