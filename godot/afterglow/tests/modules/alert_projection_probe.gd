extends RefCounted
## Shared assertions consume actual public owner projections, not private state.
const Data=preload("res://scripts/world/world_data.gd")
static func inspect(runtime:RefCounted,services:Dictionary,actor_id:String="player")->Dictionary:
	var before:Dictionary=runtime.capture_checkpoint()
	var full_modules:Dictionary=services.modules.projection(actor_id)
	var slim_modules:Dictionary=services.modules.alert_projection(actor_id)
	var factory:Dictionary=services.production.factory_projection(actor_id)
	var logistics:Dictionary=services.production.logistics_projection(actor_id)
	var expected:Array=factory.alerts.duplicate(true)
	for row:Dictionary in logistics.alerts:
		if not expected.has(row):expected.append(row)
	var slim_production:Dictionary=services.production.alert_projection(actor_id)
	var equal:bool=slim_modules=={"available":full_modules.available,"alerts":full_modules.alerts} and slim_production=={"available":bool(factory.available) or bool(logistics.available),"alerts":expected}
	var reasons:Array=[]
	for row:Dictionary in slim_modules.alerts+slim_production.alerts:
		if not reasons.has(row.reason_code):reasons.append(row.reason_code)
	# Caller edits nested rows, then fresh queries must be identical to full.
	for output:Dictionary in [slim_modules,slim_production]:
		if not output.alerts.is_empty():output.alerts[0].location.x=123456;output.alerts[0].title="caller edit"
		output.alerts.clear()
	var isolated:bool=services.modules.alert_projection(actor_id).alerts==full_modules.alerts and services.production.alert_projection(actor_id).alerts==expected
	return {"ok":equal and isolated and Data.json_equal(before,runtime.capture_checkpoint()),"reasons":reasons,"module_count":full_modules.alerts.size(),"production_count":expected.size(),"equal":equal,"isolated":isolated}
