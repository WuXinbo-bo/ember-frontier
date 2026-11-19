extends "res://tests/integration/run_village_supply15.gd"

const Compact17=preload("res://scripts/modules/compact_catalog.gd")
const Warehouse17="r34:generated:RH-HOME:village-warehouse"

func run()->void:
	wall_start15=Time.get_ticks_msec()
	outdir=OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(outdir)
	var profiles:Dictionary=Assembly.generation_profiles(17)
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles,17))
	check("new compact world prepares",prepared.get("ok",false),prepared.get("reason"))
	if not prepared.ok:return finish()
	var opening:Dictionary=Profile15.prepare_opening(prepared.capture,"playtest")
	# Explicit finite end-of-early-game material fixture. Commands must still
	# withdraw and settle every material; no actor or order state is seeded.
	for actor:Dictionary in opening.facts.actors:
		if actor.id=="player":actor.pack.merge({"timber":48,"scrap":22,"log":9,"r34:salvaged_drive_unit":1},true)
	var host:=Native.new();var built:Dictionary=host._assemble(opening);host.free()
	check("production fixture mounts",built.get("ok",false),built.get("reason"))
	if not built.ok:return finish()
	var r:RefCounted=built.runtime;live15=r
	var modules:RefCounted=r._services.modules
	var warehouse:Dictionary=modules.instance(Warehouse17)
	var dest:String=warehouse.stock_refs.storage
	var pending:Dictionary=preload("res://scripts/modules/module_stock_policy.gd").filter_check(modules,dest,{"timber":1})
	check("ruins refuse warehouse deposits",pending.get("code")=="WAREHOUSE_RESTORATION_REQUIRED",pending)
	var paid:Dictionary=r.actor("player").pack.duplicate(true)
	var receipt:Dictionary=send(r,"module.restore",Warehouse17)
	check("real paid warehouse restoration begins",receipt.ok,receipt.get("reason"))
	if not receipt.ok:return finish()
	var work:Dictionary=progress(r,800)
	warehouse=modules.instance(Warehouse17)
	check("original site becomes usable after real work and exact material payment",work.finished and warehouse.restoration.completed and r.actor("player").pack.timber==paid.timber-8 and r.actor("player").pack.scrap==paid.scrap-2 and r.actor("player").pack.cloth==paid.cloth-1,warehouse.status)
	if not warehouse.restoration.completed:return finish()
	var hammer:String=opening.source.opening_configuration.tools.hammer
	var yard:=build17(r,Compact17.YARD,"compact17:test:yard",30,21,hammer)
	var saw:=build17(r,Compact17.SAWMILL,"compact17:test:saw",35,21,hammer)
	if yard.is_empty() or saw.is_empty():return finish()
	if not near_stock(r,yard.stock_refs.storage):return finish()
	check("yard takes physically delivered logs",send(r,"deposit",yard.stock_refs.storage,{"items":{"log":2}}).ok)
	if not near_stock(r,saw.stock_refs.fuel):return finish()
	check("saw consumes real fuel from its separate port",send(r,"deposit",saw.stock_refs.fuel,{"items":{"log":1}}).ok)
	if not transfer17(r,yard.stock_refs.storage,saw.stock_refs.input,"log",2):return finish()
	var order:Dictionary=send(r,"factory.configure",saw.id,{"recipe_id":"saw_timber","batches":2})
	check("compact mill accepts the real machine recipe",order.ok,order.get("reason"))
	if not order.ok:return finish()
	for step:int in 450:
		r.tick(.1)
		if r.stock(saw.stock_refs.output).items.get("timber",0)==8:break
	check("real two-batch machine output conserves input and fuel",r.stock(saw.stock_refs.output).items.get("timber",0)==8 and r.stock(saw.stock_refs.input).items.get("log",0)==0 and r.stock(saw.stock_refs.fuel).items.get("log",0)==0)
	if not transfer17(r,saw.stock_refs.output,dest,"timber",8):return finish()
	check("same production unlocks the radio gate",preload("res://scripts/runtime/village_progression.gd").radio_ready(r.world.extension("r34:gameplay")))
	var encoded:Dictionary=Store.encode(r.capture_checkpoint())
	if encoded.ok:FileAccess.open(outdir+"/working-street.native.json",FileAccess.WRITE).store_string(encoded.text)
	var decoded:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
	var cold:=Native.new();var loaded:Dictionary=cold._assemble(decoded.capture) if decoded.ok else decoded;cold.free()
	check("working street cold mounts with boards in real warehouse",loaded.get("ok",false) and loaded.runtime.stock(dest).items.get("timber",0)==8,loaded.get("reason"))
	if loaded.get("ok",false):loaded.runtime.retire()
	if not care(r,70) or not take_source(r,dest,{"timber":8}):return finish()
	var upgrade:Dictionary=send(r,"module.upgrade",Warehouse17,{"definition_id":Compact17.WAREHOUSE_UPGRADE,"source_id":"pack:player","tool_id":hammer})
	check("restored and emptied original warehouse accepts paid upgrade",upgrade.ok,upgrade.get("reason"))
	if not upgrade.ok:return finish()
	var worked:Dictionary=progress(r,1000)
	var saved:Dictionary=modules.instance(Warehouse17)
	check("warehouse upgrades in place and keeps its completed repair ledger",worked.finished and saved.definition_id==Compact17.WAREHOUSE_UPGRADE and saved.position==warehouse.position and saved.restoration.completed and saved.get("upgrades",[]).size()==1,saved.definition_id)
	if saved.definition_id!=Compact17.WAREHOUSE_UPGRADE:return finish()
	finished15=true
	finish()

