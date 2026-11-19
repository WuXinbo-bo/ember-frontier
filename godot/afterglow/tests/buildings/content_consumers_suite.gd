extends "res://tests/buildings/domain_suite.gd"
const Content=preload("res://scripts/runtime/content_definitions.gd")
const BuildingContent=preload("res://scripts/buildings/building_content.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")

func run()->void:
	var started:=Time.get_ticks_msec()
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json"))
	var assets:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/asset_manifest.json"))
	expect("all existing B definitions resolve actual item/use/tool/station/model capabilities",BuildingContent.validate(catalog,assets.models).ok)
	var bad:=catalog.duplicate(true);bad.production_recipes[0].inputs={"undefined_formal_item":1}
	expect("unknown formal recipe input is refused without legacy fallback",not BuildingContent.validate(bad,assets.models).ok)
	bad=catalog.duplicate(true);bad.production_recipes[0].outputs.timber=0.5
	expect("fractional count formal output is refused",not BuildingContent.validate(bad,assets.models).ok)
	bad=catalog.duplicate(true);bad.production_recipes[0].stationTags=["nonexistent_station"]
	expect("unknown station capability refused",not BuildingContent.validate(bad,assets.models).ok)
	bad=catalog.duplicate(true);bad.production_recipes[0].qualities={"nonexistent_tool_quality":1}
	expect("unknown tool capability refused",not BuildingContent.validate(bad,assets.models).ok)
	bad=catalog.duplicate(true);bad.structure_definitions.workbench.usePoints=[]
	expect("workbench with no real use point refused",not BuildingContent.validate(bad,assets.models).ok)
	bad=catalog.duplicate(true);bad.structure_definitions.cabinet.usePoints=[{"x":NAN,"y":0,"z":0}]
	expect("nonfinite use point refused before consumer",not BuildingContent.validate(bad,assets.models).ok)
	bad=catalog.duplicate(true);bad.structure_definitions.workbench.assetId="unbound_model"
	expect("required unbound actual furniture model refused",not BuildingContent.validate(bad,assets.models).ok)
	bad=catalog.duplicate(true);bad.production_recipes[0].seconds=0
	expect("invalid work duration refused",not BuildingContent.validate(bad,assets.models).ok)
	bad=catalog.duplicate(true);bad.production_recipes.append(bad.production_recipes[0].duplicate(true))
	expect("duplicate recipe identity refused",not BuildingContent.validate(bad,assets.models).ok)
	bad=catalog.duplicate(true);bad.production_recipes[2].repairTool.kind="unbound_tool"
	expect("unknown repaired tool definition refused",not BuildingContent.validate(bad,assets.models).ok)
	var item:=Content.item_definition("soil_m3");item.step=99
	expect("shared definition return cannot mutate source",Content.item_definition("soil_m3").step==0.001)
	expect("unknown inventory legacy adapter explicit only",Content.quantity_step("historic_grit_m3")==0 and Content.quantity_valid("historic_grit_m3",0.123456789,true) and not Content.quantity_valid("historic_grit_m3",0.123456789))
	expect("real finite rural world loads",world.load_snapshot(Generator.generate(713)).ok)
	initialize_at({"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var seed:=building.seed_rural(world);var prepared:=world.prepare_changes(seed.world_changes,world.get_revision())
	expect("real B structures commit through C",prepared.ok and world.commit_prepared(prepared.capability).ok)
	var at:Dictionary={"x":8,"y":0,"z":16,"regionId":"RH-HOME","buildingId":"rural:v1:RH-HOME:shed","storeyId":"rural:v1:RH-HOME:shed:ground"}
	initialize_at(at,[],seed.initial_stocks)
	var f:=runtime.facts();f.actors[0].pack={"soil_m3":0.12500000000000003,"historic_grit_m3":0.123456789,"water":2}
	expect("finite legacy volume fixture configures without rounding",runtime.configure({"world":world,"facts":f,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	var p:=Production.empty_state();p.tools=seed.initial_tools;p.records=seed.initial_records
	expect("sole production table retains actual tools and records",runtime._commit({"world_changes":[building.extension_change(Production.KEY,p)]}).ok)
	var stock:="rural:v1:RH-HOME:shed:storage"
	expect("actual stock search begins",command("search",stock).ok)
	for i in 10:runtime.tick(0.1)
	var amount:=0.10000000000000003
	var result:=command("deposit",stock,{"items":{"soil_m3":amount,"historic_grit_m3":0.023456789,"water":1}})
	expect("actual unit-aware finite transfer succeeds",result.ok,result)
	expect("m3 retains exact requested finite value instead of rounding to step",runtime.stock(stock).items.get("soil_m3")==amount and runtime.actor("player").pack.soil_m3==0.12500000000000003-amount)
	expect("explicit unknown old inventory remains conserved",runtime.stock(stock).items.get("historic_grit_m3")==0.023456789 and runtime.actor("player").pack.historic_grit_m3==0.123456789-0.023456789)
	var before:=runtime.capture_checkpoint()
	for invalid:Variant in [0.5,-1.0,NAN,INF,"1"]:
		result=command("deposit",stock,{"items":{"water":invalid}})
		expect("invalid actual count transfer is atomic "+str(invalid),not result.ok and runtime.capture_checkpoint()==before,result)
	var tx:=Draft.new(actions.context);var staged:=tx.staged.duplicate(true)
	expect("domain settlement rejects fractional count before mutating",not tx.stock_delta("pack:player",{"water":0.5}) and tx.staged==staged)
	expect("domain settlement retains arbitrary finite legacy volume",tx.stock_delta("pack:player",{"soil_m3":0.00000000017}) and tx.actor("player").pack.soil_m3==float(staged.actors[0].pack.soil_m3)+0.00000000017)
	var actor:=runtime.actor("player");actor.fatigue=100;actor.stamina=60
	expect("NPC cap reads staged fatigue rather than live actor ID",not actions.below_stamina_cap(actor) and runtime.actor("player").fatigue<100)
	var original:Dictionary=production.recipes.saw_timber.duplicate(true)
	production.recipes.saw_timber.inputs={"undefined_formal_item":1}
	result=command("craft","fixture:unbuilt-station",{"recipe_id":"saw_timber","source_id":"pack:player","output_id":"pack:player"})
	expect("actual command rejects unresolved formal recipe before order or inventory mutation",not result.ok and result.code=="INVALID_CONTENT_REFERENCE" and runtime.capture_checkpoint()==before,result)
	production.recipes.saw_timber=original
	expect("all definition and draft probes leave real authority unchanged",runtime.capture_checkpoint()==before)
	finish(started)
