extends RefCounted
## Composition only. The existing Runtime remains the clock and commit owner.
const Contracts=preload("res://scripts/runtime/factory_contracts.gd")
const PATHS={"modules":"res://scripts/modules/module_service.gd","workforce":"res://scripts/runtime/settlement_workforce.gd","display":"res://scripts/runtime/factory_display.gd","zones":"res://scripts/planning/zone_service.gd","ecology":"res://scripts/ecology/ecology_service.gd","zonework":"res://scripts/planning/zone_work_service.gd"}
const REQUIRED=["configure","availability","prepare","advance","validate_extensions","hold_descriptors"]

static func required(capture:Dictionary)->bool:
	if capture.get("source",{}).get("scenario")==Contracts.SCENARIO or capture.get("facts",{}).get("scenario")==Contracts.SCENARIO:return true
	var extensions:Dictionary=capture.get("world",{}).get("extensions",{})
	for id:String in Contracts.EXTENSION_OWNERS:
		if extensions.has(id):return true
	return false

static func attach(services:Dictionary,capture:Dictionary)->Dictionary:
	var result:Dictionary=services.duplicate(false)
	if not required(capture):return {"ok":true,"services":result,"factory":false}
	for owner:String in PATHS:
		if result.get(owner)!=null:continue
		var path:String=PATHS[owner]
		if not ResourceLoader.exists(path):return _failure("MISSING_FACTORY_SERVICE","生产场景所需领域尚未交付："+owner)
		var script:Variant=load(path)
		if not script is GDScript or not script.can_instantiate():return _failure("INVALID_FACTORY_SERVICE","生产领域脚本尚未可用："+owner)
		var service:Variant=script.new()
		if not service is RefCounted:return _failure("INVALID_FACTORY_SERVICE","生产领域类型无效："+owner)
		# Ecology only prepares time/land changes; there is no direct resource
		# command route. B's timed zonework is its sole labor adapter.
		var required_methods:Array=["configure","advance","validate_extensions"] if owner=="ecology" else REQUIRED
		for method:String in required_methods:
			if not service.has_method(method):return _failure("MISSING_FACTORY_INTERFACE","生产领域缺少接口："+owner+"/"+method)
		result[owner]=service
	return {"ok":true,"services":result,"factory":true}

static func _failure(code:String,reason:String)->Dictionary:
	return {"ok":false,"code":code,"reason":reason}
