extends RefCounted
## Present E's recorded facts. Public, searched sources/known relationships
## gate display; this view never grants discovery, knowledge or rewards.
const F = preload("res://scripts/ui/factory_projection.gd")
const P = preload("res://scripts/ui/ui_projection.gd")
const Panels = preload("res://scripts/ui/ui_panels.gd")
const FLAGS := {"read_woodwork_record":"读过真实木工记录", "real_hand_saw_work":"亲手完成锯切", "tools_taken":"取得现场工具", "real_machine_output":"机器实际产出", "real_supplies_taken":"取过有限补给", "drive_unit_taken":"取走真实动力总成", "read_route_record":"读过现场路线记录"}
const PERSON_FLAGS := {"met":"已经结识", "helped":"实际帮助过对方", "member":"已加入同行", "consent":"当前同意工作", "home_arrived":"实际抵达营地", "real_delivery":"参与过真实交付"}
const STAGES := {"workshop_found":"已搜索木工现场", "tools_found":"已取得工具", "record_learned":"已掌握记录中的知识", "hand_worked":"已亲手锯切", "frame_restored":"原址旧框架已恢复", "machine_worked":"已有真实机器产出", "met":"已结识邻里", "store_searched":"已搜索小店", "supplies_taken":"已取过有限补给", "route_read":"已阅读路线记录", "stockyard_found":"已搜索料场", "drive_carried":"已取出动力总成", "machine_built":"已实付建成机器"}

static func known_rows(data: Dictionary, snapshot: Dictionary) -> Array:
	var result: Array = []
	for source: Dictionary in F.rows(data, "workforce", "stories"):
		if not source.get("available", false): continue
		var row := source.duplicate(true)
		var stocks: Array = []
		for id in row.get("sources", []):
			var stock := P.stock(snapshot, str(id))
			if not stock.is_empty() and stock.get("searched", false): stocks.append(stock)
		var people: Array = []
		var raw_people: Dictionary = row.get("people", {})
		for id: String in raw_people:
			var flags: Dictionary = raw_people[id]
			if not flags.get("met", false) and not flags.get("member", false): continue
			var actor := P.find(snapshot.get("actors", []), id)
			people.append({"id":id, "flags":flags.duplicate(true), "actor":actor})
		var recorded := false
		for key: String in FLAGS:
			if row.get("flags", {}).get(key, false): recorded = true
		# New E stages are authoritative known history, including searched places
		# now outside the nearby snapshot. Older unversioned source bindings alone
		# still cannot expose an unsearched location.
		var known_stage: bool = STAGES.has(str(row.get("stage", "")))
		if not known_stage and stocks.is_empty() and people.is_empty() and not recorded: continue
		row.visible_sources = stocks; row.visible_people = people
		result.append(row)
	return result

static func open_person(ui, actor_id: String) -> void:
	ui.factory_view.handbook_section = "stories"
	ui.factory_view.story_person = actor_id
	ui.factory_view.handbook_search = ""
	ui.open_panel("factory_handbook")

static func render(ui, body: VBoxContainer) -> void:
	var person_id := str(ui.factory_view.get("story_person", ""))
	if not person_id.is_empty():
		ui.add_button("查看全部已知地点与线索", func(): ui.factory_view.erase("story_person"); ui.queue_refresh(), "factory:stories:all", "", body)
	ui.paragraph("已发现的地点与同行经历。手册需要花时间研读，路线记录需在现场查看。", body)
	var count := 0
	for row: Dictionary in known_rows(ui.factory, ui.snapshot):
		var people: Array = row.visible_people
		if not person_id.is_empty():
			people = people.filter(func(person: Dictionary): return person.id == person_id)
			if people.is_empty(): continue
		var query := str(ui.factory_view.get("handbook_search", "")).strip_edges().to_lower()
		if not query.is_empty() and not (str(row.get("title", "")) + " " + str(row.get("text", ""))).to_lower().contains(query): continue
		count += 1
		var panel := PanelContainer.new(); body.add_child(panel)
		panel.set_meta("ui_story_id", row.id)
		var card := VBoxContainer.new(); panel.add_child(card)
		Panels.heading(ui, str(row.get("title", row.id)), card)
		if STAGES.has(str(row.get("stage", ""))): ui.paragraph(str(STAGES[row.stage]), card)
		ui.paragraph(str(row.get("text", "")) if person_id.is_empty() else "与这位幸存者一同走过的经历。", card)
		for key: String in FLAGS:
			if row.get("flags", {}).get(key, false): ui.paragraph("已记录 · " + str(FLAGS[key]), card)
		for source: Dictionary in row.visible_sources:
			var id := str(source.id)
			ui.paragraph("现场来源 · " + str(source.get("name", "已搜索容器")) + " · " + F.location(source.get("location")), card)
			ui.add_button("查看此现场容器", func(): ui.open_panel("container", id), "factory:story:source:" + id, "", card)
			if row.id == "ST01": _study(ui, card, id)
		for person: Dictionary in people:
			_person(ui, card, person)
			_experience(ui, card, row, str(person.id))
			if row.id == "ST02":
				_commands(ui, card, row, "", str(person.id))
				_followups(ui, card, row, str(person.id))
		for clue: Dictionary in F.dictionaries(row.get("clues", [])):
			ui.paragraph(str(clue.get("title", "已知线索")) + " · " + F.location(clue.get("location")), card)
		if row.id != "ST02": _commands(ui, card, row)
	if count == 0: ui.paragraph("尚无匹配的线索。到现场搜索、研读，或与附近的幸存者交谈。", body)

