extends "res://tests/world/factory_normal_source_guarantees.gd"
## New scope only: content5 lock plus actual tool-free stockyard bypass.
## No inventory grant, capture edit, teleport, terrain clearing or second stock.
const OldContract=preload("res://tests/world/fixtures/generation_before_mt01.gd")
var routes:Array=[]
func toolfree(runtime:RefCounted)->bool:
	for tool:Dictionary in runtime.world.extension("r3:production").tools:
		if tool.get("holderId")=="pack:player":return false
	return true
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	report_path=args[0];outdir=report_path.get_base_dir();wall_started=Time.get_ticks_msec()
	spec={"max_ticks_per_seed":4000,"max_wall_msec":95000}
	var profiles:Array=Modules.generation_profiles()
	for version:int in [1,2,3,4]:
		var story:int=1 if version>=3 else 0
		var before:Dictionary=OldContract.fresh(profiles,version,story)
		var after:Dictionary=Contract.fresh(profiles,version,story)
		check("historical contract bytes and digest unchanged v%d"%version,before.ok and after.ok and JSON.stringify(before.contract,"",true,true)==JSON.stringify(after.contract,"",true,true) and OldContract.digest(before.contract)==Contract.digest(after.contract))
		check("historical lock resolves without new recovery policy v%d"%version,Contract.resolve(before.contract,profiles).ok and not after.contract.has("tool_recovery_policy"))
	var lock:Dictionary=Contract.fresh(profiles,5,1)
	check("explicit content5 pins MT01 and old low-level default stays content2",lock.ok and lock.contract.tool_recovery_policy=="mt01-v1" and Contract.fresh(profiles).contract.content_version==2)
	if not lock.ok:return finish_mt01()
	for mode:String in ["missing","tampered","old-injection"]:
		var bad:Dictionary=lock.contract.duplicate(true)
		if mode=="missing":bad.erase("tool_recovery_policy")
		elif mode=="tampered":bad.tool_recovery_policy="other"
		else:bad=Contract.fresh(profiles,4,1).contract;bad.tool_recovery_policy="mt01-v1"
		check("resolve rejects recovery policy "+mode,Contract.resolve(bad,profiles).get("code")=="FACTORY_GENERATION_POLICY_MISMATCH")
	for seed:int in [713,2026]:
		current_seed=seed;tick_count=0;current={"visits":[],"transfers":[]}
		var generated:Dictionary=Factory.generate(seed,profiles,lock.contract)
		var made:Dictionary=Assembly.prepare(generated)
		if not made.get("ok",false):debug_opening(generated,seed)
		var host:=Native.new();var built:Dictionary=host._assemble(made.capture) if made.get("ok",false) else made;host.free()
		check("content5 actual Native normal world assembles",built.get("ok",false),built.get("reason"))
		if not built.get("ok",false):continue
		var runtime:RefCounted=built.runtime;var live:RefCounted=built.world
		var plan:Dictionary=live.extension("generation:RH-HOME")
		var anchor:Dictionary=plan.content_anchors[0];var id:String=str(anchor.id)+":container"
		var initial:Dictionary=runtime.capture_checkpoint();var stock:Dictionary=runtime.stock(id)
		var raster:String=raster_digest(live.snapshot())
		check("normal starts with zero carried tools and stable original source",toolfree(runtime) and runtime.actor("player").pack=={"food":1,"water":1} and id=="RH-HOME:stockyard-content:container" and stock.owner==null and plan.generation_content_version==5 and Geometry.point(stock.location)==Geometry.point(anchor.position),stock)
		var reached:bool=visit(runtime,id,"tool-free stockyard bypass")
		var search:Dictionary=send(runtime,"search",id) if reached else {"ok":false}
		var done:Dictionary=progress(runtime,150) if search.ok else {}
		check("without axe saw hammer shovel pickaxe: actual search completes",reached and search.ok and done.get("finished",false) and runtime.stock(id).searched and toolfree(runtime),slim(search))
		var taken:Dictionary=send(runtime,"take",id,{"items":{"tool_handle":1}}) if search.ok else {"ok":false}
		var home:String="r34:generated:RH-HOME:home:stock:supplies"
		var returned:bool=visit(runtime,home,"tool-free physical loaded return") if taken.ok else false
		check("tool-free real take and loaded home return preserve all terrain including roadfall",taken.ok and returned and toolfree(runtime) and runtime.actor("player").pack.get("tool_handle",0)==1 and raster_digest(live.snapshot())==raster)
		var encoded:Dictionary=Store.encode(runtime.capture_checkpoint())
		var decoded:Dictionary=Store.decode(encoded.text) if encoded.get("ok",false) else encoded
		var canonical:Dictionary=JSON.parse_string(JSON.stringify(plan,"",true,true))
		check("saved source identity searched state and content5 policy survive canonical recovery",decoded.get("ok",false) and decoded.capture.facts.stocks.filter(func(v:Dictionary)->bool:return v.id==id)[0].searched and decoded.capture.world.extensions[Factory.CONFIG_KEY].tool_recovery_policy=="mt01-v1" and Data.json_equal(decoded.capture.world.extensions["generation:RH-HOME"],canonical),{"raw_plan_exact":Data.json_equal(decoded.capture.world.extensions["generation:RH-HOME"],plan),"canonical_plan_exact":Data.json_equal(decoded.capture.world.extensions["generation:RH-HOME"],canonical),"limitation":"existing raw JSON float roundtrip is separate from canonical recovery; no epsilon or codec rewrite"})
		if encoded.get("ok",false):FileAccess.open(outdir+"/seed%d-tool-free.native.json"%seed,FileAccess.WRITE).store_string(encoded.text)
		routes.append({"seed":seed,"source_id":id,"anchor":anchor,"initial_source":stock,"initial_player":initial.facts.actors.filter(func(a:Dictionary)->bool:return a.id=="player")[0],"final_player":runtime.actor("player"),"visits":current.visits,"search":slim(search),"take":slim(taken),"initial_raster_sha256":raster,"final_raster_sha256":raster_digest(live.snapshot()),"scope":"actual new content5 normal Native/B routes and commands; source contents/backup registration belong to B, not asserted here"})
		runtime.retire()
	finish_mt01()
