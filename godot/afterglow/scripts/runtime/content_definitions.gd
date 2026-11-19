extends RefCounted
## Immutable existing-content descriptors. Queries return detached values.
## Unknown legacy inventory IDs retain their old representation only when the
## caller explicitly permits it; formal catalog references must resolve.
const VERSION:=1
const FactoryDefinitions=preload("res://scripts/runtime/factory_definitions.gd")
const ITEMS:Dictionary={
	"food":{"name":"食物","unit":"count","step":1.0,"stackable":true},
	"water":{"name":"饮水","unit":"count","step":1.0,"stackable":true},
	"medicine":{"name":"医疗包","unit":"count","step":1.0,"stackable":true},
	"timber":{"name":"木料","unit":"count","step":1.0,"stackable":true},
	"log":{"name":"原木","unit":"count","step":1.0,"stackable":true},
	"scrap":{"name":"废料","unit":"count","step":1.0,"stackable":true},
	"cloth":{"name":"布料","unit":"count","step":1.0,"stackable":true},
	"tool_handle":{"name":"工具柄","unit":"count","step":1.0,"stackable":true},
	"axe_head":{"name":"斧头金属头","unit":"count","step":1.0,"stackable":true},
	"brace":{"name":"回收支架","unit":"count","step":1.0,"stackable":true},
	"knowledge":{"name":"资料","unit":"count","step":1.0,"stackable":true},
	"manual_woodwork":{"name":"木工手册","unit":"count","step":1.0,"stackable":true},
	"manual_tool_repair":{"name":"维修手册","unit":"count","step":1.0,"stackable":true},
	"book_woodwork":{"name":"木工手册","unit":"count","step":1.0,"stackable":true},
	"book_tool_repair":{"name":"维修手册","unit":"count","step":1.0,"stackable":true},
	"soil_m3":{"name":"土方","unit":"m3","step":0.001,"stackable":true},
	"stone_m3":{"name":"石方","unit":"m3","step":0.001,"stackable":true},
	"gravel_m3":{"name":"碎石","unit":"m3","step":0.001,"stackable":true}
}
const BODY:Dictionary={"id":"human-default-v1","radius":0.26,"height":1.8,"max_step":0.55}

static func item_definition(id:String)->Dictionary:
	if not ITEMS.has(id):return FactoryDefinitions.item_definition(id)
	var result:Dictionary=ITEMS[id].duplicate(true)
	result.id=id;result.schema_version=VERSION
	return result

static func item_definitions()->Dictionary:
	var result:Dictionary={}
	for id:String in ITEMS:result[id]=item_definition(id)
	for id:String in FactoryDefinitions.item_ids():result[id]=item_definition(id)
	return result

static func consumable_definition(id:String,kind:String="")->Dictionary:
	# Keep legacy descriptors/hashes untouched while offering one additive API.
	var legacy:Dictionary={"food":{"kind":"eat","restore":35.0,"duration":1.3},"water":{"kind":"drink","restore":45.0,"duration":1.3},"medicine":{"kind":"medicine","restore":30.0,"duration":1.3}}
	var value:Variant=legacy.get(id)
	if value==null:value=item_definition(id).get("consumable")
	if not value is Dictionary or value.get("kind") not in ["eat","drink","medicine"] or (not kind.is_empty() and value.kind!=kind):return {}
	if not (value.get("restore") is int or value.get("restore") is float) or not is_finite(float(value.restore)) or float(value.restore)<=0 or float(value.restore)>100:return {}
	if not (value.get("duration") is int or value.get("duration") is float) or not is_finite(float(value.duration)) or float(value.duration)<=0:return {}
	var result:Dictionary=value.duplicate(true);result.item_id=id
	return result

static func quantity_step(id:String,allow_legacy:bool=false)->float:
	if ITEMS.has(id):return float(ITEMS[id].step)
	var added:Dictionary=FactoryDefinitions.item_definition(id)
	if not added.is_empty():return float(added.step)
	# Explicit old-save adapter, never used to resolve a formal definition.
	return (0.001 if id.ends_with("_m3") else 1.0) if allow_legacy else 0.0