static func source_actions(ui, parent: Node, source_id: String) -> void:
	var stock := F.visible_stock(ui.factory, ui.snapshot, source_id)
	if stock.is_empty() or not stock.get("searched", false) or stock.get("display_only", false): return
	for row: Dictionary in known_rows(ui.factory, ui.snapshot):
		if not row.get("sources", []).has(source_id): continue
		_commands(ui, parent, row, source_id)
		if row.get("flags", {}).get("read_source:" + source_id, false): ui.paragraph("路线记录已记入手册", parent)

static func _commands(ui, parent: Node, row: Dictionary, source_id: String = "", person_id: String = "") -> void:
	for command: Dictionary in F.dictionaries(row.get("commands", [])):
		# Reading is always an explicit owner command. Opening the page never
		# records a route, review, reward or work-consent change.
		if command.get("kind") != "settlement.read_story" or not command.get("payload") is Dictionary: continue
		var payload: Dictionary = command.payload
		if payload.get("story_id") != row.id: continue
		var target := str(command.get("target_id", ""))
		if row.id == "ST02":
			if not source_id.is_empty() or not _known_person(row, target): continue
			if not person_id.is_empty() and target != person_id: continue
			var memory: Dictionary = row.get("experiences", {}).get(target, {})
			if memory.is_empty() or payload.get("person_id") != target or payload.get("event_id") != memory.get("event_id"): continue
			if row.people[target].get("reviewed", false): continue
		elif row.id == "ST03":
			if not row.get("sources", []).has(payload.get("source_id")): continue
			if not source_id.is_empty() and payload.source_id != source_id: continue
		else: continue
		Panels._action(ui, str(command.get("label", "在现场查看记录")), "settlement.read_story", target, payload.duplicate(true), parent)

static func _known_person(row: Dictionary, id: String) -> bool:
	var person: Dictionary = row.get("people", {}).get(id, {})
	return not id.is_empty() and (person.get("met", false) or person.get("member", false))

static func _experience(ui, parent: Node, row: Dictionary, id: String) -> void:
	if row.id != "ST02" or not _known_person(row, id): return
	var memory: Dictionary = row.get("experiences", {}).get(id, {})
	if memory.is_empty() or not memory.get("location") is Dictionary: return
	var label := "真实交付" if memory.get("action") == "delivery" else "共同协防" if memory.get("action") == "defense" else ""
	if label.is_empty(): return
	var endpoint := str(memory.get("destination_id", "")) if memory.action == "delivery" else str(memory.get("target_id", ""))
	var stock := F.visible_stock(ui.factory, ui.snapshot, endpoint)
	var module := F.instance(ui.factory, endpoint)
	var destination := str(stock.get("name", module.get("name", "现场目的地")))
	ui.paragraph(label + " · " + F.location(memory.location), parent)
	if memory.action == "delivery": ui.paragraph("交付至 " + destination, parent)
	ui.paragraph("已在现场回顾" if row.people[id].get("reviewed", false) else "见面时可以回顾这次经历", parent)

static func _followups(ui, parent: Node, row: Dictionary, person_id: String) -> void:
	if row.id != "ST02": return
	for command: Dictionary in F.dictionaries(row.get("followups", [])):
		var id := str(command.get("target_id", ""))
		if not _known_person(row, id) or not row.people[id].get("reviewed", false): continue
		if not person_id.is_empty() and id != person_id: continue
		if row.get("experiences", {}).get(id, {}).is_empty(): continue
		if command.get("panel") == "workforce":
			ui.add_button("查看" + _person_name(ui, id) + "的岗位", func(): ui.open_panel("factory_people", id), "factory:story:workforce:" + id, "", parent)
		elif command.get("kind") == "job" and command.get("payload") is Dictionary and command.payload == {"job":"rest"}:
			# Consent is the current owner projection, not a historical event flag.
			if not row.people[id].get("member", false) or not row.people[id].get("consent", false): continue
			Panels._action(ui, "让" + _person_name(ui, id) + "先补给休息", "job", id, command.payload.duplicate(true), parent)

static func _person_name(ui, id: String) -> String:
	return str(P.find(ui.snapshot.get("actors", []), id).get("name", "这位幸存者"))

static func _study(ui, parent: Node, source_id: String) -> void:
	for record: Dictionary in P.records(ui.snapshot.get("records", [])):
		if str(record.get("holder_id", record.get("holderId", ""))) != source_id or record.get("itemId") != "book_woodwork": continue
		ui.paragraph("木工记录 · 研读约 " + P.number(record.get("seconds")) + " 秒；完成后掌握记录中的知识。", parent)
		Panels._action(ui, "现场研读木工记录", "study", str(record.id), {"record_id":record.id}, parent, true)

static func _person(ui, parent: Node, person: Dictionary) -> void:
	var actor: Dictionary = person.actor
	var name := str(actor.get("name", "已结识的幸存者"))
	Panels.heading(ui, name + " · 共同经历", parent)
	for key: String in PERSON_FLAGS:
		if person.flags.get(key, false): ui.paragraph(str(PERSON_FLAGS[key]), parent)
	# Current consent comes from today's public relationship, never a story
	# completion checkbox. The original NPC page owns talk/help/invite actions.
	if not actor.is_empty():
		var relationship: Dictionary = actor.get("relationship", {})
		ui.paragraph("当前关系 · " + ("同行" if relationship.get("member", false) else "各自生活") + " · " + ("同意工作" if relationship.get("consent", false) else "未授权工作"), parent)
		ui.add_button("返回人物与合作", func(): ui.open_panel("npc", str(person.id)), "factory:story:person:" + str(person.id), "", parent)
	else: ui.paragraph("暂不在附近。已有经历保留，见面后可继续交谈或交接物品。", parent)
