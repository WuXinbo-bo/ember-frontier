extends "res://tests/gameplay/generated_cooperation.gd"
## Continue the retained actual cooperative/material route with canonical
## commands only. No HP/stamina/material/knowledge/encounter/defense fixtures.
var axe:String
var hammer:String
var saw:String
var bench:String
var combat_steps:Array=[]
var original_totals:Dictionary={}
var original_tool_ids:Array=[]

func game()->Dictionary:return runtime.world.extension(Gameplay.KEY)

func totals()->Dictionary:
	var result:Dictionary={}
	for a:Dictionary in runtime.facts().actors:
		for item:String in a.pack:result[item]=float(result.get(item,0))+float(a.pack[item])
	for s:Dictionary in runtime.facts().stocks:
		for item:String in s.items:result[item]=float(result.get(item,0))+float(s.items[item])
	return result

func tool(kind:String)->String:
	for t:Dictionary in runtime.world.extension("r3:production").tools:
		if t.kind==kind and t.holderId=="pack:player":return str(t.id)
	return ""

func healthy()->bool:
	if float(runtime.actor("player").hp)>0 and runtime.facts().status=="playing":return true
	check("actual player remains alive on the real route",false,{"actor":runtime.actor("player"),"combat":combat_steps})
	return false

func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	output_dir=args[0];DirAccess.make_dir_recursive_absolute(output_dir)
	command_prefix="E-RH-continuation:"+output_dir.get_base_dir().get_file()+":"
	evidence_kind="retained-real-cooperative-material-route-then-no-grant-RH-exploration-defense-radio"
	host=Client.new()
	if args.size()!=2:check("recorded real material-route capture supplied",false);finish();return
	var capture:Variant=JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if not capture is Dictionary or not mount(capture):finish();return
	original_totals=totals()
	for t:Dictionary in runtime.world.extension("r3:production").tools:original_tool_ids.append(str(t.id))
	original_tool_ids.sort()
	check("continuation starts with unearned exploration defense and radio",game().exploration.status=="idle" and game().defense.status=="dormant" and game().radio.status=="unrepaired")
	check("actual built bench and storage survive retained material route",not runtime.world.entity("E-material:real-log-cabinet").is_empty())
	if not equip():finish();return
	write_json("actual-equipped-capture.json",runtime.capture_checkpoint())
	if not expedition():finish();return
	write_json("actual-exploration-capture.json",runtime.capture_checkpoint())
	if not defend():finish();return
	write_json("actual-defense-capture.json",runtime.capture_checkpoint())
	if not communicate():finish();return
	write_json("actual-radio-capture.json",runtime.capture_checkpoint())
	if not home_goals():finish();return
	audit()
	write_json("actual-all-RH-capture.json",runtime.capture_checkpoint())
	finish()

func audit()->void:
	var final:Dictionary=totals()
	var enemies:Array=runtime.facts().actors.filter(func(a:Dictionary)->bool:return a.get("faction")=="infected")
	check("exact original finite seven enemies are dead and settled",enemies.size()==7 and enemies.all(func(a:Dictionary)->bool:return float(a.hp)==0 and a.get("death_settled",false) and a.pack.is_empty()))
	check("all seven real corpse containers are physically emptied",enemies.all(func(a:Dictionary)->bool:return not runtime.stock(str(a.id)+":drops").is_empty() and runtime.stock(str(a.id)+":drops").items.values().all(func(q:Variant)->bool:return float(q)==0)))
	# Original recipes: repair axe1 scrap+handle; craft handle1 timber;
	# radio8 scrap+handle; gate1 timber+scrap; bed2 cloth. Seven finite
	# enemies each carry the already-defined one scrap, not respawning loot.
	for item:String in ["scrap","timber","tool_handle","cloth","log"]:
		var change:float={"scrap":-3.0,"timber":-2.0,"tool_handle":-1.0,"cloth":-2.0,"log":0.0}[item]
		check("whole-world "+item+" equals original plus exact finite encounters minus real costs",float(final.get(item,0))==float(original_totals.get(item,0))+change,{"original":original_totals.get(item,0),"final":final.get(item,0),"expected_delta":change})
	var tools:Array=[]
	for t:Dictionary in runtime.world.extension("r3:production").tools:tools.append(str(t.id))
	tools.sort()
	check("complete actual route preserves all original tool identities",tools==original_tool_ids)
	write_json("finite-route-audit.json",{"scope":"recorded historical material continuation, same current runtime; no grant fixtures, no OS acceptance","original_totals":original_totals,"final_totals":final,"tool_ids":tools,"enemy_ids":enemies.map(func(a:Dictionary)->String:return str(a.id)),"combat_hits":combat_steps.size(),"quests":runtime.facts().quests.map(func(q:Dictionary)->Dictionary:return {"id":q.id,"completed":q.completed}),"player_hp":runtime.actor("player").hp,"logical_ticks":ticks,"time":runtime.clock()})

