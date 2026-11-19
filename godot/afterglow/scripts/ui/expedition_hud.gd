extends VBoxContainer

var _title: Label
var _actions: HFlowContainer
var _key: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = Label.new()
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	_actions = HFlowContainer.new()
	_actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_actions)
	hide()

func refresh(ui, run: Dictionary, actors: Array, night: Dictionary = {}) -> void:
	if (run.is_empty() or run.get("phase") == "idle") and night.get("phase") in ["ready", "warning", "fighting", "between", "dawn"]:
		_refresh_night(ui, night, run)
		return
	visible = not run.is_empty()
	if run.is_empty(): return
	var phase: String = run.phase
	var settings: Array = [phase,run.may_depart,run.near_site,run.near_exit,run.escort_ready,run.weapon,run.bow,run.perks,run.get("choices",{}),run.get("prepared", ""),run.get("may_prepare",false),actors.filter(func(a: Dictionary) -> bool: return a.get("relationship",{}).get("member",false)).map(func(a: Dictionary) -> String: return str(a.id))]
	_title.text = {
		"idle": "探索 · 废弃补给站" if run.result.is_empty() else run.result,
		"approach": "等同伴走到补给箱旁" if run.near_site and not run.escort_ready else "补给站 · 开箱会引来丧尸",
		"warning": "第 %d 波 · 来袭 %d 秒" % [run.wave, run.warning],
		"fighting": "第 %d / 3 波 · 剩 %d 只" % [run.wave,run.remaining],
		"between": "第 %d 波已清理 · 选增益继续，或撤离结算" % run.wave,
		"complete": "三波已清理 · 带物资返回撤离点",
		"retreat": "沿路回青色撤离点"}.get(phase, "")
	if phase in ["idle", "approach"] and not run.near_site:
		var distance: int = run.get("site_distance", -1)
		_title.text += "\n沿村路找补给箱 · %d 米" % distance if distance >= 0 else "\n返回旧村前往补给站"
	if phase == "idle" and not str(run.get("prepared_label", "")).is_empty():
		_title.text += "\n已整备 · " + str(run.prepared_label)
	if phase == "between":
		_title.text += "\n下一波 · " + str(run.get("wave_preview", ""))
	if phase in ["between", "complete", "retreat"] and not str(run.get("loot_label", "")).is_empty():
		_title.text += "\n撤离可带走 · " + str(run.loot_label)
	if phase == "warning":
		_title.text += "\n" + str(run.get("wave_preview", ""))
	if phase in ["warning","fighting"]:
		_title.text += " · " + ("弓" if run.weapon == "bow" else "木棒") + "自动攻击"
	if phase != "idle" and not str(run.error).is_empty(): _title.text += "\n" + run.error
	_title.add_theme_color_override("font_color", Color("8e381b") if phase in ["warning","fighting"] else Color("324933"))
	if settings == _key: return
	_key = settings.duplicate(true)
	for child: Node in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()
	if phase == "idle" and run.get("may_prepare", false) and str(run.get("prepared", "")).is_empty():
		ui.add_button("作坊整备",func():ui.open_panel("factory_module","r34:generated:RH-HOME:woodwork"),"expedition:workshop","",_actions)
	if phase == "idle" and run.may_depart:
		if run.near_site:
			button(ui,"开箱 · 会引来丧尸","open")
		else:
			button(ui,"独自探索","depart")
		for actor: Dictionary in actors:
			if actor.id != "player" and actor.get("relationship",{}).get("member",false):
				button(ui,"带" + str(actor.name),"depart",{"escort":actor.id})
	elif phase == "approach" and run.near_site and run.escort_ready:
		button(ui,"开箱 · 会引来丧尸","open")
	elif phase == "between":
		for id: String in run.choices:
			if not run.perks.has(id): button(ui,str(run.choices[id]),"next",{"perk":id})
	elif phase == "retreat" and run.near_exit:
		button(ui,"带战利品回村","extract")
	if phase in ["warning","fighting","between","complete","approach"]:
		button(ui,"撤离","retreat")
	if run.bow and phase not in ["warning","retreat"]:
		var alternate: String = "club" if run.weapon == "bow" else "bow"
		button(ui,"切换木棒" if alternate == "club" else "切换弓","weapon",{"weapon":alternate})

func button(ui, title: String, action: String, payload: Dictionary = {}) -> void:
	ui.add_button(title,func(): ui.execute("expedition." + action,"",payload),"expedition:" + action + ":" + title,"",_actions)

func _refresh_night(ui, night: Dictionary, expedition: Dictionary) -> void:
	show()
	var phase: String = night.phase
	match phase:
		"ready":
			_title.text = "第 %d 晚 · %s可能来袭" % [night.night, night.direction]
			if not night.at_home: _title.text += "\n返回旧村准备迎战"
			elif int(night.night) == 1: _title.text += "\n可先修整防线，准备好再迎战"
			else: _title.text += "\n预计 %d 秒后集合迎战" % night.seconds
			_title.text += "\n修好旧宅和仓棚（%d/2），第二波少一只" % night.village_ready
		"warning":
			_title.text = "第 %d / 2 波 · 预计从%s来袭 · %d 秒" % [night.wave, night.direction, night.seconds]
		"fighting":
			_title.text = "守村 · 第 %d / 2 波 · 剩 %d 只\n走位即可 · %s自动攻击" % [night.wave, night.remaining, "弓" if expedition.get("weapon") == "bow" else "木棒"]
			if not str(night.get("approach", "")).is_empty(): _title.text += "\n来袭方向  " + str(night.approach)
		"between":
			_title.text = "第一波守住了 · 选一项强化迎接下一波"
			if int(night.village_ready) == 2: _title.text += "\n旧宅与仓棚完好 · 第二波少一只"
		"dawn":
			_title.text = "天亮了 · %s\n%d 处建筑受损 · %s" % ["守住旧村" if night.held else "尸潮退去", night.damage_count, "选择补给" if night.at_home else "返回旧村后领取补给"]
	if not str(night.get("error", "")).is_empty(): _title.text += "\n" + str(night.error)
	_title.add_theme_color_override("font_color", Color("8e381b") if phase in ["ready", "warning", "fighting"] else Color("324933"))
	var settings: Array = ["night", phase, night.at_home, night.get("choices", {}), expedition.get("bow", false), expedition.get("weapon", "")]
	if settings == _key: return
	_key = settings.duplicate(true)
	for child: Node in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()
	if not night.at_home: return
	match phase:
		"ready":
			_night_button(ui, "准备好了 · 迎战", "start")
		"between":
			for id: String in night.choices: _night_button(ui, night.choices[id], "next", {"perk":id})
		"dawn":
			for id: String in night.choices: _night_button(ui, night.choices[id], "reward", {"reward":id})
		"fighting":
			if expedition.get("bow", false):
				var alternate := "club" if expedition.get("weapon", "") == "bow" else "bow"
				button(ui, "换木棒" if alternate == "club" else "换弓", "weapon", {"weapon":alternate})

func _night_button(ui, title: String, action: String, payload: Dictionary = {}) -> void:
	ui.add_button(title, func(): ui.execute("night."+action, "", payload), "night:"+action+":"+title, "", _actions)
