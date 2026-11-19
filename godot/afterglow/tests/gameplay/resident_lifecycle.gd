extends "res://tests/gameplay/social_boundary.gd"
## Explicit ordinary actor add/remove/HP fixtures through A transactions,
## followed by real finite help, A care, B follow/return and native roundtrip.
const ORDINARY:="ordinary:E-lifecycle"

func actor_change(id:String,after:Variant)->Dictionary:
	var before:Dictionary=runtime.actor(id)
	return runtime._commit({"ok":true,"world_changes":[],"fact_changes":[{"collection":"actors","id":id,"before":null if before.is_empty() else before,"after":after}]})

func run()->void:
	output_dir=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output_dir)
	evidence_kind="explicit-dynamic-ordinary-actor-then-real-finite-care-and-follow"
	host=Client.new()
	var built:Dictionary=Assembly.prepare(Assembly.generate(713,Building.generation_profiles()))
	check("current generated lifecycle world prepares",built.ok,built.get("reason"))
	if not built.ok or not mount(built.capture):finish();return
	var pair:Dictionary=edge_pair()
	check("real supported close boundary points exist",not pair.is_empty(),pair)
	if pair.is_empty():finish();return
	var player:Dictionary=runtime.actor("player");player.merge(pair.from,true)
	check("explicit supported player placement uses A transaction",actor_change("player",player).ok)
	var added:Dictionary=Initial.actor(ORDINARY,"普通居民反例",pair.to,runtime.actor("player").home,{})
	added.thirst=20.0
	check("ordinary actor added AFTER configure through A only",actor_change(ORDINARY,added).ok)
	check("addition does not grant resources or consent",runtime.actor(ORDINARY).pack.is_empty() and not runtime.actor(ORDINARY).relationship.consent)
	var original_water:float=float(runtime.actor("player").pack.water)
	var helped:Dictionary=send("help",ORDINARY,{"items":{"water":1}})
	check("one original water is really transferred to dynamic actor",helped.ok and float(runtime.actor("player").pack.water)==original_water-1 and float(runtime.actor(ORDINARY).pack.water)==1,helped)
	for i:int in 16:step()
	var person:Dictionary=runtime.actor(ORDINARY)
	check("new actor without reconfigure autonomously drinks through A",float(person.thirst)>63 and float(person.pack.water)==0,person)
	check("dynamic self care creates no consent or stock",not person.relationship.consent and runtime.actor("player").pack.water==original_water-1)
	# Make a real E route, then incapacitate without moving or advancing time.
	var tx:=preload("res://scripts/actions/domain_draft.gd").new(runtime._services.residents.context)
	var walking:Dictionary=tx.actor(ORDINARY);walking.intent=null
	check("dynamic actor obtains B actual self walk",runtime._services.residents._walk(walking,runtime._services.residents._routine(walking),tx,runtime.clock()))
	walking.hp=0.0;walking.self_routine.next_decision=runtime.clock()+1000.0
	check("HP fixture commits same actor and real route",runtime._commit(tx.result()).ok)
	var incapacitated:Dictionary=runtime.actor(ORDINARY)
	step();person=runtime.actor(ORDINARY)
	check("incapacity clears E route without step food reward or skills",person.intent==null and Geometry.point(person)==Geometry.point(incapacitated) and person.pack==incapacitated.pack and person.skills==incapacitated.skills and person.self_routine.next_decision==0,person)
	person.hp=100.0
	check("HP recovery uses A transaction",actor_change(ORDINARY,person).ok)
	step();person=runtime.actor(ORDINARY)
	check("recovered actor resumes decision before stale future deadline",float(person.self_routine.next_decision)<runtime.clock()+100,person)
	# Delete an actual active decision participant, then reuse its ID with new
	# empty facts. E must have neither a retained actor nor the old care/route.
	check("live actor deletion commits through A",actor_change(ORDINARY,null).ok)
	for i:int in 3:step()
	check("deleted ordinary actor stays absent without ghost changes",runtime.actor(ORDINARY).is_empty())
	added=Initial.actor(ORDINARY,"重新加入的普通居民",pair.to,runtime.actor("player").home,{})
	check("same ID can be re-added with new authoritative facts",actor_change(ORDINARY,added).ok)
	step();person=runtime.actor(ORDINARY)
	check("re-added identity derives a fresh routine from new facts",person.has("self_routine") and person.self_routine.origin==pair.to and person.pack.is_empty() and not person.relationship.member,person)
	if not roundtrip("dynamic deletion and same-ID new facts"):finish();return
	# Pay help using the remaining original food; no inventory/consent fixture.
	if not approach(ORDINARY):finish();return
	var paid:Dictionary=send("help",ORDINARY,{"items":{"food":1}})
	check("second real finite help uses original food",paid.ok and runtime.actor("player").pack.food==0 and runtime.actor(ORDINARY).pack.food==1,paid)
	var invited:Dictionary=send("invite",ORDINARY)
	check("ordinary actor voluntarily joins with existing A social rule",invited.ok and runtime.actor(ORDINARY).relationship.consent,invited)
	var denied:Dictionary=send("job",ORDINARY,{"job":"rest"})
	check("ordinary member still must physically return before work",not denied.ok and denied.code=="RETURN_HOME_FIRST",denied)
	var home:String=str(runtime.world.extension(Gameplay.KEY).layout.home_building)
	if not stock_at(home+":storage"):finish();return
	if not wait_fact("ordinary member really follows B path home",func()->bool:return runtime.actor(ORDINARY).relationship.get("home_arrived",false),1400):finish();return
	check("ordinary home_arrived reflects actual home position",runtime._services.gameplay._at_home(runtime.actor(ORDINARY)))
	var rested:Dictionary=send("job",ORDINARY,{"job":"rest"})
	check("ordinary returned member can use same work API",rested.ok and runtime.actor(ORDINARY).job=="rest",rested)
	if not roundtrip("ordinary member real paid cooperation and return home"):finish();return
	ordinary_labor(home+":storage")
	finish()

