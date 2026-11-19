extends "res://tests/world/factory_normal_path.gd"
## Explicit9 real Native/Assembly, B standing/navigation/preview and normal
## finite tools/edit/save. No actor relocation, grants or capture mutation.
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Family=preload("res://scripts/world/factory_quality_family.gd")
var rows:Array=[]

func at_region(point:Dictionary,id:String)->Dictionary:
	var at:Dictionary=point.duplicate(true)
	at.merge({"regionId":id,"buildingId":null,"storeyId":null},true);return at

func plan_request(choice:Dictionary)->Dictionary:
	return {"actor_id":"player","kind":"module.plan","target_id":"r34:c:quality9:proposed-machine","payload":{"definition_id":choice.definition_id,"position":at_region(choice.position,"RH-HOME"),"quarter_turn":choice.quarter_turn}}

func reaches(built:Dictionary,at:Dictionary)->Dictionary:
	var feet:Dictionary=built.services.buildings.current_space().standing_point(at)
	var route:Dictionary=built.services.actions.route("player",Geometry.location(built.runtime.actor("player")),feet) if not feet.is_empty() else {"ok":false,"code":"NO_STANDING_BODY"}
	return {"ok":not feet.is_empty() and Geometry.point(feet).distance_to(Geometry.point(at))<0.001 and route.get("ok",false),"feet":feet,"route":route}

func normal_visit(rt:RefCounted,id:String,tools:Array)->Dictionary:
	var stock:Dictionary=rt.stock(id);var to:Dictionary=stock.get("location",{})
	var moved:Dictionary={"ok":false};var tries:Array=[]
	# A stock location can be the centre of its real solid container. Only
	# current B-supported/contact-permitted standing feet are actual targets.
	for offset:Vector2 in [Vector2.ZERO,Vector2(0,-1.2),Vector2(1.2,0),Vector2(-1.2,0),Vector2(0,1.2)]:
		if to.is_empty():break
		var at:Dictionary=to.duplicate(true);at.x+=offset.x;at.z+=offset.y
		var feet:Dictionary=rt._services.buildings.current_space().standing_point(at)
		if feet.is_empty():continue
		var contact:Variant=rt._services.production.reach("player",id,stock,"search")
		moved=walk(rt,feet);contact=rt._services.production.reach("player",id,stock,"search")
		tries.append({"feet":feet,"walk":moved,"contact":contact})
		if moved.get("ok",false) and contact==null:break
		moved={"ok":false}
	var searched:Dictionary=send(rt,"search",id) if moved.get("ok",false) else moved
	if searched.get("ok",false):progress(rt,120)
	var taken:Dictionary=send(rt,"take",id,{"tool_ids":tools}) if searched.get("ok",false) else searched
	return {"ok":moved.get("ok",false) and searched.get("ok",false) and rt.stock(id).get("searched",false) and taken.get("ok",false),"walk":moved.get("ok",false),"attempts":tries,"search":searched,"take":taken}

