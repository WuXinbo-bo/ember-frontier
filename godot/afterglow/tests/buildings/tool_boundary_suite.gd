extends SceneTree
const World=preload("res://scripts/world/world_state.gd")
const Generator=preload("res://scripts/world/rural_generator.gd")
const Building=preload("res://scripts/buildings/building_service.gd")
const Actions=preload("res://scripts/actions/action_service.gd")
const Production=preload("res://scripts/production/production_service.gd")
const Terrain=preload("res://scripts/terrain/terrain_service.gd")
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
var checks:Array=[]
var runtime:=Runtime.new()
var world:=World.new()
var building:=Building.new()
var production:=Production.new()
var actions:=Actions.new()
var sequence:=0

func expect(label:String,ok:bool,evidence:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"evidence":evidence})
	if not ok:print("FAIL ",label," ",JSON.stringify(evidence))

func command(kind:String,payload:Dictionary={},target:String="near-stock")->Dictionary:
	sequence+=1
	return runtime.command({"actor_id":"player","command_id":"tool-boundary:"+str(sequence),"kind":kind,"target_id":target,"payload":payload,"expected_revision":runtime.get_revision()})

func _initialize()->void:call_deferred("run")

func run()->void:
	expect("real generated world loaded",world.load_snapshot(Generator.generate(713)).ok)
	var actor:Dictionary={"id":"player","name":"player","x":30.5,"y":0.0,"z":30.0,"regionId":"RH-HOME","buildingId":null,"storeyId":null,"hp":100.0,"hunger":90.0,"thirst":90.0,"fatigue":0.0,"stamina":100.0,"pack":{},"skills":{"crafting":0,"gathering":0},"intent":null,"relationship":{}}
	var facts:Dictionary={"time":0.0,"status":"playing","actors":[actor],"stocks":[{"id":"near-stock","items":{},"location":{"x":31,"y":0,"z":30,"regionId":"RH-HOME"},"searched":true,"owner":"player"}],"actions":[],"quests":[]}
	var p:Dictionary=Production.empty_state()
	# Explicit dual-purpose fixture tool exercises cross-domain exclusivity;
	# real source shovel qualities are separately checked unchanged by legacy_suite.
	p.tools=[{"id":"world-tool:shovel","kind":"shovel","holderId":"pack:player","durability":37.5,"qualities":{"shovel":1,"chopping":1}},{"id":"world-tool:pickaxe","kind":"pickaxe","holderId":"pack:player","durability":91,"qualities":{"pickaxe":1}}]
	var draft:Dictionary=world.prepare_changes([{"op":"extension.set","id":"r3:production","before_exists":false,"before":null,"after":p}],world.get_revision())
	expect("single production tool authority created",draft.ok and world.commit_prepared(draft.capability).ok)
	var configured:Dictionary=runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"production":production,"actions":actions,"terrain":Terrain.new()}})
	expect("actual A B C services configured",configured.ok,configured)
	var request:Dictionary={"tool_id":"world-tool:shovel","held":true,"edit":{"operation":"dig","cells":[{"x":59,"y":-1,"z":60}]}}
	var started:=command("terrain",request)
	expect("selected original shovel starts real terrain work",started.ok,started)
	expect("terrain intent reserves tool for B consumers",production.tool_unavailable("world-tool:shovel") and not production.tool_reserved("world-tool:shovel"))
	var denied:=command("deposit",{"tool_ids":["world-tool:shovel"]})
	expect("cannot transfer shovel in terrain work",not denied.ok and denied.code=="RESERVED",denied)
	var tx:=Draft.new(production.context)
	var tree:Dictionary=world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.kind=="tree")[0]
	var near:=Geometry.location(tree);near.z+=1.2
	tx.actor("player").merge(near,true)
	tx.staged.stocks.append_array(Generator.empty_resource_stocks(world))
	var work:Dictionary={"actor_id":"player","kind":"harvest","command_id":"overlap","target_id":tree.id,"payload":{"tool_ids":["world-tool:shovel"],"output_id":tree.data.outputId}}
	var production_order:=production.start(tx,work)
	expect("valid actual tree specifically rejects terrain-held tool",not production_order.ok and production_order.code=="RESERVED",production_order)
	var available:=Draft.new(production.context);available.staged=tx.staged.duplicate(true);available.actor("player").intent=null
	var available_order:=production.start(available,work)
	expect("same tree and tool otherwise permit actual harvest",available_order.ok,available_order)
	var paused:=command("held",{"held":false})
	# A must dispatch held by intent owner; if not, document that integration failure.
	expect("terrain held release routed to C",paused.ok and runtime.actor("player").intent.held==false,paused)
	for n in range(20):runtime.tick(0.1)
	expect("paused terrain holds tool without spending it",production.tool_unavailable("world-tool:shovel") and runtime.tool("world-tool:shovel").durability==37.5 and world.cell_at(59,-1,60)!=0)
	expect("cancel releases terrain reservation",command("cancel").ok and not production.tool_unavailable("world-tool:shovel"))
	expect("tool transfers after cancellation",command("deposit",{"tool_ids":["world-tool:shovel"]}).ok and runtime.tool("world-tool:shovel").holderId=="near-stock")
	expect("tool transfers back with original identity",command("take",{"tool_ids":["world-tool:shovel"]}).ok and runtime.tool("world-tool:shovel").holderId=="pack:player")
	expect("terrain can restart without self-reservation deadlock",command("terrain",request).ok)
	for n in range(15):runtime.tick(0.1)
	expect("real terrain completes through A clock",world.cell_at(59,-1,60)==0 and runtime.actor("player").intent==null,runtime.actor("player").activity)
	expect("exact sole tool wear .1, second tool untouched",is_equal_approx(runtime.tool("world-tool:shovel").durability,37.4) and runtime.tool("world-tool:pickaxe").durability==91)
	expect("real terrain m3 award once",is_equal_approx(float(runtime.actor("player").pack.get("soil_m3",0)),0.125),runtime.actor("player").pack)
	expect("reservation released on actual completion",not production.tool_unavailable("world-tool:shovel"))
	var malformed:Dictionary=p.duplicate(true);malformed.tools[0].durability=-1
	var invalid:Dictionary=world.prepare_changes([building.extension_change("r3:production",malformed)],world.get_revision())
	expect("malformed tool draft rejected before commit",invalid.ok and not building.validate_world_draft(invalid.view,runtime.facts(),[building.extension_change("r3:production",malformed)]).ok)
	print(JSON.stringify({"scope":"BBB terrain/production tool boundary using real A clock and C domain; not app acceptance","ok":checks.all(func(v:Dictionary)->bool:return v.ok),"checks":checks}))
	quit(0 if checks.all(func(v:Dictionary)->bool:return v.ok) else 1)
