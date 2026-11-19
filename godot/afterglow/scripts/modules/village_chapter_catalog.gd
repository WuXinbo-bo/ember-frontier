extends RefCounted
## Additive definition identities keep the saved geometry locks immutable.
const Families=preload("res://scripts/modules/village_family_catalog.gd")
const PREFIX="r40.module."
const HOME=PREFIX+"home"
const WORKSHOP=PREFIX+"workshop"
const WAREHOUSE=PREFIX+"warehouse"
const STARTER_ITEMS={"r34:potato_seed":2,"r34:water_bucket":1}
const SALVAGE_ITEMS={"scrap":8,"cloth":4}

static func id_for(previous:String)->String:
	return PREFIX+previous.trim_prefix(Families.PREFIX) if previous.begins_with(Families.PREFIX) else previous

static func derive(rows:Array)->Array:
	var result:Array=[]
	for base:Dictionary in rows:
		if not str(base.id).begins_with(Families.PREFIX):continue
		var d:=base.duplicate(true)
		d.id=id_for(str(base.id));d.design_id=d.id;d.geometry_version=d.id+".geometry-v1";d.chapter_geometry=true
		d.mechanism.upgrade_to=base.mechanism.upgrade_to.map(func(id:String)->String:return id_for(id))
		if d.id==WORKSHOP:
			for b:Dictionary in d.buffer_specs:
				if b.id=="tools":
					for item:String in STARTER_ITEMS:b.limits[item]=STARTER_ITEMS[item]*4
		result.append(d)
	return result
