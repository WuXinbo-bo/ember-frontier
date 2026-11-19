extends "res://tests/modules/run_factory_lifecycle.gd"
const Probe=preload("res://tests/modules/alert_projection_probe.gd")
var seen_reasons:Array=[]
var sample_count:int=0
func advance(rt:RefCounted,services:Dictionary,steps:int,domain:String)->void:
	verify_alerts(rt,services,"before "+domain)
	super.advance(rt,services,steps,domain)
	verify_alerts(rt,services,"after "+domain)
func verify_alerts(rt:RefCounted,services:Dictionary,label:String)->void:
	sample_count+=1
	var result:Dictionary=Probe.inspect(rt,services)
	check("slim/full fact and copy equivalence "+str(sample_count)+" "+label,result.ok,result)
	for reason:String in result.reasons:
		if not seen_reasons.has(reason):seen_reasons.append(reason)
	for actor_id:String in ["unknown-person","repair-resident"]:
		var denied:Dictionary=Probe.inspect(rt,services,actor_id)
		check("same denied or unknown actor policy "+str(sample_count)+" "+actor_id,denied.ok and denied.module_count==0 and denied.production_count==0,denied)
func finish()->void:
	check("real lifecycle sampled construction pause machine and damage",sample_count>=15 and seen_reasons.has("paused") and seen_reasons.has("damaged") and seen_reasons.has("ruined"),seen_reasons)
	super.finish()
