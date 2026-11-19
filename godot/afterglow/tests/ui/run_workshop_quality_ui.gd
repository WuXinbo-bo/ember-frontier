extends "res://tests/ui/run_os_feedback_ui.gd"
## Real fresh Native owner refusal, native controls and an explicit in-memory
## nine-slice branch probe. No renderer, art delivery or package qualification.
const WorkshopTheme = preload("res://scripts/ui/ui_theme.gd")
const FactoryPanels = preload("res://scripts/ui/factory_panels.gd")
class Pointer extends "res://scripts/input/direct_interaction.gd":
	func _refresh() -> void: pass
	func _process(_delta: float) -> void: pass

func run() -> void:
	var args := OS.get_cmdline_user_args(); output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,800); root.content_scale_size = root.size
	host = TestNative.new(); root.add_child(host)
	var profiles: Dictionary = Assembly.generation_profiles()
	var prepared: Dictionary = Assembly.prepare(Assembly.generate(713,profiles.profiles))
	check("fresh normal world prepares with existing content lock",prepared.get("ok",false))
	if not prepared.get("ok",false): return finish(1)
	var made: Dictionary = host._assemble(prepared.capture)
	check("same Native configures current real owners",made.get("ok",false),made.get("reason"))
	if not made.get("ok",false): return finish(1)
	runtime=made.runtime; world=made.world
	router=Router.new(); host.add_child(router); router.configure(runtime)
	ui=Mount.mount(host,runtime,router); await idle(); await idle()
	var before: Dictionary = runtime.capture_checkpoint()
	var pointer := Pointer.new(); host.add_child(pointer)
	pointer.runtime=runtime; pointer.world=world; pointer.router=router; pointer.ui=ui; pointer.modules=made.services.modules
	var subject: Dictionary = {}; var receipt: Dictionary = {}
	for entity: Dictionary in world.entities():
		if not entity.get("data",{}).get("module_target",false): continue
		var ready: Dictionary=runtime.availability({"actor_id":"player","kind":"module.discover","target_id":entity.id,"payload":{}})
		if ready.get("code")=="MODULE_DISCOVER_REQUIRES_CONTACT": subject=entity; receipt=ready; break
	check("actual fresh owner produces unmet first-contact receipt",not subject.is_empty() and not receipt.get("ok",true),receipt)
	if subject.is_empty(): return finish(1)
	var original: Dictionary=receipt.duplicate(true)
	var target: Dictionary=pointer._describe(subject)
	check("A actual shell adapter carries original B code without granting discovery",target.get("code")==receipt.code and target.get("reason")==receipt.reason and target.get("primary")=="module_discover" and not target.get("enabled",true),target)
	runtime.set_target(target); ui.refresh(); await idle()
	check("world prompt explains actual contact and next action",ui._target_text.text.contains("服务面") and ui._target_text.text.contains("走近") and not ui._target_text.text.contains(receipt.code),ui._target_text.text)
	check("world prompt keeps original owner diagnostic",ui._target_text.tooltip_text.contains(receipt.code))
	pointer._feedback(receipt)
	check("actual receipt banner explains contact and retains exact code",ui._notice.text.contains("入口或装卸口") and not ui._notice.text.contains(receipt.code) and ui._notice.tooltip_text.contains("code: "+receipt.code),ui._notice.text)
	pointer._target=target; pointer._interact()
	check("disabled E path explains rejection without opening a menu",ui._notice.text.contains("走近") and ui._notice.tooltip_text==receipt.reason and ui.pages.is_empty())
	var rejected: Dictionary=ui.execute("module.discover",str(subject.id),{})
	check("real command still rejects first contact and leaves reason intact",not rejected.get("ok",true) and rejected.get("code")==receipt.code and rejected.get("reason")==receipt.reason,rejected)
	check("refused contact never discovers inventory or advances authority",Data.json_equal(before,runtime.capture_checkpoint()) and F.instance(ui.factory,str(subject.id)).is_empty() and Data.json_equal(original,receipt))
	var probe:=VBoxContainer.new(); ui.add_child(probe)
	var disabled:Button=ui.add_button("查看地点",func():check("disabled action never invokes callback",false),"quality:blocked",str(receipt.reason),probe)
	check("disabled control and reason caption both use player copy",disabled.disabled and not text_in(probe).contains(receipt.code) and text_in(probe).contains("服务面") and not disabled.tooltip_text.contains(receipt.code))
	FactoryPanels._blockers(ui,{"blockers":[receipt,{"code":"SOME_FUTURE_CODE","reason":""},{"reason":"门关闭，请先打开门"}]},probe)
	check("dictionary blockers use same player mapping and preserve specific reason",text_in(probe).contains("服务面") and text_in(probe).contains("重新查看目标") and text_in(probe).contains("门关闭，请先打开门") and not text_in(probe).contains("SOME_FUTURE_CODE"),text_in(probe))
	check("unknown machine identifiers get conservative advice without invented requirement",P.reason_text("SOME_FUTURE_CODE").contains("条件尚未满足") and P.reason_text("new_owner_reason").contains("重新查看目标") and P.reason_text("材料不足或已预留：timber")=="材料不足或已预留：木料" and P.reason_text("门关闭，请先打开门")=="门关闭，请先打开门")
	probe.free()
	for viewport:Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
		root.size=viewport; root.content_scale_size=viewport; ui.set_text_scale(1.0 if viewport.x==1280 else 1.5)
		for page:String in ["factory","factory_people","factory_catalog","pause"]:
			ui.close_panels(); ui.open_panel(page); await idle(); await idle()
			check("workshop shell remains inside viewport "+page+str(viewport),root.get_visible_rect().encloses(ui._dialog.get_global_rect()),str(ui._dialog.get_global_rect()))
			check("native title and return stay reachable "+page+str(viewport),root.get_visible_rect().encloses(ui._title.get_global_rect()) and root.get_visible_rect().encloses(ui._back_button.get_global_rect()) and ui._back_button.focus_mode==Control.FOCUS_ALL)
			if page in ["factory","factory_people"] and viewport.x==1280:
				check("new title plate keeps sparse content compact "+page,ui._dialog.size.y<680 and ui._dialog.size.x<1000,str(ui._dialog.get_global_rect()))
	check("shell changes no inventory discovery time or command facts",Data.json_equal(before,runtime.capture_checkpoint()))
	# This synthetic texture exists only in memory to exercise the optional
	# native style branch. It is not delivered artwork or a rendered screenshot.
	for kind:String in ["panel","title","slot"]:
		var original_texture:Variant=WorkshopTheme._chrome_textures.get(kind)
		WorkshopTheme._chrome_textures[kind]=null
		var fallback:StyleBox=WorkshopTheme.chrome(kind)
		var spec:Dictionary=WorkshopTheme.CHROME[kind]
		var image:=Image.create(spec.size.x,spec.size.y,false,Image.FORMAT_RGBA8); image.fill(Color("212223"))
		WorkshopTheme._chrome_textures[kind]=ImageTexture.create_from_image(image)
		var textured:StyleBox=WorkshopTheme.chrome(kind)
		check("optional nine-slice has stable content and minimum metrics "+kind,textured is StyleBoxTexture and fallback.get_minimum_size()==textured.get_minimum_size() and fallback.get_content_margin(SIDE_LEFT)==textured.get_content_margin(SIDE_LEFT),{"before":str(fallback.get_minimum_size()),"after":str(textured.get_minimum_size())})
		check("native nine-slice uses exact pixel cuts and stretches center "+kind,textured.get_texture_margin(SIDE_LEFT)==spec.slices.x and textured.get_texture_margin(SIDE_TOP)==spec.slices.y and textured.axis_stretch_horizontal==StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH and textured.draw_center)
		WorkshopTheme._chrome_textures[kind]=original_texture
	check("style probes do not change authority",Data.json_equal(before,runtime.capture_checkpoint()))
	finish(0 if checks.all(func(row:Dictionary):return row.ok) else 1)

func finish(code:int)->void:
	var failed:int=checks.filter(func(row:Dictionary):return not row.ok).size()
	if not output.is_empty():
		var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failed":failed,"method":"Actual fresh normal Native/real B first-contact rejection through A adapter and native UI; exact authority comparison; title/window bounds; explicit in-memory style branch probe only","scope":"Current source headless Control, no OS/PCK/Retina/renderer/art delivery/VA/WF/FPS/G5"},"\t",true,true));file.close()
	if is_instance_valid(host):host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(code)
