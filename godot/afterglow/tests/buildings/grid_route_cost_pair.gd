extends SceneTree
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Nav=preload("res://scripts/buildings/building_navigation.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func run()->void:
	var args:=OS.get_cmdline_user_args();var cfg:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[3]));var old:Script=load(cfg.reference_navigation)
	var input:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]));var evidence:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[2]));var s:Dictionary=evidence.rows[0].profile.actions.route.slow[0]
	var host:=Native.new();var built:Dictionary=host._assemble(input.capture);host.free()
	if not built.get("ok",false):quit(2);return
	var rt:RefCounted=built.runtime;rt.tick(0.1);var before:Dictionary=rt.capture_checkpoint();var b:RefCounted=built.services.buildings;var rows:Array=[]
	for mode:String in ["before","current","current","before"]:
		var q:RefCounted=b.space();var script:Script=old if mode=="before" else Nav
		var at:int=Time.get_ticks_usec();var cold:Dictionary=script.new().plan(q,s.actor_id,s.from,s.to);var cold_us:=Time.get_ticks_usec()-at
		at=Time.get_ticks_usec();var hot:Dictionary=script.new().plan(q,s.actor_id,s.from,s.to);var hot_us:=Time.get_ticks_usec()-at
		checks.append({"name":"complete cold/hot result equals original "+str(rows.size()),"ok":Data.json_equal(cold,s.result) and Data.json_equal(hot,s.result)})
		rows.append({"mode":mode,"cold_us":cold_us,"hot_us":hot_us,"visited":cold.get("visited"),"steps":cold.get("steps",[]).size()})
	checks.append({"name":"queries preserve entire authority","ok":Data.json_equal(before,rt.capture_checkpoint())})
	FileAccess.open(args[0]+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"rows":rows,"scope":"Same process isolated23 plus B overlay, before/current/current/before fresh projections; no instrumentation, no FPS/quiet-window claim."},"\t",true,true));rt.retire();quit(0 if checks.all(func(c:Dictionary)->bool:return c.ok) else 1)
