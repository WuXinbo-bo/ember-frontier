extends "res://tests/buildings/family_generation_suite.gd"
## Actual C persistent placement -> B consumer -> A final transaction/codec.
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
const Dressing=preload("res://scripts/buildings/building_dressing.gd")
const Data=preload("res://scripts/world/world_data.gd")
var rows:Array=[]

func patch_plan(plan:Dictionary)->Dictionary:
	return runtime._commit({"world_changes":[building.extension_change("generation:RH-HOME",plan)],"fact_changes":[]})

func consumer_for(plan:Dictionary,marker:Variant=null)->Dictionary:
	# A value-only explicit failure fixture; never modifies the live world.
	var snapshot:=world.snapshot();snapshot.extensions["generation:RH-HOME"]=plan
	if marker!=null:snapshot.extensions[Dressing.KEY]=marker
	var fixture:=World.new();var loaded:=fixture.load_snapshot(snapshot)
	if not loaded.ok:return loaded
	return Dressing.new().prepare(building,fixture,["RH-HOME"])

func conflict_cases(entity:Dictionary,plan:Dictionary)->void:
	var profile:Dictionary=entity.data.dressing_profile
	var q:RefCounted=building.current_space()
	var at:Dictionary=entity.position.duplicate(true);var bounds:=Geometry.aabb(entity.bounds)
	var clean_plan:Dictionary={"paths":[],"parcels":[]}
	var empty:Dictionary=entity.duplicate(true);empty.id="RH-HOME:fixture:dressing"
	# Exclude the existing entity only by testing a world value snapshot with
	# that one decoration absent. Real trees/buildings/terrain remain intact.
	var source:=world.snapshot();source.entities.erase(entity.id)
	var fixture:=World.new();expect("conflict fixture retains valid real generated world",fixture.load_snapshot(source).ok)
	q=building.space(fixture)
	var safe:=Dressing.safe_placement(building,fixture,q,clean_plan,empty,profile,[],[])
	expect("actual C chosen ground is fully supported and unoccupied",safe.is_empty(),safe)
	var road:Dictionary={"paths":[{"width":2,"points":[{"x":at.x-4,"z":at.z},{"x":at.x+4,"z":at.z}]}]}
	expect("road and shoulder clearance reject decoration",Dressing.safe_placement(building,fixture,q,road,empty,profile,[],[])=="road-clearance")
	var parcel:Dictionary={"parcels":[{"pad":{"xz":[bounds.position.x,bounds.position.z,bounds.end.x,bounds.end.z]}}]}
	expect("all reserved parcel pads reject scenery",Dressing.safe_placement(building,fixture,q,parcel,empty,profile,[],[])=="parcel-pad")
	var entrance:Dictionary={"parcels":[{"entrance_ports":[{"position":at}]}]}
	expect("entrance swept approach clearance remains empty",Dressing.safe_placement(building,fixture,q,entrance,empty,profile,[],[])=="entrance-clearance")
	var reservation:Dictionary={"parcels":[{"use_reservations":[{"bounds":entity.bounds}]}]}
	expect("construction and work reservations cannot be dressed over",Dressing.safe_placement(building,fixture,q,reservation,empty,profile,[],[])=="reserved-use-volume")
	expect("pending same-transaction family or scenery overlap rejected",Dressing.safe_placement(building,fixture,q,clean_plan,empty,profile,[entity],[])=="pending-entity")
	var actor:=resident("fixture-resident",{"x":at.x,"y":at.y,"z":at.z,"regionId":entity.regionId})
	expect("resident footprint plus live personal clearance rejected",Dressing.safe_placement(building,fixture,q,clean_plan,empty,profile,[],[actor])=="resident-clearance")
	var floating:=empty.duplicate(true);floating.position.y+=0.5;floating.bounds.min.y+=0.5;floating.bounds.max.y+=0.5
	expect("floating or stepped footprint rejected without terrain flattening",Dressing.safe_placement(building,fixture,q,clean_plan,floating,profile,[],[])=="unsupported-or-stepped-footprint")
	var outside:=empty.duplicate(true);outside.bounds.min.x=-2
	expect("crossing authoritative region boundary rejected",Dressing.safe_placement(building,fixture,q,clean_plan,outside,profile,[],[])=="region-boundary")
	var duplicate:=plan.duplicate(true);duplicate.dressing.append(duplicate.dressing[0].duplicate(true))
	var rejected:=consumer_for(duplicate)
	expect("duplicate durable slot identity rejected",not rejected.ok and rejected.code=="INVALID_DRESSING_PLAN",rejected.get("code"))
	var unknown:=plan.duplicate(true);unknown.dressing[0].profile_id="missing-profile"
	rejected=consumer_for(unknown)
	expect("unknown geometry profile rejected",not rejected.ok and rejected.code=="INVALID_DRESSING_PLAN")
	var changed:=plan.duplicate(true);changed.dressing[0].position.x+=0.125
	rejected=consumer_for(changed)
	expect("processed slot cannot silently move or reroll",not rejected.ok and rejected.code=="DRESSING_PLAN_CHANGED",rejected.get("code"))
	rejected=consumer_for(plan,{"version":1,"entries":[]})
	expect("malformed durable marker fails closed",not rejected.ok and rejected.code=="INVALID_DRESSING_MARKER")
	var invalid_entry:Dictionary=world.extension(Dressing.KEY);invalid_entry.entries[plan.dressing[0].id]=7
	rejected=consumer_for(plan,invalid_entry)
	expect("malformed processed slot fails closed without a script error",not rejected.ok and rejected.code=="INVALID_DRESSING_MARKER")
	var oversized:=plan.duplicate(true)
	while oversized.dressing.size()<=48:oversized.dressing.append(plan.dressing[0].duplicate(true))
	rejected=consumer_for(oversized)
	expect("bounded region list rejects more than 48 slots before work",not rejected.ok and rejected.code=="INVALID_DRESSING_PLAN")
	# Domain-boundary fixture only: use real terrain/props, explicit local
	# shovel capability and actor pose; never grants them to the live runtime.
	var terrain:=preload("res://scripts/terrain/terrain_service.gd").new()
	var operator:=resident("fixture-operator",{"x":at.x+1.8,"y":at.y,"z":at.z,"regionId":entity.regionId})
	operator.relationship.consent=true
	terrain.configure({"world":world,"actor":func(_id:String)->Dictionary:return operator,"stock":func(_id:String)->Dictionary:return {},"tool":func(_id:String)->Dictionary:return {"holderId":"pack:fixture-operator","durability":100,"qualities":{"shovel":1,"pickaxe":1}},"facts":func()->Dictionary:return {"actors":[operator]},"clock":func()->float:return 0.0})
	var cell:Dictionary={"x":floori(at.x/0.5),"y":roundi(at.y/0.5)-1,"z":floori(at.z/0.5)}
	var request:Dictionary={"actor_id":"fixture-operator","kind":"terrain","payload":{"tool_id":"fixture-tool","edit":{"operation":"dig","cells":[cell]}}}
	var protected:Dictionary=terrain.availability(request)
	expect("original terrain editor protects actual dressing foundation cells",not protected.ok and protected.code in ["FOUNDATION_SUPPORT","ENTITY_SUPPORT"],protected.get("code"))
	cell.y+=1;request.payload.edit.operation="fill"
	protected=terrain.availability(request)
	expect("original terrain editor refuses filling actual scenery body",not protected.ok and protected.code=="ENTITY_OCCUPIED",protected.get("code"))

