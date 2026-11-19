extends RefCounted

const NAMES=["旧村安顿","生产街","区域供应"]

static func read(world:RefCounted)->Dictionary:
	var fields:Array[String]=["flags"]
	var state:Variant=world.extension_fields("r34:gameplay",fields) if world.has_method("extension_fields") else world.extension("r34:gameplay")
	return from_flags(state.get("flags",{}) if state is Dictionary else {})

static func from_flags(flags:Dictionary)->Dictionary:
	var missing:Array=[]
	if not flags.get("village_home_restored",false):missing.append("修好旧宅")
	if not flags.get("village_warehouse_restored",false):missing.append("修好仓棚")
	if not missing.is_empty():return {"level":1,"name":NAMES[0],"next":NAMES[1],"missing":missing}
	if not flags.get("real_machine_output",false):missing.append("完成一次机器生产")
	if not flags.get("village_radio_connected",false):missing.append("修好电台并发报")
	return {"level":3,"name":NAMES[2],"next":"","missing":[]} if missing.is_empty() else {"level":2,"name":NAMES[1],"next":NAMES[2],"missing":missing}

static func reason(world:RefCounted,definition:Dictionary)->String:
	var required:int=int(definition.get("village_stage_required",0))
	if required<=1:return ""
	var current:=read(world)
	if int(current.level)>=required:return ""
	return "需要进入「%s」：%s"%[NAMES[required-1],"、".join(current.missing)]