func equip()->bool:
	var shed:="RH-HOME:shed:storage"
	if not stock_at(shed) or not perform("take original finite repair manual","take",shed,{"items":{"book_tool_repair":1}}):return false
	var records:Array=runtime.world.extension("r3:production").records.filter(func(r:Dictionary)->bool:return r.holderId=="pack:player" and r.itemId=="book_tool_repair")
	check("actual finite repair manual moves with its original record",records.size()==1)
	if records.size()!=1 or not perform("learn repair through real paid study","study",str(records[0].id),{"record_id":records[0].id}):return false
	check("actual study earned repair knowledge",runtime.world.extension("r3:production").knowledge.player.has("basic_tool_repair"))
	if not approach("village-resident"):return false
	var owned:Array=runtime.world.extension("r3:production").tools.filter(func(t:Dictionary)->bool:return t.holderId=="pack:village-resident" and t.kind=="salvaged_axe")
	check("original cooperating harvester retains original worn axe",owned.size()==1)
	if owned.size()!=1 or not perform("consensually retrieve original finite harvester axe","take","pack:village-resident",{"tool_ids":[owned[0].id]}):return false
	if not approach("repair-resident") or not perform("retrieve actual previously crafted finite handle","take","pack:repair-resident",{"items":{"tool_handle":1}}):return false
	axe=tool("salvaged_axe");hammer=tool("hammer");saw=tool("hand_saw")
	check("same actual axe hammer and saw now carried",not axe.is_empty() and not hammer.is_empty() and not saw.is_empty())
	if axe.is_empty() or hammer.is_empty() or saw.is_empty():return false
	var stations:Array=runtime.world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.get("definitionId")=="workbench")
	if stations.size()!=1:check("one actual retained constructed bench",false);return false
	bench=stations[0].id
	var points:Array=runtime._services.buildings.use_points(bench)
	if points.is_empty() or not walk(points[0],"actual route back to built repair station"):return false
	var pack:Dictionary=runtime.actor("player").pack.duplicate(true)
	if not perform("real axe improvement with actual handle scrap hammer knowledge","craft",bench,{"recipe_id":"repair_axe","source_id":"pack:player","output_id":"pack:player","repair_tool_id":axe,"tool_ids":[hammer]}):return false
	check("axe repair really spends one original handle and scrap",float(runtime.actor("player").pack.tool_handle)==float(pack.tool_handle)-1 and float(runtime.actor("player").pack.scrap)==float(pack.scrap)-1 and float(runtime.tool(axe).durability)>float(owned[0].durability))
	if not perform("make radio handle using remaining original timber","craft",bench,{"recipe_id":"make_handle","source_id":"pack:player","output_id":"pack:player","tool_ids":[saw]}):return false
	if not perform("real bounded pre-expedition rest","rest"):return false
	return roundtrip("actual learned repaired and crafted preparation")

func nearest_hostile()->Dictionary:
	var result:Dictionary={};var distance:=INF
	var player:Dictionary=runtime.actor("player")
	for a:Dictionary in runtime.facts().actors:
		if a.get("faction")!="infected" or float(a.hp)<=0:continue
		var d:float=Geometry.point(a).distance_to(Geometry.point(player))
		if d<distance:distance=d;result=a
	return result

func retreat(enemy:Dictionary)->void:
	var player:Dictionary=runtime.actor("player")
	var away:Vector2=Vector2(float(player.x)-float(enemy.x),float(player.z)-float(enemy.z)).normalized()
	if away.length_squared()<0.01:away=Vector2.RIGHT
	var query:RefCounted=runtime._services.buildings.current_space()
	for angle:float in [0.0,0.6,-0.6,1.2,-1.2,1.8,-1.8]:
		var direction:Vector2=away.rotated(angle)
		var point:Dictionary=Geometry.location(player)
		point.x+=direction.x*Movement.WALK_SPEED*0.1;point.z+=direction.y*Movement.WALK_SPEED*0.1
		point=query.standing_point(point)
		if point.is_empty():continue
		var moved:Dictionary=send("direct_move","",{"movement_dt":0.1,"movement_mode":"walk"},point)
		if moved.ok:return