func run()->void:
	var started:=Time.get_ticks_msec()
	var union:Dictionary={}
	for seed:int in [713,2026]:
		var snapshot:Dictionary=Generator.generate_settlement(seed,Building.generation_profiles(),"rural-3")
		expect(str(seed)+" real C rural-3 world exists",snapshot.get("generatorVersion")=="rural-3",snapshot.get("reason"))
		if snapshot.get("generatorVersion")!="rural-3":continue
		var prepared:Dictionary=Assembly.prepare(snapshot)
		expect(str(seed)+" actual A full assembler validates family and dressing together",prepared.ok,prepared.get("reason"))
		if not prepared.ok:continue
		var host:=Client.new();var assembled:Dictionary=host._assemble(prepared.capture)
		expect(str(seed)+" sole runtime accepts complete initial placement",assembled.ok,assembled.get("reason"))
		if not assembled.ok:host.free();continue
		world=assembled.world;runtime=assembled.runtime;building=assembled.services.buildings;actions=assembled.services.actions;production=assembled.services.production
		var marker:Dictionary=world.extension(Dressing.KEY)
		var entities:Array=world.entities().filter(func(e:Dictionary)->bool:return e.data.get("dressing_profile") is Dictionary)
		expect(str(seed)+" purpose placements become real world collider entities",entities.size()>=8 and marker.entries.size()>=entities.size(),{"placed":entities.size(),"processed":marker.entries.size()})
		var no_free_gameplay:=true;var colliding:=true
		var query:RefCounted=building.current_space()
		for entity:Dictionary in entities:
			union[entity.data.dressing_profile_id]=true
			if not runtime.stock(entity.id).is_empty() or not entity.data.no_stock or not entity.data.no_interaction:no_free_gameplay=false
			if not query.standing_point(Geometry.location(entity)).is_empty():colliding=false
		expect(str(seed)+" scenery adds no loot inventory water or work station",no_free_gameplay)
		expect(str(seed)+" actual B body queries collide with every placed prop",colliding)
		var before:=runtime.capture_checkpoint();var again:=building.prepare_generation(world)
		expect(str(seed)+" repeating generator does no work or restocking",not again.ok and again.code=="ALREADY_SEEDED" and Data.json_equal(before,runtime.capture_checkpoint()))
		var paths_checked:=0;var path_failures:Array=[]
		for region:Dictionary in world.regions():
			for path:Dictionary in world.extension("generation:"+str(region.id)).paths:
				var current:Dictionary={}
				for i:int in range(path.points.size()-1):
					var a:Dictionary=path.points[i];var b:Dictionary=path.points[i+1]
					var steps:=maxi(1,ceili(Vector2(b.x-a.x,b.z-a.z).length()/0.5))
					for step:int in steps+1:
						var x:=lerpf(a.x,b.x,float(step)/steps);var z:=lerpf(a.z,b.z,float(step)/steps)
						# Same finite half-open boundary/body-radius rule as C's
						# joint test. Cross-region transitions use the actual portals.
						if x<region.bounds.min.x+0.5 or x>region.bounds.max.x-0.5 or z<region.bounds.min.z+0.5 or z>region.bounds.max.z-0.5:current={};continue
						var feet:Dictionary=query.standing_point({"x":x,"y":world.surface_height(x,z),"z":z,"regionId":region.id,"buildingId":null,"storeyId":null})
						if feet.is_empty():
							path_failures.append({"path":path.id,"x":x,"z":z,"reason":"no body support"});current={};continue
						if not current.is_empty():
							var walked:Dictionary=query.walk("player",current,feet,true)
							if not walked.ok:path_failures.append({"path":path.id,"from":current,"to":feet,"result":walked})
							paths_checked+=1
						current=feet
		expect(str(seed)+" original real body road segments remain passable",path_failures.is_empty(),{"segments":paths_checked,"failures":path_failures.slice(0,8)})
		if seed==713 and not entities.is_empty():
			var plan:Dictionary=world.extension("generation:RH-HOME")
			var home_entities:Array=entities.filter(func(e:Dictionary)->bool:return e.regionId=="RH-HOME")
			conflict_cases(home_entities[0],plan)
			var view:Node3D=building.create_view({"runtime":runtime})
			expect("live building renderer contains actual eight-class props",entities.all(func(e:Dictionary)->bool:return view.objects.has(e.id)))
			var removed:Dictionary=home_entities[0]
			var removal:=runtime._commit({"world_changes":[{"op":"entity.remove","id":removed.id,"before":removed}],"fact_changes":[]})
			expect("same authority transaction removes scenery and its live mesh",removal.ok and world.entity(removed.id).is_empty() and not view.objects.has(removed.id),removal.get("reason"))
			again=building.prepare_generation(world)
			expect("removed durable ID never respawns from old generation plan",not again.ok and again.code=="ALREADY_SEEDED" and world.snapshot().retiredEntityIds.has(removed.id))
			var slot:Dictionary={"id":"RH-HOME:dressing-test:addition","profile_id":removed.data.dressing_profile_id,"position":removed.position.duplicate(),"quarter_turn":removed.data.quarterTurn,"state":"aged"}
			plan.dressing.append(slot)
			expect("explicit versioned plan amendment commits without implicit filling",patch_plan(plan).ok)
			var addition:=building.prepare_generation(world,["RH-HOME"])
			expect("existing family can receive dressing-only DTO without new stock",addition.ok and addition.assembled_parcels.is_empty() and addition.initial_stocks.is_empty() and addition.dressing_results.size()==1,addition.get("reason"))
			if addition.ok:
				var committed:=runtime._commit(addition)
				expect("dressing-only follows final safety and creates live native mesh",committed.ok and not world.entity(slot.id).is_empty() and view.objects.has(slot.id),committed.get("reason"))
			var blocked:=slot.duplicate(true);blocked.id="RH-HOME:dressing-test:blocked"
			blocked.position=Geometry.json_point(Geometry.point(runtime.actor("player")))
			plan.dressing.append(blocked)
			expect("explicit conflict proposal uses same persistent plan",patch_plan(plan).ok)
			var skipped:=building.prepare_generation(world,["RH-HOME"])
			expect("unsafe slot produces durable skip rather than unsafe collider",skipped.ok and skipped.dressing_results[0].status=="skipped" and skipped.world_changes.size()==1,skipped.get("dressing_results"))
			if skipped.ok:expect("durable skipped marker commits through original safety boundary",runtime._commit(skipped).ok)
			again=building.prepare_generation(world)
			expect("skipped slot never pops into existence later",not again.ok and again.code=="ALREADY_SEEDED" and world.entity(blocked.id).is_empty())
			for child:Node in view.get_children():child.queue_free()
			await process_frame
			view.queue_free();await process_frame
		var encoded:=Store.encode(runtime.capture_checkpoint());var decoded:=Store.decode(encoded.get("text",""))
		var restored:Dictionary=host._assemble(decoded.capture) if decoded.ok else {"ok":false}
		expect(str(seed)+" actual native codec and formal assembler restore dressing",encoded.ok and decoded.ok and restored.ok)
		if restored.ok:
			# Codec deliberately writes chunks nonresident; the formal assembler
			# performs one residency capability. Predict ONLY those exact changes.
			var expected_world:Dictionary=decoded.capture.world.duplicate(true)
			expected_world.revision+=1
			for chunk:Dictionary in expected_world.chunks.values():chunk.resident=true;chunk.revision=expected_world.revision
			expect(str(seed)+" saved entities markers all voxel cells and actor facts remain exact",Data.json_equal(restored.runtime.capture_checkpoint().world,expected_world) and Data.json_equal(restored.runtime.facts(),decoded.capture.facts))
			again=restored.services.buildings.prepare_generation(restored.world)
			expect(str(seed)+" reload does not regenerate or restock any prop",not again.ok and again.code=="ALREADY_SEEDED")
			var before_render:Dictionary=restored.runtime.capture_checkpoint()
			var restored_view:Node3D=restored.services.buildings.create_view({"runtime":restored.runtime})
			var hay_count:=0;var actual_binding:=true
			for entity:Dictionary in restored.world.entities():
				if entity.get("data",{}).get("dressing_profile_id")!="haystack":continue
				hay_count+=1
				var root:Node3D=restored_view.objects.get(entity.id)
				var assembly:MeshInstance3D=root.get_node_or_null("NativeAssembly") if root!=null else null
				var straw:=false;var rope:=false
				if assembly!=null:
					for surface:int in assembly.mesh.get_surface_count():
						var material:Material=assembly.get_active_material(surface)
						straw=straw or material==restored_view.materials.get("straw_fibres")
						rope=rope or material==restored_view.materials.get("hemp_rope")
				actual_binding=actual_binding and straw and rope
			expect(str(seed)+" saved real haystacks restore actual c08 and rope mesh consumers",hay_count>0 and actual_binding and FileAccess.get_sha256(restored_view.manifest.textures.straw_fibres.resource)==restored_view.manifest.textures.straw_fibres.sha256,{"haystacks":hay_count,"actual_materials":actual_binding})
			expect(str(seed)+" restored straw presentation changes no saved authority",Data.json_equal(before_render,restored.runtime.capture_checkpoint()))
			restored_view.free()
		rows.append({"seed":seed,"generator":world.identity().generatorVersion,"placed":entities.size(),"marker":marker,"road_segments":paths_checked})
		host.free()
	# The approved abandoned-car profile was added after the original eight.
	# Retain every original class, and require this real ninth class as well.
	var expected_profiles:Array=["well_covered","water_barrel","haystack","village_sign","stored_water_tank","abandoned_bicycle","rural_fence","abandoned_scooter","abandoned_car"]
	var actual_profiles:Array=union.keys();actual_profiles.sort();expected_profiles.sort()
	expect("real two-seed plans integrate all nine approved scenery classes exactly",actual_profiles==expected_profiles,actual_profiles)
	# Historical explored rural-2 has no dressing and must stay that way.
	var old:=World.new();old.load_snapshot(Generator.generate_settlement(713,Building.generation_profiles(),"rural-2"))
	var old_before:=old.snapshot();var old_result:=Dressing.new().prepare(building,old)
	expect("old plan absence is preserved without auto-populating explored saves",not old_result.ok and old_result.code=="ALREADY_SEEDED" and old.snapshot()==old_before)
	print("ACTUAL_PERSISTENT_DRESSING "+JSON.stringify(rows))
	finish(started)
