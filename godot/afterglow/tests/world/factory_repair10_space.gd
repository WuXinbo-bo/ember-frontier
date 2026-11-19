extends "res://tests/world/factory_quality9_space.gd"
## Only the changed natural repair and old9/new10 bridge are exercised here.
func restore_check(rt:RefCounted,world:RefCounted,profiles:Array,seed:int,out:String,cell:Dictionary)->void:
	var saved:Dictionary=Store.encode(rt.capture_checkpoint())
	var decoded:Dictionary=Store.decode(saved.text) if saved.get("ok",false) else saved
	var host:=Native.new();var cold:Dictionary=host._assemble(decoded.capture) if decoded.get("ok",false) else decoded;host.free()
	check("seed%d canonical Native cold restore accepts new10"%seed,cold.get("ok",false),cold.get("reason"))
	if not cold.get("ok",false):return
	check("seed%d full canonical facts and all persistent modules exact"%seed,Data.json_equal(cold.runtime.facts(),decoded.capture.facts) and Data.json_equal(cold.world.extension("r34:modules"),decoded.capture.world.extensions["r34:modules"]) and Data.json_equal(cold.world.extension(Factory.CONFIG_KEY),decoded.capture.world.extensions[Factory.CONFIG_KEY]))
	var draft:Dictionary=Factory.draft_region_request(Factory.region_generation_input(cold.world,profiles),Vector2i.ZERO)
	var revisit:Dictionary=Factory.prepare_region_draft(cold.world,draft,cold.world.get_revision())
	check("seed%d cold explored10 revisit retains searched source/terrain and never redraws"%seed,revisit.get("ok",false) and revisit.already_generated and revisit.world_changes.is_empty() and revisit.initial_stocks.is_empty() and revisit.module_seeds.is_empty() and Data.json_equal(cold.world.extension("generation:RH-HOME"),decoded.capture.world.extensions["generation:RH-HOME"]) and (cell.is_empty() or cold.world.cell_at(cell.x,cell.y,cell.z)==0),revisit.get("reason"))
	FileAccess.open(out+"/seed%d-normal-repair10.native.json"%seed,FileAccess.WRITE).store_string(saved.text)
	cold.runtime.retire()
