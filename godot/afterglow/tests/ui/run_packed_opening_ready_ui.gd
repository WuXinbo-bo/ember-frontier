extends "res://tests/ui/run_service_access_ui.gd"
## Source CPU/query-boundary check only. No GPU, PCK or frame-rate claim.
const P=preload("res://scripts/ui/ui_projection.gd")
const Modes=preload("res://scripts/ui/ui_work_modes.gd")
var timings:Dictionary={"legacy_full_hud_pair":[],"minimal_dirty_pair":[],"minimal_hover_pair":[],"ui_refresh":[]}

func stats(values:Array)->Dictionary:
	var sorted:=values.duplicate();sorted.sort();var total:=0.0
	for value:Variant in sorted:total+=float(value)
	return {"n":sorted.size(),"mean_us":total/maxi(1,sorted.size()),"median_us":sorted[sorted.size()/2] if not sorted.is_empty() else 0,"p95_us":sorted[mini(sorted.size()-1,int(ceil(sorted.size()*.95))-1)] if not sorted.is_empty() else 0}

func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	host=TestClient.new();root.add_child(host)
	var profiles:Dictionary=Assembly.generation_profiles()
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles))
	check("fresh current Native world prepares",prepared.get("ok",false))
	if not prepared.get("ok",false) or not await mount_capture(prepared.capture):return finish()
	ui.close_panels();await flush()
	var before:Dictionary=runtime.capture_checkpoint()
	var baseline:Dictionary=runtime._display_snapshot(false)
	var minimal:Dictionary=runtime.hud_snapshot()
	for field:String in ["player","actors","tools","knowledge","orders","quests","movement","radio","village"]:
		check("minimal HUD retains actual field "+field,Data.json_equal(baseline.get(field),minimal.get(field)))
	check("HUD pack content and free amounts remain exact",P.entries(P.player_stock(baseline),baseline)==P.entries(P.player_stock(minimal),minimal))
	var original_target:Dictionary=minimal.get("target",{})
	runtime.set_target({"kind":"container","id":"hud:test","primary":"pickup","enabled":true,"name":"actual display replay"})
	check("target updates without authority revision are never cached stale",runtime.hud_snapshot().target.get("id")=="hud:test")
	var detached:Dictionary=runtime.hud_snapshot();detached.player.hp=1
	check("returned HUD dictionary cannot mutate authority or cached core",runtime.hud_snapshot().player.hp==baseline.player.hp and runtime.actor("player").hp==baseline.player.hp)
	var old_hand:Dictionary=minimal.get("hand",{});var rebound:Dictionary=router.state();rebound.bindings.auto_pickup={"keycode":KEY_H,"label":"H","physical":true}
	runtime.set_hand(rebound)
	check("runtime hand remains fresh without revision",runtime.hud_snapshot().hand.bindings.auto_pickup.label=="H")
	# Router owns displayed bindings. An explicit display state tests the label.
	ui.snapshot.hand=rebound
	check("pickup hint resolves current actual binding",Modes.key(rebound,"auto_pickup",KEY_G)=="H")
	runtime.set_hand(old_hand);runtime.set_target(original_target)
	var nodes:Array=ui._hotbar.get_children().map(func(n:Node):return n.get_instance_id())
	for i:int in range(12):
		runtime._hud_factory_basis.clear()
		var began:=Time.get_ticks_usec();runtime._display_snapshot(false);runtime.factory_hud_snapshot();timings.legacy_full_hud_pair.append(Time.get_ticks_usec()-began)
		runtime._hud_factory_basis.clear();runtime._hud_snapshot_basis.clear()
		began=Time.get_ticks_usec();runtime.hud_snapshot();runtime.factory_hud_snapshot();timings.minimal_dirty_pair.append(Time.get_ticks_usec()-began)
		began=Time.get_ticks_usec();runtime.hud_snapshot();runtime.factory_hud_snapshot();timings.minimal_hover_pair.append(Time.get_ticks_usec()-began)
		began=Time.get_ticks_usec();ui.refresh();timings.ui_refresh.append(Time.get_ticks_usec()-began)
	check("repeated HUD updates retain visible hotbar controls",nodes==ui._hotbar.get_children().map(func(n:Node):return n.get_instance_id()))
	check("minimal query never exposes management catalogue",runtime.factory_hud_snapshot().modules.get("definitions",[]).is_empty() and runtime.hud_snapshot().work_targets.is_empty())
	check("read-only HUD performance probes preserve authority",Data.json_equal(before,runtime.capture_checkpoint()))
	var cached:Dictionary=runtime.hud_snapshot();runtime.tick(.1)
	var advanced:Dictionary=runtime.hud_snapshot()
	check("real fixed step invalidates needs and progress immediately",advanced.time>cached.time and advanced.player.thirst<cached.player.thirst)
	ui.open_panel("settings");await flush()
	check("management query still yields full original API",runtime.snapshot().catalog.size()>0 and ui._body.get_child_count()>0)
	verify_pack_cache()
	finish()

