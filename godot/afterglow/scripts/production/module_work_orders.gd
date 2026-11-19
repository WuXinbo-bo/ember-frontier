extends RefCounted
## Management requests are not material holds or a second production ledger.
## Each admitted batch is an ORIGINAL craft order and settles only in Production.
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Factory=preload("res://scripts/production/factory_kernel.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Recipes=preload("res://scripts/production/module_recipes.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Data=preload("res://scripts/world/world_data.gd")
const PREFIX="module-recipe:"
static func rows(m:Dictionary)->Array:return m.get("config",{}).get("recipe_orders",[])
static func requested(o:Dictionary,r:Dictionary,host:RefCounted,tx:RefCounted,excluding:String="")->bool:
	if o.paused:return false
	if o.mode=="quantity":return int(o.completed)<int(o.quantity)
	if o.mode=="continuous":return true
	var stock:Dictionary=tx.stock(str(o.output_id));var promised:float=host.capacity_reserved(str(o.output_id),str(o.target_item),excluding,tx)
	return float(stock.get("items",{}).get(o.target_item,0))+promised+float(r.outputs.get(o.target_item,0))<=float(o.target_quantity)+.000001
static func prepare(host:RefCounted,request:Dictionary)->Dictionary:
	var tx:=Draft.new(host.context);var a:=tx.actor(str(request.get("actor_id","")));var state:Dictionary=tx.extension("r34:modules",{"version":1,"instances":[],"projects":[],"source_receipts":{},"next_id":1});var m:=Draft.find(state.instances,str(request.get("target_id","")))
	if a.get("id")!="player" or float(a.get("hp",0))<=0 or m.is_empty() or not m.get("discovered",false) or not Factory.permitted(a,m.owner):return Data.reject("MODULE_RECIPE_PERMISSION")
	var d:=Catalog.definition_view(str(m.definition_id));var payload:Dictionary=request.get("payload",{});var recipe_id:String=str(payload.get("recipe_id",""));var recipe:Dictionary=host.recipes.get(recipe_id,{})
	if d.get("mechanism",{}).get("version")!=2:return Data.reject("MODULE_RECIPE_NOT_SUPPORTED")
	if not m.config.has("recipe_orders"):m.config.recipe_orders=[]
	var id:String=str(payload.get("order_id",str(m.id)+":"+recipe_id));var o:=Draft.find(m.config.recipe_orders,id)
	if request.kind=="module.recipe.configure":
		if recipe.is_empty() or not d.mechanism.recipes.has(recipe_id):return Data.reject("MODULE_RECIPE_NOT_ALLOWED")
		var mode:Variant=payload.get("mode","quantity");var quantity:Variant=payload.get("quantity",1)
		if mode not in ["quantity","target","continuous"] or not Data.integer(quantity) or quantity<1 or quantity>100000:return Data.reject("INVALID_RECIPE_ORDER")
		var source_id:String=str(payload.get("source_id",m.stock_refs.get("input",m.stock_refs.get("tools",m.stock_refs.get("supplies","")))));var output_id:String=str(payload.get("output_id",m.stock_refs.get("output",m.stock_refs.get("supplies",""))))
		for sid:String in [source_id,output_id]:
			var stock:=tx.stock(sid)
			if stock.is_empty() or not stock.get("searched",true) or not Factory.permitted(a,stock.get("owner")):return Data.reject("RECIPE_STOCK_PERMISSION")
		var target_item:String=str(payload.get("target_item",recipe.outputs.keys()[0] if not recipe.outputs.is_empty() else ""));var target:Variant=payload.get("target_quantity",quantity)
		if mode=="target" and (not recipe.outputs.has(target_item) or not Data.integer(target) or target<=0):return Data.reject("INVALID_RECIPE_TARGET")
		if tx.extension(host.KEY,host.empty_state()).orders.any(func(v:Dictionary)->bool:return host.active(v) and v.get("module_program_id")==id):return Data.reject("RECIPE_BATCH_IN_PROGRESS")
		if o.is_empty():
			if m.config.recipe_orders.size()>=16:return Data.reject("RECIPE_ORDER_LIMIT")
			o={"id":id};m.config.recipe_orders.append(o)
		var revision:int=int(o.get("revision",0))+1
		o.merge({"recipe_id":recipe_id,"mode":mode,"quantity":int(quantity),"completed":0,"target_item":target_item,"target_quantity":target,"source_id":source_id,"output_id":output_id,"repair_tool_id":payload.get("repair_tool_id"),"paused":false,"revision":revision,"created_at":float(host.context.clock.call())},true)
	elif request.kind in ["module.recipe.pause","module.recipe.resume","module.recipe.cancel"]:
		if o.is_empty():return Data.reject("RECIPE_ORDER_MISSING")
		o.paused=request.kind!="module.recipe.resume"
	else:return Data.reject("UNKNOWN_RECIPE_COMMAND")
	tx.events.append({"kind":"module-recipe-request","module_id":m.id,"order_id":id,"operation":request.kind});return tx.result()
static func validate(m:Dictionary,d:Dictionary)->Dictionary:
	if not m.get("config",{}).get("recipe_orders",[]) is Array or rows(m).size()>16:return Data.reject("INVALID_RECIPE_ORDERS")
	var seen:Dictionary={}
	for o:Variant in rows(m):
		if not o is Dictionary or not Data.valid_id(o.get("id")) or seen.has(o.id) or not d.get("mechanism",{}).get("recipes",[]).has(o.get("recipe_id")) or o.get("mode") not in ["quantity","target","continuous"] or not o.get("paused") is bool:return Data.reject("INVALID_RECIPE_ORDER")
		seen[o.id]=true
		for field:String in ["quantity","completed","revision"]:
			if not Data.integer(o.get(field)) or o[field]<0:return Data.reject("INVALID_RECIPE_ORDER")
		if o.quantity<1 or o.revision<1 or not Data.valid_id(o.get("source_id")) or not Data.valid_id(o.get("output_id")):return Data.reject("INVALID_RECIPE_ORDER")
	return {"ok":true,"code":"OK"}
static func program_problem(host:RefCounted,tx:RefCounted,o:Dictionary)->Variant:
	if not o.has("module_program_id"):return null
	var m:=Recipes.module(host,str(o.stationId),tx);var program:=Draft.find(rows(m),str(o.module_program_id))
	if program.is_empty() or program.paused or program.recipe_id!=o.targetId or program.revision!=o.get("module_program_revision") or program.source_id!=o.sourceId or program.output_id!=o.outputId:return "实际建筑订单已暂停或更改"
	var recipe:Dictionary=host.recipes.get(str(o.targetId),{})
	if recipe.is_empty() or not requested(program,recipe,host,tx,str(o.id)):return "实际建筑订单已满足数量或库存目标"
	var production:Dictionary=tx.extension(host.KEY,host.empty_state())
	if production.orders.any(func(other:Dictionary)->bool:return other.id!=o.id and host.active(other) and other.get("module_program_id")==program.id):return "该建筑订单已有实际批次"
	return null
static func completed(host:RefCounted,tx:RefCounted,o:Dictionary)->void:
	if not o.has("module_program_id"):return
	var m:=Recipes.module(host,str(o.stationId),tx);var program:=Draft.find(rows(m),str(o.module_program_id))
	if not program.is_empty() and program.revision==o.get("module_program_revision"):program.completed=int(program.completed)+1
static func candidates(actions:RefCounted,a:Dictionary,tx:RefCounted,only_id:String="")->Array:
	var host:RefCounted=actions.production;var state:Dictionary=Factory.modules(host,tx);var result:Array=[]
	if not actions.hold_actor(a):return result
	var production:Dictionary=tx.extension(host.KEY,host.empty_state())
	for m:Dictionary in state.instances:
		if not m.get("discovered",false) or not Factory.permitted(a,m.owner):continue
		if only_id.is_empty() and m.region!=G.location(a).regionId:continue
		if not only_id.is_empty() and actions.context.get("region_is_detailed") is Callable and not actions.context.region_is_detailed.call(str(m.region)):continue
		for o:Dictionary in rows(m):
			if only_id.is_empty() and o.get("construction_supply",false):continue
			if not only_id.is_empty() and PREFIX+str(o.id)!=only_id:continue
			var r:Dictionary=host.recipes.get(o.recipe_id,{})
			if r.is_empty() or not requested(o,r,host,tx):continue
			var reason:String="";var command:Dictionary={};var at:Dictionary={}
			if production.orders.any(func(v:Dictionary)->bool:return host.active(v) and v.get("stationId")==m.id):reason="worker_occupied"
			if reason.is_empty():
				# Borrow immutable stocks/world; copy only actor and production before
				# exercising the SAME admission at each actual service point.
				for point:Dictionary in Recipes.points(host,str(m.id)):
					var probe:=Draft.new();probe.context=tx.context;probe.staged=tx.staged.duplicate();probe.staged.actors=tx.staged.actors.duplicate();probe.initial=probe.staged;probe.extensions=tx.extensions.duplicate();probe.extensions[host.KEY]=production.duplicate(true)
					var pa:=a.duplicate(true);actions.set_location(pa,point);pa.intent=null
					for i:int in probe.staged.actors.size():
						if probe.staged.actors[i].id==a.id:probe.staged.actors[i]=pa;break
					var tools:Array=[]
					for t:Dictionary in production.tools:
						if t.id==o.repair_tool_id or float(t.durability)<=0 or host.tool_unavailable(str(t.id),"",probe):continue
						if host.reach(str(a.id),str(t.holderId),probe.stock(str(t.holderId)),"stock",probe)==null:tools.append(t.id)
					var request:Dictionary={"kind":"craft","actor_id":a.id,"target_id":m.id,"command_id":"probe:"+str(o.id),"payload":{"recipe_id":o.recipe_id,"source_id":o.source_id,"output_id":o.output_id,"tool_ids":tools,"repair_tool_id":o.repair_tool_id,"direct":false,"module_program_id":o.id,"module_program_revision":o.revision}}
					var admission:Dictionary=host.start(probe,request)
					if admission.ok:command=request;at=point.duplicate(true);break
					reason=str(admission.get("reason",admission.get("code","blocked")))
				if not command.is_empty():reason=""
				elif reason.is_empty():reason="no_supported_workpoint"
			result.append({"id":PREFIX+str(o.id),"actor_id":a.id,"kind":"craft","valid":reason.is_empty(),"reason":reason,"carrying":false,"player_priority":0.0,"wait_seconds":maxf(0,float(host.context.clock.call())-float(o.created_at)),"route_cost":G.point(G.location(a)).distance_to(G.point(at)) if not at.is_empty() else 0,"unblocks_output":false,"critical_supply":false,"module_id":m.id,"recipe_id":r.id,"order_id":o.id,"command":command,"location":at})
	return result
static func projection(m:Dictionary,host:RefCounted)->Dictionary:
	var d:=Catalog.definition_view(str(m.definition_id));var recipes:Array=[]
	for id:String in d.get("mechanism",{}).get("recipes",[]):
		if host.recipes.has(id):recipes.append(host.recipes[id].duplicate(true))
	return {"orders":rows(m).duplicate(true),"recipes":recipes,"modes":["quantity","target","continuous"],"quantity_unit":"batches","target_unit":"item native unit; output batch never overshoots target"}
