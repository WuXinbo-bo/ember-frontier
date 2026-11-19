extends "res://tests/modules/run_normal_tree_replay.gd"
const Continuous=preload("res://scripts/buildings/continuous_navigation.gd")
func run()->void:
	var path:String=OS.get_cmdline_user_args()[0]
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(path))
	var host:=Native.new();var built:Dictionary=host._assemble(decoded.capture) if decoded.ok else decoded;host.free()
	expect("normal pre-tree Native cold assembly",built.ok,built.get("reason"))
	if not built.ok:return done({})
	var rt:RefCounted=built.runtime;var q:RefCounted=built.services.buildings.current_space()
	var start:Dictionary=Geometry.location(rt.actor("player"));var target:Dictionary=built.services.actions.work_points({"kind":"harvest","target_id":"RH-HOME:home:grove3:3"})[0]
	var nav:=Continuous.new();var plan:Dictionary=nav.plan(q,"player",start,target)
	var failing:Array=[];var successful:Array=[]
	for key:String in nav.edges:
		var split:=key.split(":");var a:Dictionary=nav.nodes[int(split[0])];var b:Dictionary=nav.nodes[int(split[1])]
		var item:Dictionary={"from":a,"to":b,"result":nav.edges[key]}
		if not nav.edges[key].ok:failing.append(item)
		else:successful.append({"from":a,"to":b,"steps":nav.edges[key].steps.size()})
	var probes:Array=[]
	for offset:Vector2 in [Vector2(-0.5,0),Vector2(0.5,0),Vector2(0,-0.5),Vector2(0,0.5),Vector2(0,1.5)]:
		var to:Dictionary=start.duplicate(true);to.x+=offset.x;to.z+=offset.y
		var feet:Dictionary=q.standing_point(to)
		probes.append({"target":to,"feet":feet,"walk":q.walk("player",start,feet) if not feet.is_empty() else {"ok":false}})
	# NativeStore deliberately decodes all chunks cold; Native only warms
	# existing living/route pins. A distant unrequested tree is not such a pin.
	expect("unrequested nonresident target never grants a cold route",not built.world.region_is_resident("RH-HOME") and not plan.ok,{"resident":built.world.region_residency_state("RH-HOME"),"plan":plan})
	var before:Dictionary=rt.facts();var warming:Array=[]
	while not built.world.region_is_resident("RH-HOME"):
		var warm:Dictionary=built.world.prepare_region_residency("RH-HOME",true,built.world.get_revision(),32)
		if not warm.ok or warm.world_changes.is_empty():expect("real target warm conversion prepares",false,warm);break
		var committed:Dictionary=rt._commit(warm)
		warming.append({"ok":committed.ok,"changes":warm.world_changes.size()})
		if not committed.ok:expect("real target warm conversion commits through safety",false,committed);break
	var after:Dictionary=built.services.actions.route("player",start,target)
	expect("same genuine long route becomes available only after real target warm",after.ok and built.world.region_is_resident("RH-HOME"),after)
	expect("warming never moves people grants goods or advances time",before==rt.facts())
	done({"checkpoint":path,"actor":rt.actor("player"),"target":target,"cold_plan":plan,"warm_plan":after,"warm_batches":warming,"failing_edges":failing,"accepted_edges":successful,"local_probes":probes})
