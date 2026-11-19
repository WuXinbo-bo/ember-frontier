extends SceneTree
## Real shipping assembly, strict mesh/physics mount, life actions and storage.
const Client=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const RadioView=preload("res://scripts/presentation/gameplay_view.gd")
class TestClient extends Client:
	func _ready()->void:pass
var checks:Array=[]
var output:String
var host:Node3D
var movement:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0] if not args.is_empty() else "user://village13-integration"
	DirAccess.make_dir_recursive_absolute(output)
	host=TestClient.new();host.controls_path=output+"/controls.json";host.store=Store.new(output+"/saves");root.add_child(host)
	check("normal survival is the fresh-client default",host._new_world_profile=="normal")
	var result:Dictionary=await host.start_profiled_world("normal",713,"village13-opening")
	check("actual async entry passes unchanged geometry and physics barrier",result.ok,result)
	if not result.ok:return finish()
	host.runtime.set_paused(true)
	var generation:Dictionary=host.world.extension("generation:factory-r34")
	check("new entry pins content13 old-village generation",generation.get("content_version")==13,generation.get("content_version"))
	var actors:Array=host.runtime.facts().actors
	check("three living companions stand in the same starting village",actors.size()==3 and actors.all(func(a:Dictionary)->bool:return a.regionId=="RH-HOME" and a.hp>0 and host.world.region_at(a).get("id")==a.regionId))
	check("two companions consent and share the household from the start",actors.filter(func(a:Dictionary)->bool:return a.id!="player").all(func(a:Dictionary)->bool:return a.relationship.member and a.relationship.consent and a.householdId=="home-residents"))
	check("normal opening gives no testing board grant",host.runtime.capture_checkpoint().source.get("playtest",{}).is_empty() and host.runtime.actor("player").pack.get("timber",0)==0)
	var modules:Array=host.world.extension("r34:modules").instances
	var homes:Array=modules.filter(func(m:Dictionary)->bool:return m.definition_id=="r35.module.village_home")
	var warehouses:Array=modules.filter(func(m:Dictionary)->bool:return m.definition_id=="r35.module.village_warehouse")
	check("initial home and warehouse carry unfinished original-site restoration",homes.size()==1 and warehouses.size()==1 and not homes[0].restoration.completed and not warehouses[0].restoration.completed)
	var beds:Array=host.world.entities().filter(func(e:Dictionary)->bool:return e.get("data",{}).get("village_shelter",false))
	check("old home contains three independent usable physical sleeping entities",beds.size()==3 and beds.all(func(e:Dictionary)->bool:return e.data.sleeping and e.data.prepared and e.data.module_bed.approach.regionId=="RH-HOME"),beds.size())
	var space:RefCounted=host.runtime._services.buildings.current_space()
	var bed_routes:bool=not beds.is_empty()
	for bed:Dictionary in beds:
		var feet:Dictionary=space.standing_point(bed.data.module_bed.approach)
		if feet.is_empty() or not space.route("player",Geometry.location(host.runtime.actor("player")),feet).ok:bed_routes=false
	check("all starting beds have real clear approaches and body routes",bed_routes)
	var ui:Dictionary=host.runtime.snapshot()
	check("runtime projects village phase and all eight linked objectives",ui.get("village",{}).get("available",false) and ui.quests.size()==8 and ui.village.phase=="settle")
	for child:Node in host.scene_root.get_children():
		if child.get_script()==RadioView:
			child._process(.2)
			check("broken radio has a real visible-device mount before unlocking repair",child.statistics().station_id==ui.radio.station_id and child.statistics().panel_registered,child.statistics())
	if DisplayServer.get_name()!="headless":
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"/opening.png")
	check("opening landmarks and expansion spaces survive composition",host.world.extension("r34:gameplay").layout.get("opening_landmarks",{}).size()>=5 and host.world.extension("r34:gameplay").layout.get("expansion_spaces",[]).size()>=2)
	check("unearned radio repair is refused by the actual command gate",not host.runtime.availability({"kind":"radio","actor_id":"player","target_id":ui.get("radio",{}).get("station_id",""),"payload":{"operation":"repair"}}).ok)
	for kind:String in ["drink","eat"]:
		var action:Dictionary=host.runtime.command({"kind":kind,"actor_id":"player","command_id":"village13-life-"+kind})
		check("real opening "+kind+" command starts",action.ok,action)
		host.runtime.set_paused(false)
		for i:int in 18:host.runtime.tick(.1)
		host.runtime.set_paused(true)
	var flags:Dictionary=host.world.extension("r34:gameplay").flags
	check("real completed life events update opening objectives",flags.get("village_drink",false) and flags.get("village_eat",false),flags)
	if args.has("--movement") and DisplayServer.get_name()!="headless":await walk_and_rest(beds)
	var snapshot_before:Dictionary=host.runtime.capture_checkpoint()
	var repeat:Dictionary=host.runtime._services.modules.prepare_generation(host.world)
	check("revisiting cannot replenish opening tools or stocks",repeat.ok and repeat.initial_stocks.is_empty() and repeat.initial_tools.is_empty())
	var saved:Dictionary=await host.save_async("village13-save")
	check("actual native storage saves the complete new village",saved.ok,saved.get("reason"))
	if saved.ok:
		var loaded:Dictionary=host.store.load_current()
		var assembled:Dictionary=host._assemble(loaded.capture) if loaded.ok else loaded
		# The shipping JSON boundary canonicalizes floating-point text. Compare
		# exact persisted facts, without confusing binary float tails with edits.
		var canonical:Dictionary=Store.decode(Store.encode(snapshot_before).text)
		var cold_diff:Array=Client.Runtime.facts_diff(canonical.capture.facts,assembled.runtime.facts()) if assembled.ok and canonical.ok else []
		check("cold assembly preserves every canonical saved village fact",assembled.ok and canonical.ok and Data.json_equal(assembled.runtime.facts(),canonical.capture.facts),{"code":assembled.get("code"),"reason":assembled.get("reason"),"diff":cold_diff})
		if assembled.ok:assembled.runtime.retire()
	if DisplayServer.get_name()!="headless":
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"/after-life.png")
	finish()
