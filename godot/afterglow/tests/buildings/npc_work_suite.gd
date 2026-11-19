extends "res://tests/buildings/domain_suite.gd"
## End-to-end domain work, real runtime clock and C cells; headless, no preview.
func run() -> void:
	var started:=Time.get_ticks_msec()
	expect("C rural world load",world.load_snapshot(Generator.generate(713)).ok)
	initialize_at({"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	var seeded:Dictionary=building.seed_rural(world)
	var seeded_draft:Dictionary=world.prepare_changes(seeded.world_changes,world.get_revision())
	expect("real rural structures seed",seeded_draft.ok and world.commit_prepared(seeded_draft.capability).ok)
	var tree:Dictionary=world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.kind=="tree")[0]
	var at:=Geometry.location(tree);at.z+=1.2
	var friend:=resident("friend",at);friend.job="rest";friend.home={"x":22,"y":0,"z":43,"regionId":"RH-HOME"}
	var near:=at.duplicate(true);near.x+=0.8
	initialize_at(near,[friend],seeded.initial_stocks)
	var p:Dictionary=Production.empty_state();p.tools=seeded.initial_tools;p.records=seeded.initial_records
	for t in p.tools:t.holderId="pack:player"
	var pd:Dictionary=world.prepare_changes([building.extension_change(Production.KEY,p)],world.get_revision())
	expect("isolated tool fixture uses single live production table",pd.ok and world.commit_prepared(pd.capability).ok)
	var axe:=str(p.tools.filter(func(t:Dictionary)->bool:return t.kind=="salvaged_axe")[0].id)
	var saw:=str(p.tools.filter(func(t:Dictionary)->bool:return t.kind=="hand_saw")[0].id)
	var hammer:=str(p.tools.filter(func(t:Dictionary)->bool:return t.kind=="hammer")[0].id)
	expect("unjoined personal pack cannot receive tools by authority bypass",not command("deposit","pack:friend",{"tool_ids":[axe]}).ok)
	var f:=runtime.facts();f.actors[0].pack={"food":1}
	expect("same runtime accepts fixture setup",runtime.configure({"world":world,"services":{"buildings":building,"actions":actions,"production":production},"facts":f}).ok)
	expect("real aid transfers finite food",command("help","friend",{"items":{"food":1}}).ok)
	expect("actual invitation grants member consent",command("invite","friend").ok and runtime.actor("friend").relationship.consent)
	expect("actual tool handoff to consenting nearby NPC",command("deposit","pack:friend",{"tool_ids":[axe,saw,hammer]}).ok)
	var source_id:=str(tree.data.outputId)
	var home_id:="rural:v1:RH-HOME:old-house:storage"
	var baseline:=float(runtime.tool(axe).durability)
	expect("actual A job assigns exact tree and delivery",command("job","friend",{"job":"gather","work_target_id":tree.id,"work_payload":{"delivery_id":home_id}}).ok)
	var completed:=false
	for i in range(360):
		runtime.tick(0.1)
		if production.state().orders.any(func(o:Dictionary)->bool:return o.actorId=="friend" and o.kind=="harvest" and o.status=="completed"):completed=true;break
	expect("NPC arrives and actually completes 24s harvest",completed,{"activity":runtime.actor("friend").activity,"intent":runtime.actor("friend").get("intent")})
	expect("real logs begin on ground not camp",float(runtime.stock(source_id).items.get("log",0))==3 and float(runtime.stock(home_id).items.get("log",0))==0)
	expect("only chopping tool wears, other carried tools unchanged",is_equal_approx(runtime.tool(axe).durability,baseline-6) and runtime.tool(saw).durability==100 and runtime.tool(hammer).durability==100)
	var captured:Dictionary={}
	var arrived:=false
	for i in range(1800):
		runtime.tick(0.1)
		var actor:Dictionary=runtime.actor("friend")
		if captured.is_empty() and actor.get("pending_delivery",{}).get("phase")=="deliver":
			captured=runtime.capture_checkpoint()
			expect("pickup is real ground to NPC pack transfer",float(runtime.stock(source_id).items.get("log",0))==0 and float(actor.pack.get("log",0))==3)
			var loaded:Dictionary=world.load_snapshot(captured.world)
			expect("pending delivery checkpoint restores same facts",loaded.ok and runtime.configure({"world":world,"services":{"buildings":building,"actions":actions,"production":production},"facts":captured.facts}).ok)
		if float(runtime.stock(home_id).items.get("log",0))==3:arrived=true;break
	expect("NPC hauls actual carried logs to home stock",arrived,{"location":Geometry.location(runtime.actor("friend")),"activity":runtime.actor("friend").activity,"delivery":runtime.actor("friend").get("pending_delivery"),"intent":runtime.actor("friend").get("intent")})
	expect("delivery conserved exactly 3 logs",float(runtime.stock(source_id).items.get("log",0))+float(runtime.actor("friend").pack.get("log",0))+float(runtime.stock(home_id).items.get("log",0))==3)
	expect("delivery does not duplicate when work target already stump",not runtime.actor("friend").has("pending_delivery"))
	var final:Dictionary=building.validate_snapshot(world,runtime.facts())
	expect("all final domain references valid",final.ok,final)
	finish(started)
