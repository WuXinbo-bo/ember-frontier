extends SceneTree
## Warm string metadata must never admit changed facts, CAS or stale capabilities.
const Data=preload("res://scripts/world/world_data.gd")
const State=preload("res://scripts/world/world_state.gd")
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Modules=preload("res://scripts/modules/module_service.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func run()->void:
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,Modules.generation_profiles()))
	check("actual normal opening with original authority",prepared.get("ok",false),prepared.get("reason"))
	if not prepared.get("ok",false):finish();return
	var source:Dictionary=prepared.capture
	var original_source:Dictionary=source.duplicate(true)
	check("whole world validation warms original IDs",Data.validate(source.world).ok)
	var id:String=source.world.entities.keys()[0]
	var changed:Dictionary=source.world.duplicate(true)
	changed.entities[id].bounds.max.x=changed.entities[id].bounds.min.x
	check("same warm entity ID still rejects changed invalid bounds",not Data.validate(changed).ok)
	changed=source.world.duplicate(true);changed.entities[id].regionId="test:warm:missing-region"
	Data.valid_id(changed.entities[id].regionId)
	check("warm pure region name does not prove actual region existence",not Data.validate(changed).ok)
	changed=source.world.duplicate(true);changed.retiredEntityIds.append(id)
	check("live warm identity cannot be retired simultaneously",not Data.validate(changed).ok)
	check("complete runtime facts still validate",Runtime.validate_facts(source.facts).ok)
	var facts:Dictionary=source.facts.duplicate(true);facts.actors[0].hp=-1
	check("warm actor still rejects changed illegal HP",not Runtime.validate_facts(facts).ok)
	facts=source.facts.duplicate(true);facts.actors.append(facts.actors[0].duplicate(true))
	check("warm actor name does not waive duplicate identity rejection",not Runtime.validate_facts(facts).ok)
	facts=source.facts.duplicate(true);facts.stocks.append(facts.stocks[0].duplicate(true))
	check("warm stock name does not waive duplicate stock rejection",not Runtime.validate_facts(facts).ok)
	Data.valid_id("wood")
	facts=source.facts.duplicate(true);facts.stocks[0].items["wood"]=-1
	check("warm item name does not waive real quantity validation",not Runtime.validate_facts(facts).ok)
	var world:=State.new();var loaded:Dictionary=world.load_snapshot(source.world)
	check("actual State loads unchanged source",loaded.ok)
	var key:String="test:cache-purity";Data.valid_id(key)
	var changes:Array=[{"op":"extension.set","id":key,"before_exists":false,"before":null,"after":{"n":1}}]
	var first:Dictionary=world.prepare_changes(changes,world.get_revision())
	var concurrent:Dictionary=world.prepare_changes(changes,world.get_revision())
	check("two real isolated preparations accepted at same base",first.ok and concurrent.ok)
	if first.ok and concurrent.ok:
		check("one actual capability commits",world.commit_prepared(first.capability).ok)
		var committed:Dictionary=world.snapshot()
		var stale:Dictionary=world.commit_prepared(concurrent.capability)
		check("warm ID cannot bypass stale world revision",not stale.ok and stale.code=="STALE_WORLD_REVISION",stale)
		check("consumed capability still refuses replay",not world.commit_prepared(first.capability).ok)
		check("warm string cannot fabricate a prepared capability",not world.commit_prepared(RefCounted.new()).ok)
		var wrong:Array=[{"op":"extension.set","id":key,"before_exists":true,"before":{"n":0},"after":{"n":2}}]
		var denied:Dictionary=world.prepare_changes(wrong,world.get_revision())
		check("same cached extension ID still requires exact CAS",not denied.ok and denied.code=="CAS_MISMATCH",denied)
		check("all refused transactions preserve full world",Data.json_equal(committed,world.snapshot()))
	var host:=Native.new();var built:Dictionary=host._assemble(source);host.free()
	check("actual Native assembles original authority",built.get("ok",false),built.get("reason"))
	if built.get("ok",false):
		var runtime:RefCounted=built.runtime;var before:Dictionary=runtime.capture_checkpoint()
		for value:String in ["test:unknown-actor","test:warm-command","test:stale-command"]:Data.valid_id(value)
		var denied:Dictionary=runtime.command({"command_id":"test:warm-command","actor_id":"test:unknown-actor","kind":"eat"})
		check("warm actor syntax does not confer identity or command rights",not denied.ok,denied)
		denied=runtime.command({"command_id":"test:stale-command","actor_id":"player","kind":"eat","expected_revision":int(before.command_revision)+1})
		check("warm command name cannot bypass runtime expected revision",not denied.ok and denied.code=="STALE_REVISION",denied)
		check("refused runtime commands preserve complete original capture",Data.json_equal(before,runtime.capture_checkpoint()))
	check("original opening input was not mutated",Data.json_equal(original_source,prepared.capture))
	finish()
func finish()->void:
	var report:Dictionary={"scope":"actual Native/Runtime/State changed-fact and transaction negative controls with warmed ID predicate; no renderer/app/user slot","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var f:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t",true,true));f.close()
	print(JSON.stringify({"checks":checks.size(),"failed":report.failed}));quit(1 if report.failed else 0)