func run()->void:
	var out:String=OS.get_cmdline_user_args()[0].get_base_dir()
	var profiles:Array=Modules.generation_profiles(true);var lock:Dictionary=Contract.fresh(profiles,9,1)
	check("exact18 B profiles create explicit9 contract",profiles.size()==18 and lock.ok,lock.get("reason"))
	if not lock.ok:return finish()
	for seed:int in [713,2026,17,999]:
		var started:int=Time.get_ticks_usec();var source:Dictionary=Factory.generate(seed,profiles,lock.contract)
		var generated_us:int=Time.get_ticks_usec()-started
		var prepared:Dictionary=Assembly.prepare(source);var host:=Native.new()
		var built:Dictionary=host._assemble(prepared.capture) if prepared.get("ok",false) else prepared;host.free()
		check("seed%d real normal Assembly/Native accepts9"%seed,built.get("ok",false),built.get("reason"))
		if not built.get("ok",false):continue
		var rt:RefCounted=built.runtime;var world:RefCounted=built.world
		var plan:Dictionary=world.extension("generation:RH-HOME");var yard:Dictionary=plan.buildable_workyards[0]
		var row:Dictionary={"seed":seed,"generation_usec":generated_us,"spawn":Geometry.location(rt.actor("player")),"workyard":yard,"modules":[],"services":[],"previews":[]}
		var modules:Dictionary=world.extension("r34:modules")
		check("seed%d no workyard module, machine, stock or duplicate residents"%seed,not modules.instances.any(func(m:Dictionary)->bool:return m.id.contains("workyard") or m.definition_id in Family.IDS.machine) and not rt.facts().stocks.any(func(s:Dictionary)->bool:return s.id.contains("workyard")) and rt.facts().actors.size()==3)
		var frame:Dictionary=modules.instances.filter(func(m:Dictionary)->bool:return m.definition_id=="r34.module.fuel_woodshop")[0]
		check("seed%d S01 remains original damaged frame with restoration"%seed,frame.has("restoration") and frame.status!="operational",frame)
		var all_ports:bool=true;var failed:Array=[]
		for m:Dictionary in modules.instances:
			row.modules.append({"id":m.id,"definition_id":m.definition_id,"region":m.region,"position":m.position,"quarter_turn":m.quarter_turn})
			for port:Dictionary in Shape.ports(m,Modules.definition(m.definition_id)):
				for point:Dictionary in port.use_points:
					var reached:Dictionary=reaches(built,point)
					row.services.append({"module":m.id,"port":port.id,"at":point,"ok":reached.ok})
					if not reached.ok:all_ports=false;failed.append({"module":m.id,"port":port.id,"at":point,"result":reached})
		check("seed%d all actual B module usepoints have exact standing feet and body routes"%seed,all_ports,failed)
		var clear:bool=true
		for choice:Dictionary in yard.candidate_definitions:
			var preview:Dictionary=built.services.modules.preview(plan_request(choice))
			row.previews.append(preview);clear=clear and preview.get("ok",false) and preview.ports.size()==5
		check("seed%d both real B prospective machine footprints/five ports accept empty yard"%seed,clear,row.previews)
		var yard_reachable:bool=true;failed=[]
		for port:Dictionary in yard.service_points:
			for point:Dictionary in port.use_points:
				var at:Dictionary=at_region(point,"RH-HOME");var result:Dictionary=reaches(built,at)
				if not result.ok:yard_reachable=false;failed.append({"port":port.id,"at":at,"result":result})
		check("seed%d all five empty-yard approaches use actual B body routes"%seed,yard_reachable,failed)
		if seed in [713,2026] and clear and yard_reachable and all_ports:
			var walked:Array=[];var travelled:bool=true
			for port:Dictionary in yard.service_points:
				var at:Dictionary=at_region(port.use_points[0],"RH-HOME");var moved:Dictionary=walk(rt,at)
				walked.append({"port":port.id,"destination":at,"receipt":moved});travelled=travelled and moved.get("ok",false)
			check("seed%d normal zero-tool player really walks from spawn through every empty-yard service"%seed,travelled,walked)
			row.normal_walks=walked
			var no_source:Dictionary=rt.capture_checkpoint();var request:Dictionary=plan_request(yard.candidate_definitions[0])
			var rejected:Dictionary=send(rt,"module.plan",request.target_id,request.payload)
			check("seed%d advice is no free build or second permission"%seed,not rejected.ok and Data.json_equal(no_source,rt.capture_checkpoint()),rejected)
			var manual:String="r34:generated:RH-HOME:woodwork:stock:tools";var axe:String="r34:generated:RH-HOME:woodwork:tool:salvaged_axe"
			var tools:Dictionary=normal_visit(rt,manual,[axe]);check("seed%d normal player physically searches original finite axe source"%seed,tools.ok,tools)
			var stock:String=str(plan.content_anchors[0].id)+":container";var shovel:String=stock+":tool:shovel";var pickaxe:String=stock+":tool:pickaxe"
			tools=normal_visit(rt,stock,[shovel,pickaxe]);check("seed%d normal player physically searches original finite digging tools"%seed,tools.ok,tools)
			if tools.ok:
				var workport:Dictionary=yard.service_points.filter(func(p:Dictionary)->bool:return p.id=="work")[0]
				var at:Dictionary=at_region(workport.use_points[0],"RH-HOME");var moved:Dictionary=walk(rt,at)
				var p:Dictionary=yard.position;var turn:int=yard.quarter_turn
				var local:Vector3=Geometry.rotate(Vector3(0,0,-2.0),turn)+Geometry.point(p)
				var cell:Dictionary={"x":floori(local.x*2),"y":roundi(p.y*2)-1,"z":floori(local.z*2)}
				var material:int=world.cell_at(cell.x,cell.y,cell.z);var tool:String=pickaxe if material==3 else shovel
				var digging:Dictionary=send(rt,"terrain","terrain:%d:%d:%d"%[cell.x,cell.y,cell.z],brush(cell,"dig",tool)) if moved.get("ok",false) else moved
				var done:Dictionary=progress(rt,120) if digging.get("ok",false) else {}
				check("seed%d normal recovered tool removes real future foundation cell"%seed,digging.get("ok",false) and done.get("finished",false) and world.cell_at(cell.x,cell.y,cell.z)==0,{"cell":cell,"material":material,"walk":moved,"dig":digging,"done":done})
				var invalid:Dictionary=built.services.modules.preview(request)
				check("seed%d original B preview rechecks edited ground and refuses suggested site"%seed,invalid.get("code")=="MODULE_FOUNDATION_UNSUPPORTED",invalid)
				row.edited_cell=cell;row.edited_preview=invalid
			var jobs:=Scheduler.new();jobs.attach(rt,built.services.buildings,34,built.services.modules)
			var coord:=Vector2i(0,1);var outer:Dictionary=await peripheral(jobs,coord);jobs.shutdown()
			check("seed%d real A Thread/current CAS and B registration accept9 peripheral storage"%seed,outer.get("ok",false),outer)
			if outer.get("ok",false):
				var peripheral_plan:Dictionary=world.extension("generation:"+Factory.region_id(coord));row.peripheral=peripheral_plan
				var storage:Array=world.extension("r34:modules").instances.filter(func(m:Dictionary)->bool:return m.region==Factory.region_id(coord) and m.definition_id in Family.IDS.storage)
				check("seed%d real peripheral has selected new storage and its original storage buffer identity"%seed,storage.size()==1 and not rt.stock(storage[0].stock_refs.storage).is_empty(),storage)
				if storage.size()==1:
					var service:Dictionary=Shape.ports(storage[0],Modules.definition(storage[0].definition_id))[0].location
					var actual:Dictionary=walk(rt,service);check("seed%d normal actor really walks across boundary to new peripheral storage"%seed,actual.get("ok",false),actual)
			var saved:Dictionary=Store.encode(rt.capture_checkpoint());var decoded:Dictionary=Store.decode(saved.text) if saved.get("ok",false) else saved
			var cold_host:=Native.new();var cold:Dictionary=cold_host._assemble(decoded.capture) if decoded.get("ok",false) else decoded;cold_host.free()
			check("seed%d real Native canonical restore accepts9"%seed,cold.get("ok",false),cold.get("reason"))
			if cold.get("ok",false):
				check("seed%d canonical decoded facts including clock/packs/tools are strictly exact"%seed,Data.json_equal(cold.runtime.facts(),decoded.capture.facts))
				check("seed%d canonical decoded lock/workyard/modules are strictly exact"%seed,Data.json_equal(cold.world.extension(Factory.CONFIG_KEY),decoded.capture.world.extensions[Factory.CONFIG_KEY]) and Data.json_equal(cold.world.extension("generation:RH-HOME"),decoded.capture.world.extensions["generation:RH-HOME"]) and Data.json_equal(cold.world.extension("r34:modules"),decoded.capture.world.extensions["r34:modules"]))
				row.raw_live_facts_exact=Data.json_equal(rt.facts(),decoded.capture.facts)
				var request9:Dictionary=Factory.draft_region_request(Factory.region_generation_input(cold.world,profiles),Vector2i.ZERO)
				var revisit:Dictionary=Factory.prepare_region_draft(cold.world,request9,cold.world.get_revision())
				check("seed%d explored9 revisit does not redraw/refill/free-build"%seed,revisit.get("ok",false) and revisit.already_generated and revisit.world_changes.is_empty() and revisit.initial_stocks.is_empty() and revisit.module_seeds.is_empty() and (not row.has("edited_cell") or cold.world.cell_at(row.edited_cell.x,row.edited_cell.y,row.edited_cell.z)==0),revisit.get("reason"))
				cold.runtime.retire()
			if saved.get("ok",false):FileAccess.open(out+"/seed%d-normal-quality9.native.json"%seed,FileAccess.WRITE).store_string(saved.text)
		row.elapsed_ms=(Time.get_ticks_usec()-started)/1000.0;rows.append(row);rt.retire()
	costs.rows=rows;costs.scope="Explicit9 true Assembly/Native, four-seed B body/space checks and two-seed real normal walking/tool-source/edit/Thread peripheral/cold restore. Prospective yard preview does not prove completed-machine body/production or occlusion. No renderer, PCK, VA, OS, FPS or G4/G5 qualification."
	finish()
