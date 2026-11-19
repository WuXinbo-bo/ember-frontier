extends "res://tests/modules/companion_project_dispatch.gd"
## Normal menu composition, with no supply or position fixtures.
const Opening=preload("res://scripts/runtime/playtest_profile.gd")
const Seeder=preload("res://scripts/buildings/building_geometry.gd")
const BUILDER="repair-resident"

func run()->void:
	var seed:int=713
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):seed=int(arg.trim_prefix("--seed="))
	var profiles:=Assembly.generation_profiles()
	var prepared:=Assembly.prepare(Assembly.generate(seed,profiles.profiles))
	if not check("generate current content",prepared.ok,prepared.get("code")):return finish()
	var capture:=Opening.prepare_opening(prepared.capture,"normal")
	if not check("compose ordinary opening",capture.has("world"),capture.get("reason")):return finish()
	var production:Dictionary=capture.world.extensions["r3:production"]
	var transfer_count:int=0
	for tool:Dictionary in production.tools:
		if tool.holderId in ["pack:player","pack:"+WORKER,"pack:"+BUILDER]:transfer_count+=1
	check("four finite starting work tools",transfer_count==4,capture.source.opening_configuration)
	check("opening receipt is idempotent",Opening.prepare_opening(capture,"normal")==capture)
	var host:=Native.new()
	var built:=host._assemble(capture)
	if not check("mount ordinary opening",built.ok,built.get("reason")):host.free();return finish()
	var runtime:RefCounted=built.runtime
	var home:Dictionary={}
	for module:Dictionary in capture.world.extensions["r34:modules"].instances:
		if module.get("restoration",{}).has("cost") and module.id.ends_with(":home"):
			home=module
			break
	if not check("find original damaged home",not home.is_empty()):runtime.retire();host.free();return finish()
	var spec:=forest_order(runtime,capture)
	if not check("nearby standing tree can be assigned",not spec.is_empty()):runtime.retire();host.free();return finish()
	var forestry:Dictionary=runtime.command({"kind":"zone.create","actor_id":"player","target_id":"natural:forest","command_id":"natural:forest","payload":{"spec":spec}})
	var restore:Dictionary=runtime.command({"kind":"workforce.assign","actor_id":BUILDER,"target_id":"","command_id":"natural:restore","payload":{"candidate_id":"building-order:"+str(home.id)}})
	check("both normal commands are accepted",forestry.ok and restore.ok,[forestry,restore])
	var repaired:Dictionary={}
	for step:int in 1300:
		runtime.tick(.1)
		if step%25!=0:continue
		repaired=built.services.modules.instance(home.id)
		if repaired.status=="operational":break
		if step%250==0:
			print("T=",runtime.clock()," ",[runtime.actor(WORKER).activity,runtime.actor(BUILDER).activity]," ",built.world.extension("r34:workforce").assignments)
	var flags:Dictionary=built.world.extension("r34:gameplay").flags
	var facts:Array=built.world.extension("r3:production").facts
	var sawn:=facts.filter(func(f:Dictionary)->bool:return f.kind=="crafted" and f.actorId==BUILDER and f.targetId=="r34:saw_timber_v2")
	check("forestry order fell a real tree",facts.any(func(f:Dictionary)->bool:return f.kind=="tree-felled" and f.actorId==WORKER),facts)
	check("forestry order delivered a real load",flags.get("village_companion_delivery",false),flags)
	check("repair order paid for exactly the required two board batches",sawn.size()==2,sawn)
	check("original home restored",repaired.get("status")=="operational" and repaired.get("restoration",{}).get("completed",false),[runtime.actor(BUILDER),built.world.extension("r34:workforce").assignments])
	check("chapter credits the same companion actions",flags.get("village_hand_sawn",false) and flags.get("village_home_restored",false),flags)
	var encoded:Dictionary=Store.encode(runtime.capture_checkpoint())
	var decoded:Dictionary=Store.decode(encoded.get("text",""))
	check("ordinary world saves",encoded.ok and decoded.ok,decoded.get("reason"))
	runtime.retire()
	if decoded.ok:
		var restored:=host._assemble(decoded.capture)
		check("ordinary world cold mounts with cooperative rules",restored.ok,restored.get("reason"))
		if restored.ok:restored.runtime.retire()
	host.free()
	finish()

func forest_order(runtime:RefCounted,capture:Dictionary)->Dictionary:
	var at:=Seeder.point(Seeder.location(runtime.actor(WORKER)))
	var nearby:Array=capture.world.entities.values().filter(func(entity:Dictionary)->bool:
		return entity.kind=="tree" and entity.regionId=="RH-HOME" and entity.get("data",{}).get("harvest",{}).get("phase")=="standing")
	nearby.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		return at.distance_squared_to(Seeder.point(a.position))<at.distance_squared_to(Seeder.point(b.position)))
	var query:RefCounted=runtime.domain_service("buildings").current_space()
	var contact=preload("res://scripts/buildings/interaction_contact.gd")
	for tree:Dictionary in nearby:
		var point:=Seeder.point(tree.position)
		var cell:=Vector2i(floori(point.x*2),floori(point.z*2))
		var spec:Dictionary={"kind":"forestry","region_id":tree.regionId,"bounds":{"x0":cell.x-2,"x1":cell.x+3,"z0":cell.y-2,"z1":cell.y+3},"policy":{"worker_ids":[WORKER],"priority":4,"mode":"harvest_only","replant":false}}
		if not runtime.zone_preview(spec).get("ok",false):continue
		for foot:Dictionary in contact.tree_points(query,tree):
			if runtime.domain_service("actions").route(WORKER,Seeder.location(runtime.actor(WORKER)),foot).ok:return spec
	return {}
