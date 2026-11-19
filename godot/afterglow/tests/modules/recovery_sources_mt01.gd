extends "res://tests/modules/factory_boundary_fixture.gd"
const Generator=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
func run()->void:
	var profiles:Array=Modules.generation_profiles()
	for version:int in [4,5,6]:
		var lock:Dictionary=Contract.fresh(profiles,version,1)
		var generated:Dictionary=Generator.generate(713,profiles,lock.contract)
		var world:=World.new();var loaded:Dictionary=world.load_snapshot(generated)
		check("content"+str(version)+" actual generated world loads",loaded.ok,loaded)
		if not loaded.ok:continue
		var service:=Modules.new();var reg:Dictionary=service.prepare_generation(world)
		check("content"+str(version)+" original source registration succeeds",reg.ok,reg)
		if not reg.ok:continue
		var id:String="RH-HOME:stockyard-content:container"
		var stock:=Draft.find(reg.initial_stocks,id);var reserve:Array=reg.initial_tools.filter(func(t:Dictionary)->bool:return str(t.id).begins_with(id+":reserve-tool:"))
		check("content"+str(version)+" exact MT01 additive count",reserve.size()==(5 if version>=5 else 0))
		check("content"+str(version)+" original parts/main shovel/pick remain",stock.items.axe_head==1 and stock.items.tool_handle==1 and stock.items.scrap==4 and reg.initial_tools.filter(func(t:Dictionary)->bool:return t.id in [id+":tool:shovel",id+":tool:pickaxe"] and t.durability==100).size()==2)
		for kind:String in ["salvaged_axe","hand_saw","hammer","shovel","pickaxe"]:
			if version<5:continue
			var tool:=Draft.find(reserve,id+":reserve-tool:"+kind)
			check("unique finite reserve "+kind+" content"+str(version),tool.get("kind")==kind and tool.get("durability")==40 and tool.get("holderId")==id)
		if version>=5:
			check("String inventory keys preserve strict fact validation",stock.items.keys().all(func(k:Variant)->bool:return k is String) and stock.items.cloth==2 and stock.items.book_tool_repair==1)
			var record:=Draft.find(reg.initial_records,id+":reserve-record:book_tool_repair")
			check("one real reserve book record at original holder",record.get("holderId")==id and record.get("itemId")=="book_tool_repair" and record.get("grants")==["basic_tool_repair"] and record.get("seconds")==12)
		var plan:Dictionary=world.extension("generation:RH-HOME")
		check("source position exactly persistent plan",G.point(stock.location)==G.point(plan.content_anchors.filter(func(v:Dictionary)->bool:return v.purpose=="stockyard-and-recovery")[0].position))
		var prepared:Dictionary=world.prepare_changes(reg.world_changes,world.get_revision())
		check("registration stages exact unique world changes",prepared.ok,prepared)
		if prepared.ok:
			var committed:Dictionary=world.commit_prepared(prepared.capability)
			var repeat:Dictionary=service.prepare_generation(world)
			check("receipt prevents every second stock tool record and source grant",committed.ok and repeat.ok and repeat.initial_stocks.is_empty() and repeat.initial_tools.is_empty() and repeat.initial_records.is_empty() and repeat.world_changes.is_empty(),repeat)
		var opening:Dictionary=Assembly.prepare(generated)
		check("strict actual Assembly includes valid stocks and source identities",opening.ok,opening)
		if opening.ok:
			var cold:=mount(opening.capture,"content"+str(version)+" full cold source")
			check("all reserves/receipts survive Native cold",cold.ok and Data.json_equal(cold.runtime.capture_checkpoint().facts,opening.capture.facts))
		evidence.append({"content":version,"reserve_count":reserve.size(),"stock":stock,"source_receipts":world.extension(Modules.KEY).source_receipts})
	finish()
