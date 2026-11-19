extends "res://tests/buildings/family_generation_suite.gd"
## Exact E lifecycle capture, no actor relocation or inventory supplementation.
const Draft=preload("res://scripts/actions/domain_draft.gd")
func run()->void:
	var started:=Time.get_ticks_msec()
	var path:="res://../../work/r3-3-eee/20261114-215641-814383/lifecycle/final-capture.json"
	var raw:=FileAccess.get_file_as_string(path)
	var capture:Variant=JSON.parse_string(raw)
	expect("exact E capture exists",capture is Dictionary)
	if not capture is Dictionary:finish(started);return
	var host:=Client.new();var mounted:Dictionary=host._assemble(capture)
	expect("exact source assembles without reseeding",mounted.ok,mounted.get("reason"))
	if not mounted.ok:host.free();finish(started);return
	world=mounted.world;runtime=mounted.runtime;building=mounted.services.buildings;actions=mounted.services.actions;production=mounted.services.production
	var a:Dictionary=runtime.actor("ordinary:E-lifecycle")
	var stock:Dictionary=runtime.stock(str(a.pending_delivery.destination_id))
	var from:=Geometry.location(a);var points:Array=building.use_points(str(stock.get("structureId","")))
	expect("real cargo remains in NPC pack",a.pack.get("log")==3 and a.pending_delivery.phase=="deliver")
	if points.is_empty():points.append(Geometry.location(stock))
	var rows:Array=[];var any_route:=false
	for point:Dictionary in points:
		var t:=Time.get_ticks_usec();var route:Dictionary=actions.route(str(a.id),from,point)
		rows.append({"from":from,"to":point,"route":route,"ms":float(Time.get_ticks_usec()-t)/1000.0})
		any_route=any_route or route.ok
	expect("actual NPC cargo has a safe home route",any_route,rows)
	var arrived:=false
	if any_route:
		for n in 1800:
			runtime.tick(0.1)
			if float(runtime.stock(stock.id).items.get("log",0))>=3:arrived=true;break
	expect("actual unified clock delivers original cargo",arrived,{"actor":runtime.actor(a.id),"stock":runtime.stock(stock.id)})
	expect("three original logs conserved",float(runtime.actor(a.id).pack.get("log",0))+float(runtime.stock(stock.id).items.get("log",0))+float(runtime.stock(str(a.pending_delivery.source_id)).items.get("log",0))==3)
	print("DELIVERY_ROUTE "+JSON.stringify(rows))
	host.free();finish(started)
