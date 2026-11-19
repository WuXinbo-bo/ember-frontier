extends RefCounted
## Functional illustrations frame live native labels; no world or command reads.
## A workbench/crate/bed illustration is never a claim about building geometry.
const Identity=preload("res://scripts/ui/building_identity.gd")
const Images=preload("res://scripts/ui/ui_images.gd")
const Icons=preload("res://scripts/ui/ui_icons.gd")
const F=preload("res://scripts/ui/factory_projection.gd")
const Palette=preload("res://scripts/ui/ui_theme.gd")
const ART_ROOT:="res://themes/illustrated19/"
const ILLUSTRATIONS:={"home":"header_home.png","warehouse":"header_warehouse.png","workshop":"header_workshop.png"}
static var _wash:Texture2D

static func art(definition:Dictionary)->Dictionary:
	var family:String=Identity.family(definition)
	# The three starting functions have purpose-made, text-free illustrations.
	if ILLUSTRATIONS.has(family):
		var path:String=ART_ROOT+str(ILLUSTRATIONS[family])
		var illustration:Texture2D=Images.texture(path)
		if illustration!=null:return {"texture":illustration,"kind":"function-illustration","category":family,"path":path}
	# Other buildings prefer their exact published geometry image.
	var geometry:Texture2D=Images.module_texture(definition)
	if geometry!=null:return {"texture":geometry,"kind":"building-geometry","category":family,"path":geometry.resource_path}
	# A tool vignette is a neutral fallback for industrial functions, not a house.
	if family in ["sawmill","artisan","repair","machine"]:
		var path:String=ART_ROOT+str(ILLUSTRATIONS.workshop)
		var illustration:Texture2D=Images.texture(path)
		if illustration!=null:return {"texture":illustration,"kind":"function-illustration","category":"workshop","path":path}
	var symbol:Texture2D
	if family=="home":symbol=Icons.status_texture("fatigue")
	elif family in ["warehouse","supply"]:symbol=Icons.status_texture("inventory")
	elif family=="water":symbol=Icons.texture({"reference":{"kind":"item","item_id":"water"}})
	elif family=="canteen":symbol=Icons.texture({"reference":{"kind":"item","item_id":"r34:meal_simple"}})
	elif family in ["workshop","sawmill","artisan","repair","machine"]:symbol=Icons.texture({"reference":{"kind":"tool"},"definition_id":"hammer"})
	else:symbol=Palette.control_glyph("map",2.0,Palette.MOSS)
	return {"texture":symbol,"kind":"function-symbol","category":family,"path":""}

