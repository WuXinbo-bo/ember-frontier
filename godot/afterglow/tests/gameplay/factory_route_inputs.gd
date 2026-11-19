extends RefCounted
## Tests-only identity binding. Reads original module stock_refs, never edits facts.
const Data=preload("res://scripts/world/world_data.gd")
static func options()->Dictionary:
	var found:Dictionary={}
	for arg:String in OS.get_cmdline_user_args():
		if not arg.begins_with("--route-input="):continue
		if not found.is_empty():return {"error":"duplicate_route_input"}
		var path:String=arg.trim_prefix("--route-input=")
		var raw:String=FileAccess.get_file_as_string(path)
		var parsed:Variant=JSON.parse_string(raw)
		if not parsed is Dictionary:return {"error":"invalid_route_input"}
		found=parsed.duplicate(true);found.source_path=path;found.source_sha256=raw.sha256_text()
	return found
static func module_id(role:String)->String:
	var defaults:Dictionary={"machine":"r34:normal-built-woodshop","warehouse":"r34:normal-built-warehouse","home":"r34:generated:RH-HOME:home","store":"r34:generated:RH-VILLAGE:store"}
	return str(options().get(role+"_id",defaults.get(role,"")))
static func stock(runtime:RefCounted,role:String,buffer:String)->String:
	var module:Dictionary=runtime._services.modules.instance(module_id(role))
	return str(module.get("stock_refs",{}).get(buffer,""))
static func validate(runtime:RefCounted)->Dictionary:
	var config:Dictionary=options()
	if config.has("error"):return {"ok":false,"reason":config.error}
	var refs:Dictionary={}
	for spec:Array in [["machine","input"],["machine","fuel"],["machine","output"],["warehouse","storage"],["home","supplies"],["store","supplies"]]:
		var id:String=stock(runtime,spec[0],spec[1]);var value:Dictionary=runtime.stock(id)
		if id.is_empty() or value.is_empty():return {"ok":false,"reason":"missing_live_module_stock","role":spec[0],"buffer":spec[1],"module_id":module_id(spec[0])}
		refs[spec[0]+":"+spec[1]]=id
	for role:String in ["machine","warehouse"]:
		var module:Dictionary=runtime._services.modules.instance(module_id(role))
		if module.get("status")!="operational":return {"ok":false,"reason":"module_not_operational","role":role,"module":module}
	return {"ok":true,"config":config,"refs":refs}
