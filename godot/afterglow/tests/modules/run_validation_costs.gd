extends "res://tests/modules/run_service_approaches.gd"
func summary(samples:Array)->Dictionary:
	var ordered:Array=samples.duplicate();ordered.sort();var total:int=0
	for value:int in ordered:total+=value
	return {"queries":ordered.size(),"mean_usec":float(total)/ordered.size(),"p50_usec":ordered[int(ordered.size()*0.5)],"p95_usec":ordered[ceili(ordered.size()*0.95)-1],"max_usec":ordered[-1]}
func run()->void:
	var samples:Array=[]
	for seed:int in [713,2026]:
		var made:Dictionary=Assembly.prepare(Assembly.generate(seed,Modules.generation_profiles()))
		var host:=Native.new();var built:Dictionary=host._assemble(made.capture) if made.ok else made
		check("real full-domain opening "+str(seed),built.ok)
		if not built.ok:host.free();continue
		var rt:RefCounted=built.runtime;var facts:Dictionary=rt.facts();var before:Dictionary=rt.capture_checkpoint()
		var module_times:Array=[];var production_times:Array=[];var valid:bool=true
		for i:int in 200:
			var start:int=Time.get_ticks_usec();var module_result:Dictionary=built.services.modules.validate_extensions(facts)
			module_times.append(Time.get_ticks_usec()-start);start=Time.get_ticks_usec()
			var production_result:Dictionary=built.services.production.validate_extensions(facts)
			production_times.append(Time.get_ticks_usec()-start);valid=valid and module_result.ok and production_result.ok
		check("all complete validators still execute without mutations "+str(seed),valid and Data.json_equal(before,rt.capture_checkpoint()))
		samples.append({"seed":seed,"instances":built.services.modules.state().instances.size(),"members":built.services.modules.state().instances.reduce(func(n:int,m:Dictionary)->int:return n+m.members.size(),0),"modules":summary(module_times),"production":summary(production_times)})
		host.free()
	var ok:bool=checks.all(func(c:Dictionary)->bool:return c.ok)
	print(JSON.stringify({"ok":ok,"checks":checks,"samples":samples,"scope":"full live owner validators, same normal initial four modules two seeds repeated200, no renderer/whole tick/active scale assertion"}));quit(0 if ok else 1)
