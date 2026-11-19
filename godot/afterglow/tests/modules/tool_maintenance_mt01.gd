extends "res://tests/modules/factory_boundary_fixture.gd"
## Explicit finite damaged-tool/workbench fixture, not a normal-source claim.
const Store=preload("res://scripts/storage/native_store.gd")
var base:Dictionary={}
func fixture(recipe_id:String,durability:float=0.0,known:bool=true)->Dictionary:
	var capture:Dictionary=base.duplicate(true)
	var m:Dictionary=capture.world.extensions[Modules.KEY].instances.filter(func(v:Dictionary)->bool:return Modules.definition(v.definition_id).shape=="manual" and v.region=="RH-HOME")[0]
	put_actor(capture,port(m,"work"))
	var a:=Draft.find(capture.facts.actors,"player");a.pack.merge({"timber":4,"scrap":6,"cloth":3,"tool_handle":3},true)
	var prod:Dictionary=capture.world.extensions["r3:production"]
	prod.knowledge.player=["basic_tool_repair"] if known else []
	var ids:Dictionary={}
	for tool:Dictionary in prod.tools:
		if not ids.has(tool.kind):ids[tool.kind]=tool.id;tool.holderId="pack:player";tool.durability=100.0
	var kind:String={"repair_hand_saw":"hand_saw","repair_hammer":"hammer","repair_shovel":"shovel","repair_pickaxe":"pickaxe"}[recipe_id]
	Draft.find(prod.tools,ids[kind]).durability=durability
	var result:=mount(capture,"MT01 finite damaged "+recipe_id)
	result.merge({"target":ids[kind],"hammer":ids.hammer,"station":m.config.workbench_id,"recipe_id":recipe_id})
	return result
func payload(f:Dictionary)->Dictionary:
	return {"direct":false,"recipe_id":f.recipe_id,"repair_tool_id":f.target,"tool_ids":[f.hammer],"source_id":"pack:player","output_id":"pack:player"}
func run()->void:
	base=Store.decode(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[1])).capture
	for rid:String in ["repair_hand_saw","repair_hammer","repair_shovel","repair_pickaxe"]:
		var f:=fixture(rid)
		if not f.ok:continue
		var rt:RefCounted=f.runtime;var p:RefCounted=f.services.production;var recipe:Dictionary=p.recipes[rid]
		var before_pack:Dictionary=rt.actor("player").pack.duplicate(true);var before_tools:Array=p.state().tools.duplicate(true)
		var expected:Dictionary=before_pack.duplicate(true)
		for item:String in recipe.inputs:expected[item]-=recipe.inputs[item]
		var cid:String="B:MT01:"+rid;var started:=command(rt,"craft",f.station,payload(f),"player",cid)
		check(rid+" zero-durability original instance accepted",started.ok,started)
		if not started.ok:continue
		var order:=Draft.find(p.state().orders,cid+":order")
		check(rid+" admission holds but does not spend materials or repair",Data.json_equal(before_pack,rt.actor("player").pack) and rt.tool(f.target).durability==0)
		check(rid+" target is held separately and never an operating tool",not order.toolIds.has(f.target) and (order.toolIds.is_empty() if rid=="repair_hammer" else order.toolIds==[f.hammer]))
		var reserved_before:Dictionary=rt.capture_checkpoint();var concurrent:=command(rt,"craft",f.station,payload(f))
		check(rid+" concurrent reuse rejected without changes",not concurrent.ok and Data.json_equal(reserved_before,rt.capture_checkpoint()))
		tick(rt,30)
		var partial:Dictionary=rt.capture_checkpoint();var cold:=mount(partial,rid+" active cold restore")
		check(rid+" active cold keeps same target zero and reserved materials",cold.ok and Data.json_equal(p.state(),cold.services.production.state()) and Data.json_equal(rt.actor("player").pack,cold.runtime.actor("player").pack))
		if cold.ok:rt=cold.runtime;p=cold.services.production
		for i:int in 150:
			rt.tick(0.1)
			if Draft.find(p.state().orders,cid+":order").get("status")=="completed":break
		order=Draft.find(p.state().orders,cid+":order")
		check(rid+" twelve real seconds settle once",order.status=="completed" and is_equal_approx(order.elapsed,12.0),order)
		check(rid+" exact finite cost no substitute or free material",Data.json_equal(expected,rt.actor("player").pack))
		check(rid+" same ID holder and tool count restore exactly sixty",rt.tool(f.target).durability==60 and rt.tool(f.target).holderId=="pack:player" and p.state().tools.size()==before_tools.size())
		check(rid+" independent operator wear matches card",is_equal_approx(rt.tool(f.hammer).durability,60.0 if rid=="repair_hammer" else 99.0))
		var settled:Dictionary=rt.capture_checkpoint()
		check(rid+" completed command replay cannot repair or charge twice",command(rt,"craft",f.station,payload(f),"player",cid).ok and Data.json_equal(settled,rt.capture_checkpoint()))
		evidence.append({"recipe":rid,"target_id":f.target,"cost":recipe.inputs,"operator_ids":order.toolIds,"progress_seconds":order.elapsed,"target_after":rt.tool(f.target)})
	var full:=fixture("repair_hand_saw",100)
	var before:Dictionary=full.runtime.capture_checkpoint()
	var result:Dictionary=full.services.production.prepare({"kind":"craft","actor_id":"player","target_id":full.station,"payload":payload(full)})
	check("full durability rejects without authority mutation",not result.ok and Data.json_equal(before,full.runtime.capture_checkpoint()),result)
	var missing:=fixture("repair_shovel",0,false)
	before=missing.runtime.capture_checkpoint()
	result=missing.services.production.prepare({"kind":"craft","actor_id":"player","target_id":missing.station,"payload":payload(missing)})
	check("unlearned maintenance rejects without authority mutation",not result.ok and Data.json_equal(before,missing.runtime.capture_checkpoint()),result)
	var f:=fixture("repair_hand_saw");var rt:RefCounted=f.runtime;var p:RefCounted=f.services.production
	var absent:Dictionary=payload(f);absent.tool_ids=[];before=rt.capture_checkpoint()
	result=p.prepare({"kind":"craft","actor_id":"player","target_id":f.station,"payload":absent})
	check("saw repair needs an independent usable hammer",not result.ok and Data.json_equal(before,rt.capture_checkpoint()),result)
	var tx:=Draft.new(p.context);var target:=Draft.find(tx.extension(p.KEY,p.empty_state()).tools,f.target);target.qualities={"hammering":1}
	var self_payload:Dictionary=payload(f);self_payload.tool_ids=[f.target]
	check("even a capability-overridden target cannot operate its own repair",not p.start(tx,{"kind":"craft","actor_id":"player","target_id":f.station,"command_id":"self","payload":self_payload}).ok and Data.json_equal(before,rt.capture_checkpoint()))
	var begin:=command(rt,"craft",f.station,payload(f),"player","B:MT01:cancel")
	tick(rt,8);var worn:float=rt.tool(f.hammer).durability;var spent:float=rt.actor("player").stamina
	var stopped:=command(rt,"cancel")
	check("cancel frees materials without undoing real labor",begin.ok and stopped.ok and rt.tool(f.target).durability==0 and worn<100 and rt.tool(f.hammer).durability==worn and rt.actor("player").stamina==spent and Data.json_equal(before.facts.actors.filter(func(a:Dictionary)->bool:return a.id=="player")[0].pack,rt.actor("player").pack))
	finish()
