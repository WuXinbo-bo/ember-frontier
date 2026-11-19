extends CanvasLayer
## Native-owned lifecycle surface; survives replacement of the player UI/world.
const ShellTheme=preload("res://scripts/ui/ui_theme.gd")
const Images19=preload("res://scripts/ui/ui_images.gd")
const Feedback19=preload("res://scripts/ui/ui_feedback19.gd")
signal chosen(action:String)
var state:String="hidden"
var phase:String=""
var sequence:int=0
var history:Array=[]
var _root:Control
var _shade:ColorRect
var _title:Label
var _detail:Label
var _caption:Label
var _buttons:VBoxContainer
var _notice:PanelContainer
var _notice_text:Label
var _notice_deadline:int=0

func _ready()->void:
	layer=60;name="LifecycleInterface";process_mode=Node.PROCESS_MODE_ALWAYS
	_root=Control.new();_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_root.theme=ShellTheme.create(load("res://themes/fonts/NotoSansCJKsc-Regular.otf"));add_child(_root)
	_shade=ColorRect.new();_shade.color=Color("e1d8bf");_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_root.add_child(_shade)
	var illustration:=TextureRect.new();illustration.name="VillageMenuIllustration19"
	illustration.texture=Images19.texture("res://themes/illustrated19/menu_background.jpg")
	illustration.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;illustration.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	illustration.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);illustration.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_shade.add_child(illustration)
	var wash:=ColorRect.new();wash.color=Color(0.08,0.11,0.08,0.28);wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);wash.mouse_filter=Control.MOUSE_FILTER_IGNORE;_shade.add_child(wash)
	var center:=CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);center.mouse_filter=Control.MOUSE_FILTER_IGNORE;_shade.add_child(center)
	var paper:=PanelContainer.new();paper.name="VillageOpening";paper.custom_minimum_size=Vector2(530,0);paper.add_theme_stylebox_override("panel",ShellTheme.chrome("panel"));center.add_child(paper)
	var margin:=MarginContainer.new()
	for edge:String in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+edge,28)
	paper.add_child(margin)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",16);margin.add_child(column)
	var brand:=Label.new();brand.text="末日余晖   /   山麓农谷";brand.add_theme_color_override("font_color",ShellTheme.MOSS);column.add_child(brand)
	_title=Label.new();_title.add_theme_font_size_override("font_size",32);column.add_child(_title)
	_detail=Label.new();_detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_detail.custom_minimum_size.x=470;column.add_child(_detail)
	_caption=Label.new();_caption.add_theme_color_override("font_color",ShellTheme.SECONDARY);column.add_child(_caption)
	_buttons=VBoxContainer.new();_buttons.add_theme_constant_override("separation",10);column.add_child(_buttons)
	_notice=PanelContainer.new();_notice.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);_notice.offset_left=240;_notice.offset_right=-240;_notice.offset_top=24;_notice.mouse_filter=Control.MOUSE_FILTER_IGNORE;_root.add_child(_notice)
	_notice_text=Label.new();_notice_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_notice_text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;_notice.add_child(_notice_text)
	_shade.hide();_notice.hide()

func _process(_delta:float)->void:
	if _notice.visible and Time.get_ticks_msec()>=_notice_deadline:_notice.hide()

func _transition(next:String,next_phase:String,title:String,detail:String)->void:
	state=next;phase=next_phase;sequence+=1
	history.append({"sequence":sequence,"state":state,"phase":phase,"msec":Time.get_ticks_msec(),"process_frame":Engine.get_process_frames()})
	if history.size()>40:history.pop_front()
	_title.text=title;_detail.text=detail;_notice.hide();_shade.show()
	for child:Node in _buttons.get_children():_buttons.remove_child(child);child.queue_free()
	_caption.text=""

func _button(label:String,action:String)->void:
	var button:=Button.new();button.text=label;button.custom_minimum_size.y=44
	button.name=action.to_pascal_case();button.pressed.connect(func():
		# Lock before emitting; rapid mouse/keyboard repeats cannot start twice.
		for child:Node in _buttons.get_children():if child is Button:child.disabled=true
		chosen.emit(action))
	_buttons.add_child(button)
	button.theme_type_variation="PrimaryButton" if action in ["normal","retry_close"] else "QuietButton"
	Feedback19.bind(button)

func show_menu(message:String="")->void:
	_transition("menu","menu","旧村，重新点灯","你与两名同伴来到衰败旧村。安顿食水，修复仓棚，再让田地和工坊运转起来。" if message.is_empty() else message)
	_caption.text="正常开局与五工具试玩均使用有限真实物资。"
	_button("开始新生活 · 正常开局","normal")
	_button("五工具试玩 · 快速体验","playtest")
	_button("继续上次保存","continue")
	_button("退出游戏","quit")
	(_buttons.get_child(0) as Button).grab_focus()

func show_stage(next_phase:String,title:String,detail:String)->void:
	_transition("busy",next_phase,title,detail)
	_caption.text="按真实校验阶段推进，请稍候。"

func show_evidence(text:String)->void:
	if state=="busy" and _caption.text!=text:_caption.text=text

func show_result(result:Dictionary,has_world:bool)->void:
	if result.get("ok",false):
		state="ready";phase="ready";sequence+=1;_shade.hide()
		history.append({"sequence":sequence,"state":state,"phase":phase,"msec":Time.get_ticks_msec(),"process_frame":Engine.get_process_frames()})
		if history.size()>40:history.pop_front()
		_notice_text.text=str(result.get("reason","村庄已就绪，可以开始行动。"));_notice.show();_notice_deadline=Time.get_ticks_msec()+6500
	elif not has_world:show_menu("启动未完成："+str(result.get("reason",result.get("code","未知错误"))))
	else:
		_transition("error","failed","操作未完成",str(result.get("reason",result.get("code","未知错误"))))
		_button("回到当前世界","dismiss")

func show_close_failed(result:Dictionary)->void:
	_transition("close_failed","close_failed","保存未完成，仍留在游戏中",str(result.get("reason",result.get("code","未能确认保存成功"))))
	_button("重新保存并退出","retry_close");_button("取消退出，返回游戏","cancel_close")

func show_fatal(result:Dictionary)->void:
	_transition("error","startup_failed","启动配置未通过",str(result.get("reason",result.get("code","未知错误"))))
	_caption.text="请检查启动参数与存储位置。"
	_button("退出游戏","quit")

func dismiss()->void:
	state="hidden";phase="";_shade.hide();_notice.hide()

func snapshot()->Dictionary:
	return {"state":state,"phase":phase,"sequence":sequence,"history":history.duplicate(true),"modal":_shade.visible,"message":_detail.text}