func battle(label:String,cleared:Callable)->bool:
	for i:int in 1600:
		if not healthy():return false
		if cleared.call():check(label+" actual finite enemies defeated",true);return true
		var enemy:Dictionary=nearest_hostile()
		if enemy.is_empty():step();continue
		var player:Dictionary=runtime.actor("player")
		var distance:float=Geometry.point(player).distance_to(Geometry.point(enemy))
		if player.intent!=null and not send("cancel").ok:return false
		if float(player.cooldown)<=0 and float(player.stamina)>=14 and runtime._services.gameplay._near(player,enemy,2.05) and runtime._services.gameplay._clear(player,enemy):
			var hit:Dictionary=send("attack",str(enemy.id),{"tool_id":axe})
			if not hit.ok:check(label+" real in-range attack accepted",false,{"code":hit.get("code"),"reason":hit.get("reason")});return false
			combat_steps.append({"time":runtime.clock(),"target":enemy.id,"hp":runtime.actor(enemy.id).hp,"player_hp":runtime.actor("player").hp,"stamina":runtime.actor("player").stamina})
		# Stay still while a visible pursuer is outside attack range. Retreating
		# at 2.4m forever would keep our own controller from ever making contact.
		if distance<=2.05:retreat(enemy)
		elif distance>8.0:
			var destination:Dictionary=Geometry.location(enemy)
			var started:Dictionary=send("walk","",{},destination)
			if not started.ok:check(label+" B route reaches real threatening actor",false,{"code":started.get("code"),"reason":started.get("reason"),"actor":enemy});return false
		step()
	check(label+" actual finite combat completes within logical bound",false,{"gameplay":game(),"combat":combat_steps,"actors":runtime.facts().actors})
	return false

func loot(roster:Array,label:String)->bool:
	for id:String in roster:
		var stock:String=id+":drops"
		if not stock_at(stock):return false
		var items:Dictionary=runtime.stock(stock).items.duplicate(true)
		if not items.is_empty() and not perform(label+" actually retrieves finite corpse supplies","take",stock,{"items":items}):return false
	return true

func expedition()->bool:
	if not perform("start actual exploration at real home","explore_start"):return false
	for index:int in game().encounters.size():
		var encounter:Dictionary=game().encounters[index]
		if not walk(encounter.position,"B real travel to original encounter "+str(encounter.id)):return false
		step();encounter=game().encounters[index]
		check("original encounter really generated its full finite group",encounter.spawned and encounter.actors.size()==2,{"encounter":encounter})
		if not encounter.spawned:return false
		if not battle(str(encounter.id),func()->bool:return game().encounters[index].cleared):return false
		var choices:Array=game().exploration.candidates.duplicate()
		check("real defeated encounter earns persistent candidates",choices.size()==3,choices)
		if choices.is_empty() or not roundtrip("actual exploration after finite encounter before choice"):return false
		var selected:String=""
		for preferred:String in ["chain","stagger","guard","shove"]:
			if choices.has(preferred):selected=preferred;break
		if not perform("choose actually earned exploration upgrade","explore_choose","",{"choice_id":selected}):return false
		if not loot(encounter.actors,"exploration"):return false
		write_json("actual-encounter-"+str(index)+"-capture.json",runtime.capture_checkpoint())
	var home_stock:String=game().layout.home_building+":storage"
	if not stock_at(home_stock) or not perform("return physically then explicitly settle earned exploration","explore_end"):return false
	check("two real encounters choices loot and home return unlock finite defense",game().flags.get("exploration_completed",false) and game().defense.status=="warning" and game().exploration.settled.size()==1)
	return roundtrip("actually completed finite exploration and pending defense")

func defend()->bool:
	if not perform("real recovery rest before original finite wave","rest"):return false
	if not perform("actually request original due finite defense","defend"):return false
	step()
	check("actual defense warning produces full real finite wave",game().defense.status=="active" and game().defense.actors.size()==3,game().defense)
	if game().defense.status!="active" or not battle("actual home defense",func()->bool:return game().defense.status=="cleared"):return false
	return loot(game().defense.actors,"defense") and roundtrip("actually defeated original finite defense")

