extends "res://tests/modules/normal_module_lifecycle.gd"
## Unmodified original20 normal53 -> paid repair-v3, manual work, cold/cancel,
## controlled recovery/rebuild. Only the separately labeled damage branch is injected.
var repair_id:String="B:normal-lifecycle:hand"
var explicit_branch:Dictionary={}
var manual_seen:=false

func choose_site(rt:RefCounted,id:String,hammer:String)->Dictionary:
	for z:int in range(10,57,2):
		for x:int in range(18,57,2):
			var ground:Variant=rt.world.surface_height(x,z)
			if ground==null:continue
			var payload:Dictionary={"definition_id":"r34.module.repair_shed_v3","position":{"x":float(x),"y":float(ground),"z":float(z),"regionId":"RH-HOME"},"quarter_turn":1,"source_id":"pack:player","tool_id":hammer}
			var preview:Dictionary=rt._services.modules.preview({"kind":"module.plan","actor_id":"player","target_id":id,"payload":payload})
			if not preview.get("ok",false):continue
			for port:Dictionary in preview.ports:
				if port.purpose!="work":continue
				var route:Dictionary=rt._services.actions.route("player",Geometry.location(rt.actor("player")),port.location)
				if route.ok:return {"payload":payload,"port":port.location.duplicate(true)}
	return {}

func note(rt:RefCounted,stage:String,detail:Variant=null)->void:
	super.note(rt,stage,detail)
	if stage!="normal cancelled site restored and paid once" or manual_seen:return
	manual_seen=true
	var module:Dictionary=rt._services.modules.instance(repair_id)
	check("paid repair-v3 is registered with exact original BC04 bench",module.definition_id=="r34.module.repair_shed_v3" and module.geometry_version=="r34.module.repair_shed_v3.geometry-v2" and module.config.has("workbench_id"))
	for port:Dictionary in ModuleShape.ports(module,Modules.definition(module.definition_id)):
		var walked:Dictionary=walk(rt,port.location)
		check("real built repair-v3 body reaches original service "+str(port.id),walked.get("ok",false),walked.get("reason"))
		if not walked.get("ok",false):return
	var trees:Array=rt.world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.get("data",{}).get("harvest",{}).get("phase")=="standing")
	trees.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return Geometry.point(a.position).distance_squared_to(Geometry.point(rt.actor("player")))<Geometry.point(b.position).distance_squared_to(Geometry.point(rt.actor("player"))))
	var gathered:=false
	for tree:Dictionary in trees.slice(0,12):
		if not care(rt,50):return
		var started:Dictionary=send(rt,"harvest",tree.id,{"direct":false,"tool_ids":["r34:generated:RH-HOME:woodwork:tool:salvaged_axe"]})
		if not started.ok:continue
		var completed:Dictionary=progress(rt,1000)
		check("existing real finite tree becomes stump for new manual work",completed.finished and rt.world.entity(tree.id).data.harvest.phase=="stump",tree.id)
		if not completed.finished:return
		gathered=take_source(rt,str(tree.data.outputId),{"log":1})
		break
	check("manual repair-v3 receives one physically collected finite log",gathered)
	if not gathered:return
	var before:Dictionary=rt.actor("player").pack.duplicate(true)
	var saw:String="r34:generated:RH-HOME:woodwork:tool:hand_saw"
	var durability:float=rt.tool(saw).durability
	var craft:Dictionary=send(rt,"craft",str(module.config.workbench_id),{"direct":false,"recipe_id":"saw_timber","source_id":"pack:player","output_id":"pack:player","tool_ids":[saw]})
	var done:Dictionary=progress(rt,1000) if craft.ok else {}
	check("registered original bench performs real hand-saw labor once",craft.ok and done.get("finished",false) and float(rt.actor("player").pack.get("log",0))==float(before.get("log",0))-1 and float(rt.actor("player").pack.timber)==float(before.get("timber",0))+4 and is_equal_approx(rt.tool(saw).durability,durability-2),craft.get("reason"))
	super.note(rt,"new repair-v3 real manual batch",{"module":module,"before":before,"after":rt.actor("player").pack})
	save_scene(rt,"actual-paid-repair-v3-manual")
	var snapshot:Dictionary=rt.capture_checkpoint()
	var unsupported:=send(rt,"module.move",repair_id,{"source_id":"pack:player"})
	check("repair-v3 does not invent unsupported whole-module relocation",not unsupported.ok and Data.json_equal(snapshot,rt.capture_checkpoint()))

