extends "res://tests/gameplay/factory_zone_opening_work.gd"
## Continue actual delivered logs even while independent farm/support red is
## preserved. Original books, saw, workbench and finite materials only.
func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];options=JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]));var native:=Native.new()
	var built:Dictionary=native._assemble(decoded.capture) if decoded.get("ok",false) else decoded;native.free()
	check("actual autonomous delivered-log save mounts unchanged",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	runtime=built.runtime;initial=runtime.capture_checkpoint();elapsed_start=runtime.clock()
	note("actual-autonomous-forest-logs-delivered")
	check("only three real harvested logs remain in original rack or paid player pickup",float(runtime.stock(rack).items.get("log",0))+float(runtime.actor("player").pack.get("log",0))==3)
	var records:Array=runtime.world.extension("r3:production").records.filter(func(r:Dictionary)->bool:return r.holderId=="pack:player" and r.itemId=="book_woodwork")
	check("original recovered woodwork book retains physical identity",records.size()==1)
	if records.size()!=1:return finish()
	if not runtime.world.extension("r3:production").knowledge.get("player",[]).has("basic_woodwork"):
		if not perform("original twelve second study pays real time to learn woodwork","study",records[0].id,{"record_id":records[0].id}):return finish()
	check("woodwork knowledge is backed by actual completed original study",runtime.world.extension("r3:production").orders.any(func(o:Dictionary)->bool:return o.kind=="study" and o.status=="completed" and o.actorId=="player" and o.targetId==records[0].id))
	var missing:float=3-float(runtime.actor("player").pack.get("log",0))
	if missing>0 and not await take_stock(rack,{"log":missing}):return finish()
	var saws:Array=runtime.world.extension("r3:production").tools.filter(func(t:Dictionary)->bool:return t.holderId=="pack:player" and t.kind=="hand_saw")
	if saws.size()!=1:check("original saw identity is available",false,saws);return finish()
	var saw:String=saws[0].id;var before:float=float(runtime.tool(saw).durability);var boards:float=float(quantities().get("timber",0))
	var station:String=str(runtime.domain_service("modules").instance("r34:generated:RH-HOME:woodwork").config.get("workbench_id",""))
	check("actual operational original repair shed exposes real workbench",not station.is_empty() and runtime.domain_service("buildings").instance(station).get("hp",0)>0,station)
	if station.is_empty():return finish()
	for i:int in 3:
		if not self_care():check("processing has original paid self care",false);return finish()
		if not perform("original hand saw really processes harvested log "+str(i+1),"craft",station,{"recipe_id":"saw_timber","source_id":"pack:player","output_id":"pack:player","tool_ids":[saw],"direct":false}):return finish()
	check("original three logs become twelve boards with exact saw wear",float(runtime.actor("player").pack.get("log",0))==0 and float(quantities().get("timber",0))==boards+12 and absf(float(runtime.tool(saw).durability)-(before-6))<.000001,{"pack":runtime.actor("player").pack,"saw":runtime.tool(saw)})
	note("natural-finite-logs-processed-with-original-book-and-tools")
	cold("actual12-processing-final-cold")
	check("processing never replaces original people HP consent seed or bucket",runtime.facts().actors.size()==3 and initial.facts.actors.all(func(a:Dictionary)->bool:return runtime.actor(a.id).hp==a.hp) and ["village-resident","repair-resident"].all(func(id:String)->bool:return runtime.actor(id).relationship.consent) and quantities().get("r34:water_bucket")==1 and quantities().get("r34:potato_seed")==4)
	finish()

func finish()->void:
	if runtime!=null:save("actual12-processing-final")
	super.finish()
