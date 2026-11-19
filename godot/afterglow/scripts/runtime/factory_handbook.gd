extends RefCounted
## On-demand definition/relationship projection. No clock, inventory, recipe,
## discovery authority or background poll. Owners still validate every action.
const Data=preload("res://scripts/world/world_data.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")
const Definitions=preload("res://scripts/runtime/factory_definitions.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const Regional=preload("res://scripts/runtime/factory_regional_handbook.gd")
const SCHEMA:="afterglow-factory-handbook-v1"
const KNOWLEDGE_NAMES:={"basic_woodwork":"基础木工","basic_tool_repair":"基础工具维修"}
const TERRAIN_NAMES:={"grass":"草覆土","soil":"普通土","stone":"岩石","road":"压实路面","bedrock":"受保护基底","gravel":"碎石"}

static func empty()->Dictionary:
	return {"schema":SCHEMA,"version":1,"available":false,"world_id":"","runtime_revision":0,"sections":[],"categories":[],"entries":[],"selection":{},"preferences":{"favorites":[],"tracked_target":""}}

static func _entry(id:String,source_id:String,kind:String,category:String,section:String,name:String,definition:Dictionary={},description:String="")->Dictionary:
	return {"id":id,"source_id":source_id,"kind":kind,"category_id":category,"section_id":section,"name":name,"description":description,"definition":definition.duplicate(true),"discovered":false,"learned":null,"related_ids":[],"sources":[],"uses":[]}

static func build(host:RefCounted,actor_id:String,entry_id:String,services:Dictionary,catalog:Dictionary)->Dictionary:
	var result:Dictionary=empty()
	if actor_id!="player" or host.actor(actor_id).is_empty():return result
	var public:Dictionary=host.factory_snapshot(actor_id,false)
	if not public.get("available",false):return result
	var production:Variant=services.get("production")
	var buildings:Variant=services.get("buildings")
	if production==null or buildings==null:return result
	var content:Dictionary=Definitions.catalog()
	result.available=true;result.world_id=public.world_id;result.runtime_revision=public.runtime_revision
	result.sections=content.handbook_sections.duplicate(true);result.categories=content.categories.duplicate(true)
	var display:Variant=services.get("display")
	if display!=null:result.preferences=preferences(display.state())
	var stocks:Array=_stocks(host,production,services.modules,public,actor_id)
	var observed:Dictionary=production.state()
	var tools:Array=[];var records:Array=[]
	for tool:Dictionary in observed.get("tools",[]):
		if _has_stock(stocks,str(tool.get("holderId",""))):
			var row:Dictionary=tool.duplicate(true);row.reserved=production.tool_unavailable(str(tool.id))
			row.onsite=_stock(stocks,str(tool.holderId)).get("onsite",false);tools.append(row)
	for record:Dictionary in observed.get("records",[]):
		if _has_stock(stocks,str(record.get("holderId",""))):records.append(record.duplicate(true))
	var learned:Array=observed.get("knowledge",{}).get(actor_id,[])
	var entries:Dictionary={}
	for item_id:String in Content.item_definitions():
		var definition:Dictionary=Content.item_definition(item_id)
		var row:Dictionary=_entry("item:"+item_id,item_id,"item","material_part","materials",str(definition.name),definition,str(definition.get("description","")))
		row.discovered=stocks.any(func(stock:Dictionary)->bool:return stock.items.has(item_id));entries[row.id]=row
	for kind:String in catalog.get("tool_definitions",{}):
		var definition:Dictionary=catalog.tool_definitions[kind]
		var row:Dictionary=_entry("tool:"+kind,kind,"tool","tool_equipment","tools",str(definition.get("name",kind)),definition)
		row.definition.legacy=kind=="legacy_tool"
		row.discovered=tools.any(func(t:Dictionary)->bool:return t.get("kind")==kind)
		entries[row.id]=row
	for material:int in Data.MATERIALS:
		if material==0:continue
		var definition:Dictionary=Data.MATERIALS[material].duplicate(true);definition.material_id=material
		var row:Dictionary=_entry("terrain:"+str(definition.key),str(definition.key),"terrain","terrain_resource","sources",str(TERRAIN_NAMES.get(definition.key,definition.key)),definition,"地形修改与经济提取沿真实工具、保护基底和支撑规则；数量以实际作业结果为准。")
		row.discovered=_near_material(host,material)
		entries[row.id]=row
	var search:Dictionary=_entry("source:search","search","source","terrain_resource","sources","搜索现存物资",{},"真实到达并搜索容器；首次内容持久，取走不刷新。只显示已经搜索且有权查看的物资。")
	search.discovered=stocks.size()>1;entries[search.id]=search
	var trees:Dictionary=_entry("source:trees","harvest","source","terrain_resource","sources","采伐与树旁搬运",{},"用真实采伐工具作业，产物先落树旁容器，再真实搬回。可在林区采种、育苗与补种，生长遵同一世界时钟和实际地面条件；没有规划半径自动产木。")
	var tree_items:Dictionary={}
	# Only public type relationships leave this scan: never tree IDs, positions,
	# counts, remaining yields or future resource destinations.
	for entity:Dictionary in host.world.entities():
		if entity.get("kind")!="tree":continue
		for item_id:String in entity.get("data",{}).get("harvest",{}).get("yield",{}):tree_items[item_id]=true
		if Geometry.point(host.actor(actor_id)).distance_to(Geometry.point(entity))<=6.0 and buildings.current_space().line_clear(Geometry.location(host.actor(actor_id)),Geometry.location(entity),str(entity.id)):trees.discovered=true
	entries[trees.id]=trees
	var regional_cards:Array=Regional.cards() if services.get("ecology")!=null else []
	for card:Dictionary in regional_cards:
		var row:Dictionary=_entry(card.id,card.source_id,card.kind,card.category_id,card.section_id,card.name,card.definition,card.description)
		row.discovered=true;entries[row.id]=row
	for definition:Dictionary in public.modules.get("definitions",[]):
		var category:String="machine_facility" if definition.get("recipe_modes",[]).has("machine") else "module"
		var row:Dictionary=_entry("module:"+str(definition.id),str(definition.id),"module",category,"modules",str(definition.name),definition)
		row.discovered=public.modules.instances.any(func(m:Dictionary)->bool:return m.definition_id==definition.id)
		entries[row.id]=row
	for source:Dictionary in production.recipes.values():
		var definition:Dictionary=source.duplicate(true);definition.mode="manual"
		_add_process(entries,definition,learned)
	for source:Dictionary in public.production.get("recipes",[]):_add_process(entries,source,learned)
	for row:Dictionary in entries.values().duplicate():
		if row.kind!="process":continue
		for knowledge_id:String in row.definition.get("knowledge",[]):
			var id:String="knowledge:"+knowledge_id
			if not entries.has(id):
				var knowledge:Dictionary=_entry(id,knowledge_id,"knowledge","knowledge_recipe","knowledge",str(KNOWLEDGE_NAMES.get(knowledge_id,knowledge_id)))
				knowledge.discovered=true;knowledge.learned=learned.has(knowledge_id);entries[id]=knowledge
	# Compatibility objects are documented, never offered as new modular homes.
	for key:String in ["cabinet","workbench","yard_wall","entry_step"]:
		var definition:Dictionary=catalog.get("structure_definitions",{}).get(key,{})
		if definition.is_empty():continue
		var category:String="outdoor_segment" if key in ["yard_wall","entry_step"] else "module"
		var row:Dictionary=_entry("legacy:"+key,key,"legacy",category,"modules",str(definition.get("name",key)),definition,"特殊地点／旧档兼容对象，不代表新世界默认开放逐墙住宅建设。")
		row.definition.legacy=true;row.discovered=false;entries[row.id]=row
	for row:Dictionary in entries.values():
		if row.kind=="process":
			for item_id:String in row.definition.get("inputs",{}):_connect(entries,"item:"+item_id,row.id,"加工投入")
			for item_id:String in row.definition.get("outputs",{}):_connect(entries,row.id,"item:"+item_id,"加工产出")
			for knowledge_id:String in row.definition.get("knowledge",[]):_connect(entries,"knowledge:"+knowledge_id,row.id,"所需知识")
			for kind:String in catalog.get("tool_definitions",{}):
				if _qualities(catalog.tool_definitions[kind].get("qualities",{}),row.definition.get("qualities",{})) and not row.definition.get("qualities",{}).is_empty():_connect(entries,"tool:"+kind,row.id,"作业工具")
			if row.definition.get("createTool") is Dictionary:_connect(entries,row.id,"tool:"+str(row.definition.createTool.kind),"装配工具")
			if row.definition.get("repairTool") is Dictionary:_connect(entries,row.id,"tool:"+str(row.definition.repairTool.kind),"维修工具")
			for definition:Dictionary in public.modules.get("definitions",[]):
				var v2:bool=row.definition.get("mechanism",{}).get("version")==2
				var supports:bool=definition.get("mechanism",{}).get("recipes",[]).has(row.source_id) if v2 else definition.get("recipe_modes",[]).has(str(row.definition.mode))
				if supports:_connect(entries,"module:"+str(definition.id),row.id,"加工宿主")
		elif row.kind=="module":
			for item_id:String in row.definition.get("build_cost",{}):_connect(entries,"item:"+item_id,row.id,"建设投入")
		elif row.kind=="terrain" and not str(row.definition.get("item","")).is_empty():_connect(entries,row.id,"item:"+str(row.definition.item),"实际地形作业")
	for item_id:String in tree_items:_connect(entries,trees.id,"item:"+item_id,"采伐来源")
	for card:Dictionary in regional_cards:
		for link:Array in card.links:
			if link[2]=="input":_connect(entries,str(link[0]),card.id,str(link[1]))
			else:_connect(entries,card.id,str(link[0]),str(link[1]))
	_connect(entries,"tool:salvaged_axe",trees.id,"采伐工具")
	for item_id:String in Content.item_definitions():
		if _amount(stocks,item_id,"actual")>0:_connect(entries,search.id,"item:"+item_id,"已知实物来源")
	for record:Dictionary in records:
		for knowledge_id:String in record.get("grants",[]):_connect(entries,"item:"+str(record.get("itemId","")),"knowledge:"+knowledge_id,"阅读实物学习")
	var sorted_ids:Array=entries.keys();sorted_ids.sort()
	for id:String in sorted_ids:result.entries.append(entries[id])
	if entries.has(entry_id):
		result.selection=entries[entry_id].duplicate(true)
		result.selection.current=_current(host,production,buildings,actor_id,result.selection,public,stocks,tools,records)
	return result.duplicate(true)

static func preferences(value:Dictionary)->Dictionary:
	return value.get("handbook",{"favorites":[],"tracked_target":""}).duplicate(true)

static func _add_process(entries:Dictionary,definition:Dictionary,learned:Array)->void:
	# B intentionally reuses saw_timber for manual and machine execution. Keep
	# its action ID intact while giving the two handbook conditions distinct IDs.
	var row:Dictionary=_entry("process:"+str(definition.get("mode","manual"))+":"+str(definition.id),str(definition.id),"process","knowledge_recipe","processes",str(definition.get("name",definition.id)),definition)
	row.discovered=true;row.learned=definition.get("knowledge",[]).all(func(k:String)->bool:return learned.has(k))
	entries[row.id]=row

static func _connect(entries:Dictionary,from:String,to:String,label:String)->void:
	if not entries.has(from) or not entries.has(to):return
	if not entries[from].uses.any(func(r:Dictionary)->bool:return r.id==to and r.relation==label):entries[from].uses.append({"id":to,"label":entries[to].name,"relation":label})
	if not entries[to].sources.any(func(r:Dictionary)->bool:return r.id==from and r.relation==label):entries[to].sources.append({"id":from,"label":entries[from].name,"relation":label})
	if not entries[from].related_ids.has(to):entries[from].related_ids.append(to)
	if not entries[to].related_ids.has(from):entries[to].related_ids.append(from)

static func _stocks(host:RefCounted,production:RefCounted,modules:RefCounted,public:Dictionary,actor_id:String)->Array:
	var ids:Dictionary={"pack:"+actor_id:true}
	for module:Dictionary in public.modules.get("instances",[]):
		for buffer_id:String in module.get("stock_refs",{}):
			if module.get("stock_visibility",{}).get(buffer_id,false):ids[str(module.stock_refs[buffer_id])]=true
	# Searched legacy cupboards, stockyards and actual dropped goods retain
	# their existing owner permission. Never bypass module discovery with this
	# path, or add NPC packs/cargo a second time to material availability.
	var actor:Dictionary=host.actor(actor_id)
	for stock:Dictionary in host.facts().get("stocks",[]):
		if stock.has("module_id") or not stock.get("searched",false):continue
		if modules.permitted(actor,stock.get("owner")):ids[str(stock.id)]=true
	# Reuse one detached owner hold projection for this synchronous read. Calling
	# reserved() per SKU would rebuild the same full hold list dozens of times.
	var holds:Array=production.all_holds()
	var result:Array=[]
	for id:String in ids:
		var source:Dictionary=host.stock(id)
		if source.is_empty() or not source.get("searched",false):continue
		var row:Dictionary={"id":id,"onsite":production.reach(actor_id,id,source,"stock")==null,"items":{}}
		for item_id:String in source.get("items",{}):
			var actual:float=float(source.items[item_id]);var reserved:float=0.0
			for hold:Dictionary in holds:
				if hold.source_id==id:reserved+=float(hold.get("cost",{}).get(item_id,0))
			row.items[item_id]={"actual":actual,"reserved":reserved,"free":maxf(0.0,actual-reserved)}
		result.append(row)
	return result

static func _stock(stocks:Array,id:String)->Dictionary:
	for row:Dictionary in stocks:
		if row.id==id:return row
	return {}
static func _has_stock(stocks:Array,id:String)->bool:return not _stock(stocks,id).is_empty()
static func _amount(stocks:Array,item_id:String,field:String,onsite:bool=false)->float:
	var result:float=0.0
	for row:Dictionary in stocks:
		if not onsite or row.onsite:result+=float(row.items.get(item_id,{}).get(field,0))
	return result
static func _qualities(have:Dictionary,need:Dictionary)->bool:
	for quality:String in need:
		if float(have.get(quality,0))<float(need[quality]):return false
	return true
static func _near_material(host:RefCounted,material:int)->bool:
	var player:Dictionary=host.actor("player");var cell:float=float(host.world.config().cellSize)
	var x:int=floori(float(player.x)/cell);var y:int=floori((float(player.y)-0.1)/cell);var z:int=floori(float(player.z)/cell)
	return host.world.is_cell_known(x,y,z) and host.world.cell_at(x,y,z)==material

static func _block(current:Dictionary,code:String,reason:String)->void:
	if not current.blockers.any(func(row:Dictionary)->bool:return row.code==code):current.blockers.append({"code":code,"reason":reason})

static func _current(host:RefCounted,production:RefCounted,buildings:RefCounted,actor_id:String,row:Dictionary,public:Dictionary,stocks:Array,tools:Array,records:Array)->Dictionary:
	var current:Dictionary={"can_make":null,"onsite":null,"blockers":[],"materials":[],"stocks":[],"tools":[],"known_instances":[]}
	var definition:Dictionary=row.definition
	var inputs:Dictionary=definition.get("build_cost",{}) if row.kind=="module" else definition.get("inputs",{})
	for item_id:String in inputs:
		var required:float=float(inputs[item_id]);var free:float=_amount(stocks,item_id,"free");var nearby:float=_amount(stocks,item_id,"free",true)
		current.materials.append({"item_id":item_id,"required":required,"known_free":free,"onsite_free":nearby,"missing":maxf(0.0,required-free),"onsite_missing":maxf(0.0,required-nearby)})
		# Machine WIP has already paid its inputs. Village totals are information,
		# never a replacement for the owner's local buffer/batch readiness.
		if definition.get("mode")!="machine":
			if free<required:_block(current,"MATERIAL_MISSING","已知且未预留的材料不足")
			elif nearby<required:_block(current,"MATERIAL_REMOTE","材料在已知远处，必须真实运到现场")
	if row.kind=="item":
		for stock:Dictionary in stocks:
			if stock.items.has(row.source_id):current.stocks.append({"id":stock.id,"onsite":stock.onsite,"quantity":stock.items[row.source_id].duplicate(true)})
		current.actual=_amount(stocks,row.source_id,"actual");current.reserved=_amount(stocks,row.source_id,"reserved");current.free=_amount(stocks,row.source_id,"free");current.onsite_free=_amount(stocks,row.source_id,"free",true)
	elif row.kind=="tool":
		current.tools=tools.filter(func(t:Dictionary)->bool:return t.get("kind")==row.source_id).duplicate(true)
		current.onsite=current.tools.any(func(t:Dictionary)->bool:return t.onsite and not t.reserved and float(t.get("durability",0))>0)
		if not current.onsite:_block(current,"TOOL_UNAVAILABLE","现场没有未占用且完好的同一身份工具")
	elif row.kind=="module":
		current.known_instances=public.modules.instances.filter(func(m:Dictionary)->bool:return m.definition_id==row.source_id).duplicate(true)
		_block(current,"CHOOSE_SITE","建设还须真实选址、服务面、权限和原施工预检；本页不承诺可落地")
	elif row.kind=="process":
		if not row.learned:_block(current,"KNOWLEDGE_MISSING","尚未学习本工艺所需知识")
		if definition.get("mode")=="machine":
			_machine_current(row,current,public,stocks)
		else:_manual_current(host,production,buildings,actor_id,row,current,stocks,tools,public)
	elif row.kind=="knowledge":
		current.learned=row.learned
		for record:Dictionary in records:
			if record.get("grants",[]).has(row.source_id):current.known_instances.append(record.duplicate(true))
		if not row.learned and current.known_instances.is_empty():_block(current,"RECORD_MISSING","没有已知可阅读实物；书名和收藏不等于掌握知识")
	elif row.kind=="legacy":
		current.can_make=false;_block(current,"LEGACY_CONTENT","特殊地点／旧档兼容对象；默认建设请使用完整模块目录")
	return current

static func _machine_current(row:Dictionary,current:Dictionary,public:Dictionary,stocks:Array)->void:
	current.onsite=false;current.can_make=false;current.orders=[]
	for module:Dictionary in public.modules.instances:
		var d:Dictionary={}
		for candidate:Dictionary in public.modules.definitions:
			if candidate.id==module.definition_id:d=candidate;break
		if not d.get("recipe_modes",[]).has("machine"):continue
		current.known_instances.append(module.duplicate(true))
		for stock_id:String in module.get("stock_refs",{}).values():
			if _stock(stocks,stock_id).get("onsite",false):current.onsite=true
		# A module's generic running badge may belong to another recipe. Read
		# only the selected process's exact public order and its owner blockers.
		for order:Dictionary in public.production.get("orders",[]):
			if order.module_id!=module.id or order.get("recipe_id")!=row.source_id:continue
			current.orders.append(order.duplicate(true))
			if order.get("state_code") in ["idle","running"] and order.get("blockers",[]).is_empty():current.can_make=true
	if current.known_instances.is_empty():_block(current,"HOST_MISSING","没有已发现且有权的独立机器")
	elif current.orders.is_empty():_block(current,"MACHINE_NOT_CONFIGURED","没有已配置本工艺的机器订单；设备运行标记不等于本工艺可运行")
	elif not current.can_make:
		for order:Dictionary in current.orders:
			for code:String in order.get("blockers",[]):_block(current,code,"机器当前状态："+code)
	current.scope_note="当前可运行仅指本工艺已配置订单的真实状态。机器使用自身输入、输出容量与燃料，材料总量不代表本机可开批；加工只转换材料，不再生自然资源。"

static func _manual_current(host:RefCounted,production:RefCounted,buildings:RefCounted,actor_id:String,row:Dictionary,current:Dictionary,stocks:Array,tools:Array,public:Dictionary)->void:
	var definition:Dictionary=row.definition
	current.can_make=false;current.onsite=false
	var tool_ids:Array=[]
	for tool:Dictionary in tools:
		if tool.onsite and not tool.reserved and float(tool.get("durability",0))>0:tool_ids.append(tool.id)
	current.tools=tools.filter(func(t:Dictionary)->bool:return _qualities(production.tool_qualities(t),definition.get("qualities",{}))).duplicate(true)
	var onsite_stations:Array=[]
	var mechanism_v2:bool=definition.get("mechanism",{}).get("version")==2
	if mechanism_v2:
		# An empty legacy stationTags list does not make every old workbench a
		# water/canteen/artisan host. Definitions and visible instances are B's.
		for module:Dictionary in public.modules.get("instances",[]):
			var module_definition:Dictionary={}
			for candidate:Dictionary in public.modules.get("definitions",[]):
				if candidate.id==module.definition_id:module_definition=candidate;break
			if not module_definition.get("mechanism",{}).get("recipes",[]).has(row.source_id):continue
			onsite_stations.append(module.id);current.known_instances.append(module.duplicate(true))
	# B's existing current-space query is the authority for usable legacy work
	# stations, including module adapters. No second station registry.
	if not mechanism_v2:
		for instance:Dictionary in buildings.current_space().by_id.values():
			var d:Dictionary=buildings.geometry.definition(instance)
			if not definition.get("stationTags",[]).all(func(tag:String)->bool:return d.get("stationTags",[]).has(tag)):continue
			if buildings.can_use(actor_id,instance)==null:onsite_stations.append(instance.id)
	if onsite_stations.is_empty():_block(current,"STATION_REMOTE","需要已发现且具备本工艺能力的真实建筑或工作台");return
	current.onsite=not mechanism_v2
	var last:Dictionary={}
	for station_id:String in onsite_stations:
		for source:Dictionary in stocks:
			if not source.onsite:continue
			for destination:Dictionary in stocks:
				if not destination.onsite:continue
				var payload:Dictionary={"recipe_id":row.source_id,"source_id":source.id,"output_id":destination.id,"tool_ids":tool_ids}
				if mechanism_v2:payload.direct=true
				if definition.has("repairTool"):
					var target:Dictionary={}
					for candidate:Dictionary in tools:
						if candidate.get("kind")==definition.repairTool.kind and candidate.onsite and not candidate.reserved and float(candidate.durability)<float(production.tool_definition(candidate).get("maxDurability",100)):target=candidate;break
					if target.is_empty():_block(current,"REPAIR_TARGET_MISSING","需要现场实际受损的同一工具");return
					payload.repair_tool_id=target.id;payload.tool_ids=tool_ids.filter(func(id:String)->bool:return id!=target.id)
				last=host.availability({"actor_id":actor_id,"kind":"craft","target_id":station_id,"payload":payload})
				if last.get("ok",false):
					current.can_make=true;current.onsite=true;current.blockers=[];current.request={"kind":"craft","target_id":station_id,"payload":payload};return
	if not last.is_empty():_block(current,str(last.get("code","UNAVAILABLE")),str(last.get("reason","现场条件尚未满足")))
