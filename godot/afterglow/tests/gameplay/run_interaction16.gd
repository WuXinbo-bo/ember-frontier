extends SceneTree
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Profile=preload("res://scripts/runtime/playtest_profile.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Entities=preload("res://scripts/ecology/ecology_entities.gd")
const Restoration=preload("res://scripts/modules/module_restoration.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
var output:String
var runtime:RefCounted
var sequence:int=0
var timings:Array=[]
const WAREHOUSE="r34:generated:RH-HOME:village-warehouse"
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func command(kind:String,target:String="",payload:Dictionary={})->Dictionary:
	sequence+=1
	return runtime.command({"command_id":"interaction16:"+str(sequence),"kind":kind,"target_id":target,"actor_id":"player","payload":payload})
func mount(capture:Dictionary)->Dictionary:
	var host:=Native.new();var built:Dictionary=host._assemble(capture);host.free();return built
func cold(label:String)->bool:
	var capture:Dictionary=runtime.capture_checkpoint()
	var encoded:Dictionary=Store.encode(capture)
	if not encoded.get("ok",false):check(label+" encodes",false,encoded);return false
	var wire:String=encoded.text
	var decoded:Dictionary=Store.decode(wire)
	check(label+" checksummed native encode/decode",decoded.get("ok",false),decoded.get("reason"))
	if not decoded.get("ok",false):return false
	var built:=mount(decoded.capture)
	check(label+" cold mounts original domains and reservations",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return false
	runtime.retire();runtime=built.runtime;return true
func project()->Dictionary:
	var module:Dictionary=runtime._services.modules.instance(WAREHOUSE)
	return runtime.world.extension("r34:modules").projects.filter(func(p:Dictionary)->bool:return p.id==module.project_id)[0]
func row()->Dictionary:return runtime._services.modules.projection("player",WAREHOUSE).instances[0]
func tick_until_work()->bool:
	for step:int in 600:
		var old:=G.point(G.location(runtime.actor("player")))
		runtime.tick(.1)
		var moved:float=old.distance_to(G.point(G.location(runtime.actor("player"))));timings.append(moved)
		if moved>1:check("ordinary path never teleports a player",false,moved);return false
		if float(project().progress_seconds)>.09:return true
		if runtime.actor("player").get("intent")==null:check("route keeps its original worker claim",false,runtime.actor("player").activity);return false
	return false
func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json"))
	var expected:Dictionary={"salvaged_axe":"斧头","hand_saw":"锯子","hammer":"锤子","shovel":"铲子","pickaxe":"镐子"}
	check("all five tool display names are concise with separate descriptions",expected.keys().all(func(id:String)->bool:return catalog.tool_definitions[id].name==expected[id] and not catalog.tool_definitions[id].description.is_empty()))
	var profiles:Dictionary=Assembly.generation_profiles()
	var generated:Dictionary=Assembly.generate(713,profiles.profiles)
	var prepared:Dictionary=Assembly.prepare(generated)
	check("default16 source assembles normally",prepared.get("ok",false),prepared.get("reason"))
	if not prepared.get("ok",false):return finish()
	var configured:Dictionary=Profile.prepare_opening(prepared.capture,"normal")
	var generation:Dictionary=configured.world.extensions["generation:factory-r34"]
	check("new16 pins real harvest and opening configuration policies",generation.content_version==16 and generation.harvest_policy=="half-duration-v16" and configured.source.opening_configuration.id=="village-opening-v16")
	var before_tools:int=configured.world.extensions["r3:production"].tools.size()
	check("normal16 transfers a real original axe without fabricating tools",configured.world.extensions["r3:production"].tools.size()==before_tools and configured.world.extensions["r3:production"].tools.filter(func(t:Dictionary)->bool:return t.holderId=="pack:player").size()==1)
	var next:Dictionary=Profile.prepare_opening(configured,"normal")
	check("recorded16 configuration remains idempotent",Data.json_equal(configured,next))
	var testing:Dictionary=Profile.prepare_opening(prepared.capture,"playtest")
	check("explicit16 testing profile moves five registered tools and records16 provenance",testing.source.playtest.id=="ready-to-test-v16" and testing.source.opening_configuration.id=="village-opening-v16" and testing.world.extensions["r3:production"].tools.size()==before_tools and testing.world.extensions["r3:production"].tools.filter(func(t:Dictionary)->bool:return t.holderId=="pack:player").size()==5)
	var trees:Array=generated.entities.values().filter(func(e:Dictionary)->bool:return e.kind=="tree")
	check("new16 generated trees use 3/5/7 second profiles with original per-tree yield and wear",not trees.is_empty() and trees.all(func(t:Dictionary)->bool:return t.data.harvest.seconds in [3.0,5.0,7.0] and t.data.harvest.yield=={"log":3} and t.data.harvest.toolWear==(3.0 if t.data.harvest.size=="small" else 6.0)))
	var old_profiles:Dictionary=Assembly.generation_profiles(15)
	var old_generated:Dictionary=Assembly.generate(713,old_profiles.profiles,15)
	check("old15 generation keeps original 6/10/14 durations",old_generated.entities.values().filter(func(e:Dictionary)->bool:return e.kind=="tree").all(func(t:Dictionary)->bool:return t.data.harvest.seconds in [6.0,10.0,14.0]))
	var plant:Dictionary={"id":"tree:test","location":{"x":0,"y":0,"z":0},"region_id":"RH-HOME","stage":"mature","output_id":"tree:test:drop","tree_id":"broadleaf"}
	check("same grown tree stays 24 seconds in old15 and becomes12 only in16",Entities.tree(plant,15).data.harvest.seconds==24 and Entities.tree(plant,16).data.harvest.seconds==12 and Entities.tree(plant,15).data.harvest.toolWear==Entities.tree(plant,16).data.harvest.toolWear)
	var fresh:=mount(configured)
	check("default16 validates through complete Native assembly",fresh.get("ok",false),fresh.get("reason"))
	if not fresh.get("ok",false):return finish()
	runtime=fresh.runtime
	var missing:Dictionary=runtime.availability({"kind":"module.restore","target_id":WAREHOUSE,"actor_id":"player","payload":{}})
	check("normal fresh restore reports exact missing materials before taking a tool",not missing.ok and missing.get("code")=="MODULE_MATERIALS" and not missing.get("missing",[]).is_empty(),missing)
	runtime.retire();runtime=null
	if args.size()<2:check("real natural finite supply capture supplied",false);return finish()
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]))
	check("natural input uses original checksum codec",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish()
	var built:=mount(decoded.capture)
	check("original unfunded supply15 journey cold restores unchanged",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	runtime=built.runtime
	var pack_before:Dictionary=runtime.actor("player").pack.duplicate(true)
	var row_before:=row()
	check("authority supplies true material counts and available carried hammer",row_before.restoration_action.available and row_before.restoration_action.tool.available and row_before.restoration_action.materials.all(func(m:Dictionary)->bool:return m.missing==0))
	var wrong:Dictionary=runtime.availability({"kind":"module.restore","target_id":WAREHOUSE,"actor_id":"player","payload":{"tool_id":"r34:generated:RH-HOME:woodwork:tool:salvaged_axe"}})
	check("explicit axe cannot masquerade as restoration hammer",not wrong.ok and wrong.code=="MODULE_TOOL_REQUIRED",wrong)
	check("failed availability cannot spend physical materials",runtime.actor("player").pack==pack_before)
	FileAccess.open(output+"/actual-ready-to-restore.native.json",FileAccess.WRITE).store_string(Store.encode(runtime.capture_checkpoint()).text)
	var start:Dictionary=command("module.restore",WAREHOUSE)
	check("one empty-payload restore command admits a real route",start.ok,start)
	if not start.ok:return finish()
	var pid:String=project().id
	var wear:float=float(runtime.tool(str(project().tool_id)).durability)
	check("route starts as existing actions module_approach with zero labor and no material charge",runtime.actor("player").intent.kind=="module_approach" and project().progress_seconds==0 and runtime.actor("player").pack==pack_before)
	check("construction DTO exposes actual approaching phase worker and footprint",row().visuals.construction.phase=="approaching" and row().visuals.construction.actor_id=="player" and row().visuals.construction.has("footprint"))
	check("HUD action projection identifies actual restore approach",runtime._services.actions.actor_work_projection("player").operation=="restore" and runtime._services.actions.actor_work_projection("player").module_id==WAREHOUSE)
	if not cold("during approach"):return finish()
	var held:Dictionary=command("module.held",WAREHOUSE,{"held":false})
	var still:Dictionary=G.location(runtime.actor("player"))
	for i:int in 5:runtime.tick(.1)
	check("pausing approach preserves location inputs and project identity",held.ok and G.location(runtime.actor("player"))==still and project().id==pid and project().progress_seconds==0 and runtime.actor("player").pack==pack_before)
	var cancelled:Dictionary=command("module.cancel",WAREHOUSE)
	check("cancelling approach releases its worker with no material or tool charge",cancelled.ok and runtime.actor("player").intent==null and project().status=="cancelled" and runtime.actor("player").pack==pack_before and runtime.tool(str(project().tool_id)).durability==wear)
	if not cold("after cancelling approach"):return finish()
	var restarted:Dictionary=command("module.restore",WAREHOUSE)
	check("cancelled unpaid restoration can be requested again",restarted.ok,restarted)
	if not restarted.ok:return finish()
	check("actual route arrives and starts real labor",tick_until_work(),runtime.actor("player").activity)
	if float(project().progress_seconds)<=0:return finish()
	var progress_before:float=float(project().progress_seconds);pid=project().id
	var paused:Dictionary=command("module.held",WAREHOUSE,{"held":false})
	for i:int in 5:runtime.tick(.1)
	check("held labor pauses without losing actual paid-work progress",paused.ok and project().progress_seconds==progress_before and row().visuals.construction.phase=="paused")
	if not cold("during held actual labor"):return finish()
	check("cold held restoration retains same ledger and amount",project().id==pid and project().progress_seconds==progress_before and not runtime.actor("player").intent.held)
	var resumed:Dictionary=command("module.held",WAREHOUSE,{"held":true})
	check("existing held command resumes actual labor",resumed.ok,resumed)
	for i:int in 500:
		runtime.tick(.1)
		if project().status=="completed":break
	check("real 24-second restoration reaches original completed state",project().status=="completed" and is_equal_approx(float(project().progress_seconds),24),project())
	check("original finite pack pays exactly one warehouse repair cost",runtime.actor("player").pack.get("timber",0)==pack_before.get("timber",0)-8 and runtime.actor("player").pack.get("scrap",0)==pack_before.get("scrap",0)-2 and runtime.actor("player").pack.get("cloth",0)==pack_before.get("cloth",0)-1)
	check("hammer wear remains 0.15 per actual labor second",is_equal_approx(float(runtime.tool(str(project().tool_id)).durability),wear-24*.15))
	check("completed transition DTO has genuine completed phase",row().visuals.construction.phase=="completed" and not row().visuals.construction.active)
	if not cold("after paid restoration"):return finish()
	var repeated:Dictionary=command("module.restore",WAREHOUSE)
	check("already-restored warehouse rejects duplicate settlement",not repeated.ok and repeated.get("code")=="MODULE_NOT_RESTORABLE",repeated)
	FileAccess.open(output+"/actual-restored-warehouse.native.json",FileAccess.WRITE).store_string(Store.encode(runtime.capture_checkpoint()).text)
	finish()
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"suite":"interaction16","checks":checks,"failed":failed,"scope":"New16/default generation plus actual unfunded15 supply capture; no inventory/actor/time/permission injection. One-click original restore command, authoritative route, held/cancel/cold and one original material settlement. Headless, not GUI/FPS.","movement_steps":timings},"\t",true,true))
	if runtime!=null:runtime.retire()
	print(JSON.stringify({"suite":"interaction16","checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
