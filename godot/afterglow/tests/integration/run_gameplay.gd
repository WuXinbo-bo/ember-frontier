extends SceneTree
## Isolated real A/B/C command integration. Fixtures are explicit, never app acceptance.
const Client=preload("res://scripts/runtime/native_client.gd")
const World=preload("res://scripts/world/world_state.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const Building=preload("res://scripts/buildings/building_service.gd")
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
const Initial=preload("res://scripts/runtime/initial_state.gd")
const Gameplay=preload("res://scripts/runtime/rural_gameplay.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
var host:Node
var runtime:RefCounted
var seq:=0
func _initialize() -> void:call_deferred("run")
func check(name:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+name+" "+str(detail))
func request(kind:String,target:String="",payload:Dictionary={}) -> Dictionary:
	seq+=1
	return runtime.command({"command_id":"test:"+str(seq),"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"expected_revision":runtime.get_revision()})
func state()->Dictionary:return runtime.world.extension(Gameplay.KEY)
func run()->void:
	var output:String=OS.get_cmdline_user_args()[0]
	var world:=World.new();check("finite rural source loaded",world.load_snapshot(Rural.generate(713)).ok)
	var temporary_runtime:=Runtime.new()
	var b:=Building.new();b.configure({"world":world,"runtime":temporary_runtime})
	var seed:Dictionary=b.seed_rural(world)
	check("B actual rural buildings seeded",seed.ok,seed.get("reason"))
	if not seed.ok:finish(output);return
	var facts:Dictionary=Initial.facts(seed)
	# Fixture starts on the real village road with one running exploration and a
	# real unique axe. We do not call this fixture a completed travel route.
	facts.actors[0].merge({"x":32.0,"y":0.0,"z":-11.2,"regionId":"RH-VILLAGE","buildingId":null,"storeyId":null,"stamina":100.0},true)
	configure_fixture(facts)
	check("explicit initial fixture facts validate",Runtime.validate_facts(facts).ok,facts if not Runtime.validate_facts(facts).ok else null)
	var gameplay:Dictionary=Gameplay.initial()
	gameplay.exploration.merge({"status":"running","run_id":"fixture-run"},true)
	var production:Dictionary=Initial.production(seed)
	production.tools.append({"id":"fixture:axe","kind":"salvaged_axe","holderId":"pack:player","durability":90.0})
	var changes:Array=seed.world_changes.duplicate(true)
	changes.append_array([{"op":"extension.set","id":"r3:production","before_exists":false,"before":null,"after":production},{"op":"extension.set","id":Gameplay.KEY,"before_exists":false,"before":null,"after":gameplay},{"op":"extension.set","id":"r3:structure-orders","before_exists":false,"before":null,"after":{"version":1,"orders":[]}}])
	var draft:Dictionary=world.prepare_changes(changes,world.get_revision());check("combined fixture prepares",draft.ok,draft.get("reason"))
	if not draft.ok:finish(output);return
	check("fixture commit",world.commit_prepared(draft.capability).ok)
	host=Client.new()
	var assembled:Dictionary=host._assemble({"world":world.snapshot(),"facts":facts,"source":{"test":"isolated integration"}})
	check("actual formal client assembles all real services",assembled.ok,assembled.get("reason"))
	if not assembled.ok:finish(output);return
	runtime=assembled.runtime
	check("gameplay choices are real commands",runtime.snapshot().has("exploration"))
	check("exploration cannot restart to reroll",not request("explore_start").ok)
	check("NPC cannot be assigned before voluntary consent",not request("job","village-resident",{"job":"gather","work_target_id":"anything"}).ok)
	var before:Dictionary=runtime.capture_checkpoint()
	check("negative material rejected",not runtime.validate_facts(before.facts.merged({"stocks":[{"id":"bad","location":facts.actors[0],"items":{"scrap":-1}}]},true)).ok)
	var invalid:Dictionary=before.facts.duplicate(true);invalid.actors[0].hp="88"
	check("numeric-looking string rejected",not runtime.validate_facts(invalid).ok)
	runtime.tick(0.1)
	var enemies:Array=runtime.facts().actors.filter(func(a:Dictionary)->bool:return a.get("faction")=="infected")
	check("proximity actually spawns finite encounter",enemies.size()==2)
	if enemies.size()!=2:finish(output);return
	check("new infected explicitly bind their stable rig and shared body",enemies.all(func(a:Dictionary)->bool:return a.get("appearance_id")=="infected_walker" and a.get("body_profile_id")=="human-default-v1"))
	var old_stamina:float=runtime.actor("player").stamina
	var first:Dictionary=request("attack",enemies[0].id,{"tool_id":"fixture:axe"})
	check("real attack accepted",first.ok,first)
	check("attack has real stamina cost",is_equal_approx(old_stamina-float(runtime.actor("player").stamina),14))
	var health:float=runtime.actor(str(enemies[0].id)).hp
	check("immediate attack cannot bypass cooldown",not request("attack",enemies[0].id,{"tool_id":"fixture:axe"}).ok and runtime.actor(str(enemies[0].id)).hp==health)
	for wave:int in 14:
		for i:int in 6:runtime.tick(0.1)
		var living:Array=runtime.facts().actors.filter(func(a:Dictionary)->bool:return a.get("faction")=="infected" and float(a.hp)>0)
		if living.is_empty():break
		request("attack",str(living[0].id),{"tool_id":"fixture:axe"})
		if runtime.actor("player").stamina<14:
			for i:int in 60:runtime.tick(0.1)
	for i:int in 8:runtime.tick(0.1)
	var drops:Array=runtime.facts().stocks.filter(func(s:Dictionary)->bool:return str(s.id).begins_with("infected:"))
	check("defeated enemies create real ground containers",drops.size()==2,drops.size())
	check("loot is not silently granted to player pack",float(runtime.actor("player").pack.get("scrap",0))==0)
	var candidates:Array=state().exploration.candidates.duplicate()
	check("cleared encounter offers exactly three persistent candidates",candidates.size()==3,candidates)
	var encoded:Dictionary=Store.encode(runtime.capture_checkpoint())
	var restored:Dictionary=Store.decode(encoded.get("text",""))
	check("active exploration and enemies save roundtrip",encoded.ok and restored.ok)
	if restored.ok:
		var mounted:Dictionary=host._assemble(restored.capture)
		check("restore passes actual formal assembly validation",mounted.ok,mounted.get("reason"))
		if mounted.ok:runtime=mounted.runtime
	check("save reload does not reroll choices",state().exploration.candidates==candidates)
	if not candidates.is_empty():
		check("actual candidate choice accepted",request("explore_choose","",{"choice_id":candidates[0]}).ok)
		check("same candidate cannot be claimed twice",not request("explore_choose","",{"choice_id":candidates[0]}).ok)
		check("choice alters persistent temporary loadout",state().exploration.upgrades==[candidates[0]])
	var count:int=runtime.facts().stocks.size()
	for i:int in 20:runtime.tick(0.1)
	check("dead enemies cannot duplicate drops on later ticks",runtime.facts().stocks.size()==count)
	check("radio cannot skip actual finite defense",not request("radio","",{"operation":"transmit"}).ok)
	check("away-from-home settlement rejected",not request("explore_end").ok)
	check("real work candidates carry stable id and payload",runtime.work_targets().any(func(t:Dictionary)->bool:return t.get("job")=="gather" and t.get("work_payload",{}).get("action_kind")=="harvest"))
	continue_route()
	finish(output)
func configure_fixture(_facts:Dictionary)->void:pass
func continue_route()->void:pass
func finish(output:String)->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	DirAccess.make_dir_recursive_absolute(output)
	var report:Dictionary={"scope":"isolated real native_client/runtime/B/C commands; not formal app/RH/VA/IO acceptance","failed":failed,"checks":checks}
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print(JSON.stringify(report))
	if host!=null:host.free()
	quit(1 if failed else 0)
