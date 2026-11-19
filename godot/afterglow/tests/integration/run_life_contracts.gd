extends SceneTree
## Explicit finite fixtures with real world/B contact/production/A transactions.
## No user save, formal app or visual/performance qualification.
const World=preload("res://scripts/world/world_state.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const Buildings=preload("res://scripts/buildings/building_service.gd")
const Production=preload("res://scripts/production/production_service.gd")
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
const Initial=preload("res://scripts/runtime/initial_state.gd")
const Profiles=preload("res://scripts/runtime/actor_profiles.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const BED:="fixture:life-bed"
var checks:Array=[]
var output:String
var runtime:RefCounted

func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:push_error(label+" "+str(detail))

func setup()->void:
	var w:=World.new();var snapshot:Dictionary=Rural.generate(713)
	snapshot.entities[BED]={"id":BED,"kind":"prop","regionId":"RH-HOME","position":{"x":30.2,"y":0.0,"z":30.25},"bounds":{"min":{"x":29.8,"y":0.0,"z":29.75},"max":{"x":30.6,"y":0.6,"z":30.75}},"revision":0,"solid":false,"blocksTerrain":false,"data":{"sleeping":true,"prepared":true,"owner":"player"}}
	check("finite world with explicit nonblocking bed loads",w.load_snapshot(snapshot).ok)
	var at:Dictionary={"x":29.2,"y":0.0,"z":30.25,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	var player:Dictionary=Initial.actor("player","test",at,at,{"food":1,"water":1})
	player.stamina=20.0;player.fatigue=70.0
	var other:Dictionary=Initial.actor("ordinary:test","test",at.merged({"x":32.0},true),at,{})
	runtime=Runtime.new()
	var result:Dictionary=runtime.configure({"world":w,"facts":{"actors":[player,other],"stocks":[],"actions":[],"quests":[],"time":0.0,"status":"playing"},"services":{"buildings":Buildings.new(),"production":Production.new()}})
	check("real A/B data services configure",result.ok,result)

func command(kind:String,id:String="test:start",target:String="")->Dictionary:
	return runtime.command({"kind":kind,"command_id":id,"actor_id":"player","target_id":target})

func bed_edit(edit:Dictionary)->Dictionary:
	var before:Dictionary=runtime.world.entity(BED);var after:Dictionary=before.duplicate(true)
	after.data.merge(edit,true);after.revision+=1
	return runtime._commit({"world_changes":[{"op":"entity.put","id":BED,"before_exists":true,"before":before,"after":after}],"fact_changes":[]})

func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	setup()
	var original:Dictionary=runtime.capture_checkpoint()
	var request:Dictionary={"kind":"rest","command_id":"test:rest","actor_id":"player","target_id":BED}
	var available:Dictionary=runtime.life_availability(request)
	check("real nearby bed contact is usable",available.ok,available)
	var plan:Dictionary=runtime.prepare_life(request)
	check("public preparation is pure and contains CAS before",plan.ok and runtime.capture_checkpoint()==original and plan.fact_changes[0].before==runtime.actor("player"),plan)
	check("new native intent explicitly declares schema v1",plan.ok and plan.fact_changes[0].after.intent.schema_version==1)
	var staged:Dictionary=runtime.facts();staged.actors[0].x=50.0
	check("staged position drives contact instead of live position",not runtime.life_availability(request,staged.actors[0],staged).ok)
	staged=runtime.facts();staged.actors[0].pack.food=0
	check("staged finite inventory overrides live carried food",not runtime.life_availability({"kind":"eat"},staged.actors[0],staged).ok)
	check("bad public command fails without mutation",not runtime.prepare_life({"kind":"eat"}).ok and runtime.capture_checkpoint()==original)
	check("actual A commit accepts same public life draft",runtime._commit(plan).ok)
	var holds:Array=runtime.hold_descriptors(runtime.facts())
	check("bed hold derives once from active intent",holds.size()==1 and holds[0].use_target_id==BED and holds[0].cost.is_empty(),holds)
	var a:Dictionary=runtime._find("actors","player")
	runtime._advance_life(a,0.1)
	check("valid bed alone yields intended stamina/fatigue",is_equal_approx(a.stamina,20.5) and is_equal_approx(a.fatigue,69.85))
	check("unprepare change passes real final spatial validator",bed_edit({"prepared":false}).ok)
	a=runtime._find("actors","player");var stamina:float=a.stamina;var fatigue:float=a.fatigue
	runtime._advance_life(a,0.1)
	check("invalid continuation cancels BEFORE any bed benefit",a.intent==null and a.stamina==stamina and a.fatigue==fatigue,a)
	check("cancelled bed intent releases derived hold",runtime.hold_descriptors(runtime.facts()).is_empty())
	setup();check("owner change applies via authority",bed_edit({"owner":"ordinary:test"}).ok)
	check("player cannot rest in another private bed",runtime.life_availability(request).code=="FORBIDDEN")
	setup();check("communal ownership fixture applies",bed_edit({"owner":"home-residents"}).ok)
	var other:Dictionary=runtime.actor("ordinary:test");other.householdId="home-residents"
	check("shared household label does not manufacture consent",runtime.life_availability(request.merged({"actor_id":other.id},true),other,runtime.facts()).code=="NO_CONSENT")
	setup();staged=runtime.facts();staged.actors[1].intent={"owner":"runtime","kind":"rest","id":"other:rest","target_id":BED,"elapsed":0.0,"duration":12.0}
	check("same-tick staged bed claimant blocks double use",runtime.life_availability(request,staged.actors[0],staged).code=="RESERVED")
	staged.actors[1].hp=0.0
	check("incapacitated claimant does not retain a bed hold",runtime.life_availability(request,staged.actors[0],staged).ok)
	setup();var eating:Dictionary=command("eat","test:eat")
	check("eating starts and exposes finite material hold",eating.ok and runtime.hold_descriptors(runtime.facts())[0].cost=={"food":1})
	for i:int in 13:runtime.tick(0.1)
	check("exactly one ration consumed at completion",runtime.actor("player").pack.food==0 and runtime.actor("player").intent==null)
	check("command replay cannot consume a second ration",command("eat","test:eat").ok and runtime.actor("player").pack.food==0)
	var bad:Dictionary={"owner":"runtime","kind":"invented","id":"test:bad","elapsed":0.0,"duration":1.0}
	check("unknown kind rejected before a consumer",not runtime.validate_intent(bad).ok)
	bad.kind="eat";bad.schema_version=99
	check("unknown schema version rejected",not runtime.validate_intent(bad).ok)
	bad.schema_version=1;bad.elapsed=NAN
	check("nonfinite progress rejected",not runtime.validate_intent(bad).ok)
	var legacy:Array=Profiles.normalize_legacy([{"id":"z"},{"id":"a"},{"id":"b"}])
	check("unversioned old appearances preserve original array mapping",legacy[0].appearance_id==Profiles.HUMAN[0] and legacy[1].appearance_id==Profiles.HUMAN[1])
	var reordered:Array=Profiles.normalize_legacy([legacy[1],legacy[0],legacy[2]])
	check("persisted profile survives sorting without a face swap",reordered[0].appearance_id==legacy[1].appearance_id and reordered[1].appearance_id==legacy[0].appearance_id)
	var encoded:Dictionary=Store.encode(runtime.capture_checkpoint());var decoded:Dictionary=Store.decode(encoded.get("text",""))
	check("profile and completed finite life survive native codec",encoded.ok and decoded.ok and decoded.capture.facts.actors[0].appearance_id==runtime.actor("player").appearance_id and decoded.capture.facts.actors[0].pack.food==0)
	var before:Dictionary=runtime.facts();var after:Dictionary=before.duplicate(true);after.actors[0].pack.water=0
	var diff:Array=Runtime.facts_diff(before,after);diff[0].after.pack.water=99
	check("public diff and lookup cannot write into observer facts",before.actors[0].pack.water==1 and after.actors[0].pack.water==0 and Runtime.fact_from(before,"actors","missing").is_empty())
	var report:Dictionary={"scope":"source headless actual A/B transaction/contact/codec with explicitly constructed finite bed and need fixtures; not OS/PCK/VA/performance","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print(JSON.stringify(report));runtime=null;quit(1 if report.failed else 0)
