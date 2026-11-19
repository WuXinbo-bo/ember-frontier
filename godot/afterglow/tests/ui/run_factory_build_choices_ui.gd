extends "res://tests/ui/run_os_feedback_ui.gd"
## Actual B current-choice projection through the original Native UI. Historical
## definitions/instances stay readable. DTO-only edge probes are labelled below.
const Pictures = preload("res://scripts/ui/ui_images.gd")
const NEW_IDS := ["r34.module.woodshop_long_v3","r34.module.woodshop_yard_v3","r34.module.home_court_v3","r34.module.home_roadside_v3","r34.module.warehouse_long_v3","r34.module.warehouse_court_v3"]
const RETAINED_CHOICES := ["r34.module.hand_workshop","r34.module.repair_shed_v2","r34.module.supply_roadside_v2","r34.module.supply_rear_v3"]
class Pointer extends "res://scripts/input/direct_interaction.gd":
	func _refresh() -> void: pass
	func _process(_delta: float) -> void: pass

func ids_of(rows: Array) -> Array:
	return rows.map(func(row: Dictionary):return str(row.get("id","")))

func preview_ids() -> Array:
	var ids: Array=[]
	for button: Node in ui.find_children("*","Button",true,false):
		var key: String=str(button.get_meta("ui_focus_key",""))
		if key.begins_with("factory:preview:"):ids.append(key.trim_prefix("factory:preview:"))
	return ids