func verify_pack_cache()->void:
	# Exact display fixture only: exercise in-place DTO changes without commands.
	var original:Dictionary=ui.snapshot
	ui.snapshot={"player":{"id":"player","stock_id":"pack:test"},"stocks":[{"id":"pack:test","searched":true,"items":{"timber":8,"log":1},"reserved":{"items":{"timber":3},"tool_ids":[]},"tool_ids":["hammer:test"]}],"tools":[{"id":"hammer:test","holderId":"pack:test","definitionId":"hammer","durability":31}],"catalog":{"tool_definitions":{"hammer":{"name":"Exact tool name","maxDurability":80}},"buildings":{"wall:test":{"id":"wall:test","name":"Bound recipe"}}}}
	var stock:Dictionary=ui.snapshot.stocks[0]
	var ref:Dictionary={"kind":"item","item_id":"timber"}
	var tool:Dictionary={"kind":"tool","tool_id":"hammer:test"}
	var expected:Array=P.entries(stock,ui.snapshot)
	check("shared pack index preserves original entry projection",ui._hud_pack_index(stock).values()==expected and ui._hud_hand_entry(ref)==P.hand_entry(stock,ui.snapshot,ref) and ui._hud_hand_entry(tool)==P.hand_entry(stock,ui.snapshot,tool))
	var reads:int=ui._hud_pack_rebuilds
	for i:int in range(12):ui._hud_hand_entry(ref);ui._hud_hand_entry(tool);ui._hud_pack_index(stock)
	check("unchanged hand target and hotbar reuse one exact pack enumeration",ui._hud_pack_rebuilds==reads)
	stock["location"]={"x":99,"z":12};ui.snapshot["revision"]=999
	ui._hud_pack_index(stock)
	check("location and revision only do not rebuild pack display",ui._hud_pack_rebuilds==reads)
	stock.items.timber=9
	check("in-place item amount invalidates pack display",ui._hud_hand_entry(ref)==P.hand_entry(stock,ui.snapshot,ref) and ui._hud_hand_entry(ref).quantity==9)
	stock.reserved.items.timber=8
	check("in-place reservation invalidates free amount immediately",ui._hud_hand_entry(ref).available==1 and ui._hud_hand_entry(ref)==P.hand_entry(stock,ui.snapshot,ref))
	stock.reserved.tool_ids=["hammer:test"]
	check("tool reservation immediately invalidates pack display",ui._hud_hand_entry(tool).available==0 and ui._hud_hand_entry(tool)==P.hand_entry(stock,ui.snapshot,tool))
	ui.snapshot.tools[0].durability=12
	check("tool wear invalidates cached visible durability",ui._hud_hand_entry(tool).durability==12 and ui._hud_hand_entry(tool)==P.hand_entry(stock,ui.snapshot,tool))
	ui.snapshot.catalog.tool_definitions.hammer.maxDurability=90
	check("tool definition replacement invalidates cached tool limit",ui._hud_hand_entry(tool).max_durability==90 and ui._hud_hand_entry(tool)==P.hand_entry(stock,ui.snapshot,tool))
	stock.searched=false
	check("permission visibility change clears cached pack entries",ui._hud_pack_index(stock).is_empty() and ui._hud_hand_entry(ref).is_empty())
	stock.searched=true;ui.snapshot.tools[0].holderId="other"
	check("tool ownership change removes old cached hand entry",ui._hud_hand_entry(tool).is_empty() and ui._hud_hand_entry(tool)==P.hand_entry(stock,ui.snapshot,tool))
	var recipe:Dictionary={"kind":"recipe","definition_id":"wall:test"}
	check("bound recipe still uses original hand projection",ui._hud_hand_entry(recipe)==P.hand_entry(stock,ui.snapshot,recipe))
	ui.snapshot=original

func finish()->void:
	var failed:int=checks.filter(func(row:Dictionary):return not row.ok).size()
	var measured:Dictionary={}
	for key:String in timings:measured[key]=stats(timings[key])
	var report:Dictionary={"checks":checks,"failed":failed,"cpu":measured,"scope":"current-source headless CPU, same real fresh Native authority, 12 repeated read-only query cycles; legacy pair uses original _display_snapshot(false) and uncached original factory query; dirty pair clears only display caches; hover pair reuses exact world/runtime/clock observation; no GPU/PCK/OS/frame-rate qualification"}
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	if is_instance_valid(host):host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed,"cpu":measured}));quit(1 if failed else 0)