func walk_and_rest(beds:Array)->void:
	var chosen:Dictionary={}
	for bed:Dictionary in beds:
		if host.runtime.bed_availability(host.runtime.actor("player"),str(bed.id),{},false).ok:chosen=bed;break
	check("a shared opening bed is unreserved and usable",not chosen.is_empty())
	if chosen.is_empty():return
	var destination:Dictionary=chosen.data.module_bed.approach
	var begin_at:Vector3=Geometry.point(host.runtime.actor("player"))
	var accepted:Dictionary=host.runtime.command({"kind":"walk","actor_id":"player","command_id":"village13-visible-walk","destination":destination})
	check("normal walk command enters the actual sleeping-room approach",accepted.ok,accepted.get("reason"))
	if not accepted.ok:return
	var frames:Array[float]=[];var started:int=Time.get_ticks_usec();var previous:int=started
	preload("res://scripts/runtime/frame_costs.gd").phases.clear()
	host.runtime._authority_costs={"count":0,"failed":0,"total_usec":0,"max_usec":0,"phases":{}}
	host.runtime._simulation_costs.clear()
	host.runtime.set_paused(false)
	while Time.get_ticks_usec()-started<10000000 and host.runtime.actor("player").get("intent")!=null:
		await process_frame
		var now:int=Time.get_ticks_usec();frames.append((now-previous)/1000.0);previous=now
	host.runtime.set_paused(true)
	var end_at:Vector3=Geometry.point(host.runtime.actor("player"));frames.sort()
	movement={"scope":"One visible opening walk to a real bed; no general FPS or long-soak qualification.","frames":frames.size(),"elapsed_ms":(Time.get_ticks_usec()-started)/1000.0,"distance_m":begin_at.distance_to(end_at),"p95_ms":frames[mini(frames.size()-1,floori(frames.size()*.95))] if not frames.is_empty() else 0.0,"max_ms":frames[-1] if not frames.is_empty() else 0.0,"destination":destination}
	movement.phases=preload("res://scripts/runtime/frame_costs.gd").snapshot()
	movement.simulation=host.runtime.simulation_costs()
	movement.authority=host.runtime.authority_costs()
	movement.streaming=host._region_status()
	check("rendered physical walk reaches bed without position injection",end_at.distance_to(Geometry.point(destination))<.2,movement)
	var rested:Dictionary=host.runtime.command({"kind":"rest","actor_id":"player","command_id":"village13-real-bed-rest","target_id":chosen.id})
	check("real bed-rest command starts after physical arrival",rested.ok,rested.get("reason"))
	if rested.ok:
		host.runtime.set_paused(false)
		for step:int in 125:host.runtime.tick(.1)
		host.runtime.set_paused(true)
	var completed:Array=host.runtime.facts().quests.filter(func(q:Dictionary)->bool:return q.id=="V3-Q01" and q.completed)
	check("real food water and original sleeping place finish the first quest",completed.size()==1)
func finish()->void:
	var report:Dictionary={"scope":"Actual content13 fresh NativeClient, mesh/physics readiness, authoritative life actions and native save/cold restore; no claim of full natural production playthrough.","checks":checks,"movement":movement,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":report.failed}))
	if is_instance_valid(host):host.free()
	quit(1 if report.failed else 0)
