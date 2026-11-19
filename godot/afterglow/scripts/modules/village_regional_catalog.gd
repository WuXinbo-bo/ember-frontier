extends RefCounted

const FRAME="r39.module.heritage_mill"
const STORE="r39.module.roadside_store"
const HOME="r39.module.roadside_home"
const SHED="r39.module.field_depot"
const VARIANTS={
	"r34.module.fuel_woodshop":[FRAME,"旧锯木站","原址修复后，把原木和燃料变成板材"],
	"r34.module.supply_rear_v3":[STORE,"路边补给站","临路面接洽，物资在背面的卸货区取用"],
	"r34.module.home_roadside_v3":[HOME,"乡道住宅","邻村住宅和生活物资交接点"],
	"r34.module.warehouse_long_v3":[SHED,"田边仓棚","邻近田地和乡路的存放点"]
}

static func id_for(old_id:String,content_version:int)->String:
	return VARIANTS[old_id][0] if content_version>=19 and VARIANTS.has(old_id) else old_id

static func derive(rows:Array)->Array:
	var result:Array=[]
	for source:Dictionary in rows:
		if not VARIANTS.has(source.id):continue
		var spec:Array=VARIANTS[source.id];var d:=source.duplicate(true)
		for key:String in ["design_id","geometry_source_id","architecture"]:d.erase(key)
		d.id=spec[0];d.geometry_version=d.id+".geometry-v1";d.design_id=d.id
		d.name=spec[1];d.village_role=spec[2];d.regional_art=true;d.opening_only=true;d.visual_family="old-village"
		if d.id==FRAME:d.machine_work_point=[0,1.02,-.70]
		result.append(d)
	return result
