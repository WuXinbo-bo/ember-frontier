extends RefCounted
## Fact projection only. A owns episode history, read/ignore and resolution.
const LABELS={"damaged":"建筑受损，需要现场维修","ruined":"建筑已毁，货物保留在残骸现场","missing_input":"缺少实际原料","missing_energy":"本地燃料不足","output_full":"输出容量已满","output_fault":"输出端不可用","region_paused":"区域暂停详细模拟","paused":"已暂停","unconfigured":"尚未配置生产","missing_tool":"缺少可用工具","operator_not_at_port":"施工人员需靠近建筑","site_material_or_tool_unreachable":"材料或工具在现场不可达","target_ruined":"运输端已损毁，携货需要改送","needs_retarget":"携货暂停，需要选择合法目的地","endpoint_missing":"运输端已不存在","cancelled":"运输已取消，携货保留在原人背包","BUFFER_FULL":"目的库存容量已满","BUFFER_FILTER":"目的库存不接收这种物品","permission":"作业权限不足","unsearched":"目标库存尚未搜索"}
static func row(id:String,reason:String,location:Dictionary,episode:String="")->Dictionary:
	var severity:String="critical" if reason=="ruined" else "danger" if reason in ["damaged","target_ruined","endpoint_missing"] else "info" if reason in ["paused","unconfigured","region_paused","safe_handoff"] else "warning"
	var label:String=str(LABELS.get(reason,"作业受阻："+reason))
	var value:Dictionary={"key":id+":"+reason,"object_id":id,"reason_code":reason,"severity":severity,"location":location.duplicate(true),"title":label,"detail":label}
	if not episode.is_empty():value.episode_id=episode
	return value
