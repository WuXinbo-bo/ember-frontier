extends "res://tests/buildings/domain_suite.gd"
## Referential restore checks are rejection only, never repair or reseed.
func rejected_extension(key:String,after:Dictionary,facts:Dictionary)->Dictionary:
	var op:Dictionary=building.extension_change(key,after)
	var draft:Dictionary=world.prepare_changes([op],world.get_revision())
	return draft if not draft.ok else building.validate_snapshot(draft.view,facts)

func run()->void:
	var started:=Time.get_ticks_msec()
	expect("real source world loads",world.load_snapshot(Generator.generate(713)).ok)
	var shed:="rural:v1:RH-HOME:shed"
	var at:Dictionary={"x":8,"y":0,"z":16,"regionId":"RH-HOME","buildingId":shed,"storeyId":shed+":ground"}
	initialize_at(at)
	var seeded:Dictionary=building.seed_rural(world)
	var draft:Dictionary=world.prepare_changes(seeded.world_changes,world.get_revision())
	expect("actual buildings seed",draft.ok and world.commit_prepared(draft.capability).ok)
	initialize_at(at,[],seeded.initial_stocks)
	var p:Dictionary=Production.empty_state();p.tools=seeded.initial_tools;p.records=seeded.initial_records
	draft=world.prepare_changes([building.extension_change(Production.KEY,p)],world.get_revision())
	expect("actual tools records installed",draft.ok and world.commit_prepared(draft.capability).ok)
	var good:Dictionary=building.validate_snapshot(world,runtime.facts())
	expect("complete rural snapshot valid",good.ok,good)
	var before:=world.snapshot();var facts:=runtime.facts()
	var duplicate:=facts.duplicate(true);duplicate.stocks.append(duplicate.stocks[0].duplicate(true))
	expect("duplicate stock identity rejected",not building.validate_snapshot(world,duplicate).ok)
	var orphan:=facts.duplicate(true);orphan.stocks[0].structureId="missing:actual-parent"
	expect("orphan stock parent rejected",not building.validate_snapshot(world,orphan).ok)
	var separated:=facts.duplicate(true);separated.stocks[0].location.x+=10
	expect("stock detached from actual furniture rejected",not building.validate_snapshot(world,separated).ok)
	var bad_tool:=p.duplicate(true);bad_tool.tools[0].holderId="pack:missing-resident"
	expect("tool holder identity checked on final draft",not rejected_extension(Production.KEY,bad_tool,facts).ok)
	bad_tool=p.duplicate(true);bad_tool.tools[0].durability=-1
	expect("negative tool durability rejected",not rejected_extension(Production.KEY,bad_tool,facts).ok)
	var bad_book:=facts.duplicate(true)
	for stock in bad_book.stocks:
		if stock.id==shed+":storage":stock.items.book_woodwork=0
	expect("knowledge source requires actual physical book",not building.validate_snapshot(world,bad_book).ok)
	var bad_structure:Dictionary=building.structures();bad_structure.instances[0].hp=100000
	expect("invalid structure HP rejected",not rejected_extension(Building.EXTENSION,bad_structure,facts).ok)
	bad_structure=building.structures();bad_structure.instances[0].position.x+=0.1
	expect("entity and structure extension disagreement rejected",not rejected_extension(Building.EXTENSION,bad_structure,facts).ok)
	var second_authority:=facts.duplicate(true);second_authority.tools=[]
	expect("second live tool table rejected even when empty",not building.validate_snapshot(world,second_authority).ok)
	expect("all rejected snapshots leave actual world intact",world.snapshot()==before)
	expect("actual search starts",command("search",shed+":storage").ok)
	for n in range(10):runtime.tick(0.1)
	expect("actual physical manual taken",command("take",shed+":storage",{"items":{"book_woodwork":1}}).ok)
	var record:=shed+":record:woodwork"
	expect("real active learning begins",command("study",record,{"record_id":record}).ok)
	expect("active order snapshot is valid",building.validate_snapshot(world,runtime.facts()).ok)
	var active:=production.state();active.orders[-1].sourceId="pack:missing-resident"
	expect("active order missing material holder rejected",not rejected_extension(Production.KEY,active,runtime.facts()).ok)
	active=production.state();active.orders[-1].actorId="missing-resident"
	expect("active order missing actor rejected",not rejected_extension(Production.KEY,active,runtime.facts()).ok)
	active=production.state();active.orders[-1].toolIds=[p.tools[0].id,p.tools[0].id]
	expect("duplicate active tool reservations rejected",not rejected_extension(Production.KEY,active,runtime.facts()).ok)
	finish(started)
