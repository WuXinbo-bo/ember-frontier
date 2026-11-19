extends SceneTree
## Actual current factory/UI commands and cold assembly, plus explicitly
## synthetic map/privacy edge cases. No formal renderer, OS or VA qualification.
const Client = preload("res://scripts/runtime/native_client.gd")
const Assembly = preload("res://scripts/runtime/factory_assembly.gd")
const Mount = preload("res://scripts/ui/ui_mount.gd")
const F = preload("res://scripts/ui/factory_projection.gd")
const Alerts = preload("res://scripts/ui/factory_alerts.gd")
const Map = preload("res://scripts/ui/factory_map.gd")
const Data = preload("res://scripts/world/world_data.gd")
const Store = preload("res://scripts/storage/native_store.gd")
class TestClient extends Client:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
class TestRouter extends "res://scripts/input/input_router.gd":
	func _persist_bindings() -> bool: return true
var checks: Array = []
var output := ""
var host: Node3D
var runtime: RefCounted
var router: Node
var ui: Control
var services: Dictionary
func _initialize() -> void:
	create_timer(30).timeout.connect(func(): check("suite completed before watchdog",false); finish())
	call_deferred("run")
func check(label: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":label, "ok":ok, "detail":detail})
	if not ok: print("FAIL " + label + " " + str(detail))
func flush() -> void:
	await process_frame; await process_frame; await process_frame
func keyed(node: Node, key: String) -> Control:
	if node is Control and node.get_meta("ui_focus_key", "") == key: return node
	for child in node.get_children():
		var found := keyed(child, key)
		if found != null: return found
	return null
func text_in(node: Node) -> String:
	var result: String = node.text + "\n" if node is Label or node is Button else ""
	for child in node.get_children(): result += text_in(child)
	return result
func activate(key: String) -> bool:
	var button := keyed(ui, key) as Button
	if button == null or button.disabled:
		check("enabled button " + key, false); return false
	button.pressed.emit(); return true
func canvas() -> Control: return keyed(ui, "factory:map:canvas")
func actual_alert(reason: String, id: String) -> Dictionary:
	for row: Dictionary in runtime.factory_snapshot().alerts:
		if row.object_id == id and row.reason_code == reason: return row
	return {}
func gameplay_facts() -> Dictionary:
	var checkpoint: Dictionary = runtime.capture_checkpoint()
	checkpoint.world.extensions.erase("r34:display")
	# Display commands also advance the shared revision/receipt book; compare
	# actual facts and all gameplay extensions, not the transaction bookkeeping.
	return {"facts":runtime.facts(), "extensions":checkpoint.world.extensions, "clock":runtime.clock()}
func synthetic_map_checks() -> void:
	var value := {"schema":Map.SCHEMA, "tile_metres":4.0, "explored_tiles":[{"region_id":"A","x":-1,"z":1},{"region_id":"B","x":10,"z":-2}], "markers":[{"id":"member","kind":"member","title":"已知成员","location":{"x":-0.1,"z":4.1,"regionId":"A"}}, {"id":"site","kind":"regional_site","title":"已知地点","location":{"x":41.0,"z":-6.0,"regionId":"B"}}]}
	var before: Dictionary = value.duplicate(true)
	var map := Map.new(); root.add_child(map); map.size = Vector2(600,300)
	map.configure(value, {}, "A")
	check("synthetic negative exploration tile stays exact and region-limited", map.tiles.size()==1 and map.tiles[0].x==-1 and map.markers.size()==1 and map.markers[0].id=="member")
	map.configure(value, value.markers[1], "A")
	check("explicit public focus selects correct region and centers UI map", map.region_id=="B" and map.tiles.size()==1 and map.map_point(value.markers[1].location).is_equal_approx(map.size*0.5))
	map.configure({})
	check("unavailable map schema clears reused public presentation", map.tiles.is_empty() and map.markers.is_empty() and map.focus.is_empty())
	check("map projection never writes its source DTO", Data.json_equal(before,value))
	check("malformed locations never become map coordinates", not Map.valid_location({"x":1.0}) and not Map.valid_location({"x":NAN,"z":0,"regionId":"A"}))
	map.free()
	var attention := F.attention_alerts({"alerts":[{"id":"a","severity":"warning","status":"ignored"},{"id":"b","severity":"critical","status":"ignored"}]})
	check("critical cannot disappear even from a defensive ignored DTO", attention.size()==1 and attention[0].id=="b")
func run() -> void:
	output = OS.get_cmdline_user_args()[0]; DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,800)
	synthetic_map_checks()
	var profiles: Dictionary = Assembly.generation_profiles()
	var prepared: Dictionary = Assembly.prepare(Assembly.generate(713,profiles.profiles)) if profiles.get("ok",false) else profiles
	check("current actual normal factory capture prepares",prepared.get("ok",false),prepared.get("reason"))
	if not prepared.get("ok",false): return finish()
	host = TestClient.new(); root.add_child(host)
	var built: Dictionary = host._assemble(prepared.capture)
	check("current Native assembles real display and gameplay services",built.get("ok",false) and built.get("services",{}).has("display"),built.get("reason"))
	if not built.get("ok",false): return finish()
	runtime=built.runtime; services=built.services
	router=TestRouter.new(); host.add_child(router); router.configure(runtime)
	ui=Mount.mount(host,runtime,router); await flush()
	for index in 16: runtime.tick(0.1)
	await flush()
	var before: Dictionary=runtime.capture_checkpoint()
	ui.open_panel("factory_alerts"); await flush()
	check("WF07 mounts actual known-map DTO",canvas()!=null and ui.factory.get("map",{}).get("schema")==Map.SCHEMA)
	if canvas()==null: return finish()
	check("render and availability queries never write authority",Data.json_equal(before,runtime.capture_checkpoint()))
	check("map remains live with input barrier",not runtime.is_paused() and router.is_paused() and not router.world_is_paused())
	var map: Control=canvas()
	var public_data: Dictionary=runtime.factory_snapshot().map
	var allowed: Array=public_data.markers.filter(func(v:Dictionary): return v.location.regionId==map.region_id)
	check("map uses exactly owner-filtered marker identities",map.markers.map(func(v:Dictionary):return v.id)==allowed.map(func(v:Dictionary):return v.id))
	check("no whole generated region is painted explored",map.tiles.size()==public_data.explored_tiles.filter(func(v:Dictionary):return v.region_id==map.region_id).size() and public_data.explored_tiles.size()==1)
	if not map.markers.is_empty():
		var marker: Dictionary=map.markers.back()
		before=runtime.capture_checkpoint()
		var point: Vector2=map.global_position+map.map_point(marker.location)
		for down: bool in [true,false]:
			var event:=InputEventMouseButton.new(); event.position=point; event.global_position=point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=down
			root.push_input(event,true); await flush()
		check("native map marker click selects only UI focus",not str(ui.factory_view.get("map_focus","")).is_empty() and Data.json_equal(before,runtime.capture_checkpoint()),ui.factory_view)
	var module: Dictionary=runtime.factory_snapshot().modules.instances[0]
	var damage: Dictionary=services.modules.prepare_damage(module.id,1.0,"ui:wf07:damage")
	var receipt: Dictionary=runtime._commit(damage) if damage.get("ok",false) else damage
	check("fixture damages real known module via original owner",receipt.get("ok",false),receipt)
	ui.queue_refresh(); await flush()
	var row:=actual_alert("damaged",module.id)
	check("UI receives real persistent urgent episode and current token",not row.is_empty() and not str(row.get("notification_token","")).is_empty() and row.get("severity")=="danger",row)
	if row.is_empty(): return finish()
	check("real title detail and unresolved status are visible",text_in(ui._body).contains(str(row.title)) and text_in(ui._body).contains(str(row.detail)) and text_in(ui._body).contains("尚未解决"))
	var actual_before:=gameplay_facts()
	activate("factory:command:alerts.acknowledge:"+str(row.id)); await flush()
	check("native acknowledgement updates same real episode",actual_alert("damaged",module.id).get("status")=="acknowledged")
	check("reading does not give items repair facts advance clock or emit gameplay ledger",Data.json_equal(actual_before,gameplay_facts()))
	check("acknowledgement gives reading-specific feedback in modal",ui._panel_notice.is_visible_in_tree() and ui._panel_notice.text.contains("问题尚未解决"))
	activate("factory:command:alerts.ignore:"+str(row.id)); await flush()
	row=actual_alert("damaged",module.id)
	check("ignore button uses 60 actual simulation seconds and not resolve",row.status=="ignored" and not row.resolved and is_equal_approx(float(row.ignored_until)-runtime.clock(),60.0))
	check("ignored risk remains in unresolved list with explicit status",text_in(ui._body).contains("暂忽略 · 尚未解决") and keyed(ui,"factory:command:alerts.ignore:"+str(row.id))==null)
	check("read actions keep gameplay state and live-map policy intact",Data.json_equal(actual_before,gameplay_facts()) and not runtime.is_paused() and router.is_paused())
	var invalid:=F.alert_payload(row); invalid.notification_token="stale:token"
	before=runtime.capture_checkpoint()
	receipt=ui.execute("alerts.acknowledge",str(row.id),invalid); await flush()
	check("UI rejects stale notification token without acknowledging any episode",receipt.get("code")=="STALE_ALERT" and Data.json_equal(before,runtime.capture_checkpoint()))
	check("stale read failure is visible within live modal",ui._panel_notice.is_visible_in_tree() and not ui._panel_notice.text.is_empty())
	var excessive:=F.alert_payload(row); excessive.seconds=301.0
	receipt=ui.execute("alerts.ignore",str(row.id),excessive); await flush()
	check("invalid ignore duration is refused by real owner",receipt.get("code")=="INVALID_DURATION" and Data.json_equal(before,runtime.capture_checkpoint()))
	# Real encode/file/decode/cold assembly, not a fake UI-local read-state store.
	var encoded: Dictionary=Store.encode(runtime.capture_checkpoint())
	var path:=output+"/wf07-ignored-checkpoint.json"
	if encoded.get("ok",false):
		var file:=FileAccess.open(path,FileAccess.WRITE); file.store_string(encoded.text); file.close()
	var decoded: Dictionary=Store.decode(FileAccess.get_file_as_string(path)) if encoded.get("ok",false) else encoded
	var cold: Dictionary=host._assemble(decoded.capture) if decoded.get("ok",false) else decoded
	check("actual cold assembly preserves episode ignored status and exploration memory",cold.get("ok",false) and cold.runtime.factory_snapshot().alerts.any(func(v:Dictionary):return v.id==row.id and v.status=="ignored") and Data.json_equal(cold.runtime.factory_snapshot().map.explored_tiles,public_data.explored_tiles),cold.get("reason"))
	if cold.get("ok",false):
		var cold_ui: Control=Mount.mount(host,cold.runtime,null); cold_ui.open_panel("factory_alerts"); await flush()
		check("fresh native UI reads persisted ignore from same facade",text_in(cold_ui._body).contains("暂忽略 · 尚未解决"))
		cold_ui.free()
	var short:=F.alert_payload(row); short.seconds=0.2
	receipt=ui.execute("alerts.ignore",str(row.id),short)
	for index in 4: runtime.tick(0.1)
	ui.queue_refresh(); await flush()
	check("ignore expiry follows same world clock without marking source resolved",receipt.get("ok",false) and actual_alert("damaged",module.id).get("status")=="acknowledged")
	ui._scroll.scroll_vertical=300
	activate("factory:alert:locate:"+str(row.id)); await flush()
	check("alert locate centers public location and returns to map top",canvas().focus.get("id")==row.id and canvas().map_point(row.location).is_equal_approx(canvas().size*0.5) and ui._scroll.scroll_vertical==0)
	before=runtime.capture_checkpoint()
	Alerts.locate(ui,"not-public"); await flush()
	check("missing public marker cannot retain old coordinates or move player",canvas().focus.is_empty() and text_in(ui._body).contains("未保留其坐标") and Data.json_equal(before,runtime.capture_checkpoint()))
	# Real ruin replaces the damage source. Old buttons/tokens cannot acknowledge
	# the replacement risk, and only owner disappearance moves damage to history.
	damage=services.modules.prepare_damage(module.id,100000.0,"ui:wf07:ruin")
	receipt=runtime._commit(damage) if damage.get("ok",false) else damage
	ui.queue_refresh(); await flush()
	var critical:=actual_alert("ruined",module.id)
	check("real critical ruin stays present after previous ignored damage",receipt.get("ok",false) and critical.get("severity")=="critical" and F.attention_alerts(ui.factory).any(func(v:Dictionary):return v.id==critical.get("id")))
	if critical.is_empty(): return finish()
	check("critical UI offers acknowledgement but no ignore or resolve",keyed(ui,"factory:command:alerts.acknowledge:"+str(critical.id))!=null and keyed(ui,"factory:command:alerts.ignore:"+str(critical.id))==null and keyed(ui,"factory:command:alerts.resolve:"+str(critical.id))==null)
	before=runtime.capture_checkpoint()
	receipt=ui.execute("alerts.ignore",str(critical.id),F.alert_payload(critical)); await flush()
	check("bypassed critical ignore is rejected without writes",receipt.get("code")=="CRITICAL_ALERT" and Data.json_equal(before,runtime.capture_checkpoint()))
	receipt=ui.execute("alerts.acknowledge",str(row.id),F.alert_payload(row)); await flush()
	check("resolved old episode cannot affect real replacement",receipt.get("code")=="STALE_ALERT" and Data.json_equal(before,runtime.capture_checkpoint()))
	actual_before=gameplay_facts()
	activate("factory:command:alerts.acknowledge:"+str(critical.id)); await flush()
	check("critical acknowledgement persists without hiding or repairing ruin",actual_alert("ruined",module.id).get("status")=="acknowledged" and text_in(ui._body).contains("紧急 · 已确认，尚未解决") and Data.json_equal(actual_before,gameplay_facts()))
	check("critical remains HUD headline after acknowledgement",ui._factory_alert.text.contains(str(critical.title)))
	activate("factory:alerts:history"); await flush()
	var history: Array=ui.factory.alert_history.filter(func(v:Dictionary):return v.id==row.id)
	check("only ended real damage source becomes solved history",history.size()==1 and history[0].resolved and text_in(ui._body).contains("已解决 · 来源已结束") and text_in(ui._body).contains("结束于"))
	check("history does not expose stale read or resolve commands",keyed(ui,"factory:command:alerts.acknowledge:"+str(row.id))==null and keyed(ui,"factory:command:alerts.ignore:"+str(row.id))==null)
	before=runtime.capture_checkpoint()
	activate("factory:alert:locate:"+str(row.id)); await flush()
	check("history location is UI-only from public archived row",canvas().focus.get("id")==row.id and Data.json_equal(before,runtime.capture_checkpoint()))
	# Authoritative DTO removal must also clear any UI focus on a former enemy.
	var synthetic: Dictionary=ui.factory.duplicate(true)
	synthetic.map.markers.append({"id":"fixture-visible-hostile","kind":"hostile","title":"synthetic visible hostile","location":{"x":2.0,"z":3.0,"regionId":"RH-HOME"}})
	ui.factory=synthetic
	ui.factory_view.map_focus="fixture-visible-hostile"; ui.factory_view.map_focus_source="marker"
	check("synthetic focus exists only while public marker exists",not Alerts.focused(ui,synthetic.map).is_empty())
	synthetic.map.markers=synthetic.map.markers.filter(func(v:Dictionary):return v.id!="fixture-visible-hostile")
	check("lost LOS cannot persist enemy position in UI focus",Alerts.focused(ui,synthetic.map).is_empty())
	ui.close_panels(); ui.refresh(); await flush()
	check("close releases modal input barrier without secondary clock",not runtime.is_paused() and not router.is_paused())
	finish()
func finish() -> void:
	var report: Dictionary={"scope":"current actual factory authority/native UI commands, read-state persistence and explicit synthetic map counterexamples; no packaged app/OS/VA/performance acceptance", "checks":checks, "failed":checks.filter(func(c:Dictionary):return not c.ok).size()}
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t",true,true)); file.close()
	if is_instance_valid(host): host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":report.failed}))
	quit(1 if report.failed else 0)
