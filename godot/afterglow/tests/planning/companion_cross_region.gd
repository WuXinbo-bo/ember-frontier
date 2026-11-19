extends "res://tests/modules/companion_project_dispatch.gd"
## Uses real generated terrain and an isolated starting position near a border.
const G=preload("res://scripts/buildings/building_geometry.gd")
const Contact=preload("res://scripts/buildings/interaction_contact.gd")
const Zones=preload("res://scripts/planning/zone_service.gd")

func run()->void:
	var profiles:=Assembly.generation_profiles()
	var opening:=Assembly.prepare(Assembly.generate(713,profiles.profiles))
	if not check("prepare",opening.ok,opening.get("code")):return finish()
	var capture:Dictionary=opening.capture
	var host:=Native.new();var built:=host._assemble(capture)
	if not check("open real map",built.ok,built.get("code")):host.free();return finish()
	var query:RefCounted=built.services.buildings.current_space()
	var world:RefCounted=built.world
	var selected:Dictionary={};var start:Dictionary={};var zone_spec:Dictionary={}
	var trees:Array=capture.world.entities.values().filter(func(e:Dictionary)->bool:return e.kind=="tree" and e.get("data",{}).get("harvest",{}).get("phase")=="standing")
	for tree:Dictionary in trees:
		var at:=G.location(tree)
		var origin:Vector3=G.point(at)
		for delta:Vector2 in [Vector2(6,0),Vector2(-6,0),Vector2(0,6),Vector2(0,-6),Vector2(12,0),Vector2(-12,0),Vector2(0,12),Vector2(0,-12)]:
			var candidate:=at.duplicate();candidate.x=origin.x+delta.x;candidate.z=origin.z+delta.y
			var region:Dictionary=world.region_at(candidate)
			if region.is_empty() or region.id==tree.regionId or not built.runtime.region_is_detailed(region.id):continue
			candidate.regionId=region.id
			var feet:Dictionary=query.standing_point(candidate)
			if feet.is_empty():continue
			var cell:=Vector2i(floori(origin.x*2),floori(origin.z*2))
			var spec:Dictionary={"kind":"forestry","region_id":tree.regionId,"bounds":{"x0":cell.x,"x1":cell.x+1,"z0":cell.y,"z1":cell.y+1},"policy":{"worker_ids":[WORKER],"priority":4,"mode":"harvest_only","replant":false}}
			if not built.runtime.zone_preview(spec).get("ok",false):continue
			for contact:Dictionary in Contact.tree_points(query,tree):
				if built.services.actions.route(WORKER,feet,contact).ok:
					selected=tree;start=feet;zone_spec=spec;break
			if not selected.is_empty():break
		if not selected.is_empty():break
	if not check("found standing tree with adjacent supported route",not selected.is_empty(),[trees.size(),world.region_ids()]):built.runtime.retire();host.free();return finish()
	built.runtime.retire()
	var actor:=Draft.find(capture.facts.actors,WORKER);actor.merge(start,true);actor.hunger=90;actor.thirst=90;actor.fatigue=0;actor.relationship.home_arrived=true
	var retrieve:bool=OS.get_cmdline_user_args().has("--retrieve")
	var receiver_id:="r34:generated:RH-HOME:woodwork:stock:input"
	var axe_id:String=""
	for tool:Dictionary in capture.world.extensions["r3:production"].tools:
		if tool.kind=="salvaged_axe":tool.holderId=receiver_id if retrieve else "pack:"+WORKER;axe_id=tool.id;break
	var receiver:=Draft.find(capture.facts.stocks,receiver_id)
	receiver.searched=true
	var original:float=float(receiver.items.get("log",0))
	built=host._assemble(capture)
	if not check("assemble distant-worker fixture",built.ok,built.get("code")):host.free();return finish()
	var rt:RefCounted=built.runtime
	var standing:bool=OS.get_cmdline_user_args().has("--standing")
	if standing:zone_spec.policy[&"standing_order"]=true
	var across:Dictionary=zone_spec.duplicate(true)
	across.region_id=start.regionId
	var sx:int=floori(float(start.x)*2);var sz:int=floori(float(start.z)*2)
	across.bounds={"x0":mini(sx,zone_spec.bounds.x0),"z0":mini(sz,zone_spec.bounds.z0),"x1":maxi(sx+1,zone_spec.bounds.x1),"z1":maxi(sz+1,zone_spec.bounds.z1)}
	var two:Dictionary=rt.zone_preview(across)
	check("one target preview spans both regions and reports trees instead of ground cells",two.get("ok",false) and int(two.get("region_count",0))>=2 and int(two.get("target_count",0))>=1,two)
	var committed:Dictionary=rt.command({"kind":"zone.create","actor_id":"player","target_id":"test:cross-forestry","command_id":"test:cross-forestry","payload":{"spec":zone_spec}})
	check("accepts an order when worker is in another region",committed.ok and rt.actor(WORKER).regionId!=selected.regionId,committed.get("reason"))
	if standing and committed.ok:
		var encoded:=Store.encode(rt.capture_checkpoint())
		var decoded:=Store.decode(encoded.get("text","")) if encoded.ok else encoded
		var saved_zones: Dictionary = decoded.get("capture",{}).get("world",{}).get("extensions",{}).get(Zones.KEY,{})
		var saved_order:=Draft.find(saved_zones.get("zones",[]),"test:cross-forestry")
		check("standing order survives save codec with a valid boolean policy",decoded.ok and Zones.validate_state(saved_zones).ok and saved_order.get("policy",{}).get("standing_order")==true,decoded.get("code"))
	var offers:Array=built.services.zonework.work_candidates(WORKER)
	check("workforce can see a valid remote tree or tool offer",offers.any(func(c:Dictionary)->bool:return c.get("valid",false) and (axe_id in c.get("tool_ids",[]) if retrieve else c.get("operation")=="harvest_tree")),[offers,built.world.extension("r34:zones")])
	if OS.get_cmdline_user_args().has("--cancel"):
		var working:=false
		for i:int in 400:
			rt.tick(.1)
			var intent:Variant=rt.actor(WORKER).intent
			if intent is Dictionary and intent.get("kind")=="harvest":working=true;break
		var cancelled:Dictionary=rt.command({"kind":"zone.cancel","actor_id":"player","target_id":"test:cross-forestry","command_id":"test:cancel-forestry","payload":{}})
		for i:int in 80:rt.tick(.1)
		var intent:Variant=rt.actor(WORKER).intent
		check("cancelling while cutting stops the active task without felling the tree",working and cancelled.ok and not (intent is Dictionary and intent.get("kind")=="harvest") and built.world.entity(selected.id).data.harvest.phase=="standing",[intent,cancelled.get("reason")])
		rt.retire();host.free();return finish()
	var actual_crossing:=false;var cut:=false;var collected:=false
	for i:int in 940 if retrieve else 330:
		rt.tick(.1)
		if retrieve and not collected:collected=Draft.find(built.services.production.state().tools,axe_id).get("holderId")=="pack:"+WORKER
		if rt.actor(WORKER).regionId==selected.regionId:actual_crossing=true
		if built.world.entity(selected.id).get("data",{}).get("harvest",{}).get("phase")!="standing":cut=true;break
	if retrieve:check("worker changes physical tool ownership before cutting",collected,rt.actor(WORKER).activity)
	check("actual actor crosses the boundary and fells chosen tree",actual_crossing and cut,[rt.actor(WORKER).activity,rt.actor(WORKER).get("self_routine",{}).get("last_failure",{}),start,selected.id])
	if cut:
		for i:int in 12:rt.tick(.1)
		var order:Dictionary=rt.zone_projection("player","test:cross-forestry").get("selection",{})
		if standing:
			check("standing order stays active and waits after cutting the last tree",order.get("enabled",false) and not order.get("completed",false) and order.get("remaining_targets")==0,order)
			var empty_order:Dictionary=rt.zone_preview(zone_spec)
			check("an empty standing selection remains valid",empty_order.get("ok",false) and empty_order.get("target_count")==0,empty_order)
		else:
			check("one-shot tree order completes without becoming a permanent forestry job",order.get("completed",false) and not order.get("enabled",true),order)
		var drop_id:String=str(selected.data.outputId)
		var drop:Dictionary=rt.stock(drop_id)
		var spot:=G.location(drop)
		var dx:=floori(float(spot.x)*2);var dz:=floori(float(spot.z)*2)
		var haul:Dictionary={"kind":"stockpile","region_id":spot.regionId,"bounds":{"x0":dx,"x1":dx+1,"z0":dz,"z1":dz+1},"policy":{"mode":"collect_ground","worker_ids":[WORKER],"target_stock_id":receiver_id,"priority":4}}
		var assigned:Dictionary=rt.command({"kind":"zone.create","actor_id":"player","target_id":"test:cross-haul","command_id":"test:cross-haul","payload":{"spec":haul}})
		check("wood on ground can be assigned to a receiver in another region",assigned.ok and drop.items.get("log",0)>0 and G.location(receiver).regionId!=spot.regionId,assigned.get("reason"))
		var carried:=false
		for i:int in 790:
			rt.tick(.1)
			carried=carried or float(rt.actor(WORKER).pack.get("log",0))>0
			if float(rt.stock(receiver_id).items.get("log",0))>original:break
		check("companion physically carries and deposits the real felled logs across regions",carried and float(rt.stock(receiver_id).items.get("log",0))>original,[rt.actor(WORKER).activity,rt.actor(WORKER).get("self_routine",{}).get("last_failure",{}),rt.stock(drop_id).get("items",{})])
	rt.retire();host.free();finish()
