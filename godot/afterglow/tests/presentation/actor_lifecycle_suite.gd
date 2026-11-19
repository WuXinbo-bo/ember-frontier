extends "res://tests/buildings/domain_suite.gd"
## Real runtime projection with explicit lifecycle facts; no native VA claim.
const Actors=preload("res://scripts/presentation/actor_view.gd")
const Data=preload("res://scripts/world/world_data.gd")
var view:Node3D

func reconfigure(facts:Dictionary)->void:
	var receipt:Dictionary=runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}})
	expect("explicit lifecycle fixture accepted by same authority",receipt.ok,receipt)
	if receipt.ok:view.sync(0)

func run()->void:
	var started:int=Time.get_ticks_msec()
	expect("real finite C world loads",world.load_snapshot(Generator.generate(713)).ok)
	var at:Dictionary={"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	initialize_at(at,[resident("ordinary-a",at.merged({"x":31},true)),resident("ordinary-b",at.merged({"x":32},true))])
	view=Actors.new();root.add_child(view);view.configure(runtime);view.set_process(false)
	var before:Dictionary=runtime.capture_checkpoint()
	expect("three ordinary actors have original meshes",view.roots.size()==3 and view._skin_models.size()==3)
	var kept:int=view.roots["ordinary-a"].get_instance_id()
	var facts:Dictionary=runtime.facts();facts.actors.reverse();reconfigure(facts)
	expect("reordering live actors preserves same instance",view.roots["ordinary-a"].get_instance_id()==kept)
	facts=runtime.facts();facts.actors=facts.actors.filter(func(a:Dictionary)->bool:return a.id!="ordinary-b");reconfigure(facts)
	expect("removed ordinary actor releases all per-actor references",not view.roots.has("ordinary-b") and not view._skin_bindings.has("ordinary-b") and not view._animations.has("ordinary-b") and not view.previous.has("ordinary-b"))
	facts=runtime.facts();facts.actors.append(resident("ordinary-new",at.merged({"x":32},true)));reconfigure(facts)
	expect("new ordinary actor appears without whole-view rebuild",view.roots.has("ordinary-new") and view._animations.has("ordinary-new"))
	facts=runtime.facts()
	for a:Dictionary in facts.actors:
		if a.id=="player":a.faction="infected"
	reconfigure(facts)
	expect("saved appearance remains authoritative when gameplay faction alone changes",view._skin_models.get("player")=="r1_resident_commuter")
	facts=runtime.facts()
	for a:Dictionary in facts.actors:
		if a.id=="player":a.appearance_id="infected_walker"
	reconfigure(facts)
	expect("same ID render-family update replaces incompatible original rig",view._animations.player.has_animation("Attack") and not view._skin_models.has("player"))
	facts=runtime.facts()
	for a:Dictionary in facts.actors:
		if a.id=="player":a.hp=0.0
	reconfigure(facts);view.sync(0.2)
	expect("incapacitated infected has visible derived tilt",absf(view.roots.player.rotation.z)>0.1)
	facts=runtime.facts()
	for a:Dictionary in facts.actors:
		if a.id=="player":a.hp=100.0;a.intent=null
	reconfigure(facts)
	expect("recovery clears dead tilt and resumes actual living state",is_zero_approx(view.roots.player.rotation.z) and view._states.get("player")=="Idle")
	var old_root:int=view.roots.player.get_instance_id()
	var replacement:=Runtime.new()
	facts=runtime.facts()
	for a:Dictionary in facts.actors:
		if a.id=="player":a.erase("faction");a.appearance_id="r1_resident_commuter"
	expect("replacement authority accepts explicit resident facts",replacement.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	view.configure(replacement)
	expect("switching authority retires old same-ID roots",view.roots.player.get_instance_id()!=old_root)
	expect("replacement authority uses resident original rig",view._skin_models.get("player","").begins_with("r1_resident_") and not view._animations.player.has_animation("Attack"))
	expect("assembly exposes A approved public readiness report",view.has_method("assembly_report"))
	if view.has_method("assembly_report"):
		var report:Dictionary=view.assembly_report()
		expect("actual three-role assembly is ready",report.ok,report)
		expect("assembly report has exact approved collections and one row per actor",report.required_errors is Array and report.optional_fallbacks is Array and report.actors.size()==replacement.facts().actors.size(),report)
		report.actors.clear();report.required_errors.append({"code":"external mutation"})
		expect("returned readiness data cannot mutate live view",view.assembly_report().ok and view.assembly_report().actors.size()==replacement.facts().actors.size())
		var model:Node3D=load(Actors.MODEL_PATHS[0]).instantiate()
		var animator:AnimationPlayer=view._find_animation(model)
		var original_library:AnimationLibrary=animator.get_animation_library("")
		var fixture_library:AnimationLibrary=original_library.duplicate()
		animator.remove_animation_library("");animator.add_animation_library("",fixture_library)
		fixture_library.remove_animation("Walk")
		model.find_child("arm_r",true,false).free()
		var issues:Array=view.call("_inspect_model",model,"r1_resident_commuter","explicit-bad-model",false)
		expect("missing required clip and socket both report exact failure",issues.any(func(x:Dictionary)->bool:return x.requirement=="clip:Walk") and issues.any(func(x:Dictionary)->bool:return x.requirement=="socket:arm_r"),issues)
		expect("every required issue carries exact consumer fields",issues.all(func(x:Dictionary)->bool:return x.actor_id=="explicit-bad-model" and x.profile_id=="r1_resident_commuter" and x.resource is String and x.requirement is String and x.code is String),issues)
		issues=view._inspect_model(model,"missing-normal-fixture","explicit-no-skin",false)
		expect("missing required normal skin is a declared assembly failure",issues.any(func(x:Dictionary)->bool:return x.requirement=="skin:normal" and x.code=="SKIN_MISSING_OR_INVALID"),issues)
		model.free()
	# A owns persistent migration. Here the actual projection consumes explicit
	# saved identities, including order changes and remounts, without writing facts.
	facts=replacement.facts()
	for i:int in facts.actors.size():
		facts.actors[i].appearance_id=Actors.APPEARANCE_IDS[i%3]
		facts.actors[i].body_profile_id=Actors.BODY_PROFILE_ID
	expect("explicit stable profiles accepted by authority",replacement.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	view.sync(0)
	var expected_profiles:Dictionary={}
	for a:Dictionary in facts.actors:expected_profiles[a.id]=a.appearance_id
	facts.actors.reverse()
	expect("reordered saved profiles accepted",replacement.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	view.free();view=Actors.new();root.add_child(view);view.configure(replacement);view.set_process(false)
	expect("new mount uses saved appearance IDs rather than current array order",expected_profiles.keys().all(func(id:String)->bool:return view.roots[id].get_meta("profile_id")==expected_profiles[id]))
	var player_index:int=-1
	for i:int in facts.actors.size():
		if facts.actors[i].id=="player":player_index=i
	facts.actors[player_index].appearance_id="r1_resident_shopkeeper"
	var old_model:int=view.roots.player.get_instance_id()
	expect("same ID stable profile update accepted",replacement.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	view.sync(0)
	expect("changed explicit appearance rebinds original rig",view.roots.player.get_instance_id()!=old_model and view._skin_models.player=="r1_resident_shopkeeper")
	var invalid:=Actors.new();root.add_child(invalid);invalid.runtime=replacement;invalid.set_process(false)
	var bad:Dictionary=facts.actors[player_index].duplicate(true);bad.id="bad-profile";bad.appearance_id="unknown-profile"
	var failed_root:Node3D=invalid._spawn(bad,0)
	var bad_report:Dictionary=invalid.assembly_report()
	expect("unknown nonempty appearance is explicit required failure",not bad_report.ok and bad_report.required_errors.any(func(x:Dictionary)->bool:return x.code=="PROFILE_UNKNOWN"),bad_report)
	expect("failed profile leaves no invisible selection capsule",failed_root.find_children("*","StaticBody3D",true,false).is_empty() and failed_root.get_child_count()==0)
	bad.id="bad-body";bad.appearance_id="r1_resident_commuter";bad.body_profile_id="unknown-body"
	failed_root=invalid._spawn(bad,0);bad_report=invalid.assembly_report()
	expect("unknown body rejects selection geometry rather than assuming dimensions",failed_root.get_child_count()==0 and bad_report.required_errors.any(func(x:Dictionary)->bool:return x.actor_id=="bad-body" and x.code=="BODY_PROFILE_UNKNOWN"),bad_report)
	invalid.free()
	var other_world:=World.new()
	expect("replacement world snapshot loads",other_world.load_snapshot(world.snapshot()).ok)
	old_root=view.roots.player.get_instance_id()
	expect("same runtime accepts replacement world",replacement.configure({"world":other_world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
	view.sync(0)
	expect("same authority with changed world identity retires old roots",view.roots.player.get_instance_id()!=old_root and view.assembly_report().ok)
	var after:Dictionary=replacement.capture_checkpoint();view.sync(0.1)
	expect("view lifecycle does not mutate replacement authority",Data.json_equal(after,replacement.capture_checkpoint()))
	expect("explicit fixtures are separate from original checkpoint",not Data.json_equal(before,after))
	view.free()
	var result:Dictionary={"scope":"explicit lifecycle fixtures through real runtime and imported GLB; not OS or VA","checks":checks,"failures":failures,"elapsed_ms":Time.get_ticks_msec()-started}
	var file:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("DDD_LIFECYCLE "+JSON.stringify({"checks":checks.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
