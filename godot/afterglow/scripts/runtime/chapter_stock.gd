extends RefCounted

const Content=preload("res://scripts/runtime/content_definitions.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Factory=preload("res://scripts/production/factory_kernel.gd")
const StockPolicy=preload("res://scripts/modules/module_stock_policy.gd")

static func read(world:RefCounted,player:Dictionary,stocks:Array,actors:Array,production:Variant)->Dictionary:
	if production==null or not Factory.permitted(player,"home-residents"):return {"available":false,"rows":[]}
	var custody:Dictionary={}
	var blocked:Dictionary={}
	var fields:Array[String]=["instances"]
	for module:Dictionary in world.extension_fields("r34:modules",fields).get("instances",[]):
		var usable:bool=module.get("discovered",false) and module.get("status") in ["operational","damaged"] and Factory.permitted(player,module.get("owner"))
		if module.get("restoration") is Dictionary and not module.restoration.get("completed",false) and Catalog.definition_view(str(module.definition_id)).get("shape")=="warehouse":usable=false
		for buffer:String in module.get("stock_refs",{}):
			var id:String=str(module.stock_refs[buffer])
			if usable and module.get("owner")=="home-residents":
				custody[id]={"name":str(Catalog.definition_view(str(module.definition_id)).get("name","村庄设施"))+" · "+str({"input":"进料","output":"出料","tools":"工具台","storage":"储位","fuel":"燃料","supplies":"补给"}.get(buffer,"储位")),"reserve":StockPolicy.policy(module,buffer).get("reserve",{})}
			else:blocked[id]=true
	var held:Dictionary={}
	for hold:Dictionary in production.all_holds():
		var id:String=str(hold.get("source_id",""))
		if not held.has(id):held[id]={}
		for item:String in hold.get("cost",{}):held[id][item]=float(held[id].get(item,0))+float(hold.cost[item])
	var items:Dictionary={};var visible:Dictionary={}
	for stock:Dictionary in stocks:
		var id:String=str(stock.id)
		if blocked.has(id) or not stock.get("searched",false) or not (custody.has(id) or stock.get("owner")=="home-residents"):continue
		var entity:Dictionary=world.entity(id)
		if entity.get("data",{}).get("dropped",false):continue
		visible[id]=true
		var entry:Dictionary=custody.get(id,{})
		for item:String in stock.get("items",{}):
			var quantity:float=float(stock.items[item])
			if quantity<=0:continue
			var reserved:float=minf(quantity,float(held.get(id,{}).get(item,0)))
			var protected:float=minf(quantity-reserved,float(entry.get("reserve",{}).get(item,0)))
			var free:float=quantity-reserved-protected
			var row:=_item(items,item)
			row.total+=quantity;row.available+=free;row.reserved+=reserved;row.protected+=protected
			row.sources.append({"id":id,"name":entry.get("name","共享存放点"),"region_id":stock.get("location",stock).get("regionId",""),"quantity":quantity,"available":free,"reserved":reserved,"protected":protected})
	var workers:Dictionary={}
	for person:Dictionary in actors:workers[person.id]=person
	var task_fields:Array[String]=["tasks"]
	for task:Dictionary in world.extension_fields(Factory.LOGISTICS,task_fields).get("tasks",[]):
		if task.get("phase")!="deliver" or task.get("status") in ["completed","cancelled"] or not visible.has(task.get("destination_id")):continue
		var carrier:Dictionary=workers.get(task.get("actor_id"),{})
		if not Factory.permitted(carrier,"home-residents") or carrier.get("pending_delivery",{}).get("task_id")!=task.id:continue
		for item:String in task.get("items",{}):
			var amount:float=minf(float(task.items[item]),float(carrier.get("pack",{}).get(item,0)))
			if amount>0:_item(items,item).in_transit+=amount
	var ids:Array=items.keys();ids.sort()
	var rows:Array=[]
	for item:String in ids:rows.append(items[item])
	return {"available":true,"rows":rows}

static func _item(items:Dictionary,id:String)->Dictionary:
	if not items.has(id):items[id]={"item_id":id,"name":Content.item_definition(id).get("name",id),"total":0.0,"available":0.0,"reserved":0.0,"protected":0.0,"in_transit":0.0,"sources":[]}
	return items[id]
