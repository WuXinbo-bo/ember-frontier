extends RefCounted
## B-owned definition checks. Existing geometry/tags/usePoints are the actual
## capabilities; no parallel registry, inventory, or generated runtime state.
const Content=preload("res://scripts/runtime/content_definitions.gd")

static func bad(code:String,id:String)->Dictionary:
	return {"ok":false,"code":code,"reason":"建筑/工艺定义无法装配："+id}

static func number(v:Variant,positive:bool=false)->bool:
	return (v is int or v is float) and is_finite(float(v)) and (float(v)>0 if positive else float(v)>=0)

static func point(v:Variant)->bool:
	return v is Dictionary and ["x","y","z"].all(func(k:String)->bool:return (v.get(k) is int or v.get(k) is float) and is_finite(float(v[k])))

static func identities(v:Variant)->bool:
	return v is Array and v.all(func(id:Variant)->bool:return id is String and not id.is_empty())

static func validate(catalog:Dictionary,models:Dictionary)->Dictionary:
	if not catalog.get("structure_definitions") is Dictionary or not catalog.get("production_recipes") is Array or not catalog.get("tool_definitions") is Dictionary:return bad("INVALID_BUILDING_CONTENT","catalog")
	var tags:Dictionary={};var qualities:Dictionary={}
	for id:Variant in catalog.structure_definitions:
		var d:Variant=catalog.structure_definitions[id]
		if not d is Dictionary or d.get("id")!=id or not d.get("kind") is String or not d.get("cost") is Dictionary or not d.get("salvage") is Dictionary or not number(d.get("maxHp"),true) or not number(d.get("seconds"),true):return bad("INVALID_BUILDING_CONTENT",str(id))
		if not identities(d.get("stationTags",[])) or not d.get("usePoints") is Array or not d.usePoints.all(point):return bad("INVALID_BUILDING_USE_POINTS",str(id))
		if d.get("kind") in ["workbench","cabinet","door"] and d.usePoints.is_empty():return bad("MISSING_BUILDING_USE_POINT",str(id))
		for tag:String in d.get("stationTags",[]):
			if d.usePoints.is_empty():return bad("MISSING_BUILDING_USE_POINT",str(id))
			tags[tag]=true
		if d.get("kind") in ["workbench","cabinet"] and (not d.get("assetId") is String or not models.has(d.assetId)):return bad("MISSING_BUILDING_ASSET",str(id))
	for id:Variant in catalog.tool_definitions:
		var t:Variant=catalog.tool_definitions[id]
		if not t is Dictionary or not number(t.get("maxDurability"),true) or not t.get("qualities") is Dictionary:return bad("INVALID_TOOL_DEFINITION",str(id))
		for q:Variant in t.qualities:
			if not q is String or q.is_empty() or not number(t.qualities[q]):return bad("INVALID_TOOL_DEFINITION",str(id))
			qualities[q]=true
	var seen:Dictionary={}
	for recipe:Variant in catalog.production_recipes:
		if not recipe is Dictionary or not recipe.get("id") is String or recipe.id.is_empty() or seen.has(recipe.id):return bad("INVALID_RECIPE_DEFINITION","id")
		seen[recipe.id]=true
		if not recipe.get("inputs") is Dictionary or not recipe.get("outputs") is Dictionary or not identities(recipe.get("stationTags")) or not identities(recipe.get("knowledge")) or not recipe.get("qualities") is Dictionary:return bad("INVALID_RECIPE_DEFINITION",recipe.id)
		for field:String in ["seconds","staminaPerSecond","toolWear","minCrafting"]:
			if not number(recipe.get(field),field=="seconds"):return bad("INVALID_RECIPE_DEFINITION",recipe.id+"/"+field)
		for tag:String in recipe.stationTags:
			if not tags.has(tag):return bad("MISSING_STATION_CAPABILITY",recipe.id+"/"+tag)
		for q:Variant in recipe.qualities:
			if not qualities.has(q) or not number(recipe.qualities[q],true):return bad("MISSING_TOOL_CAPABILITY",recipe.id+"/"+str(q))
		for field:String in ["repairTool","createTool"]:
			if recipe.has(field) and (not recipe[field] is Dictionary or not catalog.tool_definitions.has(recipe[field].get("kind"))):return bad("INVALID_RECIPE_TOOL",recipe.id)
	return Content.validate_catalog(catalog)
