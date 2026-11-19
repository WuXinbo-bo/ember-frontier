extends "res://tests/buildings/domain_suite.gd"
## Actual C tree/drop, original body/navigation and one owned finite axe.
const Interaction=preload("res://scripts/buildings/interaction_contact.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Data=preload("res://scripts/world/world_data.gd")
var evidence:Array=[]
func run()->void:
	var started:=Time.get_ticks_msec()
	for seed:int in [713,2026]:
		expect("actual C finite tree world "+str(seed),world.load_snapshot(Generator.generate(seed)).ok)
		var trees:Array=world.entities("RH-HOME").filter(func(e:Dictionary)->bool:return e.kind=="tree")
		expect("C real trees exist "+str(seed),not trees.is_empty())
		if trees.is_empty():continue
		initialize_at(Geometry.location(trees[0]),[],Generator.empty_resource_stocks(world))
		var checked:=0;var near_count:=0;var valid:=true
		for tree:Dictionary in trees:
			var points:Array=actions.work_points({"kind":"harvest","target_id":tree.id})
			var box:=Geometry.aabb(tree.bounds)
			for p:Dictionary in points:
				var foot:=Geometry.point(p);var surface:=foot.max(box.position).min(box.end);surface.y=foot.y
				var distance:float=foot.distance_to(surface)
				valid=valid and not building.current_space().standing_point(p).is_empty() and Interaction.entity(building.current_space(),p,tree) and Interaction.entity(building.current_space(),p,world.entity(tree.data.outputId))
				if absf(distance-0.30)<0.001:near_count+=1
			checked+=1
		expect("all close and legacy hints retain actual body support and occlusion "+str(seed),checked>0 and near_count>=4 and valid,{"trees":checked,"near_hints":near_count})
		var tree:Dictionary=trees[0];var at:Dictionary=Geometry.location(tree);at.z+=3.2
		initialize_at(at,[],Generator.empty_resource_stocks(world))
		var state:=Production.empty_state();state.tools=[{"id":"B:finite:axe","kind":"salvaged_axe","holderId":"pack:player","durability":100.0}]
		var change:Dictionary=world.prepare_changes([building.extension_change(Production.KEY,state)],world.get_revision())
		expect("finite owned axe registers in original production "+str(seed),change.ok and world.commit_prepared(change.capability).ok)
		var before:Dictionary=runtime.capture_checkpoint();var points:Array=actions.work_points({"kind":"harvest","target_id":tree.id})
		expect("derived hints never modify facts world or tool range "+str(seed),Data.json_equal(before,runtime.capture_checkpoint()))
		# Explicit solid-but-transparent pane: sight remains clear while body
		# and tool contact must not pass through it. Remove the same entity
		# before the real travel/harvest route, without replacing the world.
		var tree_origin:=Geometry.point(tree.position)
		var pane_box:=AABB(tree_origin+Vector3(-0.30,0,0.55),Vector3(0.60,1.8,0.20))
		var pane:Dictionary={"id":"B:tree:transparent-pane","kind":"prop","regionId":tree.regionId,"position":Geometry.json_point(pane_box.position),"bounds":Geometry.json_box(pane_box),"revision":0,"blocksTerrain":false,"supportBounds":[],"data":{"solid":true,"opaque":false,"owner":null}}
		var pane_change:Dictionary=world.prepare_changes([{"op":"entity.put","id":pane.id,"before_exists":false,"before":null,"after":pane}],world.get_revision())
		expect("local transparent-solid counterexample commits "+str(seed),pane_change.ok and world.commit_prepared(pane_change.capability).ok)
		var filtered:Array=actions.work_points({"kind":"harvest","target_id":tree.id});var query:RefCounted=building.current_space()
		var south:Dictionary=Geometry.location(tree);south.z+=1.2
		expect("transparent solid never grants body or tool access through near or old hint "+str(seed),not filtered.any(func(p:Dictionary)->bool:return absf(float(p.x)-tree_origin.x)<0.01 and float(p.z)>tree_origin.z+0.5) and query.line_clear(south,Geometry.location(tree),tree.id) and not query.contact_clear(south,Geometry.location(tree),tree.id))
		pane_change=world.prepare_changes([{"op":"entity.remove","id":pane.id,"before_exists":true,"before":world.entity(pane.id),"after":null}],world.get_revision())
		expect("removing actual pane invalidates and restores legal near hints "+str(seed),pane_change.ok and world.commit_prepared(pane_change.capability).ok and actions.work_points({"kind":"harvest","target_id":tree.id}).size()==points.size())
		var request:Dictionary={"tree_id":tree.id,"output_id":tree.data.outputId,"tool_ids":["B:finite:axe"],"held":true,"direct":false}
		var result:Dictionary=command("harvest",tree.id,request)
		expect("far harvest uses original approach executor "+str(seed),result.ok and runtime.actor("player").intent.get("kind")=="approach",result)
		if not result.ok:continue
		var walked:=false;var arrived:=false
		for i:int in 70:
			var actor:Dictionary=runtime.actor("player")
			if actor.intent is Dictionary and actor.intent.kind=="approach":walked=true
			if actor.intent is Dictionary and actor.intent.kind=="harvest":arrived=true;break
			runtime.tick(0.1)
		var actual:=Geometry.point(runtime.actor("player"));var box:=Geometry.aabb(tree.bounds);var face:Vector3=actual.max(box.position).min(box.end);face.y=actual.y
		var nearest:=INF
		for p:Dictionary in points:nearest=minf(nearest,actual.distance_to(Geometry.point(p)))
		expect("real route reaches physical near trunk hint without body snap "+str(seed),walked and arrived and nearest<0.08 and actual.distance_to(face)>=0.26 and actual.distance_to(face)<=0.38,{"actual":Geometry.location(runtime.actor("player")),"surface_gap":actual.distance_to(face),"hint_remaining":nearest})
		if not arrived:continue
		for i:int in 8:runtime.tick(0.1)
		var elapsed:float=production.state().orders[-1].elapsed
		expect("same actual tree order advances on site "+str(seed),elapsed>0 and production.actor_work_projection("player").effective_work)
		expect("release keeps same order "+str(seed),command("held","",{"held":false}).ok)
		for i:int in 8:runtime.tick(0.1)
		expect("release preserves work and no remote product "+str(seed),production.state().orders[-1].elapsed==elapsed and runtime.stock(tree.data.outputId).items.is_empty())
		var host:=Native.new();var restored:Dictionary=host._assemble(runtime.capture_checkpoint())
		expect("same tree progress and near-body pose cold restore "+str(seed),restored.ok,restored.get("reason"))
		if restored.ok:
			var rt:RefCounted=restored.runtime;var pr:RefCounted=restored.services.production
			var held:Dictionary=rt.command({"kind":"held","command_id":"B:tree:resume","actor_id":"player","target_id":"","payload":{"held":true}})
			for i:int in 260:
				rt.tick(0.1)
				if restored.world.entity(tree.id).data.harvest.phase=="stump":break
			expect("resumed same labor fells into one actual ground stock "+str(seed),held.ok and restored.world.entity(tree.id).data.harvest.phase=="stump" and rt.stock(tree.data.outputId).items.get("log")==3 and rt.actor("player").pack.get("log",0)==0)
			expect("same original axe wears exactly once "+str(seed),is_equal_approx(float(rt.tool("B:finite:axe").durability),94.0))
			var duplicate:Dictionary=rt.command({"kind":"harvest","command_id":"B:tree:again","actor_id":"player","target_id":tree.id,"payload":request})
			expect("stump cannot restart labor duplicate yield or retain standing hints "+str(seed),not duplicate.ok and restored.services.actions.work_points({"kind":"harvest","target_id":tree.id}).is_empty() and rt.stock(tree.data.outputId).items.log==3)
			evidence.append({"seed":seed,"tree_id":tree.id,"actual":Geometry.location(rt.actor("player")),"surface_gap":actual.distance_to(face),"drop_id":tree.data.outputId,"elapsed_before_pause":elapsed})
		host.free()
	print(JSON.stringify({"ok":failures.is_empty(),"checks":checks,"evidence":evidence,"elapsed_ms":Time.get_ticks_msec()-started,"scope":"actual finite C tree, original B approach and authority, cold restore; not normal economy/renderer/VA/performance"}));quit(0 if failures.is_empty() else 1)
