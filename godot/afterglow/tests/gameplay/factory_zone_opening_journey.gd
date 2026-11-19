extends "res://tests/gameplay/factory_zone_patrol.gd"
## Continue A's actual new12 searched seed-bag save. The player must really
## recover the old hammer before inviting the second person. No pack seeding,
## forced consent, altered needs, teleports, capture writes or new executor.
const Movement=preload("res://scripts/runtime/movement_policy.gd")
const Gameplay=preload("res://scripts/runtime/factory_gameplay.gd")
const Residency=preload("res://scripts/runtime/region_residency.gd")
const HeadlessNative=preload("res://tests/gameplay/factory_zone_native_residency.gd")
var residency_changes:Array=[]
var stages:Array=[]
var horizontal_jumps:Array=[]
var initial:Dictionary={}
var maximum_vertical:float=0
var elapsed_start:float=0
var invitations:Dictionary={}
var source_tools:String="r34:generated:RH-HOME:woodwork:stock:tools"
var source_store:String="r34:generated:RH-VILLAGE:store:stock:supplies"
var source_home:String="r34:generated:RH-HOME:home:stock:supplies"

func tick()->void:
	var before:Dictionary={}
	for actor:Dictionary in runtime.facts().actors:before[actor.id]=G.point(actor)
	runtime.tick(.1);steps+=1
	for actor:Dictionary in runtime.facts().actors:
		var delta:Vector3=G.point(actor)-before[actor.id]
		var horizontal:float=Vector2(delta.x,delta.z).length()
		maximum_step=maxf(maximum_step,horizontal);maximum_vertical=maxf(maximum_vertical,absf(delta.y))
		if horizontal>Movement.WALK_SPEED*.1+.001 or absf(delta.y)>.501:horizontal_jumps.append({"step":steps,"actor_id":actor.id,"delta":G.json_point(delta)})
	if steps%50==0:
		observations.append({"step":steps,"time":runtime.clock(),"actors":runtime.facts().actors})
		write_progress()

func quantities()->Dictionary:
	var values:Dictionary={}
	for stock:Dictionary in runtime.facts().stocks:
		for item:String in stock.items:values[item]=float(values.get(item,0))+float(stock.items[item])
	for actor:Dictionary in runtime.facts().actors:
		for item:String in actor.pack:values[item]=float(values.get(item,0))+float(actor.pack[item])
	return values

func note(label:String)->void:
	stages.append({"stage":label,"time":runtime.clock(),"steps":steps,"quantities":quantities(),"actors":runtime.facts().actors,"production":runtime.world.extension("r3:production"),"ecology":runtime.world.extension("r34:ecology")})
	print("OPENING_JOURNEY "+label+" "+str(runtime.clock()))
	write_progress()

