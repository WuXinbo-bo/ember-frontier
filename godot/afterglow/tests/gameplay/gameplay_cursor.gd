extends "res://tests/gameplay/generated_cooperation.gd"
## Real finite transfers and original A commits. Corpse/consent/CAS fixtures
## are explicit; no granted stock, second clock, app, or FPS qualification.
const Draft=preload("res://scripts/actions/domain_draft.gd")
var evidence:Dictionary={}

class AuditRuntime extends Runtime:
	var rows:Array=[]
	func _commit(plan:Dictionary)->Dictionary:
		var before:Dictionary=world.extension("r33:gameplay")
		var result:Dictionary=super._commit(plan)
		var ids:Array=[];var kinds:Array=[]
		for c:Dictionary in plan.get("world_changes",[]):ids.append(c.get("id",c.get("op")))
		for event:Dictionary in plan.get("events",[]):kinds.append(event.get("kind"))
		var after:Dictionary=world.extension("r33:gameplay")
		var left:Dictionary=before.duplicate(true);var right:Dictionary=after.duplicate(true)
		left.erase("last_event_revision");right.erase("last_event_revision")
		rows.append({"world_ids":ids,"event_kinds":kinds,"ok":result.ok,"cursor_before":before.last_event_revision,"cursor_after":after.last_event_revision,"cursor_only":before!=after and left==right})
		return result

func run()->void:
	output_dir=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output_dir)
	evidence_kind="real-generated-cursor-with-explicit-empty-corpse-CAS-and-consent-fixtures"
	host=Client.new()
	var generated:Dictionary=Assembly.prepare(Assembly.generate(973339546,Building.generation_profiles()))
	check("same native-warning seed uses actual generated assembly",generated.ok,generated.get("reason"))
	if not generated.ok or not mount(generated.capture):finish();return
	var baseline:Dictionary=runtime.capture_checkpoint()
	movement_metadata(baseline)
	transfer_cursor(baseline)
	quest_cadence(baseline)
	write_json("cursor-evidence.json",evidence)
	finish()

func gameplay_plan()->Dictionary:
	return runtime._services.gameplay.advance(0.1)

func apply_gameplay()->Dictionary:
	var plan:Dictionary=gameplay_plan()
	if plan.get("world_changes",[]).is_empty() and plan.get("fact_changes",[]).is_empty():return {"ok":true,"noop":true,"plan":plan}
	return runtime._commit(plan)

func movement_metadata(baseline:Dictionary)->void:
	if not mount(baseline):return
	var audited:=AuditRuntime.new()
	var bound:Dictionary=host._context(runtime.world,runtime._services,runtime.facts(),baseline.source)
	bound.command_revision=runtime.get_revision()
	check("audit rebinds actual services to original inherited runtime",audited.configure(bound).ok)
	runtime=audited
	var stages:Array=[]
	for moving:bool in [false,true]:
		audited.rows.clear();var accepted:=0;var denied:=0;var direction:=1.0
		for i:int in 100:
			if moving:
				var at:Dictionary=Geometry.location(runtime.actor("player"));at.x+=0.28*direction
				var result:Dictionary=send("direct_move","",{"movement_dt":0.1,"movement_mode":"walk"},at)
				if result.ok:accepted+=1
				else:denied+=1
				if i%3==2 or not result.ok:direction=-direction
			runtime.tick(0.1)
		var metadata:Array=audited.rows.filter(func(row:Dictionary)->bool:return row.world_ids.has(Gameplay.KEY))
		var moves:int=0;var candidates:int=0
		for row:Dictionary in audited.rows:
			for kind:Variant in row.event_kinds:
				if kind=="actor-moved":moves+=1
				if kind in ["inventory-transfer","structure-completed","life-completed"]:candidates+=1
		var cursor_only:Array=metadata.filter(func(row:Dictionary)->bool:return row.cursor_only)
		stages.append({"moving":moving,"ticks":100,"accepted_player_moves":accepted,"rejected_player_moves":denied,"actual_movement_events":moves,"candidate_events":candidates,"gameplay_metadata_commits":metadata.size(),"cursor_only_commits":cursor_only.size(),"cursor":runtime.world.extension(Gameplay.KEY).last_event_revision,"metadata":metadata})
		check("real movement events stay recorded without cursor-only metadata "+str(moving),moves>0 and cursor_only.is_empty() and candidates==0,stages[-1])
		check("unrelated player/resident movement leaves durable cursor unchanged "+str(moving),int(runtime.world.extension(Gameplay.KEY).last_event_revision)==-1,stages[-1])
		if moving:check("100 actual player moves cause zero gameplay metadata writes",accepted==100 and metadata.is_empty(),stages[-1])
	evidence.movement=stages

