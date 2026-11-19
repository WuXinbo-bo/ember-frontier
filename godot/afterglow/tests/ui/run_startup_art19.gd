extends SceneTree
const Shell19=preload("res://scripts/runtime/startup_shell.gd")
var checks:Array=[]
var output:String=""
var shell:CanvasLayer
var graphics:bool=false
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func flush()->void:
	await process_frame;await process_frame;await process_frame
func capture(label:String)->void:
	if not graphics:return
	await RenderingServer.frame_post_draw
	check("real renderer capture "+label,root.get_texture().get_image().save_png(output+"/"+label+".png")==OK)
func click(button:Button)->void:
	var point:Vector2=button.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point
	root.push_input(motion,true);await flush()
	for down:bool in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
		root.push_input(event,true);await flush()
func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0]
	graphics=args.has("--graphics") and DisplayServer.get_name()!="headless"
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	shell=Shell19.new();root.add_child(shell);await flush()
	var art:TextureRect=shell.find_child("VillageMenuIllustration19",true,false)
	check("menu uses actual local generated scenery",art!=null and art.texture!=null and art.texture.get_size()==Vector2(1280,720))
	check("illustration never receives mouse input",art!=null and art.mouse_filter==Control.MOUSE_FILTER_IGNORE)
	for size:Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
		root.size=size;root.content_scale_size=size;await flush()
		shell.show_menu();await flush()
		check("menu has four live interactive buttons "+str(size.x),shell._buttons.get_child_count()==4)
		check("menu actions fit within viewport "+str(size.x),shell._buttons.get_children().all(func(node:Node):return root.get_visible_rect().encloses(node.get_global_rect())))
		check("menu primary uses image skin "+str(size.x),shell._buttons.get_child(0).get_theme_stylebox("normal") is StyleBoxTexture)
		await capture("menu-"+str(size.x))
		shell.show_stage("terrain","正在准备村庄","正在核对村庄附近的实际地形与通路。");await flush()
		shell.show_evidence("近域地形与碰撞校验进行中")
		check("loading displays actual supplied phase without fake progress",shell.snapshot().state=="busy" and shell.snapshot().phase=="terrain" and shell._caption.text=="近域地形与碰撞校验进行中")
		await capture("loading-"+str(size.x))
		shell.show_close_failed({"ok":false,"code":"IO_ERROR","reason":"测试保存失败，保留当前世界"});await flush()
		check("close failure retains retry and cancel actions",shell._buttons.get_child_count()==2 and shell.snapshot().state=="close_failed")
		await capture("close-failed-"+str(size.x))
	shell.show_menu();await flush()
	var chosen:Array=[];shell.chosen.connect(func(action:String):chosen.append(action))
	var first:Button=shell._buttons.get_child(0)
	await click(first)
	check("real menu click dispatches one original normal action",chosen==["normal"])
	check("accepted menu click disables repeat dispatch",shell._buttons.get_children().all(func(node:Button):return node.disabled))
	await click(first)
	check("repeated native click cannot start two worlds",chosen==["normal"])
	shell.show_result({"ok":true,"reason":"实际就绪回执"},true);await flush()
	check("real readiness receipt dismisses menu",shell.snapshot().state=="ready" and not shell._shade.visible)
	shell.free()
	var failed:int=checks.filter(func(row:Dictionary):return not row.ok).size()
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failed":failed,"scope":"Native startup shell art, two-size renderer snapshots and actual Viewport menu click. Injected stage/result receipts test display only, not disk save or full world loading."},"\t",true,true));file.close()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
