extends SceneTree
## Real finite rural runtime and B routes. Explicit need/recruitment spatial
## fixtures are labeled; this does not claim an OS-input player route or VA.
const Client=preload("res://scripts/runtime/native_client.gd")
const World=preload("res://scripts/world/world_state.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const Building=preload("res://scripts/buildings/building_service.gd")
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
const Initial=preload("res://scripts/runtime/initial_state.gd")
const Gameplay=preload("res://scripts/runtime/rural_gameplay.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const Movement=preload("res://scripts/runtime/movement_policy.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
var host:Node
var runtime:RefCounted
var seq:=0
func _initialize()->void:call_deferred("run")
func check(name:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+name+" "+str(detail))
func mount(capture:Dictionary)->bool:
	var built:Dictionary=host._assemble(capture)
	check("formal assembler validates real services/actors",built.ok,built.get("reason"))
	if built.ok:runtime=built.runtime
	return built.ok
func command(kind:String,target:String="",payload:Dictionary={})->Dictionary:
	seq+=1
	return runtime.command({"command_id":"resident-test:"+str(seq),"actor_id":"player","kind":kind,"target_id":target,"payload":payload})
func differences(a:Variant,b:Variant,path:String="",found:Array=[])->Array:
	if found.size()>=16:return found
	if a is PackedInt32Array:a=Array(a)
	if b is PackedInt32Array:b=Array(b)
	if a is Dictionary and b is Dictionary:
		for key in a:
			if not b.has(key):found.append({"path":path+"/"+str(key),"missing":true})
			else:differences(a[key],b[key],path+"/"+str(key),found)
		for key in b:
			if not a.has(key):found.append({"path":path+"/"+str(key),"extra":true})
	elif a is Array and b is Array:
		if a.size()!=b.size():found.append({"path":path,"sizes":[a.size(),b.size()]})
		for i:int in mini(a.size(),b.size()):differences(a[i],b[i],path+"/"+str(i),found)
	elif a!=b:
		var continuous:bool=path.get_file() in ["x","y","z","time","nextDecision","next_decision","elapsed","durability","hunger","thirst","stamina","fatigue","cooldown"]
		var inventory:bool=path.contains("/pack/") or path.contains("/items/") or path.contains("/reserved/") or path.contains("/cost/")
		if not continuous or inventory or not (a is float or a is int) or not (b is float or b is int) or absf(float(a)-float(b))>1e-12:found.append({"path":path,"before":a,"after":b})
	return found


func run()->void:
	host=Client.new()
	var world:=World.new();check("existing C rural world loads",world.load_snapshot(Rural.generate(713)).ok)
	var b:=Building.new();b.configure({"world":world,"runtime":Runtime.new()})
	var seeded:Dictionary=b.seed_rural(world);check("existing B buildings prepare",seeded.ok,seeded.get("reason"))
	if not seeded.ok:finish();return
	var changes:Array=seeded.world_changes.duplicate(true)
	changes.append_array([b.extension_change("r3:production",Initial.production(seeded)),b.extension_change(Gameplay.KEY,Gameplay.initial()),b.extension_change("r3:structure-orders",{"version":1,"orders":[]})])
	var draft:Dictionary=world.prepare_changes(changes,world.get_revision())
	check("one C transaction commits rural structures and finite facts metadata",draft.ok and world.commit_prepared(draft.capability).ok)
	if not mount({"world":world.snapshot(),"facts":Initial.facts(seeded),"source":{"fixture":"retained rural-1 real seed"}}):finish();return
	var initial:Dictionary=runtime.capture_checkpoint()
	var tracks:Dictionary={"village-resident":[],"repair-resident":[]}
	var bad_feet:Array=[];var jumps:Array=[];var previous:Dictionary={}
	for id:String in tracks:previous[id]=Geometry.point(runtime.actor(id))
	for i in 240:
		runtime.tick(0.1)
		for id:String in tracks:
			var a:Dictionary=runtime.actor(id);var at:=Geometry.point(a)
			var delta:Vector3=at-previous[id]
			if Vector2(delta.x,delta.z).length()>Movement.WALK_SPEED*0.1+0.001 or absf(delta.y)>0.501:jumps.append({"id":id,"delta":[delta.x,delta.y,delta.z]})
			if runtime._services.buildings.current_space().standing_point(Geometry.location(a)).is_empty():bad_feet.append({"id":id,"at":Geometry.location(a)})
			tracks[id].append([a.x,a.y,a.z]);previous[id]=at
	for id:String in tracks:
		var unique:Dictionary={}
		for point:Array in tracks[id]:unique[str(point)]=true
		check(id+" really walks before joining",unique.size()>3,{"positions":unique.size(),"routine":runtime.actor(id).get("self_routine"),"activity":runtime.actor(id).activity})
		check(id+" remains unjoined/unconsenting and creates no items or skill",not runtime.actor(id).relationship.member and not runtime.actor(id).relationship.consent and runtime.actor(id).pack.is_empty() and runtime.actor(id).skills==initial.facts.actors.filter(func(a:Dictionary)->bool:return a.id==id)[0].skills)
	check("all 480 actor feet use B's true terrain/body support",bad_feet.is_empty(),bad_feet)
	check("all ordinary steps obey A shared walk speed and real height steps",jumps.is_empty(),jumps)
	check("all finite stocks remain exactly conserved",Data.json_equal(initial.facts.stocks,runtime.facts().stocks))
	var denied:Dictionary=command("job","village-resident",{"job":"gather","work_target_id":"none"})
	check("autonomy never authorizes player work assignment",not denied.ok and denied.code=="NO_CONSENT",denied)
	runtime.set_paused(true);var paused:Dictionary=runtime.capture_checkpoint();runtime.tick(100)
	check("pause freezes NPCs and the one clock",Data.json_equal(paused,runtime.capture_checkpoint()))
	runtime.set_paused(false)
	# Make one real in-progress self walk, then save/restore it through C codec.
	for i in 100:
		runtime.tick(0.1)
		if runtime.actor("village-resident").get("intent") is Dictionary and runtime.actor("village-resident").intent.get("owner")=="residents":break
	var before:Dictionary=runtime.capture_checkpoint();var encoded:Dictionary=Store.encode(before)
	check("ongoing autonomous intent is native-save compatible",encoded.ok,encoded.get("reason"))
	if encoded.ok:
		var decoded:Dictionary=Store.decode(encoded.text)
		check("native envelope restores ongoing walk",decoded.ok,decoded.get("reason"))
		if decoded.ok and mount(decoded.capture):
			# JSON numeric roundtrip may change time/elapsed by a few ULPs.
			# Never allow this tolerance for inventories, IDs or discrete state.
			var changed:Array=differences(before.facts,runtime.facts(),"facts",[])
			check("restore preserves exact discrete facts and bounded continuous values without advancement",changed.is_empty(),changed)
			check("restore comparator rejects changed inventory and meaningful time",not differences({"pack":{"food":1.0}},{"pack":{"food":1.00000000000001}},"facts",[]).is_empty() and not differences({"time":1.0},{"time":1.000000001},"facts",[]).is_empty())
			var old:Vector3=Geometry.point(runtime.actor("village-resident"))
			for i in 8:runtime.tick(0.1)
			check("restored route continues through B real steps",Geometry.point(runtime.actor("village-resident")).distance_to(old)>0.05)
	var need:Dictionary=runtime.capture_checkpoint()
	for a:Dictionary in need.facts.actors:
		if a.id=="village-resident":a.thirst=20.0;a.pack={"water":1};a.intent=null;a.self_routine.next_decision=need.facts.time
	if mount(need):
		var player_pack:Dictionary=runtime.actor("player").pack
		for i in 20:runtime.tick(0.1)
		check("explicit thirsty fixture drinks exactly one OWN real water",runtime.actor("village-resident").pack.water==0 and runtime.actor("village-resident").thirst>63.0,runtime.actor("village-resident"))
		check("self-care never takes player/shared supplies or consents",runtime.actor("player").pack==player_pack and not runtime.actor("village-resident").relationship.consent)
		var thirst:float=runtime.actor("village-resident").thirst
		for i in 20:runtime.tick(0.1)
		check("empty pack never generates another drink",runtime.actor("village-resident").pack.water==0 and runtime.actor("village-resident").thirst<thirst)
	finish()
func finish()->void:
	var report:Dictionary={"scope":"real one-runtime self-routines, B physical step/door executor, native checkpoint roundtrip, explicit needs fixture; not native input/VA acceptance","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var path:String=OS.get_cmdline_user_args()[0]
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print(JSON.stringify(report));host.free();quit(1 if report.failed else 0)
