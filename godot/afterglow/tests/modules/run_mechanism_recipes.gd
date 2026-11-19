extends "res://tests/modules/run_architecture_lifecycle.gd"
## Reuses real paid module captures. Additional finite ingredient/tool/knowledge
## setup is explicitly a laboratory fixture, never a natural economy proof.
const Recipes=preload("res://scripts/production/module_recipes.gd")
func idle(rt:RefCounted,limit:int=600)->void:
	for i:int in limit:
		rt.tick(.1)
		if rt.actor("player").get("intent")==null:break
func run()->void:
	var args:=OS.get_cmdline_user_args();out=args[0];var family:String=args[1]
	for r:Dictionary in Recipes.definitions():
		if r.mechanism.family!=family:continue
		var choices:Array=Catalog.definitions().filter(func(d:Dictionary)->bool:return d.get("mechanism",{}).get("recipes",[]).has(r.id))
		choices.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return float(a.build_cost.timber)<float(b.build_cost.timber) if a.build_cost.timber!=b.build_cost.timber else str(a.id)<str(b.id))
		var d:Dictionary=choices[0];var basename:String=str(d.architecture.family)+"-"+str(d.architecture.tier)+"-"+str(d.architecture.variant)+".native.json"
		var path:String=args[2]+"/"+basename
		if not FileAccess.file_exists(path):path=args[3]+"/"+basename
		var decoded:=Store.decode(FileAccess.get_file_as_string(path));check("real paid fixture decodes "+r.id,decoded.ok,path)
		if not decoded.ok:continue
		var capture:Dictionary=decoded.capture;var player:=Draft.find(capture.facts.actors,"player");var p:Dictionary=capture.world.extensions["r3:production"]
		player.intent=null;player.stamina=100;player.fatigue=0;player.skills.crafting=20
		p.knowledge.player=["basic_woodwork","basic_tool_repair"]
		for item:String in r.inputs:player.pack[item]=float(player.pack.get(item,0))+float(r.inputs[item])*3
		var tools:Array=[]
		for kind:String in ["hammer","hand_saw","shovel","pickaxe"]:
			var id:String="B:recipe-fixture:"+str(r.id)+":"+kind
			p.tools.append({"id":id,"kind":kind,"holderId":"pack:player","durability":100.0});tools.append(id)
		var repair_id:Variant=null
		if r.has("repairTool"):
			repair_id="B:repair-fixture:"+str(r.id);p.tools.append({"id":repair_id,"kind":r.repairTool.kind,"holderId":"pack:player","durability":20.0})
		var live:=mount(capture);check("finite recipe setup retains paid building "+r.id,live.get("ok",false),live.get("reason"))
		if not live.get("ok",false):continue
		var rt:RefCounted=live.runtime;var m_id:String="B:mechanism:"+str(d.id);var before:Dictionary=rt.actor("player").pack;var count:int=live.services.production.state().tools.size()
		var admitted:=send(rt,"craft",m_id,{"recipe_id":r.id,"source_id":"pack:player","output_id":"pack:player","tool_ids":tools,"repair_tool_id":repair_id,"direct":false})
		check("actual public craft admits exact registered capability "+r.id,admitted.ok,admitted)
		if not admitted.ok:rt.retire();continue
		for i:int in 5:rt.tick(.1)
		var held:=send(rt,"held","",{"held":false});var paused:Dictionary=rt.actor("player");var orders_before:Dictionary=live.services.production.state()
		for i:int in 4:rt.tick(.1)
		check("standard hold keeps material and labor unspent "+r.id,held.ok and Data.json_equal(paused.pack,rt.actor("player").pack) and Data.json_equal(orders_before,live.services.production.state()))
		var encoded:=Store.encode(rt.capture_checkpoint());var cold:=mount(Store.decode(encoded.text).capture) if encoded.ok else encoded
		check("active paused recipe full JSON cold "+r.id,cold.get("ok",false),cold.get("reason"))
		if not cold.get("ok",false):rt.retire();continue
		rt.retire();rt=cold.runtime;live=cold
		var resumed:=send(rt,"held","",{"held":true});idle(rt)
		var exact:bool=resumed.ok and rt.actor("player").get("intent")==null
		for item:String in r.inputs:exact=exact and float(rt.actor("player").pack.get(item,0))==float(before.get(item,0))-float(r.inputs[item])+float(r.outputs.get(item,0))
		for item:String in r.outputs:
			if not r.inputs.has(item):exact=exact and float(rt.actor("player").pack.get(item,0))==float(before.get(item,0))+float(r.outputs[item])
		if r.has("repairTool"):exact=exact and float(rt.tool(str(repair_id)).durability)==minf(100,20+float(r.repairTool.restore))
		if r.has("createTool"):exact=exact and live.services.production.state().tools.size()==count+1 and live.services.production.state().tools.any(func(t:Dictionary)->bool:return t.kind==r.createTool.kind and t.holderId=="pack:player" and t.durability==r.createTool.durability)
		check("real arrival labor settles exact materials outputs and tools once "+r.id,exact,{"activity":rt.actor("player").activity,"intent":rt.actor("player").get("intent"),"orders":live.services.production.state().orders})
		var terminal:Dictionary=live.services.production.state();for i:int in 3:rt.tick(.1)
		check("no duplicate completion after terminal ticks "+r.id,Data.json_equal(terminal,live.services.production.state()))
		rt.retire()
	finish()
func finish()->void:
	var report:Dictionary={"checks":checks,"scope":"Real paid module ledger captures plus explicit finite ingredients/tools/knowledge lab fixture. Actual original public craft, real arrival, standard hold, JSONcold, exact material/tool settlement. Not natural economy/PCK/OS/VA/FPS."}
	FileAccess.open(out+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print(JSON.stringify(report));quit(0 if not checks.is_empty() and checks.all(func(c:Dictionary)->bool:return c.ok) else 1)
