extends RefCounted
## Planning vocabulary only. Resources, labor and growth remain domain facts.
const KINDS := {
	"forestry":{"name":"林业区","description":"成熟采伐、育苗补种与木材取送"},
	"farm":{"name":"种植区","description":"整地、播种、照料、收获与留种"},
	"forage":{"name":"采集区","description":"采集范围内实际存在的资源"},
	"stockpile":{"name":"堆场","description":"分类接收与取送实际物资"},
	"clear":{"name":"清理区","description":"清理草木、树桩和废料"},
	"terrain":{"name":"地形工程区","description":"付出劳动和土石完成挖填"},
	"patrol":{"name":"巡逻区","description":"安排真实巡视和警戒"}}
const MAX_ZONES := 128
const MAX_ZONE_CELLS := 1024
const MAX_ORDER_CELLS := 4096
const MAX_ORDER_REGIONS := 4
const MAX_ORDER_TARGETS := 256
const MAX_TOTAL_CELLS := 32768
const MAX_COORD := 1048576
const POLICY_FIELDS := ["crop_id","tree_id","replant","mature_only","conserve","priority","target_stock_id","target_height","mode","reserve_seed","target_quantity","enabled","source_stock_id","water_stock_id","worker_ids","item_ids","fill_material","standing_order"]
const BOOL_FIELDS := ["replant","mature_only","conserve","enabled","standing_order"]
const NUMBER_FIELDS := ["target_height","reserve_seed","target_quantity"]

static func number(value:Variant)->bool:
	return (value is int or value is float) and is_finite(float(value))

static func integer(value:Variant)->bool:
	return value is int or (value is float and is_finite(value) and value==floorf(value))

static func cell_key(cell:Dictionary)->String:
	return "%d:%d:%d"%[int(cell.x),int(cell.y),int(cell.z)]

static func valid_cell(value:Variant)->bool:
	if not value is Dictionary or not value.has_all(["x","y","z"]):return false
	for key:String in ["x","y","z"]:
		var coordinate:Variant=value[key]
		# Most in-memory plans contain integers; JSON restores contain floats.
		# Keep both exact domains, including all finite/integral/range checks,
		# without repeated Variant-to-float calls on every cell coordinate.
		if coordinate is int:
			if coordinate < -MAX_COORD or coordinate > MAX_COORD:return false
		elif coordinate is float:
			if not is_finite(coordinate) or coordinate < -MAX_COORD or coordinate > MAX_COORD or coordinate!=floorf(coordinate):return false
		else:return false
	return true

static func bounds_check(value:Variant,limit:int=MAX_ZONE_CELLS)->Dictionary:
	if not value is Dictionary or not value.has_all(["x0","z0","x1","z1"]):return bad("INVALID_ZONE_BOUNDS","请在同一地区拖出有效区域")
	for key:String in ["x0","z0","x1","z1"]:
		if not integer(value[key]) or absi(int(value[key]))>MAX_COORD:return bad("INVALID_ZONE_BOUNDS","区域边界必须是有效地形格")
	var width:int=int(value.x1)-int(value.x0)
	var depth:int=int(value.z1)-int(value.z0)
	if width<=0 or depth<=0:return bad("EMPTY_ZONE","请拖出至少一格区域")
	if width>limit or depth>limit or width*depth>limit:return bad("ZONE_TOO_LARGE","范围最多 %d 格，请缩小框选范围" % limit)
	return {"ok":true,"code":"OK","cell_count":width*depth}

static func target_mode(spec:Dictionary)->String:
	var policy:Variant=spec.get("policy",{})
	if not policy is Dictionary:return ""
	var mode:String=str(policy.get("mode",""))
	if (spec.get("kind")=="forestry" and mode=="harvest_only") or (spec.get("kind")=="stockpile" and mode=="collect_ground"):return mode
	return ""

static func contains_xz(bounds:Dictionary,at:Dictionary,size:float)->bool:
	if not at.has_all(["x","z"]):return false
	var x:int=floori(float(at.x)/size);var z:int=floori(float(at.z)/size)
	return x>=int(bounds.x0) and x<int(bounds.x1) and z>=int(bounds.z0) and z<int(bounds.z1)

static func policy_check(value:Variant)->Dictionary:
	if not value is Dictionary:return bad("INVALID_ZONE_POLICY","作业策略格式无效")
	for raw_key:Variant in value:
		# GDScript dot assignment can add a StringName key. The save codec
		# round-trips it as a String, so validate both against the same names.
		if not (raw_key is String or raw_key is StringName):return bad("INVALID_ZONE_POLICY","未识别的区域策略")
		var key:=str(raw_key)
		if not POLICY_FIELDS.has(key):return bad("INVALID_ZONE_POLICY","未识别的区域策略")
		var v:Variant=value[raw_key]
		if BOOL_FIELDS.has(key):
			if not v is bool:return bad("INVALID_ZONE_POLICY","区域开关必须明确启用或关闭")
		elif NUMBER_FIELDS.has(key):
			if not number(v) or absf(float(v))>1000000 or (key!="target_height" and float(v)<0):return bad("INVALID_ZONE_POLICY","数量或目标高度无效")
		elif key=="fill_material":
			if not integer(v) or int(v) not in [2,3,6]:return bad("INVALID_ZONE_POLICY","填料须选择土、石或沙")
		elif key=="priority":
			if not integer(v) or int(v)<0 or int(v)>5:return bad("INVALID_ZONE_POLICY","工作优先级须为0至5")
		elif key in ["worker_ids","item_ids"]:
			if not v is Array or v.size()>64:return bad("INVALID_ZONE_POLICY","人员或物品筛选过多")
			for id:Variant in v:
				if not id is String or id.is_empty() or id.length()>128:return bad("INVALID_ZONE_POLICY","人员或物品标识无效")
		elif not v is String or v.length()>128:return bad("INVALID_ZONE_POLICY","区域策略标识无效")
	return {"ok":true,"code":"OK"}

static func defaults(kind:String)->Dictionary:
	var result:Dictionary={"priority":2}
	if kind=="forestry":result.merge({"mode":"sustainable","replant":true,"mature_only":true})
	if kind=="farm":result.merge({"replant":true,"reserve_seed":1})
	return result

static func bad(code:String,reason:String)->Dictionary:
	return {"ok":false,"code":code,"reason":reason,"world_changes":[],"fact_changes":[],"events":[]}
