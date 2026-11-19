extends "res://tests/modules/run_mechanism_production.gd"
const Housing=preload("res://scripts/modules/module_housing.gd")
func run()->void:
	out=OS.get_cmdline_user_args()[0];var fixture:=flat_base()
	check("declared bounded housing laboratory",fixture.ok)
	if not fixture.ok:return finish()
	for d:Dictionary in Catalog.definitions():
		if not Housing.applies(d):continue
		if OS.get_cmdline_user_args().size()>1 and d.architecture.variant!=OS.get_cmdline_user_args()[1]:continue
		var capture:Dictionary=fixture.capture.duplicate(true);var id:String="B:bed:"+str(d.id)
		var v:=Modules.record_for({"id":id,"definition_id":d.id,"region":"RH-HOME","position":{"x":40,"y":0,"z":40},"quarter_turn":0})
		var a:=Draft.find(capture.facts.actors,"player");a.merge(Shape.ports(v,d)[0].location,true);a.intent=null;a.stamina=100;a.fatigue=0;a.pack={"timber":300,"stone_m3":30,"scrap":100,"cloth":100}
		var hammer:Dictionary={}
		for t:Dictionary in capture.world.extensions["r3:production"].tools:
			if t.kind=="hammer":hammer=t;hammer.holderId="pack:player";hammer.durability=100;break
		var mounted:=mount(capture);check("actual Native housing mount "+str(d.id),mounted.get("ok",false),mounted.get("reason"))
		if not mounted.get("ok",false):continue
		var rt:RefCounted=mounted.runtime;var modules:RefCounted=mounted.services.modules
		var plan:=send(rt,"module.plan",id,{"definition_id":d.id,"position":{"x":40,"y":0,"z":40,"regionId":"RH-HOME"},"quarter_turn":0,"source_id":"pack:player","tool_id":hammer.id})
		var built:bool=plan.ok and advance(rt,modules,float(d.build_seconds)+.1)
		check("full real paid construction "+str(d.id),built and modules.instance(id).status=="operational",plan)
		if not built:rt.retire();continue
		var saved:=Store.encode(rt.capture_checkpoint());FileAccess.open(out+"/"+str(d.architecture.variant)+".native.json",FileAccess.WRITE).store_string(saved.text)
		var projection:Dictionary=modules.housing_projection("player");var h:=Draft.find(projection.homes,id)
		var details:Array=[]
		for br:Dictionary in h.beds:
			var q:RefCounted=mounted.services.buildings.current_space() if mounted.services.has("buildings") else modules.context.spatial.current_space();var feet:Dictionary=q.standing_point(br.approach);var bed:Dictionary=mounted.world.entity(br.bed_id)
			details.append({"id":br.bed_id,"feet":feet,"contact":not feet.is_empty() and preload("res://scripts/buildings/interaction_contact.gd").entity(q,feet,bed),"route":mounted.services.actions.route("player",G.location(rt.actor("player")),br.approach)})
		observations.append({"id":d.id,"diagnostic":details})
		check("actual entities and supported clear reachable beds "+str(d.id),h.bed_count==int(d.mechanism.beds) and h.reachable_bed_count==h.bed_count and h.available_bed_count==h.bed_count,{"design":d.mechanism.beds,"home":h})
		if h.available_bed_count>0:
			var first:Dictionary=h.beds.filter(func(b:Dictionary)->bool:return b.available)[0];var walking:=send(rt,"walk","",{"destination":first.approach})
			# Walk is a Runtime command with top-level destination.
			if not walking.ok:
				sequence+=1;walking=rt.command({"kind":"walk","actor_id":"player","command_id":"B:bedwalk:"+str(sequence),"target_id":"","destination":first.approach,"payload":{}})
			for i:int in 1000:
				rt.tick(.1)
				if rt.actor("player").get("intent")==null:break
			var rest:=send(rt,"rest",str(first.bed_id))
			check("real walk arrival uses same authority bed rest "+str(d.id),walking.ok and rest.ok,{"walk":walking,"rest":rest,"at":G.location(rt.actor("player")),"approach":first.approach,"activity":rt.actor("player").activity})
			if rest.ok:
				var occupied:Dictionary=modules.housing_projection("player");check("occupancy excludes demolition "+str(d.id),Draft.find(occupied.homes,id).beds.any(func(b:Dictionary)->bool:return b.occupied))
				var encoded:=Store.encode(rt.capture_checkpoint());var decoded:=Store.decode(encoded.text) if encoded.ok else encoded;var cold:=mount(decoded.capture) if decoded.get("ok",false) else decoded
				check("cold preserves exact live bed/rest DTO "+str(d.id),cold.get("ok",false) and Data.json_equal(cold.runtime.facts(),decoded.capture.facts) and Data.json_equal(cold.world.snapshot().entities,decoded.capture.world.entities),cold.get("reason"))
				if cold.get("ok",false):cold.runtime.retire()
				send(rt,"cancel_action","")
		observations.append({"definition_id":d.id,"home":h})
		rt.retire()
	finish()
