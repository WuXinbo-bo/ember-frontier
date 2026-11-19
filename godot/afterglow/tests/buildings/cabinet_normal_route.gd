extends "res://tests/integration/run_factory_economy.gd"
## Continue the actual candidate17 economy; all travel, costs, deposits and
## moves use shipping Runtime/InputRouter and the original physical world.
const Router=preload("res://scripts/input/input_router.gd")
var input_sha:String=""
var input_path:String=""
var input_router:Node

func send(runtime:RefCounted,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	sequence+=1
	return runtime.command({"command_id":"B:MV01:normal:%d"%sequence,"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"destination":destination})

func near_stock(runtime:RefCounted,id:String)->bool:
	var stock:Dictionary=runtime.stock(id)
	if not stock.has("module_id"):return super.near_stock(runtime,id)
	var guidance:Dictionary=runtime.module_service_approaches(str(stock.module_id))
	for row:Dictionary in guidance.get("approaches",[]):
		if row.get("stock_ref")!=id or not row.get("available",false):continue
		var reached:Dictionary=walk(runtime,row.location)
		if not reached.get("ok",false):note(runtime,"real public stock service walk failed",reached)
		return reached.get("ok",false) and runtime._services.production.reach("player",id,runtime.stock(id),"search")==null
	note(runtime,"actual public stock guidance has no reachable service face",guidance)
	return false

func site_pair(runtime:RefCounted)->Dictionary:
	var building:RefCounted=runtime._services.buildings;var query:RefCounted=building.current_space()
	for x:int in range(10,15):
		for z:int in range(4,14):
			var region:Dictionary=runtime.world.region_at({"x":x,"y":0.5,"z":z})
			var y:Variant=runtime.world.surface_height(x,z)
			if region.get("id")!="RH-HOME" or y==null:continue
			var at:Dictionary={"x":x,"y":y,"z":z,"regionId":region.id}
			var original:Dictionary=building.make_instance("cabinet","B:MV01:normal-cabinet",at)
			if not building.prepare_edit([],[original]).ok:continue
			var destination:Dictionary=original.duplicate(true);destination.position.x+=1.0
			if not building.prepare_edit([],[destination]).ok:continue
			var uses:Array=query.use_points(original);var feet:Dictionary=query.standing_point(uses[0])
			if feet.is_empty() or not runtime._services.actions.route("player",Geometry.location(runtime.actor("player")),feet).ok:continue
			return {"original":original,"destination":destination,"feet":feet}
	return {}

func structure_request(runtime:RefCounted,piece:Dictionary,kind:String)->Dictionary:
	var payload:Dictionary={"kind":kind,"source_id":"pack:player","output_id":"pack:player","tool_id":"r34:generated:RH-HOME:woodwork:tool:hammer","held":true,"requires_hold":false,"direct":true}
	payload["instance" if kind=="place" else "destination"]=piece
	return {"kind":"structure","actor_id":"player","target_id":piece.id,"payload":payload}

func native_cold(runtime:RefCounted,label:String)->Dictionary:
	var encoded:Dictionary=Store.encode(runtime.capture_checkpoint())
	if not encoded.ok:return encoded
	FileAccess.open(outdir+"/"+label+".native.json",FileAccess.WRITE).store_string(encoded.text)
	var decoded:Dictionary=Store.decode(encoded.text)
	if not decoded.ok:return decoded
	var host:=Native.new();var rebuilt:Dictionary=host._assemble(decoded.capture);host.free()
	return rebuilt

func run()->void:
	var args:=OS.get_cmdline_user_args();outdir=args[0];input_path=args[1];DirAccess.make_dir_recursive_absolute(outdir)
	input_sha=FileAccess.get_sha256(input_path)
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(input_path))
	check("immutable candidate17 actual normal economy decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish()
	var host:=Native.new();var built:Dictionary=host._assemble(decoded.capture);host.free()
	check("actual normal C4 authority restores with original three people",built.get("ok",false) and built.runtime.facts().actors.size()==3,built.get("reason"))
	if not built.get("ok",false):return finish()
	var runtime:RefCounted=built.runtime;var building:RefCounted=built.services.buildings
	note(runtime,"candidate17 normal53 immutable successful checkpoint",input_sha)
	check("optional cabinet starts after both real machine batches and four real hauling trips",runtime.stock("r34:normal-built-warehouse:stock:storage").items.get("timber",0)==8 and runtime.actor("player").pack.timber==2)
	if not care(runtime):check("real personal care remains usable",false);return finish()
	var warehouse_before:float=runtime.stock("r34:normal-built-warehouse:stock:storage").items.timber
	if not take_source(runtime,"r34:normal-built-warehouse:stock:storage",{"timber":1}):return finish()
	check("one missing board is physically taken from real produced and delivered stock",runtime.actor("player").pack.timber==3 and runtime.stock("r34:normal-built-warehouse:stock:storage").items.timber==warehouse_before-1)
	var sites:Dictionary=site_pair(runtime)
	check("real woodwork courtyard has supported non-module sites and a true body route",not sites.is_empty(),sites)
	if sites.is_empty():return finish()
	var walked:Dictionary=walk(runtime,sites.feet)
	check("original player physically walks to real external cabinet use point",walked.get("ok",false),walked)
	if not walked.get("ok",false):return finish()
	input_router=Router.new();input_router.controls_path=outdir+"/isolated-controls.json";input_router.configure(runtime,false)
	var entered:Dictionary=input_router.begin_facility_placement("cabinet")
	check("public normal input enters only the real cabinet placement mode",entered.ok and input_router.state().mode=="facility_place" and input_router.state().facility_definition_id=="cabinet",entered)
	if not entered.ok:return finish()
	var request:Dictionary=structure_request(runtime,sites.original,"place")
	var available:Dictionary=runtime.availability(request)
	var pack_before:Dictionary=runtime.actor("player").pack.duplicate(true)
	var started:Dictionary=input_router.request(request.kind,request.target_id,request.payload)
	check("same legal placement preview and public input submit agree",available.ok and started.ok,{"preview":available.get("reason"),"submit":started.get("reason")})
	if not started.ok:return finish()
	var done:Dictionary=progress(runtime,100)
	check("eight seconds of actual construction creates one real cabinet and stock",done.finished and is_equal_approx(done.sim_seconds,8.0) and not building.instance(sites.original.id).is_empty() and runtime.stock(sites.original.id).structureId==sites.original.id,done)
	if not done.finished or building.instance(sites.original.id).is_empty():return finish()
	var paid:Dictionary=pack_before.duplicate(true);paid.timber-=3;paid.scrap-=1
	check("initial construction alone pays original three boards and one scrap",Data.json_equal(paid,runtime.actor("player").pack))
	var relation:Dictionary=runtime.movable_facility(sites.original.id)
	check("public movable facility uses exact real stock-to-cabinet relation and live permission",relation.get("available",false) and relation.get("can_move",false) and relation.get("structure_id")==sites.original.id and relation.get("definition_id")=="cabinet",relation)
	check("unknown stock player pack and real warehouse cannot masquerade as movable cabinet",not runtime.movable_facility("B:MV01:unknown-stock").available and not runtime.movable_facility("pack:player").available and not runtime.movable_facility("r34:normal-built-warehouse:stock:storage").available)
	note(runtime,"actual normal paid cabinet built",building.instance(sites.original.id))
	# Use the existing real damage action so preserving HP during movement is
	# observable; do not edit the object or manufacture a damaged fixture.
	var damage:Dictionary=send(runtime,"structure",sites.original.id,{"kind":"damage","source_id":"pack:player","output_id":"pack:player","tool_id":"r34:generated:RH-HOME:woodwork:tool:hammer","direct":true})
	var damaged:Dictionary=progress(runtime,30) if damage.ok else {}
	check("existing two-second damage action produces actual 60HP before movement",damage.ok and damaged.get("finished",false) and building.instance(sites.original.id).hp==60,damage.get("reason"))
	if not damage.ok or not damaged.get("finished",false):return finish()
	var axe:String="r34:generated:RH-HOME:woodwork:tool:salvaged_axe"
	var deposit:Dictionary=send(runtime,"deposit",sites.original.id,{"items":{"scrap":1,"book_woodwork":1},"tool_ids":[axe]})
	check("real deposit transfers own remaining scrap original book and original axe",deposit.ok,deposit)
	if not deposit.ok:return finish()
	var original:Dictionary=building.instance(sites.original.id);var stock:Dictionary=runtime.stock(original.id)
	var original_axe:Dictionary=runtime.tool(axe);var original_records:Array=runtime._services.production.state().records
	var pack_after_deposit:Dictionary=runtime.actor("player").pack.duplicate(true)
	# A nearby unsupported destination was previously green until the last tick.
	var unsupported:Dictionary=sites.destination.duplicate(true);unsupported.position.y+=0.5
	var denied:Dictionary=structure_request(runtime,unsupported,"move")
	var before_denial:Dictionary=runtime.capture_checkpoint()
	var preview:Dictionary=runtime.availability(denied)
	var submit:Dictionary=send(runtime,"structure",denied.target_id,denied.payload)
	check("unsupported nearby move rejects both preview and admission before labor",not preview.ok and not submit.ok and preview.get("code")=="DEPENDENT" and submit.get("code")=="DEPENDENT",{"preview":preview,"submit":submit})
	check("rejected move preserves full world inventories identities and clock",Data.json_equal(before_denial,runtime.capture_checkpoint()))
	var body_blocked:Dictionary=original.duplicate(true);body_blocked.position=Geometry.json_point(Geometry.point(runtime.actor("player")))
	var occupied_request:Dictionary=structure_request(runtime,body_blocked,"move")
	var occupied_preview:Dictionary=runtime.availability(occupied_request)
	var occupied_submit:Dictionary=send(runtime,"structure",original.id,occupied_request.payload)
	check("actual living player blocks destination in both preview and authoritative admission",not occupied_preview.ok and not occupied_submit.ok and occupied_preview.get("code")=="OCCUPIED" and occupied_submit.get("code")=="OCCUPIED",{"preview":occupied_preview,"submit":occupied_submit})
	check("occupied rejection keeps the original damaged loaded cabinet and every fact",Data.json_equal(before_denial,runtime.capture_checkpoint()))
	var move:Dictionary=structure_request(runtime,sites.destination,"move")
	check("normal actual cabinet enters original move input",input_router.begin_structure_action("move",original.id).ok)
	var moving:Dictionary=input_router.request(move.kind,move.target_id,move.payload)
	check("loaded cabinet admits original nearby move without another manufacturing cost",moving.ok,moving)
	if not moving.ok:return finish()
	for step:int in 20:runtime.tick(0.1)
	var cancelled:Dictionary=send(runtime,"cancel")
	check("cancel after real partial labor keeps original loaded cabinet at origin",cancelled.ok and building.instance(original.id)==original and runtime.stock(original.id)==stock and Data.json_equal(pack_after_deposit,runtime.actor("player").pack),cancelled)
	var resumed:Dictionary=input_router.request(move.kind,move.target_id,move.payload)
	if not resumed.ok:check("original loaded move restarts after cancel",false,resumed);return finish()
	for step:int in 20:runtime.tick(0.1)
	var restored:Dictionary=native_cold(runtime,"actual-mv01-moving")
	check("in-flight original loaded cabinet cold saves and restores",restored.get("ok",false),restored.get("reason"))
	if not restored.get("ok",false):return finish()
	runtime=restored.runtime;building=restored.services.buildings
	var completed:Dictionary=progress(runtime,60)
	var moved:Dictionary=building.instance(original.id);var moved_stock:Dictionary=runtime.stock(original.id)
	var wanted:Dictionary=original.duplicate(true);wanted.position=sites.destination.position;wanted.version=int(original.version)+1
	check("remaining real move work changes only position and one structure version",completed.finished and Data.json_equal(wanted,moved),{"actual":moved,"expected":wanted})
	var wanted_stock:Dictionary=stock.duplicate(true);wanted_stock.location=Geometry.location(sites.destination)
	check("same one stock follows loaded cabinet with exact owner contents and references",Data.json_equal(wanted_stock,moved_stock) and runtime.facts().stocks.filter(func(s:Dictionary)->bool:return s.id==original.id).size()==1)
	check("move preserves exact original axe and book identities with no repeated material cost",Data.json_equal(original_axe,runtime.tool(axe)) and Data.json_equal(original_records,runtime._services.production.state().records) and Data.json_equal(pack_after_deposit,runtime.actor("player").pack))
	note(runtime,"original cabinet physically moved after cancellation and native cold resume",moved)
	if not near_stock(runtime,original.id):check("real player reaches moved cabinet",false);return finish()
	var retrieved:Dictionary=send(runtime,"take",original.id,{"items":{"scrap":1,"book_woodwork":1},"tool_ids":[axe]})
	check("original deposited material book and axe are physically retrieved at new place",retrieved.ok and runtime.tool(axe).holderId=="pack:player" and runtime.actor("player").pack.scrap==1 and runtime.actor("player").pack.book_woodwork==1 and runtime.stock(original.id).items.values().all(func(n:Variant)->bool:return float(n)==0),retrieved)
	var final:Dictionary=native_cold(runtime,"actual-mv01-completed")
	check("completed move and retrieved original contents cold restore exact authorities",final.get("ok",false) and Data.json_equal(final.runtime.facts(),runtime.facts()) and Data.json_equal(final.world.extension("r3:production"),runtime.world.extension("r3:production")) and Data.json_equal(final.services.buildings.instance(original.id),moved),final.get("reason"))
	check("original candidate17 source remains byte-identical",FileAccess.get_sha256(input_path)==input_sha)
	finish()

func finish()->void:
	var report:Dictionary={"checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size(),"input_sha256":input_sha,"journey":journey,"scope":"actual C4 normal53 checkpoint -> real board source -> InputRouter paid cabinet -> deposit -> original move/cancel/cold -> retrieval; no fixture terrain/actor/material or GUI/package/OS/VA qualification"}
	FileAccess.open(outdir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	if input_router!=null:input_router.free()
	print(JSON.stringify(report));quit(1 if report.failed else 0)
