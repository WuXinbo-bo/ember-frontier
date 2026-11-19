extends RefCounted
## Quantities remain in the one real stock. A policy is a spending floor or
## target, never a reservation pretending that more material exists.
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")
const Data=preload("res://scripts/world/world_data.gd")
const KEY="r34:modules"
static func policy(m:Dictionary,buffer:String)->Dictionary:return m.get("config",{}).get("stock_policies",{}).get(buffer,{"filter":[],"reserve":{},"target":{}})
static func locate(host:RefCounted,stock_id:String,tx:RefCounted=null)->Dictionary:
	var source:Variant=tx.extensions[KEY] if tx!=null and tx.extensions.has(KEY) else host.context.world.extension(KEY)
	for m:Dictionary in source.get("instances",[]) if source is Dictionary else []:
		for buffer:Variant in m.stock_refs:
			if m.stock_refs[buffer]==stock_id:return {"module":m,"buffer":str(buffer),"policy":policy(m,str(buffer))}
	return {}
static func floor_for(host:RefCounted,stock_id:String,item:String,tx:RefCounted=null)->float:
	var row:=locate(host,stock_id,tx)
	return float(row.get("policy",{}).get("reserve",{}).get(item,0))
static func filter_check(host:RefCounted,stock_id:String,items:Dictionary,tx:RefCounted=null)->Dictionary:
	var row:=locate(host,stock_id,tx)
	var m:Dictionary=row.get("module",{})
	if m.get("restoration") is Dictionary and not m.restoration.get("completed",false) and Catalog.definition_view(str(m.definition_id)).shape=="warehouse":return Data.reject("WAREHOUSE_RESTORATION_REQUIRED","先补齐仓棚屋面和承重货架")
	var selected:Array=row.get("policy",{}).get("filter",[])
	if not selected.is_empty():
		for item:String in items:
			if not selected.has(item):return Data.reject("STOCK_POLICY_FILTER","仓储分类不接收这项物资")
	return {"ok":true,"code":"OK"}
static func validate_policy(value:Variant,spec:Dictionary)->Dictionary:
	if not value is Dictionary or not value.get("filter") is Array or not value.get("reserve") is Dictionary or not value.get("target") is Dictionary:return Data.reject("INVALID_STOCK_POLICY")
	for key:Variant in value:
		if key not in ["filter","reserve","target"]:return Data.reject("INVALID_STOCK_POLICY")
	var seen:Dictionary={}
	for item:Variant in value.filter:
		if not item is String or not spec.limits.has(item) or seen.has(item):return Data.reject("INVALID_STOCK_FILTER")
		seen[item]=true
	for group:String in ["reserve","target"]:
		for item:Variant in value[group]:
			if not item is String or not spec.limits.has(item) or not Content.quantity_valid(item,value[group][item]) or float(value[group][item])>float(spec.limits[item]):return Data.reject("INVALID_STOCK_THRESHOLD")
	return {"ok":true,"code":"OK"}
static func prepare(host:RefCounted,request:Dictionary)->Dictionary:
	var tx:=Draft.new(host.context);var actor:Dictionary=tx.actor(str(request.get("actor_id","")))
	var source:Dictionary=tx.extension(KEY,host.initial());var m:=Draft.find(source.instances,str(request.get("target_id","")))
	if actor.get("id")!="player" or float(actor.get("hp",0))<=0 or m.is_empty() or not m.get("discovered",false) or not host.permitted(actor,m.owner):return Data.reject("STOCK_POLICY_PERMISSION")
	var d:=Catalog.definition_view(str(m.definition_id));var payload:Variant=request.get("payload",{})
	if d.get("mechanism",{}).get("version")!=2 or not payload is Dictionary:return Data.reject("STOCK_POLICY_NOT_SUPPORTED")
	var buffer:String=str(payload.get("buffer_id",""));var spec:=Draft.find(d.buffer_specs,buffer)
	var value:Variant=payload.get("policy")
	if spec.is_empty():return Data.reject("UNKNOWN_MODULE_BUFFER")
	var checked:=validate_policy(value,spec)
	if not checked.ok:return checked
	if not m.config.has("stock_policies"):m.config.stock_policies={}
	m.config.stock_policies[buffer]=value.duplicate(true)
	tx.events.append({"kind":"module-stock-policy","module_id":m.id,"buffer_id":buffer,"actor_id":actor.id})
	return tx.result()
static func validate(m:Dictionary,d:Dictionary)->Dictionary:
	var value:Variant=m.get("config",{}).get("stock_policies",{})
	if not value is Dictionary:return Data.reject("INVALID_STOCK_POLICY")
	for buffer:Variant in value:
		var spec:=Draft.find(d.buffer_specs,str(buffer))
		if spec.is_empty():return Data.reject("UNKNOWN_MODULE_BUFFER")
		var checked:=validate_policy(value[buffer],spec)
		if not checked.ok:return checked
	return {"ok":true,"code":"OK"}
static func projection(host:RefCounted,m:Dictionary,d:Dictionary,facts:Dictionary)->Array:
	var result:Array=[]
	for b:Dictionary in d.buffer_specs:
		var stock:=Draft.find(facts.get("stocks",[]),str(m.stock_refs[b.id]))
		if not stock.get("searched",true):continue
		var p:=policy(m,str(b.id));var rows:Array=[]
		for item:String in b.limits:
			var actual:float=float(stock.get("items",{}).get(item,0));var reserved:float=0
			if host._production!=null and host._production.get_ref()!=null:reserved=host._production.get_ref().reserved(str(stock.id),item)
			rows.append({"item_id":item,"unit":Content.item_definition(item).get("unit","count"),"onsite":actual,"reserved":reserved,"reserve_floor":float(p.reserve.get(item,0)),"target":float(p.target.get(item,0)),"available_for_work":maxf(0,actual-reserved-float(p.reserve.get(item,0))),"capacity":b.limits[item]})
		result.append({"buffer_id":b.id,"stock_id":m.stock_refs[b.id],"policy":p.duplicate(true),"items":rows})
	return result
