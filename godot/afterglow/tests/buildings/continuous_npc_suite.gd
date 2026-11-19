extends "res://tests/buildings/family_generation_suite.gd"
## Production geometry/cells, explicit initial NPC stance, no exits metadata.
func run()->void:
	var started:=Time.get_ticks_msec()
	var capture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../work/r3-3-eee/20261114-215641-814383/lifecycle/final-capture.json"))
	# Controlled management-metadata fixture: actual regions/chunks/buildings
	# are unchanged. No authored portal can be used to make this test pass.
	for region:Dictionary in capture.world.regions.values():region.exits=[]
	var host:=Client.new();var assembly:Dictionary=host._assemble(capture)
	expect("actual captured world assembles without portal metadata",assembly.ok,assembly.get("reason"))
	if not assembly.ok:host.free();finish(started);return
	world=assembly.world;runtime=assembly.runtime;building=assembly.services.buildings;actions=assembly.services.actions;production=assembly.services.production
	var id:="ordinary:E-lifecycle";var query:RefCounted=building.current_space()
	var home:Dictionary=building.use_points("RH-HOME:home:storage")[0]
	var goal:Dictionary=world.extension("generation:RH-VILLAGE").anchors.arrival.duplicate(true)
	goal.regionId="RH-VILLAGE";goal.buildingId=null;goal.storeyId=null
	goal=query.standing_point(goal)
	var observed:=runtime.facts()
	for a:Dictionary in observed.actors:
		if a.id==id:
			a.merge(home,true);a.intent=null;a.job="rest";a.erase("pending_delivery");a.erase("suspended_work")
	expect("explicit indoor NPC stance configured on real floor",not home.is_empty() and not goal.is_empty() and runtime.configure({"world":world,"facts":observed,"services":assembly.services}).ok)
	var t:=Time.get_ticks_usec();var route:Dictionary=actions.route(id,home,goal)
	expect("indoor through real door and continuous boundary plan",route.ok,{"reason":route.get("reason"),"ms":float(Time.get_ticks_usec()-t)/1000,"steps":route.get("steps",[]).size()})
	if route.ok:
		var started_walk:Dictionary=runtime.command({"command_id":"fixture:npc-continuous","actor_id":id,"kind":"walk","destination":goal,"payload":{},"expected_revision":runtime.get_revision()})
		expect("real NPC command accepts same route",started_walk.ok,started_walk)
		var crossed:=false;var arrived:=false;var broken:=false
		for n in 1200:
			runtime.tick(0.1)
			var a:Dictionary=runtime.actor(id)
			crossed=crossed or a.regionId==goal.regionId
			if Geometry.point(Geometry.location(a)).distance_to(Geometry.point(goal))<0.1:arrived=true;break
			if a.get("intent")==null and n>30:broken=true;break
		expect("NPC actually walks across management boundary without teleport",crossed and arrived and not broken,{"actor":runtime.actor(id),"goal":goal})
		var encoded:=Store.encode(runtime.capture_checkpoint());var decoded:=Store.decode(encoded.get("text",""))
		var restored:Dictionary=host._assemble(decoded.capture) if encoded.ok and decoded.ok else {"ok":false}
		expect("crossed NPC native checkpoint restores same position",restored.ok and Geometry.point(Geometry.location(restored.runtime.actor(id))).distance_to(Geometry.point(Geometry.location(runtime.actor(id))))<0.00001)
	host.free();finish(started)
