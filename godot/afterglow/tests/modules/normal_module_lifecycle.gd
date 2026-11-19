extends "res://tests/integration/run_factory_economy.gd"
const Content=preload("res://scripts/runtime/content_definitions.gd")
## Continue the original normal53 save with real finite sources and commands.
## No capture edits/teleports/grants/HP changes or domain-direct commits.
var commands:Array=[]
var source_path:String
var live:Dictionary={}
var construction_request:Dictionary={}
var cold_differences:Dictionary={}
var live_roundtrip:Array=[]
func differences(a:Variant,b:Variant,path:String="")->Array:
	if Data.json_equal(a,b):return []
	var result:Array=[]
	if a is Dictionary and b is Dictionary:
		for key:Variant in a:
			if not b.has(key):result.append({"path":path+"/"+str(key),"missing":"after"})
			else:result.append_array(differences(a[key],b[key],path+"/"+str(key)))
		for key:Variant in b:
			if not a.has(key):result.append({"path":path+"/"+str(key),"missing":"before"})
	elif a is Array and b is Array and a.size()==b.size():
		for i:int in a.size():result.append_array(differences(a[i],b[i],path+"/"+str(i)))
	else:result.append({"path":path,"before":a,"after":b})
	return result
func send(rt:RefCounted,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	sequence+=1
	var request:Dictionary={"command_id":"B:R34:normal-lifecycle:%d"%sequence,"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"destination":destination}
	var result:Dictionary=rt.command(request)
	commands.append({"clock":rt.clock(),"request":request.duplicate(true),"code":result.get("code"),"ok":result.get("ok",false),"reason":result.get("reason")})
	return result
func check(label:String,ok:bool,detail:Variant=null)->void:
	super.check(label,ok,detail);print("LIFECYCLE "+str(checks.size())+" "+str(ok)+" "+label)
func near_stock(rt:RefCounted,id:String)->bool:
	var stock:Dictionary=rt.stock(id)
	if not stock.has("module_id"):return super.near_stock(rt,id)
	for row:Dictionary in rt.module_service_approaches(stock.module_id).get("approaches",[]):
		if row.get("stock_ref")==id and row.get("available",false):
			return walk(rt,row.location).get("ok",false) and rt._services.production.reach("player",id,rt.stock(id),"search")==null
	return false
func cold(label:String)->bool:
	var rt:RefCounted=live.runtime;var before:Dictionary=rt.capture_checkpoint();var world_before:Dictionary=live.world.snapshot()
	var encoded:Dictionary=Store.encode(before);check(label+" actual Store encode",encoded.get("ok",false))
	if not encoded.get("ok",false):return false
	FileAccess.open(outdir+"/"+label+".native.json",FileAccess.WRITE).store_string(encoded.text)
	var decoded:Dictionary=Store.decode(encoded.text);var native:=Native.new();var restored:Dictionary=native._assemble(decoded.capture) if decoded.get("ok",false) else decoded;native.free()
	check(label+" actual cold Native assembly",restored.get("ok",false),restored.get("reason"))
	if not restored.get("ok",false):return false
	var after:Dictionary=restored.runtime.capture_checkpoint()
	cold_differences[label]=differences({"facts":before.facts,"world":world_before,"receipts":before.receipts,"simulation":before.simulation},{"facts":after.facts,"world":restored.world.snapshot(),"receipts":after.receipts,"simulation":after.simulation})
	FileAccess.open(outdir+"/cold-differences.json",FileAccess.WRITE).store_string(JSON.stringify(cold_differences,"\t",true,true))
	# Preserve live binary DTO tails and legitimate Native residency conversion
	# as separate evidence. The persisted payload itself must restore EXACTLY;
	# do not accept numeric tolerance for facts/materials/receipts/simulation.
	live_roundtrip.append({"label":label,"live_byte_values_equal":cold_differences[label].is_empty(),"differences":cold_differences[label]})
	var restored_world:Dictionary=restored.world.snapshot();var canonical:Dictionary=decoded.capture
	check(label+" exact persisted facts/extensions/entities/receipts/simulation",Data.json_equal(canonical.facts,after.facts) and Data.json_equal(canonical.world.extensions,restored_world.extensions) and Data.json_equal(canonical.world.entities,restored_world.entities) and Data.json_equal(canonical.receipts,after.receipts) and Data.json_equal(canonical.simulation,after.simulation))
	var chunks_equal:bool=canonical.world.chunks.size()==restored_world.chunks.size()
	for key:String in canonical.world.chunks:
		if not restored_world.chunks.has(key):chunks_equal=false;continue
		var old:Dictionary=canonical.world.chunks[key];var current:Dictionary=restored_world.chunks[key]
		var a:String=str(old.cell_page.raw_sha256) if old.has("cell_page") else Data.ChunkPage.fingerprint(old.cells)
		var b:String=str(current.cell_page.raw_sha256) if current.has("cell_page") else Data.ChunkPage.fingerprint(current.cells)
		chunks_equal=chunks_equal and a==b and old.key==current.key and Data.json_equal(old.coord,current.coord) and old.generated==current.generated
	check(label+" all actual voxel fingerprints retain identity across Native residency",chunks_equal)
	rt.retire();live=restored;return true
func work_port(rt:RefCounted,module:Dictionary)->Dictionary:
	for port:Dictionary in ModuleShape.ports(module,Modules.definition(str(module.definition_id))):
		if port.purpose not in ["work","repair","service","input"]:continue
		var q:RefCounted=rt._services.buildings.current_space()
		if q.standing_point(port.location).is_empty():continue
		var route:Dictionary=rt._services.actions.route("player",Geometry.location(rt.actor("player")),port.location)
		if route.ok:return port.location.duplicate(true)
	return {}
func choose_site(rt:RefCounted,id:String,hammer:String)->Dictionary:
	for z:int in range(10,57,2):
		for x:int in range(18,57,2):
			var ground:Variant=rt.world.surface_height(x,z)
			if ground==null:continue
			var payload:Dictionary={"definition_id":"r34.module.hand_workshop","position":{"x":float(x),"y":float(ground),"z":float(z),"regionId":"RH-HOME"},"quarter_turn":0,"source_id":"pack:player","tool_id":hammer}
			var request:Dictionary={"kind":"module.plan","actor_id":"player","target_id":id,"payload":payload}
			var preview:Dictionary=rt._services.modules.preview(request)
			if not preview.get("ok",false):continue
			for port:Dictionary in preview.ports:
				if port.purpose not in ["work","repair","service","input"]:continue
				var route:Dictionary=rt._services.actions.route("player",Geometry.location(rt.actor("player")),port.location)
				if route.ok:return {"payload":payload,"port":port.location.duplicate(true)}
	return {}
func dismantle(id:String,hammer:String,label:String)->bool:
	var rt:RefCounted=live.runtime;var module:Dictionary=rt._services.modules.instance(id)
	if not care(rt,80.0):return false
	var port:=work_port(rt,module);var walked:Dictionary=walk(rt,port) if not port.is_empty() else {"ok":false}
	check(label+" actual body walks to live work port",walked.get("ok",false))
	if not walked.get("ok",false):return false
	var before:Dictionary=rt.actor("player").pack.duplicate(true)
	var request:Dictionary=send(rt,"module.dismantle",id,{"source_id":"pack:player","output_id":"pack:player","tool_id":hammer})
	var completed:Dictionary=progress(rt,400) if request.ok else {}
	module=rt._services.modules.instance(id)
	check(label+" real twelve-second controlled dismantle completes",request.ok and completed.get("finished",false) and module.get("status")=="dismantled",request)
	if not request.ok or module.get("status")!="dismantled":return false
	var expected:Dictionary={}
	for item:String in module.paid_cost:
		var paid:float=float(module.paid_cost[item]);var unit:float=Content.quantity_step(item)
		var count:float=minf(1.0,paid) if item=="r34:salvaged_drive_unit" else floorf(paid*0.75/unit)*unit
		if count>0:expected[item]=count
	check(label+" exact adopted75% and original drive one returned once",Data.json_equal(module.recovery_settlement.items,expected) and module.recovery_settlement.claimed)
	var exact:bool=true
	for item:String in expected:exact=exact and float(rt.actor("player").pack.get(item,0))==float(before.get(item,0))+float(expected[item])
	check(label+" physical pack receives exact actual ledger only",exact)
	var old_pack:Dictionary=rt.actor("player").pack.duplicate(true);var again:Dictionary=send(rt,"module.dismantle",id,{"source_id":"pack:player","output_id":"pack:player","tool_id":hammer})
	check(label+" repeated new command cannot grant recovery twice",not again.ok and Data.json_equal(rt.actor("player").pack,old_pack))
	note(rt,label,{"module":module,"before_pack":before,"expected":expected});return true
func run()->void:
	var args:=OS.get_cmdline_user_args();outdir=args[0];source_path=args[1];DirAccess.make_dir_recursive_absolute(outdir)
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(source_path));var native:=Native.new();live=native._assemble(decoded.capture) if decoded.get("ok",false) else decoded;native.free()
	check("exact original20 normal53 input identity and formal Native",FileAccess.get_sha256(source_path)=="968d950768146a1683f73900be469d14c982163bd58ca31ba008d795e2cc9ea5" and live.get("ok",false))
	if not live.get("ok",false):return finish()
	var rt:RefCounted=live.runtime;var hammer:String="r34:generated:RH-HOME:woodwork:tool:hammer"
	var warehouse:Dictionary=rt._services.modules.instance("r34:normal-built-warehouse")
	var warehouse_stock:String=str(warehouse.stock_refs.storage)
	check("original finite spare scrap and warehouse output are not refilled",rt.actor("player").pack.get("scrap")==2 and rt.stock(warehouse_stock).items.get("timber")==8 and rt.tool(hammer).holderId=="pack:player")
	if not take_source(rt,warehouse_stock,{"timber":2}):return finish()
	if not care(rt,80.0):return finish()
	var id:String="B:normal-lifecycle:hand";var choice:=choose_site(rt,id,hammer)
	check("unmodified generated land offers actual support/exits/body-safe site",not choice.is_empty())
	if choice.is_empty():return finish()
	var walked:Dictionary=walk(rt,choice.port);check("builder walks actual route to chosen footprint",walked.get("ok",false))
	if not walked.get("ok",false):return finish()
	var pack_before:Dictionary=rt.actor("player").pack.duplicate(true)
	var planned:Dictionary=send(rt,"module.plan",id,choice.payload);construction_request=commands[-1].request.duplicate(true)
	check("normal real finite plan reserves only and creates empty buffers",planned.ok and Data.json_equal(pack_before,rt.actor("player").pack) and rt.facts().stocks.filter(func(s:Dictionary)->bool:return s.get("module_id")==id).all(func(s:Dictionary)->bool:return s.items.is_empty()),planned)
	if not planned.ok:return finish()
	for i:int in 20:rt.tick(0.1)
	var project:Dictionary=rt._services.modules.state().projects.filter(func(p:Dictionary)->bool:return p.module_id==id)[0]
	var progress_before:float=float(project.progress_seconds);var project_id:String=str(project.id)
	check("actual hammer labor advances before cancellation with unpaid materials",progress_before>0 and progress_before<12 and Data.json_equal(pack_before,rt.actor("player").pack) and rt._services.production.reserved("pack:player","timber")==4)
	var cancelled:Dictionary=send(rt,"module.cancel",id)
	check("module.cancel retains site/project/progress and releases exact holds without refund",cancelled.ok and rt._services.modules.instance(id).status=="planned" and rt._services.modules.state().projects[-1].status=="cancelled" and rt._services.modules.state().projects[-1].progress_seconds==progress_before and rt._services.production.reserved("pack:player","timber")==0 and Data.json_equal(pack_before,rt.actor("player").pack))
	if not cold("actual-cancelled-construction"):return finish()
	rt=live.runtime
	check("cold keeps exact cancelled identity and unpaid cost",rt._services.modules.instance(id).project_id==project_id and rt._services.modules.state().projects[-1].progress_seconds==progress_before and Data.json_equal(pack_before,rt.actor("player").pack))
	var resume:Dictionary=send(rt,"module.work",id);var completed:Dictionary=progress(rt,400) if resume.ok else {}
	var module:Dictionary=rt._services.modules.instance(id)
	check("same cancelled project resumes actual remaining labor and completes once",resume.ok and completed.get("finished",false) and module.get("status")=="operational" and module.project_id==project_id and Data.json_equal(module.paid_cost,{"timber":4,"scrap":2}),{"code":resume.get("code"),"finished":completed.get("finished"),"status":module.get("status"),"project_id":module.project_id,"expected_project_id":project_id,"paid_cost":module.paid_cost})
	if not resume.ok or module.get("status")!="operational":return finish()
	check("full adopted build cost deducted once after cold",rt.actor("player").pack.timber==float(pack_before.timber)-4 and rt.actor("player").pack.scrap==float(pack_before.scrap)-2)
	var paid_pack:Dictionary=rt.actor("player").pack.duplicate(true);var duplicate:Dictionary=rt.command(construction_request)
	check("original command receipt cannot create/pay another module",duplicate.ok and Data.json_equal(rt.actor("player").pack,paid_pack) and rt._services.modules.state().projects.filter(func(p:Dictionary)->bool:return p.module_id==id).size()==1)
	note(rt,"normal cancelled site restored and paid once",module)
	# Normal finite scrap is exhausted. Deliberately reclaim the original EMPTY
	# paid machine as a real economic tradeoff, retaining its one actual drive.
	var machine_id:String="r34:normal-built-woodshop";var paused:Dictionary=send(rt,"factory.pause",machine_id)
	check("original empty machine is truly paused before controlled reclamation",paused.ok,paused)
	if not paused.ok or not dismantle(machine_id,hammer,"original-empty-paid-machine-reclaimed"):return finish()
	if not dismantle(id,hammer,"normal-new-hand-reclaimed"):return finish()
	if not cold("actual-controlled-recovery"):return finish()
	rt=live.runtime
	var cleared:Dictionary=rt._services.modules.instance(id)
	check("cold retains exact75% settlement and retired member identity",cleared.status=="dismantled" and Data.json_equal(cleared.recovery_settlement.items,{"timber":3,"scrap":1}) and live.world.entity(id).is_empty() and rt.actor("player").pack.get("r34:salvaged_drive_unit")==1)
	var stale:Dictionary=send(rt,"module.dismantle",id,{"source_id":"pack:player","output_id":"pack:player","tool_id":hammer})
	check("cold cannot pay controlled recovery twice",not stale.ok)
	if not care(rt,80.0):return finish()
	walked=walk(rt,choice.port);check("same legal old site reached again through actual route",walked.get("ok",false))
	if not walked.get("ok",false):return finish()
	var next_id:String=id+":rebuilt";var next_pack:Dictionary=rt.actor("player").pack.duplicate(true)
	var rebuilt:Dictionary=send(rt,"module.plan",next_id,choice.payload);completed=progress(rt,400) if rebuilt.ok else {}
	var next:Dictionary=rt._services.modules.instance(next_id)
	check("same footprint rebuilt legally with new stable ID and actual material/labor",rebuilt.ok and completed.get("finished",false) and next.get("status")=="operational" and Data.json_equal(next.position,module.position) and rt.actor("player").pack.timber==float(next_pack.timber)-4 and rt.actor("player").pack.scrap==float(next_pack.scrap)-2,rebuilt)
	if not rebuilt.ok or next.get("status")!="operational":return finish()
	check("prior controlled ledger does not change on rebuilding",Data.json_equal(rt._services.modules.instance(id).recovery_settlement,cleared.recovery_settlement))
	if not cold("actual-legally-rebuilt"):return finish()
	rt=live.runtime
	check("final original machine reclamation is disclosed, no fake restored production line",rt._services.modules.instance(machine_id).status=="dismantled" and rt._services.modules.instance(next_id).status=="operational" and rt._services.modules.instance("r34:normal-built-warehouse").status=="operational" and rt.stock(warehouse_stock).items.timber==6)
	check("original three living identities/HP retained",rt.facts().actors.size()==3 and rt.facts().actors.all(func(a:Dictionary)->bool:return a.hp==100))
	note(rt,"legally rebuilt hand workshop, original machine deliberately reclaimed",{"rebuilt":next,"original_machine":rt._services.modules.instance(machine_id)})
	finish()
func finish()->void:
	if live.get("ok",false):save_scene(live.runtime,"actual-lifecycle-final")
	var report:Dictionary={"checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size(),"journey":journey,"commands":commands,"source":source_path,"live_roundtrip":live_roundtrip,"scope":"unchanged candidate PCK/normal20 finite saved state; real take/walk/cancel/cold/resume/pay/controlled recovery/cold/rebuild, deliberate old empty machine reclamation is finite scrap source. Strict persisted payload restoration and voxel content separately validated; live float DTO tails and legitimate Native chunk.storage revision changes remain explicitly recorded, NOT claimed bit-identical. Not machine production recovery, repair/damage, OS/VA/FPS or R34 whole item"}
	FileAccess.open(outdir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print(JSON.stringify({"checks":checks.size(),"failed":report.failed}));
	if live.get("ok",false):live.runtime.retire()
	quit(0 if report.failed==0 else 1)
