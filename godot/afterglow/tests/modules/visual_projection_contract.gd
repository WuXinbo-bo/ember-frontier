extends "res://tests/modules/factory_boundary_fixture.gd"
## Actual Native-assembled content13; public read equality and CPU demand cost.
const Store=preload("res://scripts/storage/native_store.gd")
var measurements:Array=[]

func compare(label:String,rt:RefCounted,service:RefCounted,actor_id:String="player",id:String="")->void:
	var before:Dictionary=rt.capture_checkpoint()
	var full:Dictionary=service.projection(actor_id,id)
	var visual:Dictionary=service.visual_projection(actor_id,id)
	var expected_definitions:Array=[];var definition_ids:Dictionary={}
	for row:Dictionary in full.instances:
		if not definition_ids.has(row.definition_id):
			definition_ids[row.definition_id]=true;expected_definitions.append(Draft.find(full.definitions,str(row.definition_id)))
	check(label+" retains availability and exact complete used definitions",full.available==visual.available and expected_definitions==visual.definitions)
	check(label+" preserves visible permission-filtered instance order",full.instances.map(func(row:Dictionary)->String:return row.id)==visual.instances.map(func(row:Dictionary)->String:return row.id))
	for row:Dictionary in full.instances:
		var slim:Dictionary=Draft.find(visual.instances,str(row.id))
		var equal:bool=true
		for key:String in ["id","definition_id","name","location","quarter_turn","detailed","state_code","stock_visibility","visuals"]:
			if row.get(key)!=slim.get(key):equal=false
		check(label+" exact complete visual fields "+str(row.id),equal)
		check(label+" management API retains UI-only fields "+str(row.id),row.has("action_requirements") and row.has("recipe_management") and row.has("upgrade_proposals") and row.has("stock_policies") and row.has("ports") and not slim.has("upgrade_proposals") and not slim.has("recipe_management") and not slim.has("stock_policies"))
	if not visual.instances.is_empty():
		var row:Dictionary=visual.instances[0]
		row.location.x=123456.0
		row.visuals.anchors.clear();row.visuals.buffers.clear();row.visuals.damage.hp=-1
	if not visual.definitions.is_empty():visual.definitions[0].name="caller mutation"
	var again:Dictionary=service.visual_projection(actor_id,id)
	for row:Dictionary in full.instances:
		var slim:Dictionary=Draft.find(again.instances,str(row.id))
		check(label+" nested DTO edits stay isolated "+str(row.id),row.location==slim.location and row.visuals==slim.visuals)
	check(label+" definitions remain detached",expected_definitions==again.definitions)
	check(label+" all projection reads preserve canonical facts/world",Data.json_equal(before,rt.capture_checkpoint()))

func benchmark(label:String,rt:RefCounted,service:RefCounted)->void:
	var before:Dictionary=rt.capture_checkpoint();var full:Array=[];var visual:Array=[]
	service.projection();service.visual_projection()
	for i:int in 24:
		# Alternate ordering to avoid giving either API a persistent warm lead.
		for kind:String in (["projection","visual_projection"] if i%2==0 else ["visual_projection","projection"]):
			var start:int=Time.get_ticks_usec();service.call(kind);var elapsed:int=Time.get_ticks_usec()-start
			if kind=="projection":full.append(elapsed)
			else:visual.append(elapsed)
	full.sort();visual.sort()
	var result:Dictionary={"label":label,"samples":24,"full_median_us":full[12],"visual_median_us":visual[12],"full_p95_us":full[22],"visual_p95_us":visual[22],"median_reduction_percent":100.0*(1.0-float(visual[12])/maxf(1.0,float(full[12])))}
	measurements.append(result)
	check(label+" visual median lowers actual CPU demand",visual[12]<full[12],result)
	check(label+" repeated benchmark preserves canonical facts/world",Data.json_equal(before,rt.capture_checkpoint()))

func run()->void:
	var args:=OS.get_cmdline_user_args();var capture:Dictionary={}
	if args.size()>1:
		var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]))
		check("provided canonical benchmark capture decodes",decoded.get("ok",false))
		capture=decoded.get("capture",{})
	else:
		var profiles:Dictionary=Assembly.generation_profiles(13)
		var generated:Dictionary=Assembly.generate(713,profiles.get("profiles",[]),13)
		var prepared:Dictionary=Assembly.prepare(generated)
		check("real content13 opening prepares",prepared.get("ok",false),prepared.get("code"))
		capture=prepared.get("capture",{})
	if capture.is_empty():finish();return
	var built:Dictionary=mount(capture,"visual projection authority")
	if not built.get("ok",false):finish();return
	var rt:RefCounted=built.runtime;var service:RefCounted=built.services.modules
	compare("native opening",rt,service)
	compare("unknown actor",rt,service,"visual-test:no-such-person")
	var visible:Dictionary=service.visual_projection()
	if not visible.instances.is_empty():compare("single target",rt,service,"player",str(visible.instances[0].id))
	compare("unknown target",rt,service,"player","visual-test:no-such-module")
	benchmark("native opening",rt,service)
	# Start a genuine restoration with an explicit funded/contact fixture, then
	# compare the same real active construction/material/geometry projection.
	var repairable:Array=service.state().instances.filter(func(row:Dictionary)->bool:return row.definition_id=="r35.module.village_warehouse" and not row.restoration.completed)
	if not repairable.is_empty():
		var warehouse:Dictionary=repairable[0];var funded:Dictionary=rt.capture_checkpoint()
		put_actor(funded,port(warehouse,"repair"));Draft.find(funded.facts.actors,"player").pack={"timber":20,"scrap":10,"cloth":3,"food":4,"water":4}
		var hammer:String=""
		for tool:Dictionary in funded.world.extensions["r3:production"].tools:
			if tool.kind=="hammer":tool.holderId="pack:player";hammer=tool.id;break
		var active:Dictionary=mount(funded,"funded construction fixture")
		if active.get("ok",false):
			var started:Dictionary=command(active.runtime,"module.restore",str(warehouse.id),{"source_id":"pack:player","tool_id":hammer})
			check("actual restoration starts",started.get("ok",false),started.get("code"))
			if started.get("ok",false):
				active.runtime.tick(.1)
				compare("active actual restoration",active.runtime,active.services.modules)
				var row:Dictionary=Draft.find(active.services.modules.visual_projection().instances,str(warehouse.id))
				check("same real labor drives visible construction",row.visuals.construction.get("active",false) and row.visuals.construction.get("progress_seconds",0)>0)
			active.runtime.retire()
	rt.retire()
	evidence.append({"cpu_measurements":measurements,"scope":"Actual Native-generated source-state comparison; every render field including all cargo/anchors/visibility/reservations/construction/damage/mechanism, permission/id filter, detached caller edits and canonical purity. CPU benchmark is source/headless API demand, not packaged frame/FPS acceptance."})
	finish()