func communicate()->bool:
	var stock:="RH-VILLAGE:repair:tools"
	if float(runtime.actor("player").pack.get("scrap",0))<8:
		if not stock_at(stock) or not perform("search real original repair supply stock","search",stock):return false
		var need:int=8-int(runtime.actor("player").pack.get("scrap",0))
		if not perform("take only missing finite original repair scrap","take",stock,{"items":{"scrap":need}}):return false
	var points:Array=runtime._services.buildings.use_points(bench)
	if points.is_empty() or not walk(points[0],"actual return to original built radio station"):return false
	var before:Dictionary=runtime.actor("player").pack.duplicate(true)
	if not perform("actual earned-defense radio repair pays original finite materials","radio",bench,{"operation":"repair","tool_id":hammer}):return false
	check("naturally enabled radio charges exact original eight plus one",game().radio.status=="repaired" and float(runtime.actor("player").pack.scrap)==float(before.scrap)-8 and float(runtime.actor("player").pack.tool_handle)==float(before.tool_handle)-1)
	if not roundtrip("actual paid repaired radio before transmission"):return false
	if not perform("actually transmit using repaired real station","radio",bench,{"operation":"transmit"}):return false
	check("actual finite route reaches original radio goal",game().radio.status=="connected" and game().flags.get("radio_connected",false) and healthy())
	for i:int in 6:step()
	check("normal half-second quest scheduler observes actual earned radio completion",runtime.facts().quests.any(func(q:Dictionary)->bool:return q.id=="RH-Q08" and q.completed))
	write_json("combat-evidence.json",combat_steps)
	return roundtrip("actual original exploration defense paid repair transmission completed")

func home_goals()->bool:
	# Close the original remaining Q01/Q03 with finite original stock and
	# canonical labor; do not write quest flags or prepare/repair fixtures.
	var shelves:Array=runtime.facts().stocks.filter(func(s:Dictionary)->bool:return str(s.id).begins_with(str(game().layout.store_prefix)) and float(s.items.get("water",0))>=1 and float(s.items.get("food",0))>=1)
	check("original finite village supplies still physically exist",not shelves.is_empty())
	if shelves.is_empty():return false
	var shelf:String=shelves[0].id
	if not stock_at(shelf) or not perform("actually search original village shop","search",shelf) or not perform("retrieve actual village food and water","take",shelf,{"items":{"water":1,"food":1}}):return false
	var stock:String=game().layout.home_building+":storage"
	if not stock_at(stock) or not perform("take original finite cloth for real bed preparation","take",stock,{"items":{"cloth":2}}):return false
	var gate:String=game().layout.gate_id
	var building:RefCounted=runtime._services.buildings
	var points:Array=building.use_points(gate)
	var reached:=false
	for point:Dictionary in points:
		var route:Dictionary=send("walk","",{},point)
		if route.ok and idle() and building.can_use("player",building.instance(gate))==null:reached=true;break
	check("B real route reaches repairable original yard gate",reached)
	if not reached:return false
	var before:Dictionary=runtime.actor("player").pack.duplicate(true)
	if not perform("repair original damaged gate with real timber scrap hammer","structure",gate,{"kind":"repair","source_id":"pack:player","output_id":"pack:player","tool_id":hammer}):return false
	check("gate actual repair consumes finite original timber and scrap once",float(runtime.actor("player").pack.timber)==float(before.timber)-1 and float(runtime.actor("player").pack.scrap)==float(before.scrap)-1 and float(building.instance(gate).hp)>60)
	var bed:String=str(game().layout.home_building)+":sleeping-place"
	points=runtime._services.residents._bed_points(runtime.world.entity(bed))
	reached=false
	for point:Dictionary in points:
		var route:Dictionary=send("walk","",{},point)
		if route.ok and idle():reached=true;break
	check("B actual standing route reaches original unprepared home bed",reached)
	if not reached or not perform("actually prepare original home bed with original two cloth","prepare_bed",bed,{"source_id":"pack:player"}):return false
	check("real bed preparation changes actual object and consumes two cloth",runtime.world.entity(bed).data.prepared and float(runtime.actor("player").pack.cloth)==0)
	if not perform("actually rest at original prepared bed","rest",bed):return false
	for i:int in 6:step()
	check("all eight original RH quest facts are naturally satisfied by recorded route continuation",runtime.facts().quests.size()==8 and runtime.facts().quests.all(func(q:Dictionary)->bool:return q.completed),runtime.facts().quests)
	return roundtrip("actual finite complete RH quest chain and prepared home")
