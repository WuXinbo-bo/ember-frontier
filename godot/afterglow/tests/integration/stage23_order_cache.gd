extends SceneTree
## A discarded NPC prepare must not mutate the performance schema cache.
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Data=preload("res://scripts/world/world_data.gd")
const KEY="r34:workforce"
var checks:Array=[]
var output:String
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool)->void:
	checks.append({"name":label,"ok":ok})
	if not ok:print("FAIL "+label)
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed},"\t"))
	quit(1 if failed else 0)
func workforce_change(plan:Dictionary)->Dictionary:
	for change:Dictionary in plan.get("world_changes",[]):
		if change.get("id")==KEY:return change
	return {}
func run()->void:
	output=OS.get_cmdline_user_args()[0]
	var profiles:=Assembly.generation_profiles()
	var opening:=Assembly.prepare(Assembly.generate(713,profiles.profiles))
	check("current village prepares",opening.ok)
	if not opening.ok:return finish()
	var warehouse:Dictionary=opening.capture.world.extensions["r34:modules"].instances.filter(func(v:Dictionary)->bool:return v.id=="r34:generated:RH-HOME:village-warehouse")[0]
	for stock:Dictionary in opening.capture.facts.stocks:
		for item:String in warehouse.restoration.cost:stock.items.erase(item)
	for actor:Dictionary in opening.capture.facts.actors:
		for item:String in warehouse.restoration.cost:actor.pack.erase(item)
	var host:=Native.new();var built:=host._assemble(opening.capture)
	check("current authority assembles",built.ok)
	if not built.ok:host.free();return finish()
	var rt:RefCounted=built.runtime
	var request:Dictionary={"kind":"workforce.assign","actor_id":"village-resident","command_id":"stage23:cache-order","target_id":"","payload":{"candidate_id":"building-order:"+str(warehouse.id)}}
	var assigned:Dictionary=rt.command(request)
	check("real pending work order admitted",assigned.ok)
	if assigned.ok:
		var service:RefCounted=rt.domain_service("workforce")
		var authority_before:Dictionary=built.world.extension(KEY)
		var proof_before:Dictionary=service._check_extension(KEY).source.duplicate(true)
		var first:Dictionary=service.advance(.1)
		var first_change:=workforce_change(first)
		check("prepare actually stages a pending order change",first.ok and not first_change.is_empty() and not Data.json_equal(first_change.after,authority_before))
		check("discarded prepare leaves world authority unchanged",Data.json_equal(authority_before,built.world.extension(KEY)))
		check("discarded prepare leaves cached proof unchanged",Data.json_equal(proof_before,service._check_extension(KEY).source))
		var second:Dictionary=service.advance(.1)
		check("repeat prepare returns the same order change",second.ok and not first_change.is_empty() and Data.json_equal(first_change,workforce_change(second)))
		check("repeat prepare still leaves authority unchanged",Data.json_equal(authority_before,built.world.extension(KEY)))
	rt.retire();host.free();finish()