func run() -> void:
	var args:=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	if args.size()<2:check("original normal-economy input supplied",false);return finish(1)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	var original: String=FileAccess.get_file_as_string(args[1])
	var decoded: Dictionary=Store.decode(original)
	check("historical normal-economy save decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish(1)
	host=TestNative.new();root.add_child(host)
	if not await assemble_capture(decoded.capture):return finish(1)
	# Original A cancellation consumer, with only ray/3D refresh disabled. A
	# mounted router alone emits cancel_requested; it does not own mode reset.
	var camera:=Camera3D.new();host.add_child(camera)
	var pointer:=Pointer.new();host.add_child(pointer)
	pointer.configure({"runtime":runtime,"world":world,"router":router,"camera":camera,"buildings":null,"terrain":host,"ui":ui})
	var before: Dictionary=runtime.capture_checkpoint()
	var published: Dictionary=runtime.factory_snapshot("player")
	var owner_ids: Array=published.modules.get("build_definition_ids",[])
	var expected: Array=NEW_IDS+RETAINED_CHOICES
	var sorted_owner:=owner_ids.duplicate();sorted_owner.sort();expected.sort()
	check("real modules owner publishes exact ten current choices",owner_ids.size()==10 and sorted_owner==expected,owner_ids)
	check("real modules keeps all eighteen historical definitions",F.rows(published,"modules","definitions").size()==18)
	check("UI choices preserve owner order without duplicates",ids_of(F.build_definitions(published))==owner_ids)
	for id: String in NEW_IDS:
		var definition: Dictionary=F.definition(published,id)
		# source03 art is now adopted. The archived build-choices02 retains the
		# earlier no-image evidence; current runs must consume the new exact image.
		check("new definition stays geometry-v2 with its adopted thumbnail "+id,not definition.is_empty() and definition.get("geometry_version")==id+".geometry-v2" and Pictures.module_texture(definition)!=null)
	# Explicit read-only DTO compatibility/invalid-input probes. They never
	# replace the runtime projection or act as permission to build anything.
	var legacy: Dictionary=published.duplicate(true);legacy.modules.erase("build_definition_ids")
	check("missing field retains historical UI behaviour",ids_of(F.build_definitions(legacy))==ids_of(F.rows(legacy,"modules","definitions")))
	var empty: Dictionary=published.duplicate(true);empty.modules.build_definition_ids=[]
	check("explicit empty current choices do not promote historical definitions",F.build_definitions(empty).is_empty())
	var malformed: Dictionary=published.duplicate(true);malformed.modules.build_definition_ids=null
	check("malformed present field fails closed for menu selection",F.build_definitions(malformed).is_empty())
	var unknown: Dictionary=published.duplicate(true);unknown.modules.build_definition_ids=[owner_ids[0],owner_ids[0],"not-a-real-definition",42]
	check("unknown duplicate and non-string ids never create menu choices",ids_of(F.build_definitions(unknown))==[owner_ids[0]])
	var input_before: Dictionary=published.duplicate(true)
	var copies: Array=F.build_definitions(published);copies[0].name="DTO-only mutation probe"
	check("menu projection detaches rows and leaves owner snapshot untouched",Data.json_equal(input_before,published))
	ui.open_panel("factory_catalog");await idle();await idle()
	check("actual catalogue renders ten owner choices rather than eighteen",preview_ids()==owner_ids,preview_ids())
	var current_id: String=NEW_IDS[0]
	ui.factory_favorites[current_id]=true
	ui.factory_favorites["r34.module.home_service"]=true
	ui.factory_view.catalog_category="favorites";ui.refresh();await idle()
	check("favorites remain scoped to current choices without deleting old preferences",preview_ids()==[current_id] and ui.factory_favorites.has("r34.module.home_service"),preview_ids())
	ui.factory_view.catalog_category="all"
	ui.factory_view.catalog_search=str(F.definition(published,current_id).name)
	ui.refresh();await idle()
	check("search filters current choices and retains the new definition",preview_ids().has(current_id) and preview_ids().size()<=owner_ids.size(),preview_ids())
	ui.factory_view.catalog_search="";ui.refresh();await idle()
	var action: Button=keyed("factory:preview:"+current_id) as Button
	if action!=null:ui._scroll.ensure_control_visible(action);await idle()
	check("new current-choice native placement action is reachable",action!=null and not action.disabled and root.get_visible_rect().encloses(action.get_global_rect()))
	if action==null:return finish(1)
	await click(action.get_global_rect().get_center())
	check("native click routes exact definition to the original placement owner",router.state().mode=="module_place" and router.state().module_definition_id==current_id,router.state())
	check("choosing a current building neither spends materials nor creates geometry",Data.json_equal(before,runtime.capture_checkpoint()))
	await key(KEY_ESCAPE)
	check("Esc cancels original placement without authority changes",router.state().mode!="module_place" and Data.json_equal(before,runtime.capture_checkpoint()),{"mode":router.state().mode,"checkpoint_unchanged":Data.json_equal(before,runtime.capture_checkpoint())})
	var old_instance: Dictionary={}
	for row: Dictionary in F.rows(published,"modules","instances"):
		if not owner_ids.has(str(row.get("definition_id",""))):old_instance=row;break
	check("historical save retains an actual old-definition facility",not old_instance.is_empty(),old_instance.get("definition_id"))
	if not old_instance.is_empty():
		var old_id: String=str(old_instance.definition_id)
		ui.close_panels();ui.open_panel("factory_module",str(old_instance.id));await idle()
		check("old facility detail uses the same real instance and full definition",ui.pages.back().subject==old_instance.id and not F.instance(ui.factory,str(old_instance.id)).is_empty() and not F.definition(ui.factory,old_id).is_empty())
		ui.open_handbook("module:"+old_id);await idle()
		check("old module handbook remains queryable after menu filtering",ui.handbook.get("available",false) and ui.handbook.get("selection",{}).get("id")=="module:"+old_id,ui.handbook.get("selection",{}).get("id"))
	ui.close_panels();root.size=Vector2i(1000,700);root.content_scale_size=root.size;ui.set_text_scale(1.5)
	ui.open_panel("factory_catalog");await idle();await idle()
	check("current choices retain small-window large-type title and return bounds",preview_ids()==owner_ids and root.get_visible_rect().encloses(ui._dialog.get_global_rect()) and root.get_visible_rect().encloses(ui._back_button.get_global_rect()),str(ui._dialog.get_global_rect()))
	check("catalogue compatibility keeps original checkpoint and input bytes",Data.json_equal(before,runtime.capture_checkpoint()) and FileAccess.get_file_as_string(args[1])==original)
	finish(0 if checks.all(func(row: Dictionary):return row.ok) else 1)

func finish(code: int) -> void:
	var failed: int=checks.filter(func(row: Dictionary):return not row.ok).size()
	if not output.is_empty():
		var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failed":failed,"trace":trace,"method":"Actual B build_definition_ids via original Runtime/Native/UI and untouched old normal-economy save; current catalogue native pointer/placement/cancel via real A adapter with ray/3D refresh disabled; historical instance and handbook; explicit detached DTO edge probes","scope":"Current source headless Control only, no new geometry/PCK/OS/renderer/Retina/VA/WF/FPS/G5 qualification"},"\t",true,true));file.close()
	if is_instance_valid(host):host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(code)
