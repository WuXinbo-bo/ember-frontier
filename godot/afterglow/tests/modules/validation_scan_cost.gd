extends SceneTree
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func run()->void:
	var args:=OS.get_cmdline_user_args();var inputs:Array=[args[1]]
	if args.size()>4:inputs.append(args[4])
	var rows:Array=[]
	for path:String in inputs:
		var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(path));var h:=Native.new();var built:Dictionary=h._assemble(decoded.capture);h.free()
		checks.append({"name":"actual Native mounts "+path,"ok":built.get("ok",false)})
		if not built.get("ok",false):continue
		var rt:RefCounted=built.runtime;var module:RefCounted=built.services.modules;var facts:Dictionary=rt.facts();var state:Dictionary=module.state();var before:Dictionary=rt.capture_checkpoint();var cases:Array=[]
		for mode:String in ["copy_only","full","source_override","full"]:
			var at:=Time.get_ticks_usec();var ok:=true
			for n in 300:
				if mode=="copy_only":module.state()
				else:
					var result:Dictionary=module.validate_extensions(facts,{module.KEY:state} if mode=="source_override" else {})
					ok=ok and result.get("ok",false)
			var cost:=Time.get_ticks_usec()-at;checks.append({"name":"all300 validation calls succeed "+path+mode+str(cases.size()),"ok":ok})
			cases.append({"mode":mode,"calls":300,"usec":cost,"mean_usec":float(cost)/300})
		checks.append({"name":"cost queries preserve complete authority "+path,"ok":Data.json_equal(before,rt.capture_checkpoint())})
		rows.append({"input":path,"instances":state.instances.size(),"projects":state.projects.size(),"stocks":facts.stocks.size(),"cases":cases});rt.retire()
	FileAccess.open(args[0]+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"rows":rows,"scope":"Actual normal20 and optional actual23 S01 Native input; pure validator CPU, repeated source-only override separated. Not movement/FPS/pass."},"\t",true,true));quit(0 if checks.all(func(c:Dictionary)->bool:return c.ok) else 1)