func ordinary_labor(home_stock:String)->void:
	var shed:String="RH-HOME:shed:storage"
	if not stock_at(shed) or not perform("ordinary labor searches real shed","search",shed):return
	var axes:Array=runtime.world.extension("r3:production").tools.filter(func(t:Dictionary)->bool:return t.holderId==shed and t.kind=="salvaged_axe")
	check("ordinary labor needs one existing finite original axe",axes.size()==1,axes)
	if axes.size()!=1:return
	var axe:String=axes[0].id
	var durability:float=float(axes[0].durability)
	if not perform("take original physical axe for ordinary worker","take",shed,{"tool_ids":[axe]}):return
	if not approach(ORDINARY) or not perform("hand actual axe to consenting ordinary worker","deposit","pack:"+ORDINARY,{"tool_ids":[axe]}):return
	var trees:Array=runtime.work_targets().filter(func(t:Dictionary)->bool:return t.job=="gather" and runtime.world.entity(t.actual_target_id).get("regionId")=="RH-HOME")
	trees.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return Geometry.point(Geometry.location(runtime.world.entity(a.actual_target_id))).distance_squared_to(Geometry.point(runtime.actor(ORDINARY)))<Geometry.point(Geometry.location(runtime.world.entity(b.actual_target_id))).distance_squared_to(Geometry.point(runtime.actor(ORDINARY))))
	check("ordinary worker has actual generated standing tree target",not trees.is_empty())
	if trees.is_empty():return
	var tree:Dictionary=trees[0]
	var before:float=float(runtime.stock(home_stock).items.get("log",0))
	if not perform("ordinary actor takes same B harvest job","job",ORDINARY,{"job":"gather","work_target_id":tree.id}):return
	if not wait_fact("ordinary worker really harvests and delivers original three logs",func()->bool:return float(runtime.stock(home_stock).items.get("log",0))==before+3,1800):return
	check("ordinary work uses and wears original transferred axe",runtime.tool(axe).holderId=="pack:"+ORDINARY and float(runtime.tool(axe).durability)<durability)
	check("ordinary harvesting actually changes original tree state",runtime.world.entity(tree.actual_target_id).get("data",{}).get("harvest",{}).get("phase")!="standing")
	if not perform("stop ordinary repeating work using same job API","job",ORDINARY,{"job":"rest"}):return
	roundtrip("ordinary resident actual finite harvesting and home delivery")
	write_json("ordinary-completed-labor-capture.json",runtime.capture_checkpoint())