func add_empty_drop()->String:
	var gameplay:RefCounted=runtime._services.gameplay
	var tx:=Draft.new(gameplay.context)
	var at:Dictionary=Geometry.location(runtime.actor("player"))
	var corpse:Dictionary=Initial.actor("infected:E-cursor-empty","explicit empty dead source fixture",at,at,{})
	corpse.faction="infected";corpse.appearance_id="infected_walker";corpse.encounter_id="E-cursor-empty";corpse.hp=0.0
	tx.staged.actors.append(corpse)
	gameplay._drop(tx,corpse)
	var result:Dictionary=runtime._commit(tx.result())
	check("explicit empty corpse creates actual non-solid drop via original validated commit",result.ok,result)
	return str(corpse.id)+":drops" if result.ok else ""

func total_item(item:String)->float:
	var total:=0.0
	for a:Dictionary in runtime.facts().actors:total+=float(a.pack.get(item,0))
	for stock:Dictionary in runtime.facts().stocks:total+=float(stock.items.get(item,0))
	return total

func restore_cursor(label:String)->bool:
	var before:Dictionary=runtime.capture_checkpoint()
	var encoded:Dictionary=Store.encode(before)
	var decoded:Dictionary=Store.decode(encoded.get("text",""))
	check(label+" actual native codec",encoded.ok and decoded.ok,decoded.get("reason"))
	if not encoded.ok or not decoded.ok or not mount(decoded.capture):return false
	var changed:Array=differences(before.world.extensions[Gameplay.KEY],runtime.world.extension(Gameplay.KEY),"gameplay",[])
	differences(before.facts.ledger,runtime.facts().ledger,"ledger",changed)
	check(label+" exact discrete cursor/events and bounded JSON continuous values",changed.is_empty(),changed)
	return true

func supported_home_point()->Dictionary:
	var home:Dictionary=runtime.world.extension(Gameplay.KEY).layout.home
	var start:Vector3=Geometry.point(runtime.actor("player"))
	for fraction:float in [0.2,0.35,0.5,0.65,0.8,1.0]:
		var position:Vector3=start.lerp(Geometry.point(home),fraction)
		var height:Variant=runtime.world.surface_height(position.x,position.z)
		if height==null:continue
		var raw:Dictionary=home.duplicate(true);raw.x=position.x;raw.z=position.z;raw.y=float(height)
		var feet:Dictionary=runtime._services.buildings.current_space().standing_point(raw)
		if not feet.is_empty() and runtime._services.gameplay._at_home(feet):return feet
	return {}

