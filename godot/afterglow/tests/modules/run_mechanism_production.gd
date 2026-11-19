extends "res://tests/modules/run_architecture_lifecycle.gd"
## Explicit finite laboratory; NEVER offered as a natural opening/economy proof.
const Recipes=preload("res://scripts/production/module_recipes.gd")
func flat_base()->Dictionary:
	var opening:=Assembly.prepare(Generator.generate(713,Catalog.profiles()))
	if not opening.ok:return opening
	var base:Dictionary=opening.capture.duplicate(true)
	for key:String in base.world.chunks:
		var c:Vector3i=Data.coord(key)
		if c.x not in [3,4,5,6] or c.z not in [3,4,5,6]:continue
		var cells:PackedInt32Array=base.world.chunks[key].cells.duplicate()
		for y:int in 16:
			for z:int in 16:
				for x:int in 16:cells[x+16*(z+16*y)]=2 if c.y*16+y<0 else 0
		base.world.chunks[key].cells=cells
	for id:String in base.world.entities.keys():
		if G.aabb(base.world.entities[id].bounds).intersects(AABB(Vector3(24,-1,24),Vector3(32,20,32))):base.world.entities.erase(id)
	return {"ok":true,"capture":base}
func run()->void:
	out=OS.get_cmdline_user_args()[0];var fixture:=flat_base()
	check("explicit fixture prepared",fixture.ok)
	if not fixture.ok:return finish()
	check("catalog complete and content12 exactly preserves stable10 profiles",Catalog.validate().ok and Data.json_equal(Catalog.profiles_for_content(12),Catalog.profiles_for_content(10)) and Catalog.profiles_for_content(12).size()==19)
	var variants:Array=Catalog.definitions().filter(func(d:Dictionary)->bool:return d.get("mechanism",{}).get("version")==2)
	check("exactly30 new explicit mechanism definitions, old30 readable",variants.size()==30 and Catalog.definitions().filter(func(d:Dictionary)->bool:return d.has("architecture") and not d.has("mechanism")).size()==30)
	var recipes:Array=Recipes.definitions()
	check("23 registered real recipes validate current Content",recipes.size()==23 and recipes.all(func(r:Dictionary)->bool:return preload("res://scripts/runtime/content_definitions.gd").validate_catalog({"production_recipes":[r]}).ok))
	for d:Dictionary in variants:
		if OS.get_cmdline_user_args().size()>1 and str(d.architecture.family)!=OS.get_cmdline_user_args()[1] and str(d.id)!=OS.get_cmdline_user_args()[1]:continue
		var label:String=str(d.id);var capture:Dictionary=fixture.capture.duplicate(true);var site:=Modules.record_for({"id":"B:mechanism:"+label,"definition_id":label,"region":"RH-HOME","position":{"x":40,"y":0,"z":40},"quarter_turn":0})
		var player:=Draft.find(capture.facts.actors,"player");var at:Dictionary=Shape.ports(site,d)[0].location
		player.merge(at,true);player.intent=null;player.stamina=100;player.fatigue=0;player.pack={"timber":300,"stone_m3":30,"scrap":100,"cloth":100,"r34:salvaged_drive_unit":8,"water":12,"log":20,"tool_handle":5,"brace":10,"r34:potato":8,"r34:raw_water":10,"r34:filtered_water":10}
		var p:Dictionary=capture.world.extensions["r3:production"];p.knowledge.player=["basic_woodwork","basic_tool_repair"];player.skills.crafting=20
		var hammer:Dictionary={}
		for t:Dictionary in p.tools:
			if t.kind in ["hammer","hand_saw"]:t.holderId="pack:player";t.durability=100
			if t.kind=="hammer":hammer=t
		var mounted:=mount(capture);check("new mechanism Native mount "+label,mounted.get("ok",false),mounted.get("reason"))
		if not mounted.get("ok",false):continue
		var rt:RefCounted=mounted.runtime;var modules:RefCounted=mounted.services.modules
		var plan:=send(rt,"module.plan",site.id,{"definition_id":label,"position":at.merged({"x":40,"z":40},true),"quarter_turn":0,"source_id":"pack:player","tool_id":hammer.id})
		var built:bool=plan.ok and advance(rt,modules,float(d.build_seconds)+.2)
		check("unique full grade cost and labor produce live building "+label,built and modules.instance(site.id).status=="operational" and Data.json_equal(modules.instance(site.id).paid_cost,d.build_cost),plan.get("code"))
		if not built:rt.retire();continue
		var v:Dictionary=modules.instance(site.id)
		var paid_save:=Store.encode(rt.capture_checkpoint())
		if paid_save.ok:FileAccess.open(out+"/"+str(d.architecture.family)+"-"+str(d.architecture.tier)+"-"+str(d.architecture.variant)+".native.json",FileAccess.WRITE).store_string(paid_save.text)
		for r:Dictionary in recipes:
			if not d.mechanism.recipes.has(r.id):continue
			if r.has("repairTool") or r.has("createTool"):continue
			var complete_inputs:bool=r.inputs.keys().all(func(item:String)->bool:return rt.actor("player").pack.get(item,0)>=r.inputs[item])
			if not complete_inputs:continue
			var order_id:String="B:program:"+str(r.id);var configure:=send(rt,"module.recipe.configure",v.id,{"order_id":order_id,"recipe_id":r.id,"mode":"quantity","quantity":1,"source_id":"pack:player","output_id":"pack:player"})
			check("real management config "+label+" "+str(r.id),configure.ok,configure)
			if not configure.ok:continue
			var c:Dictionary={}
			for row:Dictionary in mounted.services.actions.workforce_candidates("player"):
				if row.id=="module-recipe:"+order_id:c=row;break
			check("existing actions bridge exposes exact craft admission "+label+" "+str(r.id),not c.is_empty() and c.valid,c.get("reason"))
			if c.is_empty() or not c.valid:continue
			var before:Dictionary=rt.actor("player").pack;var prepared:Dictionary=mounted.services.actions.prepare_workforce({"actor_id":"player","candidate_id":c.id,"command_id":"B:batch:"+str(sequence)});sequence+=1
			var committed:Dictionary=rt._commit(prepared) if prepared.ok else prepared
			for step:int in 700:
				rt.tick(.1)
				if rt.actor("player").get("intent")==null:break
			var active:Dictionary=modules.instance(v.id);var program:=Draft.find(active.config.recipe_orders,order_id);var exact:bool=committed.ok and int(program.completed)==1
			for item:String in r.inputs:exact=exact and float(rt.actor("player").pack.get(item,0))==float(before.get(item,0))-float(r.inputs[item])+float(r.outputs.get(item,0))
			for item:String in r.outputs:
				if not r.inputs.has(item):exact=exact and float(rt.actor("player").pack.get(item,0))==float(before.get(item,0))+float(r.outputs[item])
			check("actual arrival labor original single craft settlement "+label+" "+str(r.id),exact,{"commit":committed.get("code"),"program":program,"intent":rt.actor("player").get("intent")})
			if rt.actor("player").get("intent")!=null:send(rt,"cancel_action","")
			# Only this declared fixture replenishes stamina through original rest.
			var rest:=send(rt,"rest","")
			if rest.ok:
				for step:int in 125:rt.tick(.1)
			break
		var encoded:=Store.encode(rt.capture_checkpoint());var decoded:=Store.decode(encoded.text) if encoded.ok else encoded;var cold:=mount(decoded.capture) if decoded.get("ok",false) else decoded
		check("new paid grade exact canonical cold "+label,cold.get("ok",false) and Data.json_equal(cold.runtime.capture_checkpoint().facts,decoded.capture.facts) and Data.json_equal(cold.world.snapshot().extensions,decoded.capture.world.extensions),cold.get("reason"))
		if cold.get("ok",false):cold.runtime.retire()
		rt.retire()
	finish()
func finish()->void:
	var report:Dictionary={"checks":checks,"observations":observations,"scope":"Explicit flattened32m lab/finite declared pack, initial skills/book knowledge/station; current actual Native/Runtime commands and sole craft ledger. Not natural economy, package, OS, VA or FPS."}
	FileAccess.open(out+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print(JSON.stringify(report));quit(0 if not checks.is_empty() and checks.all(func(c:Dictionary)->bool:return c.ok) else 1)
