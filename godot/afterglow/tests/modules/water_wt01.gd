extends "res://tests/modules/factory_boundary_fixture.gd"
const Generator=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Water=preload("res://scripts/modules/module_water.gd")
var base:Dictionary={}
var source_id:String=""
func request(rt:RefCounted,kind:String,payload:Dictionary={},identity:String="")->Dictionary:return command(rt,"module.water."+kind,source_id,payload,"player",identity)
func complete(rt:RefCounted,pid:String,limit:int=190)->Dictionary:
	for i:int in limit:
		rt.tick(0.1)
		var p:=Draft.find(rt.world.extension(Modules.KEY).water.projects,pid)
		if p.get("status")=="completed":return p
	return Draft.find(rt.world.extension(Modules.KEY).water.projects,pid)
func run()->void:
	var profiles:Array=Modules.generation_profiles();var config:Dictionary=Contract.fresh(profiles,6,1)
	var opening:Dictionary=Assembly.prepare(Generator.generate(713,profiles,config.contract))
	check("content6 actual C descriptor/B registration/A Assembly succeeds",opening.ok,opening.get("reason"))
	if not opening.ok:finish();return
	base=opening.capture
	var src:Dictionary=base.world.extensions[Modules.KEY].water.sources[0];source_id=src.id
	put_actor(base,src.use_point)
	var a:=Draft.find(base.facts.actors,"player");a.pack["timber"]=2;a.pack["scrap"]=2
	var legacy:Dictionary=base.world.extensions["r3:production"];legacy.knowledge["player"]=["basic_tool_repair"]
	var hammer_id:String=""
	for t:Dictionary in legacy.tools:
		if t.kind=="hammer":t.holderId="pack:player";hammer_id=t.id;break
	var mounted:=mount(base,"WT01 explicit finite site/tool/material/knowledge fixture")
	if not mounted.ok:finish();return
	var rt:RefCounted=mounted.runtime;var service:RefCounted=mounted.services.modules;var prod:RefCounted=mounted.services.production
	var before:Dictionary=rt.capture_checkpoint()
	check("undiscovered facility does not leak source balance",service.water_projection().sources.is_empty() and Data.json_equal(before,rt.capture_checkpoint()))
	check("NPC cannot disclose or start facility work",not service.water_projection("village-resident").available and not service.prepare({"kind":"module.water.discover","actor_id":"village-resident","target_id":source_id}).ok)
	var discovered:=request(rt,"discover")
	check("real supported near contact discovers exact source",discovered.ok and service.water_projection().sources[0].remaining==48,discovered)
	var material_before:Dictionary=rt.actor("player").pack.duplicate(true);var tools_before:Array=prod.state().tools.duplicate(true)
	var start:=request(rt,"repair",{"source_id":"pack:player","tool_id":hammer_id},"B:WT:repair")
	check("repair starts with real 2timber 2scrap and hammer",start.ok,start)
	if not start.ok:finish();return
	check("admission only reserves, no free readiness or water",rt.world.extension(Modules.KEY).water.sources[0].status=="needs_repair" and Data.json_equal(material_before,rt.actor("player").pack))
	var held:Array=service.hold_descriptors(rt.facts())
	check("same modules owner reserves real materials/tool/source",held.any(func(h:Dictionary)->bool:return h.intent_id=="B:WT:repair:water" and h.cost==Water.COST and h.tool_ids==[hammer_id] and h.use_target_id==source_id))
	tick(rt,20);var progress:float=rt.world.extension(Modules.KEY).water.projects[0].progress_seconds
	var paused:=request(rt,"held",{"held":false});tick(rt,3)
	check("paused held work consumes neither material nor water",paused.ok and rt.world.extension(Modules.KEY).water.projects[0].progress_seconds==progress and Data.json_equal(material_before,rt.actor("player").pack))
	check("held resumes same original project",request(rt,"held",{"held":true}).ok)
	var partial:Dictionary=rt.capture_checkpoint();var cold:=mount(partial,"WT01 held/active cold")
	check("cold retains same facility remaining paid inputs held labor",cold.ok and Data.json_equal(service.state(),cold.services.modules.state()) and Data.json_equal(rt.facts(),cold.runtime.facts()))
	if cold.ok:rt=cold.runtime;service=cold.services.modules;prod=cold.services.production
	var repaired:=complete(rt,"B:WT:repair:water")
	check("sixteen real labor seconds restore once",repaired.status=="completed" and is_equal_approx(repaired.progress_seconds,16.0) and service.water_projection().sources[0].status=="ready",repaired)
	var expected:Dictionary=material_before.duplicate(true);expected.timber-=2;expected.scrap-=2
	check("exact materials paid and original hammer loses one",Data.json_equal(expected,rt.actor("player").pack) and is_equal_approx(rt.tool(hammer_id).durability,Draft.find(tools_before,hammer_id).durability-1))
	var complete_before:Dictionary=rt.capture_checkpoint()
	check("repair replay cannot charge or refill",request(rt,"repair",{"source_id":"pack:player","tool_id":hammer_id},"B:WT:repair").ok and Data.json_equal(complete_before,rt.capture_checkpoint()))
	var available:Dictionary=service.availability({"kind":"module.water.repair","actor_id":"player","target_id":source_id,"payload":{"source_id":"pack:player","tool_id":hammer_id}})
	check("already-ready repair rejected without charge",not available.ok and Data.json_equal(complete_before,rt.capture_checkpoint()))
	var water_before:float=rt.actor("player").pack.get("water",0)
	check("draw starts a real finite reservation",request(rt,"draw",{"output_id":"pack:player"},"B:WT:cancel-draw").ok)
	check("reserved output and last source unit share transaction",prod.capacity_reserved("pack:player","water")==1 and service.water_projection().sources[0].reserved==1)
	tick(rt,5);var cancel:=request(rt,"cancel")
	check("cancel draw does not debit source or credit pack",cancel.ok and service.water_projection().sources[0].remaining==48 and rt.actor("player").pack.get("water",0)==water_before and prod.capacity_reserved("pack:player","water")==0)
	for i:int in 2:
		var cid:String="B:WT:draw:"+str(i)
		check("draw "+str(i)+" accepts only current site",request(rt,"draw",{"output_id":"pack:player"},cid).ok)
		var state_before:Dictionary=rt.capture_checkpoint()
		check("parallel request rejected without changing source or pack",not request(rt,"draw",{"output_id":"pack:player"}).ok and Data.json_equal(state_before,rt.capture_checkpoint()))
		var project:=complete(rt,cid+":water",145)
		check("draw "+str(i)+" full twelve seconds settles water1",project.status=="completed" and is_equal_approx(project.progress_seconds,12.0) and service.water_projection().sources[0].remaining==47-i and rt.actor("player").pack.get("water",0)==water_before+i+1,project)
		state_before=rt.capture_checkpoint()
		check("draw "+str(i)+" receipt replay cannot duplicate water",request(rt,"draw",{"output_id":"pack:player"},cid).ok and Data.json_equal(state_before,rt.capture_checkpoint()))
	var final:Dictionary=rt.capture_checkpoint();var last:=mount(final,"WT01 exact final cold")
	check("final cold preserves finite balance/cost/order ledger",last.ok and Data.json_equal(service.state(),last.services.modules.state()) and Data.json_equal(rt.facts(),last.runtime.facts()))
	var bad:Dictionary=service.state();bad.water.sources[0].remaining+=1
	check("free balance increase rejected by completed-draw conservation",not service.validate_extensions(rt.facts(),{Modules.KEY:bad}).ok)
	bad=service.state();bad.water.sources[0].position.x+=1
	check("source relocation away from persistent C origin rejected",not service.validate_extensions(rt.facts(),{Modules.KEY:bad}).ok)
	var tx:=Draft.new(service.context);var observed:Dictionary=tx.extension(Modules.KEY);observed.water.projects.append({})
	check("malformed work rejected strictly",not service.validate_extensions(rt.facts(),tx.extensions).ok)
	evidence.append({"remaining":service.water_projection().sources[0].remaining,"player_pack":rt.actor("player").pack,"water":service.state().water,"scope":"Explicit finite fixture supplied only initial2timber/2scrap/knowledge/hammer/site placement; subsequent commands/ticks/holds/payments/cold are real. E owns actual normal journey proof."})
	finish()
