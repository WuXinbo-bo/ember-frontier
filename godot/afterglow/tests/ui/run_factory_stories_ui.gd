extends SceneTree
## Real normal-source search/study/cancel/cold restore, plus explicitly
## synthetic public-projection privacy cases. No OS/VA/package acceptance.
const Client = preload("res://scripts/runtime/native_client.gd")
const Assembly = preload("res://scripts/runtime/factory_assembly.gd")
const Mount = preload("res://scripts/ui/ui_mount.gd")
const Stories = preload("res://scripts/ui/factory_stories.gd")
const F = preload("res://scripts/ui/factory_projection.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
const Data = preload("res://scripts/world/world_data.gd")
const Store = preload("res://scripts/storage/native_store.gd")
const Geometry = preload("res://scripts/buildings/building_geometry.gd")
class TestClient extends Client:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
class TestRouter extends "res://scripts/input/input_router.gd":
	func _persist_bindings() -> bool: return true
var output := ""
var checks: Array = []
var host: Node3D
var ui: Control
var runtime: RefCounted
var router: Node
var sequence := 0
func _initialize() -> void:
	create_timer(55).timeout.connect(func(): check("suite completes before watchdog",false); finish())
	call_deferred("run")
func check(label: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok: print("FAIL " + label + " " + str(detail))
func flush() -> void:
	await process_frame; await process_frame; await process_frame
func text_in(node: Node) -> String:
	var value: String = node.text + "\n" if node is Label or node is Button else ""
	for child in node.get_children(): value += text_in(child)
	return value
func button_with(label: String) -> Button:
	for node in ui.find_children("*","Button",true,false):
		if node.text == label: return node
	return null
func has_story(id: String) -> bool:
	return Stories.known_rows(runtime.factory_snapshot(),runtime.snapshot()).any(func(row: Dictionary): return row.id==id)
func story_flag(flag: String) -> bool:
	return bool(F.find(F.rows(runtime.factory_snapshot(),"workforce","stories"),"ST01").get("flags",{}).get(flag,false))
func send(kind: String, target: String = "", payload: Dictionary = {}, destination: Dictionary = {}) -> Dictionary:
	sequence += 1
	return runtime.command({"command_id":"ui:story-route:"+str(sequence),"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"destination":destination})
func progress(limit: int = 1200) -> bool:
	for index in limit:
		if runtime.actor("player").get("intent")==null: return true
		runtime.tick(0.1)
	return runtime.actor("player").get("intent")==null
func open_stories() -> void:
	ui.close_panels(); ui.factory_view.handbook_section="stories"; ui.factory_view.erase("story_person")
	ui.open_panel("factory_handbook"); await flush()
func synthetic_checks() -> void:
	var rows: Array = []
	for id: String in ["ST01","ST02","ST03","ST04"]:
		rows.append({"id":id,"available":true,"sources":["unsearched:"+id],"flags":{},"people":{}})
	rows[1].people={"a":{"met":false,"helped":true},"b":{"met":false,"real_delivery":true}}
	var data: Dictionary={"workforce":{"available":true,"stories":rows}}
	var snapshot: Dictionary={"stocks":[{"id":"unsearched:ST01","searched":false}],"actors":[]}
	var original: Dictionary=data.duplicate(true)
	check("synthetic source binding and unintroduced relationships reveal no story",Stories.known_rows(data,snapshot).is_empty())
	check("privacy filtering is a pure public DTO read",Data.json_equal(data,original))
	for i in 4:
		var known: Dictionary=snapshot.duplicate(true)
		known.stocks=[{"id":"unsearched:"+str(rows[i].id),"searched":true,"name":"known"}]
		var visible: Array=Stories.known_rows(data,known)
		check("synthetic searched public source unlocks only "+str(rows[i].id),visible.size()==1 and visible[0].id==rows[i].id)
	data.workforce.stories[1].people.a.met=true
	var visible: Array=Stories.known_rows(data,snapshot)
	check("synthetic per-person record excludes an unrelated stranger",visible.size()==1 and visible[0].visible_people.size()==1 and visible[0].visible_people[0].id=="a")
	check("synthetic known but out-of-projection person has no position",visible[0].visible_people[0].actor.is_empty())
	data.workforce.stories[1].available=false
	check("explicit unavailable story overrides known relationship",Stories.known_rows(data,snapshot).is_empty())
	data.workforce.stories[0].flags.read_woodwork_record=true
	check("real-recorded flag shape preserves knowledge without a current nearby source",Stories.known_rows(data,snapshot).size()==1)
	data.workforce.available=false
	check("unavailable workforce cannot leak bare raw stories",Stories.known_rows(data,snapshot).is_empty())
	data.workforce.available=true; data.workforce.stories[0].flags={}; data.workforce.stories[0].stage="workshop_found"
	check("published authoritative discovery persists outside nearby source snapshot",Stories.known_rows(data,snapshot).size()==1)
func run() -> void:
	output=OS.get_cmdline_user_args()[0]; DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,800)
	synthetic_checks()
	var profiles: Dictionary=Assembly.generation_profiles()
	var prepared: Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles)) if profiles.get("ok",false) else profiles
	check("current normal content prepares",prepared.get("ok",false),prepared.get("reason"))
	if not prepared.get("ok",false): return finish()
	host=TestClient.new(); root.add_child(host)
	var built: Dictionary=host._assemble(prepared.capture)
	check("actual Native services assemble",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false): return finish()
	runtime=built.runtime; router=TestRouter.new(); host.add_child(router); router.configure(runtime)
	ui=Mount.mount(host,runtime,router); await flush()
	for index in 2: runtime.tick(0.1)
	check("normal start has no donated knowledge",not runtime.snapshot().get("knowledge",{}).get("player",[]).has("basic_woodwork"))
	var before: Dictionary=runtime.capture_checkpoint()
	await open_stories()
	check("unknown store and drive stories are not disclosed by raw registered sources",not has_story("ST03") and not has_story("ST04") and not text_in(ui._body).contains("临路小店") and not text_in(ui._body).contains("田边仓棚"))
	check("rendering stories changes no inventory relationship or knowledge",Data.json_equal(before,runtime.capture_checkpoint()))
	ui.close_panels()
	var stock_id := "r34:generated:RH-HOME:woodwork:stock:tools"
	var stock: Dictionary=runtime.stock(stock_id)
	check("normal source exists in actual generation",not stock.is_empty())
	if stock.is_empty(): return finish()
	var walked: Dictionary=send("walk","",{},stock.location)
	var arrived: bool=progress() if walked.get("ok",false) else false
	check("normal player actually walks to woodwork source",walked.get("ok",false) and arrived,walked.get("reason"))
	if not arrived: return finish()
	var searched: Dictionary=send("search",stock_id)
	var completed: bool=progress() if searched.get("ok",false) else false
	check("actual search completes and publishes the searched source",completed and runtime.stock(stock_id).searched,searched.get("reason"))
	if not completed: return finish()
	await open_stories()
	check("searched woodwork source reveals true story and real study action",has_story("ST01") and text_in(ui._body).contains("主人离开的木工小院") and button_with("现场研读木工记录")!=null)
	check("opening and reading text alone never records learned flag",not story_flag("read_woodwork_record"))
	var study: Button=button_with("现场研读木工记录")
	check("on-site study goes through actual availability",study!=null and not study.disabled)
	if study==null or study.disabled: return finish()
	study.pressed.emit(); await flush()
	check("accepted real study closes page and resumes the single clock",ui.pages.is_empty() and not runtime.is_paused() and not router.is_paused() and runtime.actor("player").get("intent") is Dictionary)
	for index in 10: runtime.tick(0.1)
	check("partial actual work does not mark record read",not story_flag("read_woodwork_record") and not runtime.snapshot().get("knowledge",{}).get("player",[]).has("basic_woodwork"))
	var cancelled: Dictionary=ui.execute("cancel","",{},true)
	check("actual cancellation never awards knowledge",cancelled.get("ok",false) and runtime.actor("player").get("intent")==null and not story_flag("read_woodwork_record"),cancelled.get("reason"))
	await open_stories(); study=button_with("现场研读木工记录")
	check("cancelled study can retry through current authority",study!=null and not study.disabled)
	if study==null or study.disabled: return finish()
	study.pressed.emit(); await flush(); completed=progress(180)
	# E observes the committed production fact on the following shared STEP.
	# Do not invent a UI read flag during the production transaction itself.
	runtime.tick(0.1)
	check("completed actual study grants real knowledge and E learned fact",completed and runtime.snapshot().get("knowledge",{}).get("player",[]).has("basic_woodwork") and story_flag("read_woodwork_record"),{"completed":completed,"knowledge":runtime.snapshot().get("knowledge"),"stories":F.rows(runtime.factory_snapshot(),"workforce","stories")})
	await open_stories(); study=button_with("现场研读木工记录")
	check("known record cannot be studied a second time",study!=null and study.disabled and text_in(ui._body).contains("读过真实木工记录"))
	before=runtime.capture_checkpoint()
	for index in 3: ui.queue_refresh(); await flush()
	check("repeat story viewing neither duplicates goods nor changes relationships",Data.json_equal(before,runtime.capture_checkpoint()))
	var encoded: Dictionary=Store.encode(before)
	var path := output+"/actual-story-checkpoint.json"
	if encoded.get("ok",false):
		var saved:=FileAccess.open(path,FileAccess.WRITE); saved.store_string(encoded.text); saved.close()
	var decoded: Dictionary=Store.decode(FileAccess.get_file_as_string(path)) if encoded.get("ok",false) else encoded
	var cold: Dictionary=host._assemble(decoded.capture) if decoded.get("ok",false) else decoded
	check("actual file codec and cold Native assembly preserve learned and source facts",cold.get("ok",false) and Data.json_equal(cold.runtime.snapshot().get("knowledge"),runtime.snapshot().get("knowledge")) and cold.runtime.stock(stock_id).searched,cold.get("reason"))
	if cold.get("ok",false):
		var cold_ui: Control=Mount.mount(host,cold.runtime,null)
		cold_ui.factory_view.handbook_section="stories"; cold_ui.open_panel("factory_handbook"); await flush()
		check("fresh UI consumes persisted E story without local completion state",text_in(cold_ui._body).contains("读过真实木工记录"))
		cold_ui.get_parent().free()
	await real_relationship()
	await formal_route_record(profiles.profiles)
	finish()
func real_relationship() -> void:
	ui.close_panels()
	var id := "village-resident"
	var approached := false
	for attempt in 8:
		if runtime.availability({"kind":"talk","actor_id":"player","target_id":id}).get("ok",false): approached=true; break
		var at: Dictionary=Geometry.location(runtime.actor(id)); at.x+=0.9
		var feet: Dictionary=runtime._services.buildings.current_space().standing_point(at)
		if not feet.is_empty():
			var walked: Dictionary=send("walk","",{},feet)
			if walked.get("ok",false): progress()
	check("actual normal player reaches original resident for physical conversation",approached)
	if not approached: return
	var other_before: Dictionary=runtime.actor("repair-resident").relationship.duplicate(true)
	ui.open_panel("npc",id); await flush()
	var talk: Button=button_with("交谈")
	check("unintroduced resident offers actual conversation before story shortcut",talk!=null and not talk.disabled and button_with("共同经历")==null)
	if talk==null or talk.disabled: return
	talk.pressed.emit(); await flush(); runtime.tick(0.1)
	ui.open_panel("npc",id); await flush()
	var experiences: Button=button_with("共同经历")
	check("real talk publishes own experiences without helping or recruiting",experiences!=null and runtime.actor(id).relationship.met and not runtime.actor(id).relationship.helped and not runtime.actor(id).relationship.member and runtime.actor("repair-resident").relationship==other_before)
	if experiences==null: return
	var before: Dictionary=runtime.capture_checkpoint()
	ui.factory_view.handbook_search="old unmatched search"
	experiences.pressed.emit(); await flush()
	check("native NPC shortcut opens own history and clears unrelated search",ui.factory_view.get("story_person")==id and ui.factory_view.handbook_search=="" and text_in(ui._body).contains("已经结识") and not text_in(ui._body).contains("老许"))
	check("viewing shared experiences does not grant supplies consent or recruitment",Data.json_equal(before,runtime.capture_checkpoint()))
	var body:=VBoxContainer.new(); ui._body.add_child(body)
	var saved: Dictionary=ui.factory.duplicate(true)
	var stories: Array=ui.factory.workforce.stories
	var known: Dictionary=F.find(stories,"ST02")
	known.people["repair-resident"]={"met":true,"helped":true}
	known.text="周婶和老许各有真实经历，合成DTO不可混入单人卡"
	for i in stories.size():
		if stories[i].id=="ST02": stories[i]=known
	Stories.render(ui,body)
	check("synthetic two-known-person source still filters the selected experience",not text_in(body).contains("老许") and not text_in(body).contains("实际帮助过对方"))
	body.free(); ui.factory=saved
func formal_route_record(profiles: Array) -> void:
	# Use A's actual current new-world policy, including its persisted story
	# contract. Do not opt in here or claim this source is in candidate16.
	ui.get_parent().free(); router.free()
	var prepared: Dictionary=Assembly.prepare(Assembly.generate(713,profiles))
	var built: Dictionary=host._assemble(prepared.capture) if prepared.get("ok",false) else prepared
	check("formal current new-world policy assembles through real Native",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false): return
	runtime=built.runtime; router=TestRouter.new(); host.add_child(router); router.configure(runtime)
	ui=Mount.mount(host,runtime,router); await flush()
	var id := "r34:generated:RH-VILLAGE:store:stock:supplies"
	var stock: Dictionary=runtime.stock(id)
	check("formal current source resolves finite village shop",not stock.is_empty())
	if stock.is_empty(): return
	var walked: Dictionary=send("walk","",{},stock.location)
	var arrived: bool=progress() if walked.get("ok",false) else false
	check("formal current source follows actual normal path to shop",arrived,walked.get("reason"))
	if not arrived: return
	var searched: Dictionary=send("search",id)
	var completed: bool=progress() if searched.get("ok",false) else false
	check("formal current source is searched before any route can be read",completed and runtime.stock(id).searched,searched.get("reason"))
	if not completed: return
	await open_stories()
	var read_button: Button=button_with("在现场阅读路线记录")
	check("searched source exposes exact E command without pre-reading route",read_button!=null and not read_button.disabled and not text_in(ui._body).contains("读过现场路线记录") and runtime.factory_snapshot().map.markers.all(func(row: Dictionary): return row.get("kind")!="route_clue"))
	if read_button==null or read_button.disabled: return
	var before: Dictionary=runtime.capture_checkpoint()
	ui.queue_refresh(); await flush()
	check("rendering a source-bound read command never submits it",Data.json_equal(before,runtime.capture_checkpoint()))
	ui.close_panels(); ui.open_panel("container",id); await flush()
	read_button=button_with("在现场阅读路线记录")
	check("formal searched-container route offers the exact read action directly",ui.pages.back().page=="factory_inventory" and read_button!=null and not read_button.disabled and Data.json_equal(before,runtime.capture_checkpoint()))
	if read_button==null or read_button.disabled: return
	var pack: Dictionary=runtime.actor("player").pack.duplicate(true)
	read_button=button_with("在现场阅读路线记录"); read_button.pressed.emit(); await flush()
	check("native container story action records true onsite read and public clue",text_in(ui._body).contains("路线记录已记入手册") and runtime.factory_snapshot().map.markers.any(func(row: Dictionary): return row.get("kind")=="route_clue") and button_with("在现场阅读路线记录")==null)
	await open_stories()
	check("same formal handbook reflects source reading without a second UI state",text_in(ui._body).contains("读过现场路线记录") and button_with("在现场阅读路线记录")==null)
	check("route reading neither grants goods nor starts regional threat",runtime.actor("player").pack==pack and runtime.world.extension("r34:gameplay").defense.status=="dormant")
	before=runtime.capture_checkpoint()
	var refused: Dictionary=ui.execute("settlement.read_story","",{"story_id":"ST03","source_id":"not-a-source"})
	check("forged or stale source read fails visibly without writes",not refused.get("ok",false) and Data.json_equal(before,runtime.capture_checkpoint()) and not ui._notice.text.is_empty())
	var encoded: Dictionary=Store.encode(runtime.capture_checkpoint())
	var decoded: Dictionary=Store.decode(encoded.text) if encoded.get("ok",false) else encoded
	var cold: Dictionary=host._assemble(decoded.capture) if decoded.get("ok",false) else decoded
	check("true read and clue survive the same Native storage codec",cold.get("ok",false) and cold.runtime.factory_snapshot().map.markers.any(func(row: Dictionary): return row.get("kind")=="route_clue"),cold.get("reason"))
func finish() -> void:
	var failed: int=checks.filter(func(row: Dictionary): return not row.ok).size()
	var report: Dictionary={"checks":checks,"failed":failed,"scope":"actual normal-source Native/UI search/study/cancel/cold restore plus explicit synthetic public DTO privacy; no OS/VA/package/performance acceptance"}
	var saved:=FileAccess.open(output+"/results.json",FileAccess.WRITE); saved.store_string(JSON.stringify(report,"\t",true,true)); saved.close()
	if is_instance_valid(host): host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed})); quit(1 if failed else 0)
