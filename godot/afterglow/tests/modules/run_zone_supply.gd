extends "res://tests/modules/run_mechanism_production.gd"
var live:Dictionary={}
func idle(rt:RefCounted,limit:int=500)->void:
	for i:int in limit:
		rt.tick(.1)
		if rt.actor("player").get("intent")==null:break
func offer(rt:RefCounted,operation:String,supply:bool)->Dictionary:
	var rows:Array=rt.domain_service("zonework").work_candidates("player")
	for c:Dictionary in rows:
		if supply and c.kind=="supply" and c.valid:return c
		if not supply and c.kind=="zonework" and c.operation==operation and c.valid:return c
	return {}
func invoke(rt:RefCounted,c:Dictionary)->Dictionary:
	if c.is_empty():return {"ok":false,"code":"NO_CANDIDATE"}
	return send(rt,str(c.command.kind),str(c.command.target_id),c.command.payload)
func run()->void:
	out=OS.get_cmdline_user_args()[0];var fixture:=flat_base()
	if not fixture.ok:return finish()
	var capture:Dictionary=fixture.capture;var a:=Draft.find(capture.facts.actors,"player");a.merge({"x":40,"y":0,"z":30,"regionId":"RH-HOME","buildingId":null,"storeyId":null},true);a.pack={"food":4,"water":4};a.intent=null;a.stamina=100
	var rack:String="B:supply:finite-rack";var at:Dictionary={"x":38,"y":0,"z":34,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	capture.facts.stocks.append({"id":rack,"location":at,"items":{"r34:potato_seed":1,"r34:raw_water":2},"owner":"home-residents","searched":true})
	capture.world.entities[rack]={"id":rack,"kind":"container","regionId":"RH-HOME","position":{"x":38,"y":0,"z":34},"bounds":{"min":{"x":37.5,"y":0,"z":33.5},"max":{"x":38.5,"y":1.2,"z":34.5}},"revision":0,"data":{"solid":true,"opaque":true,"owner":"home-residents"}}
	capture.world.extensions["r3:production"].tools.append({"id":"B:supply:finite-shovel","kind":"shovel","holderId":rack,"durability":100,"qualities":{"shovel":1}})
	live=mount(capture);check("declared finite solid rack and actual Native mount",live.get("ok",false),live.get("reason"))
	if not live.get("ok",false):return finish()
	var rt:RefCounted=live.runtime;var zone:String="B:supply:farm"
	var created:=send(rt,"zone.create",zone,{"spec":{"kind":"farm","region_id":"RH-HOME","bounds":{"x0":84,"x1":85,"z0":92,"z1":93},"policy":{"crop_id":"potato","target_stock_id":rack}}})
	check("real farm admitted by C ground",created.ok,created)
	var initial_save:=Store.encode(rt.capture_checkpoint())
	if initial_save.ok:FileAccess.open(out+"/actual-finite-before-supply.native.json",FileAccess.WRITE).store_string(initial_save.text)
	var c:=offer(rt,"till",true);check("missing shovel creates exact actionable supply DTO",not c.is_empty() and c.tool_ids==["B:supply:finite-shovel"] and c.items.is_empty(),c)
	if c.is_empty():return finish_live()
	var started:=invoke(rt,c);check("public player command admits original actual supply route",started.ok and rt.actor("player").intent.kind=="zone_supply",started)
	if not started.ok:return finish_live()
	check("no tool teleport before actual walking",rt.tool("B:supply:finite-shovel").holderId==rack and rt.actor("player").intent.steps.size()>0)
	check("original hold reserves the real tool",live.services.production.tool_unavailable("B:supply:finite-shovel"))
	var pause:=send(rt,"held","",{"held":false});var before:Dictionary=rt.capture_checkpoint()
	for i:int in 4:rt.tick(.1)
	check("standard held pauses movement and transfer",pause.ok and Data.json_equal(G.location(rt.actor("player")),G.location(Draft.find(before.facts.actors,"player"))) and rt.tool("B:supply:finite-shovel").holderId==rack)
	var encoded:=Store.encode(rt.capture_checkpoint());var decoded:=Store.decode(encoded.text) if encoded.ok else encoded
	check("paused supply exact JSON encodes",decoded.ok,decoded.get("code"))
	if encoded.ok:FileAccess.open(out+"/actual-finite-paused-supply.native.json",FileAccess.WRITE).store_string(encoded.text)
	if not decoded.ok:return finish_live()
	var cold:=mount(decoded.capture);check("original schema cold restores real route and hold",cold.get("ok",false) and cold.runtime.actor("player").intent.kind=="zone_supply",cold.get("reason"))
	if not cold.get("ok",false):return finish_live()
	rt.retire();live=cold;rt=live.runtime
	var resumed:=send(rt,"held","",{"held":true});idle(rt)
	check("real contact transfers exactly one shovel and releases hold",resumed.ok and rt.actor("player").get("intent")==null and rt.tool("B:supply:finite-shovel").holderId=="pack:player" and not live.services.production.tool_unavailable("B:supply:finite-shovel"),{"activity":rt.actor("player").activity,"tool":rt.tool("B:supply:finite-shovel")})
	var till:=invoke(rt,offer(rt,"till",false));idle(rt)
	check("only after pickup actual arrival and tool labor till field",till.ok and rt.tool("B:supply:finite-shovel").durability<100 and rt.domain_service("ecology").state().plants.size()>0,{"result":till,"actor":rt.actor("player")})
	c=offer(rt,"sow",true);check("missing crop seed uses finite source and real materials",not c.is_empty() and Data.json_equal(c.items,{"r34:potato_seed":1}) and c.tool_ids.is_empty(),c)
	if c.is_empty():return finish_live()
	var pickup:=invoke(rt,c);idle(rt)
	check("actual seed pickup decrements source once",pickup.ok and rt.actor("player").pack.get("r34:potato_seed",0)==1 and rt.stock(rack).items["r34:potato_seed"]==0,{"actor":rt.actor("player"),"stock":rt.stock(rack)})
	var sow:=invoke(rt,offer(rt,"sow",false));idle(rt)
	check("real seed consumes only once at completed sow",sow.ok and rt.actor("player").pack.get("r34:potato_seed",0)==0,sow)
	for i:int in 3010:rt.tick(.1)
	c=offer(rt,"water",true);var stale:=c.duplicate(true)
	check("watering offers finite actual raw water",not c.is_empty() and Data.json_equal(c.items,{"r34:raw_water":1}),c)
	if c.is_empty():return finish_live()
	var delivered_water:=invoke(rt,c);idle(rt)
	var watering:=invoke(rt,offer(rt,"water",false));idle(rt)
	check("real water is taken then consumed by C only at field labor",delivered_water.ok and watering.ok and rt.actor("player").pack.get("r34:raw_water",0)==0 and rt.stock(rack).items["r34:raw_water"]==1)
	for i:int in 3010:rt.tick(.1)
	var harvesting:=invoke(rt,offer(rt,"harvest_crop",false));idle(rt)
	check("real harvest credits only pack before original haul",harvesting.ok and rt.actor("player").pack.get("r34:potato",0)==3 and rt.stock(rack).items.get("r34:potato",0)==0,harvesting)
	var carrying:Dictionary={}
	for row:Dictionary in rt.domain_service("zonework").work_candidates("player"):
		if row.kind=="haul" and row.carrying:carrying=row;break
	check("actual completed field creates original logistics custody",not carrying.is_empty() and carrying.items.get("r34:potato")==3,carrying)
	if carrying.is_empty():return finish_live()
	var custody_save:=Store.encode(rt.capture_checkpoint())
	if custody_save.ok:FileAccess.open(out+"/actual-finite-harvest-custody.native.json",FileAccess.WRITE).store_string(custody_save.text)
	var deliver:=invoke(rt,carrying);idle(rt)
	check("original supported walk and deposit settle true harvest once",deliver.ok and rt.actor("player").pack.get("r34:potato",0)==0 and rt.stock(rack).items.get("r34:potato",0)==3 and rt.stock(rack).items.get("r34:crop_residue",0)==1,{"deliver":deliver,"actor":rt.actor("player"),"stock":rt.stock(rack)})
	var repeat_deliver:=invoke(rt,carrying)
	check("completed haul cannot duplicate food",not repeat_deliver.ok and rt.stock(rack).items.get("r34:potato",0)==3,repeat_deliver)
	var next_sow:=invoke(rt,offer(rt,"sow",false));idle(rt)
	check("retained seed restarts without new supply",next_sow.ok and rt.actor("player").pack.get("r34:potato_seed",0)==0)
	for i:int in 3010:rt.tick(.1)
	c=offer(rt,"water",true);stale=c.duplicate(true)
	var water_pickup:=invoke(rt,c);check("raw water fetch starts without grant",water_pickup.ok and rt.actor("player").pack.get("r34:raw_water",0)==0)
	var cancelled:=send(rt,"cancel_action","");check("cancel releases uncollected material and preserves source",cancelled.ok and rt.actor("player").get("intent")==null and rt.stock(rack).items["r34:raw_water"]==1 and live.services.production.reserved(rack,"r34:raw_water")==0)
	check("second real pickup may begin",invoke(rt,c).ok)
	var changed:=send(rt,"zone.policy",zone,{"patch":{"policy":{"crop_id":"potato","worker_ids":[str(rt.facts().actors[1].id)]}}});rt.tick(.1)
	check("zone revision or worker policy invalidates in-flight supply without consumption",changed.ok and rt.actor("player").get("intent")==null and rt.stock(rack).items["r34:raw_water"]==1)
	var checkpoint:Dictionary=rt.capture_checkpoint();var rejected:=invoke(rt,stale)
	check("stale public DTO atomically rejects and cannot smuggle old supply",not rejected.ok and Data.json_equal(rt.capture_checkpoint(),checkpoint),rejected)
	var save:=Store.encode(rt.capture_checkpoint());if save.ok:FileAccess.open(out+"/actual-finite-zone-supply.native.json",FileAccess.WRITE).store_string(save.text)
	finish_live()
func finish_live()->void:
	if not live.is_empty():live.runtime.retire();live={}
	finish()
