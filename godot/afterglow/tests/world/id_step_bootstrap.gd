extends SceneTree
## Test-only source pack; no project/app export and no production instrumentation.
func _initialize()->void:call_deferred("run")
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2:quit(2);return
	var manifest:Variant=JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not manifest is Dictionary or ResourceLoader.has_cached("res://scripts/world/world_data.gd"):quit(3);return
	var pack:=PCKPacker.new()
	if pack.pck_start(args[1]+"/sources.pck")!=OK:quit(4);return
	for row:Dictionary in manifest.files:
		if pack.add_file(row.path,row.file)!=OK:quit(5);return
	if pack.flush()!=OK or not ProjectSettings.load_resource_pack(args[1]+"/sources.pck",true):quit(6);return
	var script:Script=load("res://tests/world/id_step_case.gd")
	if script==null:quit(7);return
	script.new().run(self,args[1],manifest)
