extends "res://tests/modules/run_service_approaches.gd"
## Same-process public entry comparison; no tick scheduling or renderer claim.
const Probe=preload("res://tests/modules/alert_projection_probe.gd")
func read_full(services:Dictionary)->void:
	services.modules.projection();services.production.factory_projection();services.production.logistics_projection()
func read_slim(services:Dictionary)->void:
	services.modules.alert_projection();services.production.alert_projection()
func stats(samples:Array)->Dictionary:
	var ordered:Array=samples.duplicate();ordered.sort();var total:int=0
	for value:int in ordered:total+=value
	return {"queries":ordered.size(),"mean_usec":float(total)/ordered.size(),"p50_usec":ordered[int(ordered.size()*0.5)],"p95_usec":ordered[mini(ordered.size()-1,ceili(ordered.size()*0.95)-1)],"max_usec":ordered[-1]}
func run()->void:
	var samples:Array=[]
	for seed:int in [713,2026]:
		var made:Dictionary=Assembly.prepare(Assembly.generate(seed,Modules.generation_profiles()))
		var host:=Native.new();var built:Dictionary=host._assemble(made.capture) if made.ok else made
		check("real normal opening "+str(seed),built.ok)
		if not built.ok:host.free();continue
		var rt:RefCounted=built.runtime;var services:Dictionary=built.services
		var before:Dictionary=rt.capture_checkpoint();var start:int=Time.get_ticks_usec();read_full(services)
		var first_full:int=Time.get_ticks_usec()-start;start=Time.get_ticks_usec();read_slim(services)
		var first_slim:int=Time.get_ticks_usec()-start
		var damaged:Dictionary=rt._commit(services.modules.prepare_damage("r34:generated:RH-HOME:home",10,"B:cost:damage"))
		check("actual committed damaged source is present "+str(seed),damaged.ok and services.modules.alert_projection().alerts.any(func(v:Dictionary)->bool:return v.reason_code=="damaged"))
		before=rt.capture_checkpoint();var full:Array=[];var slim:Array=[]
		for i:int in 100:
			# Alternate order so the old reader does not always pay first.
			if i%2==0:
				start=Time.get_ticks_usec();read_full(services);full.append(Time.get_ticks_usec()-start)
				start=Time.get_ticks_usec();read_slim(services);slim.append(Time.get_ticks_usec()-start)
			else:
				start=Time.get_ticks_usec();read_slim(services);slim.append(Time.get_ticks_usec()-start)
				start=Time.get_ticks_usec();read_full(services);full.append(Time.get_ticks_usec()-start)
		check("same real alerts detached and read-only "+str(seed),Probe.inspect(rt,services).ok and Data.json_equal(before,rt.capture_checkpoint()))
		samples.append({"seed":seed,"module_instances":services.modules.state().instances.size(),"factory_orders":services.production.factory_projection().orders.size(),"first_full_usec":first_full,"first_slim_usec":first_slim,"full":stats(full),"slim":stats(slim)})
		host.free()
	var ok:bool=checks.all(func(c:Dictionary)->bool:return c.ok)
	print(JSON.stringify({"ok":ok,"checks":checks,"samples":samples,"scope":"same process normal initial modules with real committed damage, alternating 100 owner read calls, no active machine orders, no renderer/FPS or total tick budget claim"}));quit(0 if ok else 1)
