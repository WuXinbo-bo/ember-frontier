extends SceneTree
## Uses production A/B/C modules. No alternate runtime/inventory implementation.
const World = preload("res://scripts/world/world_state.gd")
const Generator = preload("res://scripts/world/rural_generator.gd")
const Runtime = preload("res://scripts/runtime/game_runtime.gd")
const Router = preload("res://scripts/input/input_router.gd")
const Building = preload("res://scripts/buildings/building_service.gd")
const Actions = preload("res://scripts/actions/action_service.gd")
const Production = preload("res://scripts/production/production_service.gd")
const Mount = preload("res://scripts/ui/ui_mount.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
var checks: Array = []
var failed := false

func _initialize() -> void:
	create_timer(30).timeout.connect(func():quit(2))
	call_deferred("run")

func check(name: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok: failed=true;push_error(name+" "+str(detail))

func run() -> void:
	var world:=World.new()
	var result: Dictionary=world.load_snapshot(Generator.generate(713))
	check("real C generated world",result.get("ok",false),result.get("reason"))
	var runtime:=Runtime.new()
	var building:=Building.new()
	var actions:=Actions.new()
	var production:=Production.new()
	var position: Dictionary={"x":30.0,"y":0.0,"z":43.0,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	var actor: Dictionary={"id":"player","name":"连接检查角色","hp":100.0,"hunger":100.0,"thirst":100.0,"fatigue":0.0,"stamina":100.0,"pack":{"food":2},"skills":{"crafting":2},"relationship":{"member":true,"consent":true},"intent":null}
	actor.merge(position)
	var chest: Dictionary={"id":"ui-connection:chest","owner":"home-residents","searched":true,"items":{"food":4},"location":position.duplicate()}
	result=runtime.configure({"world":world,"services":{"buildings":building,"production":production,"actions":actions},"facts":{"time":0.0,"status":"playing","actors":[actor],"stocks":[chest],"actions":[],"quests":[]}})
	check("real A runtime and B services configure",result.get("ok",false),result.get("reason"))
	var p: Dictionary=Production.empty_state()
	p.tools=[{"id":"ui-connection:axe","kind":"salvaged_axe","holderId":chest.id,"durability":94.0}]
	var prepared: Dictionary=world.prepare_changes([building.extension_change(Production.KEY,p)],world.get_revision())
	check("real C accepts B production fixture",prepared.get("ok",false),prepared.get("reason"))
	if not prepared.get("ok",false):finish();return
	result=world.commit_prepared(prepared.capability)
	check("real C commits fixture once",result.get("ok",false))
	var router:=Router.new()
	root.add_child(router)
	router.configure(runtime)
	var ui: Control=Mount.mount(root,runtime,router)
	await process_frame
	ui.open_panel("container",chest.id)
	var snapshot: Dictionary=runtime.snapshot()
	check("actual runtime exposes nearby container",P.stock(snapshot,chest.id).get("id")==chest.id)
	var source: Dictionary=ui.layout.cells(P.stock(snapshot,chest.id),snapshot)[0]
	source.merge({"kind":"inventory","stock_id":chest.id,"reference":{"kind":"item","item_id":"food"}})
	var data: Dictionary=ui._create_drag(source)
	ui._drop({"kind":"inventory","stock_id":"pack:player","index":18},data)
	await process_frame
	snapshot=runtime.snapshot()
	check("UI drop traverses real A command B transfer C draft",runtime.actor("player").pack.food==6 and runtime.stock(chest.id).items.food==0,{"pack":runtime.actor("player").pack,"stock":runtime.stock(chest.id).items,"notice":ui._notice.text})
	var cells: Array=ui.layout.cells(P.player_stock(snapshot),snapshot)
	check("real transfer arrives at requested UI cell",cells[18].entry.get("key")=="item:food" and cells[18].quantity==4)
	var tool_cell: Dictionary={}
	for cell: Dictionary in ui.layout.cells(P.stock(snapshot,chest.id),snapshot):
		if cell.entry.get("key")=="tool:ui-connection:axe":tool_cell=cell
	check("actual unique tool visible in container",not tool_cell.is_empty())
	if not tool_cell.is_empty():
		tool_cell.merge({"kind":"inventory","stock_id":chest.id,"reference":{"kind":"tool","tool_id":"ui-connection:axe"}})
		data=ui._create_drag(tool_cell)
		ui._drop({"kind":"inventory","stock_id":"pack:player","index":19},data)
		await process_frame
		snapshot=runtime.snapshot()
		check("tool transfer changes sole B holder",runtime.tool("ui-connection:axe").get("holderId")=="pack:player",ui._notice.text)
		var actual: Dictionary=ui.layout.cells(P.player_stock(snapshot),snapshot)[19]
		actual.merge({"kind":"inventory","stock_id":"pack:player","reference":{"kind":"tool","tool_id":"ui-connection:axe"}})
		data=ui._create_drag(actual)
		ui._drop({"kind":"hotbar","index":2},data)
		check("actual tool binds through real router",router.state().slots[2].get("id")=="ui-connection:axe")
	var before:=runtime.clock()
	runtime.tick(0.5)
	check("real inventory UI freezes sole runtime clock",runtime.clock()==before)
	var food_cell: Dictionary={}
	for cell: Dictionary in ui.layout.cells(P.player_stock(snapshot),snapshot):
		if cell.entry.get("key")=="item:food":food_cell=cell;break
	food_cell.merge({"kind":"inventory","stock_id":"pack:player","reference":{"kind":"item","item_id":"food"}})
	data=ui._create_drag(food_cell)
	result=runtime.command({"command_id":"ui-connection:authoritative-deposit","actor_id":"player","kind":"deposit","target_id":chest.id,"payload":{"items":{"food":6},"tool_ids":[]},"destination":{},"expected_revision":runtime.get_revision()})
	check("source can change through real authoritative command",result.get("ok",false),result.get("reason"))
	var facts_before: Dictionary=runtime.facts()
	var revision_before:=world.get_revision()
	ui._drop({"kind":"inventory","stock_id":"pack:player","index":20},data)
	check("stale source drop neither moves another stack nor mutates authority",facts_before==runtime.facts() and revision_before==world.get_revision(),ui._notice.text)
	ui.cancel_transient()
	ui.close_panels()
	runtime.tick(0.5)
	check("close inventory resumes sole clock",runtime.clock()>before)
	ui.get_parent().queue_free()
	router.queue_free()
	await process_frame
	finish()

func finish() -> void:
	print(JSON.stringify({"scope":"actual A/B/C/UI headless connection; not exported app or complete IO route","ok":not failed,"checks":checks}))
	quit(1 if failed else 0)
