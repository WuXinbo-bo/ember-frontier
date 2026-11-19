extends "res://tests/modules/run_logistics_recovery.gd"
const Probe=preload("res://tests/modules/alert_projection_probe.gd")
var mounted_services:Dictionary={}
var seen_reasons:Array=[]
var samples:int=0
func mount(capture:Dictionary)->Dictionary:
	var result:Dictionary=super.mount(capture)
	if result.ok:
		mounted_services[result.runtime.get_instance_id()]=result.services
		verify_alerts(result.runtime,"Native restore")
	return result
func command(rt:RefCounted,kind:String,target:String="",payload:Dictionary={})->Dictionary:
	var result:Dictionary=super.command(rt,kind,target,payload)
	verify_alerts(rt,kind)
	return result
func carried(rt:RefCounted)->bool:
	var result:bool=super.carried(rt);verify_alerts(rt,"actual pickup");return result
func deliver(rt:RefCounted)->void:
	super.deliver(rt);verify_alerts(rt,"actual delivery")
func verify_alerts(rt:RefCounted,label:String)->void:
	var services:Dictionary=mounted_services[rt.get_instance_id()];samples+=1
	var result:Dictionary=Probe.inspect(rt,services)
	check("logistics slim/full and isolated "+str(samples)+" "+label,result.ok,result)
	for reason:String in result.reasons:
		if not seen_reasons.has(reason):seen_reasons.append(reason)
	var denied:Dictionary=Probe.inspect(rt,services,"unknown-person")
	check("unknown actor has same empty alert surface "+str(samples),denied.ok and denied.module_count==0 and denied.production_count==0)
func finish()->void:
	check("actual carry cancel ruin retarget and delivery sampled",samples>=15 and seen_reasons.has("cancelled") and seen_reasons.has("target_ruined") and seen_reasons.has("ruined"),seen_reasons)
	super.finish()
