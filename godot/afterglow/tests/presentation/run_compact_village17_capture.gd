extends SceneTree
## Capture the shipping camera and mounted world. Focus on a site for detail.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
class CaptureClient extends Native:
	func _ready()->void:pass

func _initialize()->void:call_deferred("run")

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name()=="headless":quit(2);return
	var out:String=args[0]
	DirAccess.make_dir_recursive_absolute(out)
	root.size=Vector2i(1280,800)
	var host:=CaptureClient.new()
	host.controls_path=out+"/controls.json";host.store=Store.new(out+"/isolated-saves")
	root.add_child(host)
	var made:Dictionary={}
	if args.size()>1:
		var decoded:=Store.decode(FileAccess.get_file_as_string(args[1]))
		if not decoded.ok:push_error(str(decoded));quit(1);return
		made=await host._mount_ready(decoded.capture)
	else:made=await host.start_profiled_world("normal",713,"compact-village-graphics")
	if not made.get("ok",false):push_error(str(made));quit(1);return
	host.runtime.set_paused(true);host.set_process(false)
	var failed:bool=not await shot(out+"/opening.png")
	var modules:RefCounted=host.runtime._services.modules
	for spec:Array in [["workshop","r34:generated:RH-HOME:woodwork"],["warehouse","r34:generated:RH-HOME:village-warehouse"],["sawmill","compact17:test:saw"],["water","v18:test:water"],["kitchen","v19:test:kitchen"],["repair","v19:test:repair"],["heritage-mill","RH-HOME:woodshop-old-frame"]]:
		var row:Dictionary=modules.instance(spec[1])
		if row.is_empty():continue
		var p:Dictionary=row.position;var focus:=Vector3(p.x,p.y,p.z)
		host.camera.position=focus+host._camera_offset
		host.camera.look_at(focus,Vector3.UP)
		if not await shot(out+"/"+str(spec[0])+"-normal.png"):failed=true
		host.camera.size=12
		if not await shot(out+"/"+str(spec[0])+"-close.png"):failed=true
		host.camera.size=24
	var until:=Time.get_ticks_msec()+30000
	while host._streaming and Time.get_ticks_msec()<until:await process_frame
	print("Compact village graphics captured in "+out)
	quit(1 if host._streaming or failed else 0)

func shot(path:String)->bool:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	return image.save_png(path)==OK
