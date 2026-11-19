extends "res://tests/modules/factory_boundary_fixture.gd"
## Existing five methods only; no sixth recipe invented. Tests real identity
## creation/repair and exact input/output settlement through original actions.
func run()->void:
	var capture:=opening()
	if capture.is_empty():finish();return
	var m:Dictionary=capture.world.extensions[Modules.KEY].instances.filter(func(v:Dictionary)->bool:return Modules.definition(v.definition_id).shape=="manual" and v.region=="RH-HOME")[0]
	put_actor(capture,port(m,"work"))
	var a:=Draft.find(capture.facts.actors,"player")
	a.pack={"log":1,"timber":0,"scrap":4,"tool_handle":1,"axe_head":1};a.skills.crafting=2.0
	var legacy:Dictionary=capture.world.extensions["r3:production"]
	legacy.knowledge["player"]=["basic_woodwork","basic_tool_repair"]
	var ids:Dictionary={}
	for t:Dictionary in legacy.tools:
		if t.kind in ["hand_saw","hammer","salvaged_axe"] and not ids.has(t.kind):
			ids[t.kind]=t.id;t.holderId="pack:player";t.durability=20.0 if t.kind=="salvaged_axe" else 100.0
	var mounted:=mount(capture,"finite recipe and known-method fixture")
	if not mounted.ok:finish();return
	var rt:RefCounted=mounted.runtime;var production:RefCounted=mounted.services.production
	var initial_tools:int=production.state().tools.size()
	var station:String=m.config.workbench_id
	for recipe_id:String in ["saw_timber","make_handle","assemble_field_axe","repair_axe","assemble_brace"]:
		var recipe:Dictionary=production.recipes[recipe_id]
		var original_pack:Dictionary=rt.actor("player").pack.duplicate(true)
		var original_tools:Array=production.state().tools.duplicate(true)
		var expected:Dictionary=original_pack.duplicate(true)
		for item:String in recipe.inputs:expected[item]=float(expected.get(item,0))-float(recipe.inputs[item])
		for item:String in recipe.outputs:expected[item]=float(expected.get(item,0))+float(recipe.outputs[item])
		var payload:Dictionary={"direct":false,"recipe_id":recipe_id,"source_id":"pack:player","output_id":"pack:player","tool_ids":[ids.hand_saw,ids.hammer]}
		if recipe_id=="repair_axe":payload.repair_tool_id=ids.salvaged_axe
		var command_id:String="B:craft-identity:"+recipe_id
		var started:=command(rt,"craft",station,payload,"player",command_id)
		check(recipe_id+" accepts existing actual method at original workbench",started.ok,started)
		if not started.ok:continue
		check(recipe_id+" admission only reserves original inputs",Data.json_equal(original_pack,rt.actor("player").pack))
		for i:int in 450:
			rt.tick(0.1)
			var found:Dictionary=Draft.find(production.state().orders,command_id+":order")
			if found.get("status")=="completed":break
		var order:Dictionary=Draft.find(production.state().orders,command_id+":order")
		check(recipe_id+" actual work duration completes once",order.get("status")=="completed" and is_equal_approx(float(order.get("elapsed",-1)),float(recipe.seconds)),order)
		check(recipe_id+" exact original pack transformation preserves every other item",Data.json_equal(expected,rt.actor("player").pack),{"before":original_pack,"expected":expected,"actual":rt.actor("player").pack})
		var tools:Array=production.state().tools
		if recipe.has("createTool"):
			var created:Dictionary=Draft.find(tools,command_id+":order:tool")
			check("assembly consumes components and creates one original-method identity",tools.size()==original_tools.size()+1 and created.get("kind")=="salvaged_axe" and created.get("holderId")=="pack:player" and created.get("durability")==65 and rt.tool(ids.salvaged_axe).durability==20,created)
		elif recipe.has("repairTool"):
			check("repair restores original axe without creating a replacement",tools.size()==original_tools.size() and rt.tool(ids.salvaged_axe).durability==80 and rt.tool(ids.salvaged_axe).holderId=="pack:player")
		else:check(recipe_id+" does not create tools",tools.size()==original_tools.size())
		var source:Dictionary=rt.capture_checkpoint()
		check(recipe_id+" replay cannot spend inputs or settle another output",command(rt,"craft",station,payload,"player",command_id).ok and Data.json_equal(source,rt.capture_checkpoint()))
		var before_pack:Dictionary=rt.actor("player").pack.duplicate(true);var before_tools:Array=production.state().tools.duplicate(true)
		tick(rt,5)
		check(recipe_id+" completed idle ticks cannot duplicate product or wear",Data.json_equal(before_pack,rt.actor("player").pack) and Data.json_equal(before_tools,production.state().tools))
		evidence.append({"recipe_id":recipe_id,"inputs":recipe.inputs,"outputs":recipe.outputs,"order_id":command_id+":order","actual_pack":rt.actor("player").pack,"create_tool":recipe.get("createTool"),"repair_tool":recipe.get("repairTool")})
	check("all five actual methods traversed with one additional tool only",evidence.size()==5 and production.state().tools.size()==initial_tools+1)
	var final:Dictionary=rt.capture_checkpoint();var cold:=mount(final,"completed distinct methods checkpoint")
	check("cold restore retains exact original item tool method settlements",cold.ok and Data.json_equal(final.facts,cold.runtime.facts()) and Data.json_equal(production.state(),cold.services.production.state()))
	finish()