func transfer_cursor(baseline:Dictionary)->void:
	if not mount(baseline):return
	var home:Dictionary=supported_home_point()
	check("generated home radius has an actual supported approach point",not home.is_empty())
	if home.is_empty() or not walk(home,"physically enter generated home radius before exploration checks"):return
	check("initial scheduled quest observation commits normally",apply_gameplay().ok)
	var original:Dictionary={"food":total_item("food"),"water":total_item("water")}
	var drop:String=add_empty_drop()
	if drop.is_empty():return
	check("finite original food/water put through actual B command",send("deposit",drop,{"items":{"food":1,"water":1}}).ok)
	check("initial finite-source event consumed",apply_gameplay().ok)
	var before:Dictionary=runtime.world.extension(Gameplay.KEY)
	var taken:Dictionary=send("take",drop,{"items":{"water":1}})
	var take_revision:int=runtime.get_revision()
	check("pre-exploration take is real inventory debit/credit",taken.ok and float(runtime.stock(drop).items.water)==0 and float(runtime.actor("player").pack.water)==1,taken)
	check("candidate with no gameplay effect still commits consumption",apply_gameplay().ok and int(runtime.world.extension(Gameplay.KEY).last_event_revision)==take_revision)
	var after:Dictionary=runtime.world.extension(Gameplay.KEY)
	var left:=before.duplicate(true);var right:=after.duplicate(true)
	left.erase("last_event_revision");right.erase("last_event_revision")
	check("pre-exploration infected-source transfer changes cursor only",left==right and int(after.exploration.loot_collected)==0)
	if not restore_cursor("consumed non-effect transfer"):return
	check("exploration starts by actual home availability/command",send("explore_start").ok)
	check("starting exploration never reinterprets consumed old transfer",apply_gameplay().ok and int(runtime.world.extension(Gameplay.KEY).exploration.loot_collected)==0)
	check("same original water is put back by real command",send("deposit",drop,{"items":{"water":1}}).ok and apply_gameplay().ok)
	var tx:=Draft.new(runtime._services.actions.context)
	var a:Dictionary=runtime._services.actions.transfer_in(tx,"player",drop,"pack:player",{"items":{"water":1}})
	var b:Dictionary=runtime._services.actions.transfer_in(tx,"player",drop,"pack:player",{"items":{"food":1}})
	check("two original finite items transfer in one actual B transaction",a.ok and b.ok and runtime._commit(tx.result()).ok)
	var revision:int=runtime.get_revision()
	var same:Array=runtime.facts().ledger.filter(func(event:Dictionary)->bool:return int(event.revision)==revision and event.kind=="inventory-transfer")
	check("two distinct candidate ledger events really share one committed revision",same.size()==2 and same[0].id!=same[1].id,same)
	var plan:Dictionary=gameplay_plan()
	var staged:Dictionary={}
	for change:Dictionary in plan.world_changes:
		if change.get("id")==Gameplay.KEY:staged=change.after
	check("both same-revision candidates process before cutoff changes",int(staged.get("exploration",{}).get("loot_collected",-1))==2 and int(staged.get("last_event_revision",-1))==revision,staged)
	check("preparation alone cannot acknowledge or award pending candidates",int(runtime.world.extension(Gameplay.KEY).exploration.loot_collected)==0 and int(runtime.world.extension(Gameplay.KEY).last_event_revision)<revision)
	var conflict:=Draft.new(runtime._services.gameplay.context)
	conflict.extension(Gameplay.KEY).flags.E_cursor_conflict_fixture=true
	check("explicit concurrent metadata fixture installs through original commit",runtime._commit(conflict.result()).ok)
	var rejected_before:Dictionary=runtime.capture_checkpoint()
	var rejected:Dictionary=runtime._commit(plan)
	check("stale candidate draft really rejects without acknowledging or changing any fact",not rejected.ok and Data.json_equal(rejected_before,runtime.capture_checkpoint()),rejected)
	if not restore_cursor("rejected candidates still pending"):return
	check("fresh retry consumes both pending candidates exactly once",apply_gameplay().ok and int(runtime.world.extension(Gameplay.KEY).exploration.loot_collected)==2 and int(runtime.world.extension(Gameplay.KEY).last_event_revision)==revision)
	check("second scan is no-op instead of duplicate loot",apply_gameplay().get("noop",false) and int(runtime.world.extension(Gameplay.KEY).exploration.loot_collected)==2)
	if not restore_cursor("successfully consumed pair"):return
	check("reload cannot count the consumed pair again",apply_gameplay().ok and int(runtime.world.extension(Gameplay.KEY).exploration.loot_collected)==2)
	check("all real food/water remain conserved without grants",total_item("food")==original.food and total_item("water")==original.water)
	evidence.transfers={"pre_explore_revision":take_revision,"same_revision":revision,"same_revision_events":same,"rejection":rejected,"final_state":runtime.world.extension(Gameplay.KEY),"original_totals":original,"final_totals":{"food":total_item("food"),"water":total_item("water")}}

func quest_cadence(baseline:Dictionary)->void:
	if not mount(baseline):return
	var fixture:Dictionary=baseline.duplicate(true)
	var at:Dictionary=supported_home_point()
	check("explicit at-home consent fixture uses actual supported home point",not at.is_empty())
	if at.is_empty():return
	for a:Dictionary in fixture.facts.actors:
		if a.id=="village-resident":a.merge(at,true);a.intent=null;a.job="rest";a.relationship={"met":true,"helped":true,"member":true,"consent":true,"home_arrived":false}
	if not mount(fixture):return
	runtime.tick(0.1)
	check("scheduled quest marks explicit consenting member physically at real home",runtime.actor("village-resident").relationship.get("home_arrived",false) and runtime._services.gameplay._at_home(runtime.actor("village-resident")))
	var next:float=runtime._services.gameplay._next_quest_check
	var tx:=Draft.new(runtime._services.gameplay.context)
	tx.actor("village-resident").relationship.home_arrived=false
	Draft.find(tx.staged.quests,"RH-Q02").progress="explicit-cadence-fixture"
	check("explicit cadence sentinel uses actual fact CAS",runtime._commit(tx.result()).ok)
	var early:=true
	while runtime.clock()+0.100001<next:
		runtime.tick(0.1)
		early=early and not runtime.actor("village-resident").relationship.home_arrived and Draft.find(runtime.facts().quests,"RH-Q02").progress=="explicit-cadence-fixture"
	check("quest still waits its original half-second schedule",early)
	for i:int in 2:
		if runtime.clock()>=next:break
		runtime.tick(0.1)
	check("no candidate cursor change does not skip due quest or member arrival",runtime.actor("village-resident").relationship.home_arrived and Draft.find(runtime.facts().quests,"RH-Q02").progress!="explicit-cadence-fixture" and runtime._services.gameplay._next_quest_check>next)
	evidence.quest={"due_at":next,"checked_at":runtime.clock(),"member":runtime.actor("village-resident").relationship,"quest":Draft.find(runtime.facts().quests,"RH-Q02")}