static func quantity_valid(id:String,value:Variant,allow_legacy:bool=false)->bool:
	if not (value is int or value is float) or not is_finite(float(value)) or float(value)<0:return false
	var step:float=quantity_step(id,allow_legacy)
	if step<=0:return false
	if step==1.0:return float(value)==floorf(float(value))
	# Existing terrain yields fractional cell volumes (0.125m3). Retain old
	# finite m3 quantities exactly; step is the transfer/UI minimum increment,
	# not permission to round or destroy historical stock.
	return true

static func body_definition(id:String)->Dictionary:
	return BODY.duplicate(true) if id==BODY.id else {}

static func actor_effects(actor:Dictionary)->Dictionary:
	var skills:Variant=actor.get("skills",{})
	return {"stamina_max":maxf(25.0,100.0-float(actor.get("fatigue",0))*0.45),"skills":skills.duplicate(true) if skills is Dictionary else {},"labor_multiplier":1.0,"recovery_multiplier":1.0}

static func content_lock()->Dictionary:
	var items:Dictionary={}
	for id:String in item_definitions():items[id]=JSON.stringify(item_definition(id),"",true,true).sha256_text()
	return {"schema":"afterglow-runtime-content-v1","items":items,"bodies":{str(BODY.id):JSON.stringify(BODY,"",true,true).sha256_text()},"effects":"existing-life-v1"}

static func validate_lock(value:Variant)->Dictionary:
	# Older native captures have no core-content stamp. Adapt once on capture;
	# C's generation lock and B's geometry history remain separate authorities.
	if value is Dictionary and value.is_empty():return {"ok":true,"legacy":true}
	var current:Dictionary=content_lock()
	if not value is Dictionary or value.get("schema")!=current.schema or value.get("effects")!=current.effects:return {"ok":false,"code":"CONTENT_MIGRATION_REQUIRED","reason":"核心内容版本未知，须显式迁移，原档保留"}
	for field:String in ["items","bodies"]:
		if not value.get(field) is Dictionary:return {"ok":false,"code":"CONTENT_MIGRATION_REQUIRED","reason":"核心内容锁格式无效"}
		for id:Variant in value[field]:
			if not id is String or current[field].get(id)!=value[field][id]:return {"ok":false,"code":"CONTENT_MIGRATION_REQUIRED","reason":"已用内容定义变化或缺失："+str(id)}
	return {"ok":true,"legacy":false}

static func validate_catalog(catalog:Dictionary)->Dictionary:
	var factory:Dictionary=FactoryDefinitions.validation(ITEMS)
	if not factory.ok:return factory
	if not catalog.get("structure_definitions",{}) is Dictionary or not catalog.get("production_recipes",[]) is Array:return {"ok":false,"code":"INVALID_CONTENT_REFERENCE","reason":"正式内容目录类型无效"}
	for definition:Variant in catalog.get("structure_definitions",{}).values():
		if not definition is Dictionary:return {"ok":false,"code":"INVALID_CONTENT_REFERENCE","reason":"建筑定义须为对象"}
		for field:String in ["cost","salvage"]:
			if not definition.get(field,{}) is Dictionary:return {"ok":false,"code":"INVALID_CONTENT_REFERENCE","reason":"建筑物资表须为对象"}
			for id:String in definition.get(field,{}):
				if not quantity_valid(id,definition[field][id]):return {"ok":false,"code":"INVALID_CONTENT_REFERENCE","reason":"建筑物资定义无效："+str(definition.get("id",""))+"/"+id}
	for recipe:Variant in catalog.get("production_recipes",[]):
		if not recipe is Dictionary:return {"ok":false,"code":"INVALID_CONTENT_REFERENCE","reason":"配方定义须为对象"}
		for field:String in ["inputs","outputs"]:
			if not recipe.get(field,{}) is Dictionary:return {"ok":false,"code":"INVALID_CONTENT_REFERENCE","reason":"配方物资表须为对象"}
			for id:String in recipe.get(field,{}):
				if not quantity_valid(id,recipe[field][id]):return {"ok":false,"code":"INVALID_CONTENT_REFERENCE","reason":"配方物资定义无效："+str(recipe.get("id",""))+"/"+id}
	return {"ok":true,"code":"OK","schema_version":VERSION}
