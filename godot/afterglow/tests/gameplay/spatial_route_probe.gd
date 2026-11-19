extends "res://tests/gameplay/generated_cooperation.gd"
## Only diagnostic inheritance: the original Runtime commit executes unchanged.
## Failure snapshots belong to this isolated test, never the running user world.
class DiagnosticRuntime:
	extends "res://scripts/runtime/game_runtime.gd"
	var diagnostics_dir:String
	var rejections:Array=[]
	func _commit(prepared:Dictionary)->Dictionary:
		var result:Dictionary=super._commit(prepared)
		if not result.ok and rejections.size()<4:
			var name:String="rejection-"+str(rejections.size()+1)+".json"
			var file:=FileAccess.open(diagnostics_dir+"/"+name,FileAccess.WRITE)
			# Rejected commits have not changed authoritative facts/world. Keep
			# exact original CAS before-images and complete proposed changes.
			file.store_string(JSON.stringify({"result":result,"prepared":prepared,"capture":capture_checkpoint()},"\t",true,true));file.close()
			rejections.append({"result":result,"time":clock(),"snapshot":name})
		return result

func mount(capture:Dictionary)->bool:
	if not super.mount(capture):return false
	var saved:Dictionary=runtime.capture_checkpoint()
	var diagnostic:=DiagnosticRuntime.new();diagnostic.diagnostics_dir=output_dir
	var ready:Dictionary=diagnostic.configure(host._context(runtime.world,runtime._services,saved.facts,saved.get("source",{}),int(saved.get("command_revision",0)),saved.get("receipts",{})))
	check("isolated diagnostic binds the same services and original A runtime",ready.ok,ready.get("reason"))
	if not ready.ok:return false
	runtime=diagnostic
	return true

func run()->void:
	output_dir=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output_dir)
	evidence_kind="same-seed-original-B-route-with-original-A-commit-failure-capture-not-OS-replay"
	host=Client.new()
	var generated:Dictionary=Assembly.prepare(Assembly.generate(973339546,Building.generation_profiles()))
	check("native-warning seed assembles real generated routes",generated.ok,generated.get("reason"))
	if not generated.ok:finish();return
	var start:Dictionary={"x":9.19477134058252,"y":1.0,"z":12.0184513521381,"regionId":"RH-HOME","buildingId":"RH-HOME:shed","storeyId":"RH-HOME:shed:ground"}
	var destination:Dictionary={"x":17.110546369935,"y":2.5,"z":-49.6824738486903,"regionId":"RH-VILLAGE","buildingId":"RH-VILLAGE:neighbor","storeyId":"RH-VILLAGE:neighbor:ground"}
	for a:Dictionary in generated.capture.facts.actors:
		if a.id=="player":a.merge(start,true);a.intent=null
	if not mount(generated.capture):finish();return
	check("actual log shed sample is supported in isolated fresh geometry",not runtime._services.buildings.current_space().standing_point(start).is_empty())
	if walk(destination,"original B route goes shed to actual neighbor log sample"):
		walk(start,"same original B route returns to shed through actual shared boundary")
	check("this isolated command route has no rejected original runtime commit",runtime.rejections.is_empty(),runtime.rejections)
	write_json("diagnostic.json",{"scope":"fresh seed973339546 normal B command route and A ticks; not native user path/door/edit-state replay","seed":973339546,"start_log_sample":start,"end_log_sample":destination,"ticks":ticks,"rejections":runtime.rejections})
	finish()
