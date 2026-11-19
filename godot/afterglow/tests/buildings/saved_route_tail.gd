extends SceneTree
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool)->void:checks.append({"name":label,"ok":ok})
func run()->void:
	var args:=OS.get_cmdline_user_args();var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]))
	var host:=Native.new();var built:Dictionary=host._assemble(decoded.capture);host.free()
	check("original normal20 Native assembly",built.get("ok",false))
	if not built.get("ok",false):quit(1);return
	var rt:RefCounted=built.runtime;var original:Dictionary=rt.capture_checkpoint();var start:=Time.get_ticks_usec()
	rt.tick(0.1)
	var tick_cost:=Time.get_ticks_usec()-start
	var evidence:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	var source:Dictionary=evidence.rows[0].profile.actions.route.slow[0]
	var captured:Dictionary=Engine.get_meta("B_ROUTE",{})
	if not captured.is_empty():check("actual first tick route is original recorded actor/from/to/result",Data.json_equal(captured.result,source.result) and captured.actor_id==source.actor_id and captured.from==source.from and captured.to==source.to)
	var tick_meters:Dictionary=Engine.get_meta("B_METERS",{}).duplicate(true)
	var after_tick:Dictionary=rt.capture_checkpoint();var b:RefCounted=built.services.buildings;var rows:Array=[]
	for i:int in 2:
		var q:RefCounted=b.space();start=Time.get_ticks_usec();var cold:Dictionary=q.route(source.actor_id,source.from,source.to);var cold_us:=Time.get_ticks_usec()-start
		start=Time.get_ticks_usec();var hot:Dictionary=q.route(source.actor_id,source.from,source.to);var hot_us:=Time.get_ticks_usec()-start
		check("cold and hot complete original route "+str(i),Data.json_equal(cold,source.result) and Data.json_equal(hot,source.result))
		rows.append({"cold_us":cold_us,"hot_us":hot_us,"steps":cold.get("steps",[]).size(),"visited":cold.get("visited"),"route":cold})
	check("queries leave all authority unchanged",Data.json_equal(after_tick,rt.capture_checkpoint()))
	check("one fixed simulation step only",is_equal_approx(rt.clock()-float(original.facts.time),0.1))
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(var_to_bytes(after_tick))
	var result:Dictionary={"checks":checks,"tick_usec":tick_cost,"tick_route":captured,"tick_meters":tick_meters,"meters":Engine.get_meta("B_METERS",{}),"rows":rows,"after_tick_capture_sha256":h.finish().hex_encode(),"simulation_costs":rt.simulation_costs(),"scope":"Actual first tick normal20 plus exact cold/hot repeated queries; meters inclusive and extra overhead; background CPU only. No route/map/inventory mutation, no FPS claim."}
	FileAccess.open(args[0]+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true))
	print(JSON.stringify({"checks":checks,"tick_usec":tick_cost,"tick_meters":tick_meters,"rows":rows.map(func(r:Dictionary)->Dictionary:return {"cold_us":r.cold_us,"hot_us":r.hot_us,"steps":r.steps,"visited":r.visited})}));rt.retire();quit(0 if checks.all(func(c:Dictionary)->bool:return c.ok) else 1)
