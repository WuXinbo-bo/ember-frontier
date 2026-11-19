extends "res://tests/gameplay/factory_survival.gd"
## Observe exactly one installed advance, at its real clock and movement budget.
const Gameplay=preload("res://scripts/runtime/factory_gameplay.gd")
class Observer extends "res://scripts/runtime/settlement_workforce.gd":
	var last_plan:Dictionary={}
	var calls:int=0
	func advance(dt:float)->Dictionary:
		calls+=1;last_plan=super.advance(dt);return last_plan
var fields:Dictionary={}
var components:Dictionary={}
func add_cost(key:String,started:int)->void:
	components[key]=int(components.get(key,0))+Time.get_ticks_usec()-started
func changed_paths(before:Variant,after:Variant,prefix:String="")->Array:
	if Data.json_equal(before,after):return []
	var result:Array=[]
	if before is Dictionary and after is Dictionary:
		for key:Variant in before:
			if not after.has(key):result.append(prefix+str(key))
		for key:Variant in after:
			if not before.has(key):result.append(prefix+str(key))
			else:result.append_array(changed_paths(before[key],after[key],prefix+str(key)+"."))
	else:result.append(prefix.trim_suffix("."))
	return result
func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output);host=Native.new()
	var profiles:Dictionary=Assembly.generation_profiles()
	var opening:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles))
	if not mount(opening.capture):return finish()
	var observer:=Observer.new()
	observer.configure(runtime._context.merged({"runtime":runtime,"services":runtime._services,"spatial":runtime._services.buildings},true))
	runtime._services.workforce=observer
	var samples:Array=[];var changed:int=0;var empty:int=0;var moving:int=0
	for i:int in 600:
		runtime.tick(0.1)
		var plan:Dictionary=observer.last_plan
		var rows:Array=[]
		var step_moved:bool=false
		for change:Dictionary in plan.fact_changes:
			var paths:Array=changed_paths(change.before,change.after)
			for path:String in paths:
				var key:String=str(change.collection)+"/"+str(change.id)+"/"+path;fields[key]=int(fields.get(key,0))+1
				if change.collection=="actors" and path in ["x","y","z","regionId"]:step_moved=true
			rows.append({"collection":change.collection,"id":change.id,"fields":paths})
		for change:Dictionary in plan.world_changes:rows.append({"extension":change.id,"fields":changed_paths(change.before,change.after)})
		if rows.is_empty():empty+=1
		else:changed+=1
		if step_moved:moving+=1
		if samples.size()<12 and not rows.is_empty():samples.append({"clock":runtime.clock(),"changes":rows})
	check("observer invokes original workforce exactly once per real fixed step",observer.calls==600)
	var control:Dictionary=host._assemble(opening.capture)
	if control.ok:
		for i:int in 600:control.runtime.tick(0.1)
	check("single-call observation preserves complete unobserved authority",control.ok and Data.json_equal(runtime.capture_checkpoint(),control.runtime.capture_checkpoint()))
	check("six hundred full fixed steps preserve time and all three identities",absf(runtime.clock()-60)<1e-9 and runtime.facts().actors.size()==3)
	FileAccess.open(output+"/changes.json",FileAccess.WRITE).store_string(JSON.stringify({"changed_steps":changed,"empty_steps":empty,"moving_steps":moving,"field_counts":fields,"first_samples":samples,"installed_costs":runtime.simulation_costs(),"scope":"Single installed advance return observer; exact final capture compared with unobserved control. Diagnostic overhead excluded from budget or FPS claims."},"\t",true,true))
	finish()
