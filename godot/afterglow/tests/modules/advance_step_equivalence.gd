extends SceneTree
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
var held:Array=[]
func _initialize()->void:call_deferred("run")
func digest(value:Variant)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(var_to_bytes(value));return hash.finish().hex_encode()
func mount(capture:Dictionary)->Dictionary:
	var native:=Native.new();var built:Dictionary=native._assemble(capture);native.free();return built
func run()->void:
	var args:=OS.get_cmdline_user_args();var output:String=args[0];var config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	var loaded:=Store.decode(FileAccess.get_file_as_string(args[1]));var built:=mount(loaded.capture) if loaded.get("ok",false) else loaded
	if not built.get("ok",false):printerr(built);quit(2);return
	var rt:RefCounted=built.runtime;var rows:Array=[];var cold:Array=[];var profiles:Array=[]
	for i:int in int(config.steps):
		var at:int=Time.get_ticks_usec();rt.tick(0.1);var elapsed:int=Time.get_ticks_usec()-at
		var plans:Dictionary={};var costs:Dictionary={}
		for id:String in ["actions","modules","production"]:
			plans[id]=digest(rt._services[id].b_plans);rt._services[id].b_plans.clear()
			costs[id]=rt._services[id].b_cost.duplicate(true);rt._services[id].b_cost.clear()
		rows.append({"step":i,"sha256":digest(rt.capture_checkpoint()),"plans":plans,"costs":costs,"tick_usec":elapsed})
		if i==int(config.get("cold_at",650)):
			profiles.append({"simulation":rt.simulation_costs(),"draft":Engine.get_meta("bbb_profile",{}).duplicate(true)});Engine.set_meta("bbb_profile",{})
			var encoded:=Store.encode(rt.capture_checkpoint());FileAccess.open(output+"/cold.native.json",FileAccess.WRITE).store_string(encoded.text)
			loaded=Store.decode(encoded.text);rt.retire();built=mount(loaded.capture) if loaded.get("ok",false) else loaded
			if not built.get("ok",false):printerr(built);quit(3);return
			rt=built.runtime;cold.append({"step":i,"mounted":digest(rt.capture_checkpoint()),"decoded":digest(loaded.capture)})
	profiles.append({"simulation":rt.simulation_costs(),"draft":Engine.get_meta("bbb_profile",{}).duplicate(true)})
	var final:=Store.encode(rt.capture_checkpoint());FileAccess.open(output+"/final.native.json",FileAccess.WRITE).store_string(final.text)
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"cold":cold,"profiles":profiles,"steps":rows.size(),"scope":"Same immutable21 plus explicit B/E overlays; complete lossless capture and B prepared plan SHA per fixed0.1 step; background diagnostic only"},"\t",true,true))
	rt.retire();print("B_ADVANCE_DONE");quit()