func damage_branch()->void:
	# Branch from the real final paid/rebuilt state without changing captured
	# actors, tools, materials, permissions, map, HP or member geometry.
	var source:Dictionary=live.runtime.capture_checkpoint();var native:=Native.new()
	var branch:Dictionary=native._assemble(source);native.free()
	check("explicit damage sibling restores unchanged real paid state",branch.get("ok",false),branch.get("reason"))
	if not branch.get("ok",false):return
	var rt:RefCounted=branch.runtime;var services:Dictionary=branch.services
	var id:String=repair_id+":rebuilt";var original:Dictionary=services.modules.instance(id)
	var port:=work_port(rt,original);var arrived:=walk(rt,port)
	check("explicit damage branch still requires actual work-face arrival",arrived.get("ok",false))
	if not arrived.get("ok",false):rt.retire();return
	var hit:Dictionary=rt._commit(services.modules.prepare_damage(id,32,"B:repair-quality:fixture-damage"))
	check("EXPLICIT fixture damage uses original transaction and HP ledger",hit.ok and services.modules.instance(id).hp==88,hit.get("reason"))
	var before:Dictionary=rt.actor("player").pack.duplicate(true)
	var hammer:String="r34:generated:RH-HOME:woodwork:tool:hammer"
	var repair:=send(rt,"module.repair",id,{"source_id":"pack:player","tool_id":hammer})
	var done:Dictionary=progress(rt,200) if repair.ok else {}
	var fixed:Dictionary=services.modules.instance(id)
	check("real repair labor pays2 boards1 scrap and keeps original paid basis",repair.ok and done.get("finished",false) and fixed.hp==120 and fixed.status=="operational" and Data.json_equal(fixed.paid_cost,original.paid_cost) and float(before.timber)-float(rt.actor("player").pack.timber)==2 and float(before.scrap)-float(rt.actor("player").pack.scrap)==1,repair.get("reason"))
	var replay:Dictionary=rt._commit(services.modules.prepare_damage(id,32,"B:repair-quality:fixture-damage"))
	check("old fixture cause cannot damage a repaired shed twice",replay.ok and services.modules.instance(id).hp==120)
	var destroy:Dictionary=rt._commit(services.modules.prepare_damage(id,1000,"B:repair-quality:fixture-ruin"))
	var ruin:Dictionary=services.modules.instance(id)
	check("EXPLICIT fixture ruin freezes original50percent recovery",destroy.ok and ruin.status=="ruined" and Data.json_equal(ruin.recovery.items,{"timber":2,"scrap":1}) and not ruin.recovery.claimed)
	var clear:=send(rt,"module.clear_ruin",id,{"source_id":"pack:player","output_id":"pack:player","tool_id":hammer})
	done=progress(rt,200) if clear.ok else {}
	check("true empty caches permit paid-basis ruin clear and unique settlement",clear.ok and done.get("finished",false) and services.modules.instance(id).status=="dismantled" and services.modules.instance(id).recovery.claimed and branch.world.entity(id).is_empty(),clear.get("reason"))
	var pack:Dictionary=rt.actor("player").pack.duplicate(true)
	var again:=send(rt,"module.clear_ruin",id,{"source_id":"pack:player","output_id":"pack:player","tool_id":hammer})
	check("claimed ruin cannot issue another recovery",not again.ok and Data.json_equal(pack,rt.actor("player").pack))
	var encoded:=Store.encode(rt.capture_checkpoint());var decoded:=Store.decode(encoded.text) if encoded.ok else encoded
	var host:=Native.new();var cold:Dictionary=host._assemble(decoded.capture) if decoded.get("ok",false) else decoded;host.free()
	check("explicit damage repair and ruin settlement survive canonical cold",cold.get("ok",false) and Data.json_equal(decoded.capture.facts,cold.runtime.capture_checkpoint().facts) and Data.json_equal(decoded.capture.world.extensions,cold.world.snapshot().extensions),cold.get("reason"))
	if cold.get("ok",false):cold.runtime.retire()
	if encoded.ok:FileAccess.open(outdir+"/explicit-damage-branch.native.json",FileAccess.WRITE).store_string(encoded.text)
	explicit_branch={"scope":"Only damage32/ruin1000 are explicit original-domain injected causes, NOT natural enemy attack. Body/material/labor/cache/clear commands remain real.","module":services.modules.instance(id),"pack":pack}
	rt.retire()

func finish()->void:
	if live.get("ok",false):save_scene(live.runtime,"actual-repair-v3-normal-final")
	if live.get("ok",false) and manual_seen and checks.all(func(row:Dictionary)->bool:return row.ok):damage_branch()
	var report:Dictionary={"checks":checks,"failed":checks.filter(func(row:Dictionary)->bool:return not row.ok).size(),"source":source_path,"journey":journey,"commands":commands,"live_roundtrip":live_roundtrip,"explicit_damage_branch":explicit_branch,"scope":"Current production after25; unchanged original20 normal53 finite save. Real paid repair-v3 build/cancel/cold/resume, existing axe tree and manual bench, controlled old empty machine reclamation as disclosed finite scrap source, dismantle/rebuild. Separate explicit damage/repair/ruin branch. Not actual25 repair-v3, natural enemy attack, content10 generation, renderer/OS/VA/FPS."}
	FileAccess.open(outdir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":report.failed}))
	if live.get("ok",false):live.runtime.retire()
	quit(0 if report.failed==0 else 1)