func build17(r:RefCounted,definition:String,id:String,x:int,z:int,hammer:String)->Dictionary:
	if not care(r,75):return {}
	var at:Dictionary={"x":x,"z":z,"y":r.world.surface_height(x,z),"regionId":"RH-HOME"}
	var payload:Dictionary={"definition_id":definition,"position":at,"quarter_turn":0,"source_id":"pack:player","tool_id":hammer}
	var preview:Dictionary=r._services.modules.preview({"actor_id":"player","kind":"module.plan","target_id":id,"payload":payload})
	check("real build preview "+definition,preview.ok,preview.get("code"))
	if not preview.ok:return {}
	for port:Dictionary in preview.ports:
		if port.purpose not in ["work","repair","input"]:continue
		if not walk(r,port.location).get("ok",false):continue
		var plan:Dictionary=send(r,"module.plan",id,payload)
		check("starts paid construction "+definition,plan.ok,plan.get("reason"))
		if not plan.ok:return {}
		var done:Dictionary=progress(r,900)
		var built:Dictionary=r._services.modules.instance(id)
		check("real construction completes "+definition,done.finished and built.get("status")=="operational",built.get("status"))
		return built if built.get("status")=="operational" else {}
	check("real route reaches "+definition,false)
	return {}

func transfer17(r:RefCounted,source:String,destination:String,item:String,qty:int)->bool:
	var task:Dictionary=send(r,"logistics.create","",{"source_id":source,"destination_id":destination,"items":{item:qty},"repeat":false})
	check("queues work without teleporting "+item,task.ok and r.stock(destination).items.get(item,0)==0,task.get("reason"))
	if not task.ok:return false
	var workers:Dictionary={}
	for step:int in 1500:
		r.tick(.1)
		for row:Dictionary in r.world.extension("r34:logistics").tasks:
			if not row.actor_id.is_empty():workers[row.actor_id]=true
		if r.stock(destination).items.get(item,0)==qty:break
	var delivered:bool=not workers.is_empty() and not workers.has("player") and r.stock(destination).items.get(item,0)==qty and r.stock(source).items.get(item,0)==0
	check("companion physically transports "+item,delivered,{"actors":workers.keys(),"stock":r.stock(destination).items,"tasks":r.world.extension("r34:logistics").tasks})
	return delivered

func finish()->void:
	check("full compact production street settles",finished15)
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(outdir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed},"\t"))
	print(JSON.stringify({"suite":"compact-production17","checks":checks.size(),"failed":failed}))
	if live15!=null:live15.retire()
	quit(1 if failed else 0)