func write_progress()->void:
	FileAccess.open(output+"/progress.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"steps":steps,"stages":stages,"actors":runtime.facts().actors},"\t",true,true))

func send_to(kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	sequence+=1
	var request:Dictionary={"command_id":"E:new12:"+str(options.run_id)+":"+str(sequence),"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"destination":destination}
	var receipt:Dictionary=runtime.command(request)
	commands.append({"request":request,"result":receipt,"time":runtime.clock()})
	return receipt

func progress(limit:int=1800)->bool:
	for i:int in limit:
		if runtime.actor("player").get("intent")==null:return true
		tick()
	return runtime.actor("player").get("intent")==null

func perform(label:String,kind:String,target:String="",payload:Dictionary={})->bool:
	var receipt:Dictionary=send_to(kind,target,payload)
	var ok:bool=receipt.get("ok",false) and progress()
	check(label,ok,receipt if not ok else null)
	return ok

func self_care()->bool:
	var player:Dictionary=runtime.actor("player")
	for spec:Array in [["drink","thirst","water"],["eat","hunger","food"]]:
		if float(player.get(spec[1],100))<40:
			if float(player.pack.get(spec[2],0))<1:return false
			if not perform("player pays original finite "+str(spec[2])+" for actual self care",spec[0]):return false
			player=runtime.actor("player")
	if float(player.stamina)<25:return perform("player rests for original paid game time","rest")
	return true

func go(at:Dictionary,label:String)->bool:
	if not self_care():check(label+" has actual self-care supplies",false,runtime.actor("player"));return false
	if runtime.actor("player").regionId!=at.regionId and not runtime.region_is_detailed(at.regionId):
		# A distant cold target is not yet a legal body route. Physically walk
		# to the existing authored connecting face, then let A's real fringe
		# policy request its data. Do not preload arbitrary destinations.
		var exits:Array=runtime.world.region(runtime.actor("player").regionId).get("exits",[]).filter(func(row:Dictionary)->bool:return row.get("toRegionId")==at.regionId)
		if exits.is_empty():check(label+" has an actual adjacent exit",false);return false
		var edge:Dictionary=G.location(exits[0].position);edge.regionId=runtime.actor("player").regionId
		if not await go(edge,label+" physical approach to resident boundary"):return false
		if not await warm_required(at.regionId):return false
	var receipt:Dictionary=send_to("walk","",{},at)
	var ok:bool=receipt.get("ok",false) and progress() and runtime.actor("player").regionId==at.regionId and G.point(runtime.actor("player")).distance_to(G.point(at))<.4
	check(label,ok,{"receipt":receipt,"destination":at,"actor":runtime.actor("player")} if not ok else null)
	return ok

func warm_required(id:String)->bool:
	var pins:Dictionary=Residency.required_regions(runtime)
	check("physical fringe really requires target before Native warm "+id,pins.has(id),pins)
	if not pins.has(id):return false
	var client:=HeadlessNative.new();client.runtime=runtime;client.world=runtime.world;client._residency.attach(runtime);root.add_child(client)
	var before:Dictionary=runtime.facts()
	var result:Dictionary=await client._change_residency({"region_id":id,"resident":true,"pins":pins})
	var after:Dictionary=runtime.facts()
	residency_changes.append({"step":steps,"pins":pins,"result":result,"before_facts":before,"after_facts":after})
	client.free()
	# Original Native CAS records one storage event per successful batch. Keep
	# and verify those events; demanding unchanged ledger would reject the
	# exact authorized path rather than detect a gameplay mutation.
	var batches:int=int(result.get("batches",0))
	var added:Array=after.ledger.slice(after.ledger.size()-batches) if batches>0 else []
	var expected:Array=before.ledger.duplicate(true);expected.append_array(added);expected=expected.slice(maxi(0,expected.size()-256))
	var unchanged:bool=before.keys().all(func(key:String)->bool:return key=="ledger" or Data.json_equal(before[key],after.get(key)))
	var storage_only:bool=added.size()==batches and added.all(func(row:Dictionary)->bool:return row.get("kind")=="region-storage-changed" and row.get("region_id")==id and row.get("resident")==true and row.get("time")==before.time) and Data.json_equal(expected,after.ledger)
	var ok:bool=result.get("ok",false) and runtime.region_is_detailed(id) and unchanged and storage_only
	check("original Native detached warm preserves gameplay facts "+id,ok,result)
	return ok

func reach_stock(id:String)->bool:
	var stock:Dictionary=runtime.stock(id)
	if stock.is_empty():check("actual stock exists "+id,false);return false
	return await go(G.location(stock),"player physically reaches "+id)

func take_stock(id:String,items:Dictionary={},tools:Array=[])->bool:
	if not await reach_stock(id):return false
	if not runtime.stock(id).get("searched",false):
		if not perform("original timed search discovers "+id,"search",id):return false
	return perform("original transfer takes only finite source contents "+id,"take",id,{"items":items,"tool_ids":tools})

func social_reach(id:String)->bool:
	var a:Dictionary=runtime.actor("player");var b:Dictionary=runtime.actor(id)
	return a.regionId==b.regionId and a.get("buildingId")==b.get("buildingId") and a.get("storeyId")==b.get("storeyId") and G.point(a).distance_to(G.point(b))<=2.1 and runtime.domain_service("buildings").current_space().line_clear(G.location(a),G.location(b),"")

func approach(id:String)->bool:
	for attempt:int in 8:
		if social_reach(id):return true
		var receipt:Dictionary=send_to("walk","",{},G.location(runtime.actor(id)))
		if not receipt.get("ok",false):check("real social route to "+id,false,receipt);return false
		for i:int in 1000:
			if social_reach(id):
				if runtime.actor("player").get("intent")!=null:return send_to("cancel").get("ok",false)
				return true
			if runtime.actor("player").get("intent")==null:break
			tick()
	check("real social contact with "+id,false,{"player":runtime.actor("player"),"person":runtime.actor(id)})
	return false

func recruit(id:String,item:String)->bool:
	if not approach(id):return false
	var before:float=float(runtime.actor("player").pack.get(item,0))
	if not perform("actual finite help to "+id,"help",id,{"items":{item:1}}):return false
	check("help is a paid transfer rather than a supply grant "+id,float(runtime.actor("player").pack.get(item,0))==before-1)
	if not perform("original voluntary invitation "+id,"invite",id):return false
	invitations[id]=runtime.clock()
	return true

func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];options=JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]));var native:=Native.new()
	var built:Dictionary=native._assemble(decoded.capture) if decoded.get("ok",false) else decoded;native.free()
	check("identified actual searched new12 source mounts unchanged",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	runtime=built.runtime;initial=runtime.capture_checkpoint();elapsed_start=runtime.clock()
	check("opening retains exactly original three unrecruited people and finite seeds",runtime.facts().actors.size()==3 and ["village-resident","repair-resident"].all(func(id:String)->bool:return not runtime.actor(id).relationship.consent) and ["r34:potato_seed","r34:bean_seed","r34:rice_seed"].all(func(id:String)->bool:return runtime.actor("player").pack.get(id)==4) and runtime.actor("player").pack.get("r34:water_bucket")==1)
	note("actual12-start")
	if not await take_stock(source_store,{"food":2,"water":3}):return finish()
	if not recruit("village-resident","water"):return finish()
	note("first-real-voluntary-member")
	# The second invitation is gated by the ORIGINAL hammer rule. Return to
	# recover it at its finite source, not by modifying that rule or a holder.
	var layout:Dictionary=runtime.world.extension(Gameplay.KEY).layout
	if not await go(layout.home,"first real trip returns to original home entrance"):return finish()
	var tools:Array=[]
	for tool:Dictionary in runtime.world.extension("r3:production").tools:
		if tool.holderId==source_tools and tool.kind in ["hammer","hand_saw","salvaged_axe"]:tools.append(tool.id)
	check("original finite workshop contains the three actual tool identities",tools.size()==3,tools)
	if tools.size()!=3 or not await take_stock(source_tools,{"book_woodwork":1,"book_tool_repair":1},tools):return finish()
	note("tools-recovered-through-real-home-trip")
	if not cold("actual12-tools-mid-route-cold"):return finish()
	if not recruit("repair-resident","food"):return finish()
	note("two-real-voluntary-members")
	if not await go(layout.home,"actual player return along connected village-home route"):return finish()
	for i:int in 1600:
		if ["village-resident","repair-resident"].all(func(id:String)->bool:return runtime.actor(id).relationship.get("home_arrived",false)):break
		tick()
	check("both original people actually return home by E-B shared routes",["village-resident","repair-resident"].all(func(id:String)->bool:return runtime.actor(id).relationship.get("home_arrived",false) and runtime.actor(id).regionId==layout.home.regionId and G.point(runtime.actor(id)).distance_to(G.point(layout.home))<=float(layout.get("home_radius",18))))
	check("recruitment never injects seeds bucket food water materials or population",runtime.facts().actors.size()==3 and ["r34:potato_seed","r34:bean_seed","r34:rice_seed"].all(func(id:String)->bool:return quantities().get(id)==4) and quantities().get("r34:water_bucket")==1 and float(quantities().get("food",0))<=9 and float(quantities().get("water",0))<=10)
	check("real original tools all remain same identities and unrepaired durability",tools.all(func(id:String)->bool:return runtime.tool(id).holderId=="pack:player" and float(runtime.tool(id).durability)==float(initial.world.extensions["r3:production"].tools.filter(func(t:Dictionary)->bool:return t.id==id)[0].durability)))
	check("people retain original HP and voluntary consent without replacement",initial.facts.actors.all(func(a:Dictionary)->bool:return runtime.actor(a.id).hp==a.hp) and ["village-resident","repair-resident"].all(func(id:String)->bool:return runtime.actor(id).relationship.consent and runtime.actor(id).relationship.member))
	note("actual12-joined-home-finite-start")
	cold("actual12-joined-home-final-cold")
	finish()

func finish()->void:
	if runtime!=null:
		check("all real travel preserves body speed and supported half-metre steps",horizontal_jumps.is_empty(),{"jumps":horizontal_jumps,"max_horizontal":maximum_step,"max_vertical":maximum_vertical})
		save("actual12-joined-home-final")
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"commands":commands,"observations":observations,"stages":stages,"residency_changes":residency_changes,"steps":steps,"simulation_seconds":runtime.clock()-elapsed_start if runtime!=null else 0,"scope":"Actual A opening12 source pickup continuation; real finite store search, paid help, hammer gate, two voluntary original members, E-B routes to home, exact active/final Native cold. Tools are player-recovered from original source, not NPC autonomous tooling yet. Headless data residency uses original Native detached warm only after actual boundary travel and original required_regions pin; no terrain mesh/physics qualification. No grants, fixture, teleport, altered needs or capture mutation. Not farming, water processing, canteen or sustainable economy completion; source functional only, no package/OS/VA/FPS/wall long."},"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed,"steps":steps}));quit(1 if failed else 0)