func run()->void:
	var args:=OS.get_cmdline_user_args();var out:String=args[0].get_base_dir()
	var profiles:Array=Modules.generation_profiles_for_content(10)
	var lock:Dictionary=Contract.fresh(profiles,10,1)
	check("explicit19 real B version API creates10",profiles.size()==19 and lock.ok,lock.get("reason"))
	if not lock.ok:return finish()
	for seed:int in [713,2026,17,999]:
		var started:int=Time.get_ticks_usec()
		var source:Dictionary=Factory.generate(seed,profiles,lock.contract)
		var generated_us:int=Time.get_ticks_usec()-started
		var prepared:Dictionary=Assembly.prepare(source);var host:=Native.new()
		var built:Dictionary=host._assemble(prepared.capture) if prepared.get("ok",false) else prepared;host.free()
		check("seed%d actual normal Assembly/Native accepts10"%seed,built.get("ok",false),built.get("reason"))
		if not built.get("ok",false):continue
		var rt:RefCounted=built.runtime;var world:RefCounted=built.world
		var plan:Dictionary=world.extension("generation:RH-HOME")
		var instances:Array=world.extension("r34:modules").instances
		var repair:Array=instances.filter(func(m:Dictionary)->bool:return m.id=="r34:generated:RH-HOME:woodwork")
		check("seed%d exact natural repair keeps old permanent module/source identity"%seed,repair.size()==1 and repair[0].definition_id==Contract.REPAIR_ID and repair[0].geometry_version==Contract.REPAIR_ID+".geometry-v2" and repair[0].source_key=="r34:%d:RH-HOME:woodwork"%seed,repair)
		if repair.size()!=1:rt.retire();continue
		var module:Dictionary=repair[0];var ports:Array=Shape.ports(module,Modules.definition(module.definition_id))
		var row:Dictionary={"seed":seed,"generation_usec":generated_us,"repair":module,"services":[],"normal":{},"spawn":Geometry.location(rt.actor("player"))}
		var ok:bool=true;var failures:Array=[]
		for port:Dictionary in ports:
			for point:Dictionary in port.use_points:
				var reached:Dictionary=reaches(built,point)
				row.services.append({"port":port.id,"point":point,"result":reached})
				if not reached.ok:ok=false;failures.append({"port":port.id,"point":point,"result":reached})
		check("seed%d every rotated natural repair usepoint has real B body support/clearance/route"%seed,ok and ports.size()==3,failures)
		var manual:String="r34:generated:RH-HOME:woodwork:stock:tools"
		var axe:String="r34:generated:RH-HOME:woodwork:tool:salvaged_axe"
		var rack:Array=module.members.filter(func(m:Dictionary)->bool:return m.kind=="entity" and str(m.id).begins_with(str(module.id)+":part:rear-empty-rack:"))
		check("seed%d original finite source/tool and real five-part rack are registered once"%seed,not rt.stock(manual).is_empty() and not rt.tool(axe).is_empty() and module.stock_refs.tools==manual and rack.size()==5 and rack.all(func(m:Dictionary)->bool:
			var e:Dictionary=world.entity(m.id)
			return not e.is_empty() and e.data.solid and e.data.opaque and e.data.module_id==module.id and e.data.module_geometry_version==module.geometry_version and e.data.module_part.material=="b_wood_aged" and not e.bounds.is_empty()),rack)
		check("seed%d repair-only policy preserves original three actors/no granted machine"%seed,rt.facts().actors.size()==3 and instances.filter(func(m:Dictionary)->bool:return m.definition_id in Family.IDS.machine).is_empty() and plan.story_sites[0].definition_id=="r34.module.fuel_woodshop")
		if seed in [713,2026] and ok:
			var walked:Array=[];var all_walked:bool=true
			for port:Dictionary in ports:
				var moved:Dictionary=walk(rt,port.use_points[0]);walked.append({"port":port.id,"walk":moved});all_walked=all_walked and moved.get("ok",false)
			check("seed%d normal zero-tool spawn really walks all three repair service mouths"%seed,all_walked,walked)
			var tools:Dictionary=normal_visit(rt,manual,[axe])
			check("seed%d natural new toolsrack searchable and original finite axe actually taken"%seed,tools.ok and rt.stock(manual).searched and rt.tool(axe).holderId=="pack:player",tools)
			row.normal={"walks":walked,"source":tools}
			var stock:String=str(plan.content_anchors[0].id)+":container"
			var shovel:String=stock+":tool:shovel";var pickaxe:String=stock+":tool:pickaxe"
			var digging_tools:Dictionary=normal_visit(rt,stock,[shovel,pickaxe])
			check("seed%d old finite digging tool identities remain usable in10"%seed,digging_tools.ok,digging_tools)
			var cell:Dictionary={}
			if digging_tools.ok:
				var yard:Dictionary=plan.buildable_workyards[0];var work:Dictionary=yard.service_points.filter(func(p:Dictionary)->bool:return p.id=="work")[0]
				var moved:Dictionary=walk(rt,at_region(work.use_points[0],"RH-HOME"))
				var point:Vector3=Geometry.rotate(Vector3(0,0,-2),yard.quarter_turn)+Geometry.point(yard.position)
				cell={"x":floori(point.x*2),"y":roundi(yard.position.y*2)-1,"z":floori(point.z*2)}
				var tool:String=pickaxe if world.cell_at(cell.x,cell.y,cell.z)==3 else shovel
				var order:Dictionary=send(rt,"terrain","terrain:%d:%d:%d"%[cell.x,cell.y,cell.z],brush(cell,"dig",tool)) if moved.get("ok",false) else moved
				var done:Dictionary=progress(rt,120) if order.get("ok",false) else {}
				check("seed%d actual normal terrain edit uses recovered tool not fixture"%seed,order.get("ok",false) and done.get("finished",false) and world.cell_at(cell.x,cell.y,cell.z)==0,{"cell":cell,"order":order,"done":done})
				row.normal.edited_cell=cell
			var jobs:=Scheduler.new();jobs.attach(rt,built.services.buildings,3410,built.services.modules)
			var outer:Dictionary=await peripheral(jobs,Vector2i(0,1));jobs.shutdown()
			check("seed%d current A real worker/CAS/B registration honors explicit10"%seed,outer.get("ok",false) and world.extension("generation:"+Factory.region_id(Vector2i(0,1))).get("repair_geometry_policy")==Contract.REPAIR_POLICY,outer)
			restore_check(rt,world,profiles,seed,out,cell)
		row.elapsed_ms=(Time.get_ticks_usec()-started)/1000.0;rows.append(row);rt.retire()
	# Read an immutable actual25 normal9 checkpoint, never edit its capture.
	var old:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]))
	var old_host:=Native.new();var restored:Dictionary=old_host._assemble(old.capture) if old.get("ok",false) else old;old_host.free()
	check("actual25 normal9 save still reassembles with additive19 definitions",restored.get("ok",false),restored.get("reason"))
	if restored.get("ok",false):
		var before:Dictionary=old.capture.world.extensions["r34:modules"]
		check("actual saved9 exact lock/plan/source/members retained; no repair replacement",Data.json_equal(restored.world.extension("r34:modules"),before) and Data.json_equal(restored.world.extension(Factory.CONFIG_KEY),old.capture.world.extensions[Factory.CONFIG_KEY]) and Data.json_equal(restored.world.extension("generation:RH-HOME"),old.capture.world.extensions["generation:RH-HOME"]))
		var jobs:=Scheduler.new();jobs.attach(restored.runtime,restored.services.buildings,3409,restored.services.modules)
		var extra:Dictionary=await peripheral(jobs,Vector2i(1,0));jobs.shutdown()
		check("saved9 real scheduler still chooses18 and preserves all old members",extra.get("ok",false) and restored.world.extension("generation:"+Factory.region_id(Vector2i(1,0))).generation_content_version==9 and before.instances.all(func(m:Dictionary)->bool:return restored.world.extension("r34:modules").instances.any(func(n:Dictionary)->bool:return Data.json_equal(m,n))),extra)
		restored.runtime.retire()
	costs.rows=rows;costs.scope="Repair-only10 actual source Native/B body/normal finite search-take/real terrain edit/Thread/canonical cold restore, plus actual25 normal9 compatibility. 17/999 query only. No grants/teleport/capture mutation, no renderer/PCK/OS/VA/FPS."
	finish()
