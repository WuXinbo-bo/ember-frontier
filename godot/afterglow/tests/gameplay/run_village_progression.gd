extends SceneTree
const Village=preload("res://scripts/runtime/village_progression.gd")
const Gameplay=preload("res://scripts/runtime/factory_gameplay.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Playtest=preload("res://scripts/runtime/playtest_profile.gd")
const Radio=preload("res://scripts/runtime/rural_gameplay.gd")
var checks:Array=[]
class TestWorld extends RefCounted:
	var values:Dictionary={}
	func extension(id:String)->Variant:return values.get(id)

func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool)->void:
	checks.append({"name":label,"ok":ok})
	if not ok:push_error(label)

func run()->void:
	var at:Dictionary={"x":10.0,"y":0.0,"z":30.0,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	var layout:Dictionary={"opening_version":3,"content_version":13,"home":at,"spawn_points":{"player":at,"village-resident":at.merged({"x":12.0}),"repair-resident":at.merged({"x":14.0})}}
	var initial:Dictionary=Gameplay.initial(layout,{"ok":true,"spawn_points":layout.spawn_points,"initial_stocks":[],"initial_tools":[],"initial_records":[],"world_changes":[]})
	check("scenario three opening composes",initial.get("ok",false))
	if not initial.get("ok",false):finish();return
	var facts:Dictionary=initial.facts
	check("eight real progression quests replace legacy factory tutorial",facts.quests.size()==8 and facts.quests[0].id=="V3-Q01" and facts.quests[-1].id=="V3-Q08")
	for actor:Dictionary in facts.actors:
		if actor.id=="player":continue
		check("original companion joined voluntarily: "+str(actor.id),actor.relationship.member and actor.relationship.consent and actor.relationship.home_arrived and actor.householdId=="home-residents")
		check("companion finite emergency supplies: "+str(actor.id),actor.pack=={"food":1,"water":1})
	var legacy:Dictionary=Gameplay.initial({"home":at,"spawn_points":layout.spawn_points},{"ok":true,"spawn_points":layout.spawn_points,"initial_stocks":[],"initial_tools":[],"initial_records":[],"world_changes":[]})
	check("old opening keeps four quests and unrecruited residents",legacy.facts.quests.size()==4 and not legacy.facts.actors[1].relationship.member)
	var state:Dictionary=initial.world_changes[-1].after.duplicate(true)
	var world:=TestWorld.new();world.values={"r34:gameplay":state,"r34:modules":{"instances":[],"projects":[]},"r3:production":{"facts":[],"tools":[]}}
	var tx:=Draft.new({"world":world,"facts":func()->Dictionary:return facts.duplicate(true)})
	Village.reconcile(tx,state)
	check("elapsed time does not finish opening",not tx.staged.quests[0].completed)
	Village.observe(state,{"kind":"life-completed","actor_id":"player","operation":"drink"})
	Village.observe(state,{"kind":"life-completed","actor_id":"player","operation":"eat"})
	Village.observe(state,{"kind":"life-completed","actor_id":"player","operation":"rest","target_id":"real-bed:0"})
	Village.reconcile(tx,state)
	check("real food water and bed labor completes first phase",tx.staged.quests[0].completed)
	check("care does not counterfeit harvest repair or radio",not tx.staged.quests[1].completed and not tx.staged.quests[2].completed and not Village.radio_ready(state))
	Village.observe(state,{"kind":"crafted","targetId":"r34:boil_water_v2"})
	check("completed clean-water recipe recorded without issuing inventory",state.flags.village_clean_water and tx.staged.stocks.is_empty())
	world.values["r34:modules"]={"instances":[{"id":"warehouse:actual","definition_id":"r35.module.village_warehouse","restoration":{"policy":"village-heritage-v1","completed":true}}],"projects":[{"id":"warehouse:restore","module_id":"warehouse:actual","operation":"restore","status":"completed","cost":{}}]}
	var unpaid:=Draft.new({"world":world,"facts":func()->Dictionary:return facts.duplicate(true)})
	Village.reconcile(unpaid,state)
	check("free completion flag without paid restore ledger cannot finish warehouse",not state.flags.get("village_warehouse_restored",false))
	world.values["r34:modules"].projects[0].cost={"timber":8,"scrap":2,"cloth":1}
	var paid:=Draft.new({"world":world,"facts":func()->Dictionary:return facts.duplicate(true)})
	Village.reconcile(paid,state)
	check("completed original warehouse restore project advances real milestone",state.flags.get("village_warehouse_restored",false))
	state.flags.real_machine_output=true
	check("radio unlock requires actual warehouse and production outcomes",Village.radio_ready(state))
	world.values["r34:gameplay"]=state
	var snap:Dictionary=Village.snapshot(tx.staged,world)
	check("read-only progression chooses first unfinished phase",snap.available and snap.phase=="handwork" and snap.quests.size()==8)
	check("radio has no invented workbench command",snap.radio.station_id.is_empty() and snap.radio.choices.is_empty())
	var capture:Dictionary={"world":{"extensions":{"r34:gameplay":state,"r3:production":{"tools":[]}}},"facts":facts,"source":{}}
	var tested:Dictionary=Playtest.apply(capture)
	check("village playtest does not bypass first saw with gifted boards",tested.facts.actors[0].pack.get("timber",0)==0 and tested.world.extensions["r3:production"].tools.is_empty())
	var radio:=Radio.new();radio.context={"world":world}
	var intent:Dictionary={"schema_version":1,"owner":"gameplay","kind":"radio","id":"radio:test:1","source_id":"pack:player","cost":{"scrap":8,"tool_handle":1},"operation":"repair","target_id":"real-workbench","tool_id":"real-hammer","elapsed":0.0,"duration":20.0}
	check("scenario three saved radio intent validates",radio.validate_intent(intent,{"id":"player"},{"scenario":"factory-settlement-r34"}).ok)
	intent.cost.scrap=0
	check("radio cannot forge free repair material basis",not radio.validate_intent(intent,{"id":"player"},{"scenario":"factory-settlement-r34"}).ok)
	finish()

func finish()->void:
	var result:Dictionary={"ok":checks.all(func(row:Dictionary)->bool:return row.ok),"checks":checks}
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if not args.is_empty():
		DirAccess.make_dir_recursive_absolute(args[0]);var file:=FileAccess.open(args[0].path_join("results.json"),FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));quit(0 if result.ok else 1)