func debug_opening(generated:Dictionary,seed:int)->void:
	var state:=State.new();state.load_snapshot(generated)
	var registration:Dictionary=Modules.new().prepare_generation(state)
	var seed_data:Dictionary=registration.seed_result.duplicate(true)
	seed_data.initial_stocks.append_array(Factory.initial_resource_stocks(state))
	registration.seed_result=seed_data
	for field:String in ["initial_stocks","initial_tools","initial_records"]:registration[field]=seed_data[field].duplicate(true)
	var tx:Dictionary=state.prepare_changes(registration.world_changes,state.get_revision())
	var building:=Building.new()
	building.configure({"world":state,"actor":func(_id:String)->Dictionary:return {},"stock":func(_id:String)->Dictionary:return {},"tool":func(_id:String)->Dictionary:return {},"facts":func()->Dictionary:return {},"clock":func()->float:return 0.0})
	var layout:Dictionary=Assembly._layout(state,building.space(tx.view,{}, {"actors":[]}),seed_data.spawn_points)
	seed_data.spawn_points=layout.spawn_points;seed_data.home=layout.home;registration.seed_result=seed_data
	var opening:Dictionary=Assembly.Gameplay.initial(layout,registration)
	opening.diagnostics={"stocks":[],"actors":[],"validation":Assembly.Runtime.validate_facts(opening.facts)}
	for row:Dictionary in opening.facts.stocks:
		if not Data.valid_id(row.id) or not Assembly.Runtime._items_valid(row.items) or not Data.vec(row.location) or not Data.valid_id(row.location.regionId):
			var items:Array=[]
			for key:Variant in row.items:items.append({"key":key,"key_type":typeof(key),"id_valid":Data.valid_id(key),"value":row.items[key],"number":Assembly.Runtime._number(row.items[key]),"quantity":Assembly.Content.quantity_valid(str(key),row.items[key],true)})
			opening.diagnostics.stocks.append({"row":row,"item_detail":items,"id":Data.valid_id(row.id),"items":Assembly.Runtime._items_valid(row.items),"vec":Data.vec(row.location),"region":Data.valid_id(row.location.regionId)})
	for row:Dictionary in opening.facts.actors:
		var values:Dictionary={"id":Data.valid_id(row.id),"pack":Assembly.Runtime._items_valid(row.pack),"vec":Data.vec(row),"region":Data.valid_id(row.regionId)}
		for key:String in ["hp","hunger","thirst","fatigue","stamina","cooldown","nextDecision"]:values[key]=Assembly.Runtime._number(row[key]) and float(row[key])>=0 and float(row[key])<=100
		opening.diagnostics.actors.append(values)
	FileAccess.open(outdir+"/seed%d-opening-diagnostic.json"%seed,FileAccess.WRITE).store_string(JSON.stringify(opening,"\t",true,true))
func finish_mt01()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"routes":routes,"scope":"C MT01 generation policy and two bounded actual zero-tool routes; not four-seed rerun, reserve grant/repair economy or package/OS/G5 qualification"},"\t",true,true))
	quit(1 if failed else 0)
