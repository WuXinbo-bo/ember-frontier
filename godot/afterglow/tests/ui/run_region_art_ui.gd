extends "res://tests/ui/run_architecture_catalog_ui.gd"
## Final22/v2 reuse delta only. Definitions and production/handbook are real;
## the standalone slot matrix is explicitly display-only, not owned inventory.
const Icons=preload("res://scripts/ui/ui_icons.gd")
const Slot=preload("res://scripts/ui/inventory_slot.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")

func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0];DirAccess.make_dir_recursive_absolute(output)
	var original:=FileAccess.get_file_as_string(args[1]);var decoded:=Store.decode(original)
	check("unchanged real QA capture decodes",decoded.get("ok",false))
	if not decoded.get("ok",false):return finish(1)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	host=TestNative.new();root.add_child(host)
	if not await assemble_capture(decoded.capture):return finish(1)
	var before:=runtime.capture_checkpoint();var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[2]));var entries:Array=manifest.entries
	check("final22 exact registered identities supplied",entries.size()==22 and Icons.REGION_ITEM_ICONS.size()==22)
	for entry:Dictionary in entries:
		var id:=str(entry.item_id);var display:Dictionary={"reference":{"kind":"item","item_id":id}}
		var icon:=Icons.texture(display);var source:=Image.load_from_file(args[2].get_base_dir().get_base_dir().get_base_dir().path_join(str(entry.path)))
		check("exact final PNG and registered Chinese name "+id,icon!=null and source!=null and icon.get_size()==Vector2(256,256) and icon.get_image().get_data()==source.get_data() and P.item_name(id)==str(Content.item_definition(id).get("name")) and not P.item_name(id).begins_with("r34:"))
		ui.open_handbook("item:"+id);await idle();await idle()
		check("real handbook binds item image "+id,ui._body.find_children("*","TextureRect",true,false).any(func(node):return node.texture==icon))
		if id in ["r34:raw_water","r34:filtered_water"]:check("actual handbook explicitly rejects drinking "+id,text_in(ui._body).contains("不可") and Content.consumable_definition(id,"drink").is_empty())
	var v2:Array=F.rows(ui.factory,"modules","definitions").filter(func(row:Dictionary):return row.get("mechanism",{}).get("version")==2)
	check("real build catalog publishes all30 new mechanism editions",v2.size()==30)
	for definition:Dictionary in v2:
		var parent:=F.definition(ui.factory,str(definition.get("geometry_source_id","")))
		var delivered:Dictionary=Pictures.ARCHITECTURE_MODULES.get(str(parent.get("id","")),{})
		var housing:Dictionary=Pictures.HOUSING_MECHANISM_V2.get(str(definition.id),{})
		var exact:bool=delivered.get("geometry_version")==definition.get("geometry_version")
		var housing_exact:bool=housing.get("geometry_source_id")==parent.get("id") and housing.get("geometry_version")==definition.get("geometry_version")
		check("explicit source adopts only exact delivered geometry "+str(definition.id),not parent.is_empty() and (Pictures.module_texture(definition)==Pictures.texture(housing.path) if housing_exact else Pictures.module_texture(definition)!=null and Pictures.module_texture(definition)==Pictures.module_texture(parent) if exact else Pictures.module_texture(definition)==null),{"geometry":definition.geometry_version,"image_geometry":housing.get("geometry_version",delivered.get("geometry_version")),"waiting_new_image":not exact and not housing_exact})
		var wrong:=definition.duplicate(true);wrong.geometry_version+=".unadopted"
		var missing:=definition.duplicate(true);missing.erase("geometry_source_id")
		check("never guess aliases or use mismatched geometry "+str(definition.id),Pictures.module_texture(wrong)==null and Pictures.module_texture(missing)==null)
	ui.close_panels()
	var matrix:=HFlowContainer.new();matrix.position=Vector2(24,24);matrix.size=Vector2(700,600);root.add_child(matrix)
	for entry:Dictionary in entries:
		var id:=str(entry.item_id);var slot:=Slot.new();matrix.add_child(slot)
		var reference:Dictionary={"kind":"item","item_id":id}
		slot.slot={"kind":"inventory","reference":reference,"quantity":1,"available":1,"entry":{"reference":reference,"name":P.item_name(id)}}
		slot.present(P.item_name(id))
		check("native display-only slot binds final image "+id,slot.get_meta("ui_icon").available and slot.find_children("*","TextureRect",true,false).any(func(node):return node.texture==Icons.texture({"reference":reference})))
		if id in ["r34:raw_water","r34:filtered_water"]:check("slot water safety is visible without hover "+id,text_in(slot).contains("不可饮用") and slot.tooltip_text.contains("不可"))
	matrix.free()
	ui.open_panel("factory_catalog");await idle();await idle()
	check("catalog honestly shows image or explicit new-geometry fallback",v2.all(func(row:Dictionary):return card(str(row.id))!=null and (not text_in(card(str(row.id))).contains("缩图待交付") if Pictures.module_texture(row)!=null else text_in(card(str(row.id))).contains("缩图待交付"))))
	for viewport:Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
		root.size=viewport;root.content_scale_size=viewport;ui.set_text_scale(1.0 if viewport.x==1280 else 1.5);await idle();await idle()
		check("new edition catalog remains scene-side at "+str(viewport),root.get_visible_rect().encloses(ui._dialog.get_global_rect()) and ui._body.get_combined_minimum_size().x<=ui._scroll.size.x+1)
	check("all art and metadata queries preserve authority and original file",Data.json_equal(before,runtime.capture_checkpoint()) and FileAccess.get_file_as_string(args[1])==original)
	finish(0 if checks.all(func(row:Dictionary):return row.ok) else 1)
