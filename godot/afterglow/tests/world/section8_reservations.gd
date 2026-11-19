extends SceneTree
## Cross-domain acceptance probe: actual C intent, A clock/restore, B inventory.
## A missing B reservation is reported as a failure, never converted into a
## passing C-only mock or worked around by writing another inventory owner.
const State = preload("res://scripts/world/world_state.gd")
const Generator = preload("res://scripts/world/rural_generator.gd")
const Codec = preload("res://scripts/world/world_codec.gd")
const Terrain = preload("res://scripts/terrain/terrain_service.gd")
const Runtime = preload("res://scripts/runtime/game_runtime.gd")
const Building = preload("res://scripts/buildings/building_service.gd")
const Actions = preload("res://scripts/actions/action_service.gd")
const Production = preload("res://scripts/production/production_service.gd")
var checks: Array = []
var gaps: Array = []
var world := State.new()
var runtime := Runtime.new()
var production := Production.new()
var services := {"terrain":Terrain.new(),"buildings":Building.new(),"actions":Actions.new(),"production":production}
var sequence := 0

func check(label: String,ok: bool,detail: Variant=null) -> void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok: print("FAIL ",label," ",JSON.stringify(detail))

func command(kind: String,payload: Dictionary={},target: String="fixture:near-stock") -> Dictionary:
	sequence+=1
	if kind=="terrain": target="terrain:59:-1:60"
	return runtime.command({"command_id":"terrain-hold:"+str(sequence),"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"expected_revision":runtime.get_revision()})

func steps(count: int) -> void:
	for i in count: runtime.tick(0.1)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	check("finite world loaded",world.load_snapshot(Generator.generate()).ok)
	var p := Production.empty_state()
	p.tools=[{"id":"fixture:shovel","kind":"shovel","holderId":"pack:player","durability":90.0,"qualities":{"shovel":1}}]
	var change := {"op":"extension.set","id":"r3:production","before_exists":false,"before":null,"after":p}
	var draft: Dictionary = world.prepare_changes([change],world.get_revision())
	check("sole production authority installed",draft.ok and world.commit_prepared(draft.capability).ok)
	var actor := {"id":"player","x":29.2,"y":0.0,"z":30.25,"regionId":"RH-HOME","buildingId":null,"storeyId":null,"hp":100.0,"hunger":100.0,"thirst":100.0,"stamina":100.0,"fatigue":0.0,"pack":{"soil_m3":1.0},"intent":null,"relationship":{"consent":true}}
	var stock := {"id":"fixture:near-stock","items":{},"owner":"player","searched":true,"location":{"x":28.75,"y":0,"z":30.25,"regionId":"RH-HOME","buildingId":null,"storeyId":null}}
	check("real A/B/C services configured",runtime.configure({"world":world,"facts":{"actors":[actor],"stocks":[stock],"actions":[],"quests":[],"time":0.0,"status":"playing"},"services":services}).ok)
	var dig := {"tool_id":"fixture:shovel","held":true,"edit":{"operation":"dig","cells":[{"x":59,"y":-1,"z":60}]}}
	var started := command("terrain",dig)
	check("dig reserves no future material output",started.ok and runtime.actor("player").intent.get("cost")=={})
	steps(15)
	check("real dig creates fill target without early award",started.ok and world.cell_at(59,-1,60)==0 and runtime.actor("player").intent==null and is_equal_approx(runtime.actor("player").pack.soil_m3,1.125))
	var fill := {"tool_id":"fixture:shovel","held":true,"edit":{"operation":"fill","material":2,"cells":[{"x":59,"y":-1,"z":60}]}}
	started=command("terrain",fill)
	var intent: Dictionary = runtime.actor("player").get("intent",{}).duplicate(true)
	check("C intent publishes stable id/source and net actual material cost",started.ok and intent.get("id")==started.get("command_id") and intent.get("source_id")=="pack:player" and intent.get("cost")=={"soil_m3":0.125},intent)
	var held := command("held",{"held":false})
	check("paused terrain retains same reservation identity and tool",held.ok and runtime.actor("player").intent.id==intent.id and production.tool_unavailable("fixture:shovel"))
	var saved_intent: Dictionary = runtime.actor("player").intent.duplicate(true)
	var encoded := Codec.encode_checkpoint(world.snapshot(),{"runtime":runtime.facts()},"section8:terrain-hold")
	var decoded: Dictionary = Codec.decode_checkpoint(encoded.envelope) if encoded.ok else encoded
	var restored := false
	if decoded.ok and world.load_snapshot(decoded.state).ok:
		restored=runtime.configure({"world":world,"facts":decoded.extensions.runtime,"services":services}).ok
	# Godot JSON numbers decode as floats. Compare the exact encoded fact,
	# including nested request/cost, rather than requiring an in-memory int tag.
	var serialized_intent: Variant = JSON.parse_string(JSON.stringify(saved_intent,"",true,true))
	check("saved pending intent restores encoded cost/source/id without another authority",restored and runtime.actor("player").intent==serialized_intent,decoded.get("code"))
	var amount: float = production.reserved("pack:player","soil_m3")
	check("B query includes paused terrain material and excludes own id",is_equal_approx(amount,0.125) and production.reserved("pack:player","soil_m3",intent.id)==0.0,{"actual_reserved":amount,"expected":0.125,"intent_id":intent.id})
	var spare := command("deposit",{"items":{"soil_m3":1.0}})
	check("unreserved surplus can still be transferred during terrain work",spare.ok and is_equal_approx(runtime.actor("player").pack.soil_m3,0.125),spare)
	var before := runtime.facts()
	var denied := command("deposit",{"items":{"soil_m3":0.125}})
	check("actual B transfer cannot spend paused terrain-held material",not denied.ok and denied.get("code")=="RESERVED" and runtime.facts()==before,denied)
	if denied.ok or amount!=0.125:
		gaps.append({"owner":"B production_service.reserved","intent":intent,"actual_reserved":amount,"request":{"kind":"deposit","target_id":stock.id,"payload":{"items":{"soil_m3":0.125}}},"actual_receipt":denied,"required":"count owner=terrain/kind=terrain source_id/cost, excluding own id, including tx.staged and paused intents; do not count output"})
	var tool_denied := command("deposit",{"tool_ids":["fixture:shovel"]})
	check("B still protects the tool while material boundary is inspected",not tool_denied.ok and tool_denied.get("code")=="RESERVED",tool_denied)
	command("held",{"held":true});steps(15)
	if denied.ok:
		check("missing reservation still fails closed at C completion without free terrain",world.cell_at(59,-1,60)==0 and runtime.actor("player").intent==null and runtime.actor("player").pack.soil_m3==0.0 and is_equal_approx(runtime.tool("fixture:shovel").durability,89.9),runtime.actor("player"))
		command("take",{"items":{"soil_m3":0.125}})
		started=command("terrain",fill);steps(15)
		check("C can restart and complete after returning actual material",started.ok and world.cell_at(59,-1,60)==2 and runtime.actor("player").intent==null,started)
	else:
		check("C completion excludes own hold and commits exact material once",world.cell_at(59,-1,60)==2 and runtime.actor("player").intent==null and runtime.actor("player").pack.soil_m3==0.0)
	check("actual completion releases all terrain holds",production.reserved("pack:player","soil_m3")==0.0 and not production.tool_unavailable("fixture:shovel"))
	var cancel_dig := command("terrain",dig);steps(15)
	var cancel_fill := command("terrain",fill)
	check("real material-consuming fill can restart for cancellation",cancel_dig.ok and cancel_fill.ok and runtime.actor("player").intent.cost=={"soil_m3":0.125})
	command("held",{"held":false})
	var cancel_before: float = runtime.actor("player").pack.soil_m3
	var cancelled := command("cancel")
	check("cancelling paused fill releases intent/material/tool without spending",cancelled.ok and runtime.actor("player").intent==null and runtime.actor("player").pack.soil_m3==cancel_before and world.cell_at(59,-1,60)==0 and production.reserved("pack:player","soil_m3")==0.0 and not production.tool_unavailable("fixture:shovel"),cancelled)
	var failed := checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var result := {"scope":"real C pending terrain hold through A runtime/codec and B transfer; not formal app acceptance","checks":checks,"failed":failed,"shared_reservation_gaps":gaps}
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var file := FileAccess.open(args[0],FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t",true,true)+"\n")
	print(JSON.stringify(result));services.terrain.configure({});quit(1 if failed else 0)
