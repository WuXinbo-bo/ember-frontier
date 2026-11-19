extends "res://tests/gameplay/factory_alerts.gd"
## Compare the public full reader with the optional bounded reader on every
## original unknown/member/warning/blocked fixture, including changed facts.
var sample:int=0
var timings:Array=[]

func mount(capture:Dictionary)->bool:
	if not super.mount(capture):return false
	sample+=1
	var before:Dictionary=runtime.capture_checkpoint()
	var workforce:RefCounted=runtime._services.workforce
	for id:String in ["player","*","repair-resident","unknown"]:
		var full:Dictionary=workforce.projection(id)
		var compact:Dictionary=workforce.alert_projection(id)
		check("bounded alert reader equals original visibility and availability sample%d %s"%[sample,id],compact.keys().size()==2 and compact.available==full.available and Data.json_equal(compact.alerts,full.alerts))
		compact.alerts.append({"key":"untrusted:mutation"})
		if not full.alerts.is_empty():
			var changed:Dictionary=workforce.alert_projection(id)
			changed.alerts[0].location.x=99999
		check("bounded alerts are detached without changing risks bodies or clock sample%d %s"%[sample,id],Data.json_equal(workforce.alert_projection(id).alerts,full.alerts) and Data.json_equal(before,runtime.capture_checkpoint()))
	var started:int=Time.get_ticks_usec()
	for i in 10:workforce.projection("*")
	var full_us:int=Time.get_ticks_usec()-started
	started=Time.get_ticks_usec()
	for i in 10:workforce.alert_projection("*")
	timings.append({"sample":sample,"calls":10,"full_usec":full_us,"bounded_usec":Time.get_ticks_usec()-started,"scope":"diagnostic current headless reader only, no isolated performance qualification"})
	return true

func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"reader_timings":timings,"scope":"Same original alert fixtures and real Runtime configuration, compare full/bounded public reader including changed snapshots, permissions and detached copies. No alert lifecycle or second clock. Source-only, no final performance/OS/PCK qualification."},"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));host.free();quit(1 if failed else 0)