static func render(ui,parent:Node,module:Dictionary,definition:Dictionary)->PanelContainer:
	var scale_factor:float=clampf(float(ui.text_scale),0.75,2.0)
	var selected:Dictionary=art(definition)
	var banner:=PanelContainer.new()
	banner.name="BuildingHero19"
	banner.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	banner.custom_minimum_size.y=roundi(116*scale_factor)
	banner.mouse_filter=Control.MOUSE_FILTER_IGNORE
	banner.clip_contents=true
	banner.set_meta("ui_building_identity",str(module.get("id","")))
	banner.set_meta("ui_building_hero19",str(module.get("id","")))
	banner.set_meta("ui_hero_family",Identity.family(definition))
	banner.set_meta("ui_hero_art_kind",str(selected.kind))
	banner.set_meta("ui_hero_art_category",str(selected.category))
	banner.set_meta("ui_hero_art_path",str(selected.path))
	var frame:=StyleBoxFlat.new()
	frame.bg_color=Palette.SURFACE;frame.border_color=Palette.EDGE
	frame.set_border_width_all(1);frame.set_corner_radius_all(6)
	banner.add_theme_stylebox_override("panel",frame)
	parent.add_child(banner)
	var art_layer:=Control.new();art_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE;banner.add_child(art_layer)
	var picture:=TextureRect.new()
	picture.name="BuildingHeroArt";picture.texture=selected.texture
	picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED if selected.kind=="function-illustration" else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if selected.kind!="function-illustration":picture.anchor_left=0.59;picture.offset_left=0
	picture.set_meta("ui_hero_image",true)
	picture.set_meta("ui_function_illustration",selected.kind=="function-illustration")
	art_layer.add_child(picture)
	var veil:=TextureRect.new();veil.name="BuildingHeroLegibility";veil.texture=_wash_texture()
	veil.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;veil.stretch_mode=TextureRect.STRETCH_SCALE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);veil.mouse_filter=Control.MOUSE_FILTER_IGNORE
	art_layer.add_child(veil)
	var inset:=MarginContainer.new();inset.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for edge:String in ["left","right"]:inset.add_theme_constant_override("margin_"+edge,roundi(14*scale_factor))
	for edge:String in ["top","bottom"]:inset.add_theme_constant_override("margin_"+edge,roundi(10*scale_factor))
	banner.add_child(inset)
	var line:=HBoxContainer.new();line.mouse_filter=Control.MOUSE_FILTER_IGNORE;line.add_theme_constant_override("separation",0);inset.add_child(line)
	var text:=VBoxContainer.new();text.mouse_filter=Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;text.size_flags_stretch_ratio=1.5
	text.size_flags_vertical=Control.SIZE_SHRINK_CENTER;text.add_theme_constant_override("separation",roundi(4*scale_factor));line.add_child(text)
	_label(text,"BuildingHeroTitle",Identity.instance_name(definition,module),roundi(23*scale_factor),Palette.INK,"ui_hero_live_title")
	_label(text,"BuildingHeroPurpose",Identity.purpose(definition),roundi(13*scale_factor),Palette.INK,"ui_hero_live_purpose")
	var state_line:=HBoxContainer.new();state_line.mouse_filter=Control.MOUSE_FILTER_IGNORE;text.add_child(state_line)
	var badge:=PanelContainer.new();badge.mouse_filter=Control.MOUSE_FILTER_IGNORE
	badge.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var status:StyleBoxFlat=Palette.box(Color("f7f1df"),Palette.EDGE,1)
	status.content_margin_left=7;status.content_margin_right=7;status.content_margin_top=3;status.content_margin_bottom=3
	badge.add_theme_stylebox_override("panel",status);state_line.add_child(badge)
	var warning:bool=str(module.get("state_code",module.get("status",""))) in ["needs_restoration","ruined","damaged","blocked","missing_input","missing_energy","output_full"]
	_label(badge,"BuildingHeroState",F.state_text(module),roundi(12*scale_factor),Palette.RUST if warning else Palette.MOSS,"ui_hero_live_state")
	var reserved_art:=Control.new();reserved_art.mouse_filter=Control.MOUSE_FILTER_IGNORE
	reserved_art.size_flags_horizontal=Control.SIZE_EXPAND_FILL;reserved_art.size_flags_stretch_ratio=1.0;line.add_child(reserved_art)
	return banner

static func _label(parent:Node,node_name:String,value:String,font_size:int,color:Color,identity:String)->Label:
	var label:=Label.new();label.name=node_name;label.text=value
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.clip_text=false;label.text_overrun_behavior=TextServer.OVERRUN_NO_TRIMMING
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.set_meta(identity,true);parent.add_child(label)
	return label

static func _wash_texture()->Texture2D:
	if _wash!=null:return _wash
	var gradient:=Gradient.new()
	gradient.offsets=PackedFloat32Array([0.0,0.49,0.7,1.0])
	var paper:Color=Palette.SURFACE
	gradient.colors=PackedColorArray([Color(paper,0.98),Color(paper,0.96),Color(paper,0.0),Color(paper,0.0)])
	var texture:=GradientTexture2D.new();texture.width=256;texture.height=1;texture.gradient=gradient
	texture.fill_from=Vector2.ZERO;texture.fill_to=Vector2.RIGHT;_wash=texture
	return _wash
