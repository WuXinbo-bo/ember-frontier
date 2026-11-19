extends SceneTree
## Native layout and Viewport input; generated assets stay decoration only.
const Hero=preload("res://scripts/ui/building_hero19.gd")
const Images=preload("res://scripts/ui/ui_images.gd")
const Palette=preload("res://scripts/ui/ui_theme.gd")
const Data=preload("res://scripts/world/world_data.gd")
class Facade extends RefCounted:
	var text_scale:float=1.0
var checks:Array=[]
var observed:Array=[]
var presses:int=0
var body:VBoxContainer
var scroll:ScrollContainer
func check(label:String,ok:bool,detail:Variant=null)->void:checks.append({"name":label,"ok":ok,"detail":detail})
func _initialize()->void:call_deferred("run")
func flush()->void:
	await process_frame;await process_frame;await process_frame
func label(parent:Node,name_:String)->Label:return parent.find_child(name_,true,false) as Label
func decorative_input_only(parent:Node)->bool:
	if parent is Control and parent.mouse_filter!=Control.MOUSE_FILTER_IGNORE:return false
	for child:Node in parent.get_children():
		if not decorative_input_only(child):return false
	return true
func clear_body()->void:
	for child:Node in body.get_children():child.free()
	scroll.scroll_vertical=0
func run()->void:
	root.size=Vector2i(1000,700);root.content_scale_size=root.size
	var canvas:=Control.new();canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(canvas)
	canvas.theme=Palette.create(null,1.0)
	scroll=ScrollContainer.new();scroll.position=Vector2(450,16);scroll.size=Vector2(520,668)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;canvas.add_child(scroll)
	body=VBoxContainer.new();body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(body)
	var ui:=Facade.new()
	for family:String in ["workshop","warehouse","home"]:
		clear_body()
		var definition:Dictionary={"id":"public-"+family,"mechanism":{"family":family},"generation_role":"home" if family=="home" else "storage" if family=="warehouse" else "workshop"}
		var module:Dictionary={"id":"observed-"+family,"state_code":"needs_restoration","state_label":"待修复"}
		var before:Dictionary={"module":module.duplicate(true),"definition":definition.duplicate(true)}
		var banner:=Hero.render(ui,body,module,definition)
		await flush()
		var art:TextureRect=banner.find_child("BuildingHeroArt",true,false) as TextureRect
		check("real illustration asset used "+family,art!=null and art.texture!=null and banner.get_meta("ui_hero_art_kind","")=="function-illustration" and banner.get_meta("ui_hero_art_category","")==family,banner.get_meta("ui_hero_art_path",""))
		check("banner fills native page width "+family,banner.size.x>=body.size.x-2 and banner.size.y>=110,banner.size)
		check("full width image is separate from native live labels "+family,art!=null and art.size.x>=banner.size.x-4 and label(banner,"BuildingHeroTitle")!=null and label(banner,"BuildingHeroState").text=="待修复")
		check("all banner decoration ignores input "+family,decorative_input_only(banner))
		check("existing identity marker remains exact "+family,banner.get_meta("ui_building_identity","")==module.id)
		check("render does not edit published facts "+family,Data.json_equal(before,{"module":module,"definition":definition}))
		observed.append({"family":family,"art_kind":banner.get_meta("ui_hero_art_kind"),"path":banner.get_meta("ui_hero_art_path"),"size":{"x":banner.size.x,"y":banner.size.y},"title":label(banner,"BuildingHeroTitle").text})
	clear_body()
	var sawmill:Dictionary={"id":"r34.module.sawmill_mid_v1","geometry_version":"r34.module.sawmill_mid_v1.geometry-v1","architecture":{"family":"sawmill"}}
	var actual:Texture2D=Images.module_texture(sawmill)
	var selected:Dictionary=Hero.art(sawmill)
	check("sawmill uses its exact geometry when published",selected.kind=="building-geometry" and selected.texture==actual if actual!=null else selected.kind!="building-geometry")
	check("sawmill is never illustrated as a residence",selected.category!="home" and not str(selected.path).ends_with("header_home.png"))
	var custom:Dictionary={"id":"custom-home","custom_name":"河湾东侧第一栋同伴住宅与生活补给屋","state_code":"blocked","state_label":"正在等待木板送达"}
	var definition:Dictionary={"id":"home","mechanism":{"family":"home"}}
	var before:Dictionary=custom.duplicate(true)
	ui.text_scale=1.25
	var banner:=Hero.render(ui,body,custom,definition)
	var action:=Button.new();action.text="可用功能";action.pressed.connect(func():presses+=1);body.add_child(action)
	var filler:=Control.new();filler.custom_minimum_size.y=700;body.add_child(filler)
	await flush()
	var title:Label=label(banner,"BuildingHeroTitle")
	check("custom name is live native text",title.text==custom.custom_name)
	check("live status remains original DTO text",label(banner,"BuildingHeroState").text==custom.state_label)
	check("long title wraps without text truncation",title.autowrap_mode==TextServer.AUTOWRAP_WORD_SMART and not title.clip_text and title.text_overrun_behavior==TextServer.OVERRUN_NO_TRIMMING and title.max_lines_visible==-1 and title.get_line_count()>1,title.get_line_count())
	check("native header grows to keep full text inside",title.get_global_rect().end.y<=banner.get_global_rect().end.y and title.get_global_rect().end.x<=banner.get_global_rect().end.x)
	check("small window keeps a scrollable native action page",banner.size.x<=520 and scroll.get_v_scroll_bar().max_value>scroll.size.y)
	var at:Vector2=action.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new();motion.position=at;root.push_input(motion,true);await flush()
	for pressed:bool in [true,false]:
		var event:=InputEventMouseButton.new();event.position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true);await flush()
	check("real Viewport click reaches native action below artwork",presses==1,presses)
	check("layout and clicking retain published module state",Data.json_equal(before,custom))
	clear_body();custom.state_code="running";custom.state_label="运行中";var refreshed:=Hero.render(ui,body,custom,definition);await flush()
	check("rerender reflects changed live status",label(refreshed,"BuildingHeroState").text=="运行中")
	var failed:int=checks.filter(func(row:Dictionary):return not row.ok).size()
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():
		DirAccess.make_dir_recursive_absolute(args[0]);var output:=FileAccess.open(args[0]+"/results.json",FileAccess.WRITE)
		output.store_string(JSON.stringify({"checks":checks,"failed":failed,"observed":observed,"scope":"Native hero controls, exact asset identity, live public labels, small-window wrapping/scrolling and real Viewport button input. No commands, world simulation, GPU frame-rate or geometry equivalence claim."},"\t",true,true));output.close()
	canvas.free();print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
