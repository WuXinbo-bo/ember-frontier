extends RefCounted
## On-demand consumer of B's actual teacher offers through A's safe facade.
const C = preload("res://scripts/ui/ui_composition.gd")
const P = preload("res://scripts/ui/ui_projection.gd")

static func render(ui, parent: Node, teacher_id: String) -> void:
	if teacher_id.is_empty() or not is_instance_valid(ui.runtime) or not ui.runtime.has_method("teaching_snapshot"): return
	var value: Variant = ui.runtime.call("teaching_snapshot", "player", teacher_id)
	if not value is Dictionary or value.get("available") != true or not value.get("offers") is Array: return
	var offers: Array = value.offers.filter(func(row): return row is Dictionary and row.get("teacher_id") == teacher_id)
	if offers.is_empty(): return
	var card := C.card(parent)
	C.heading(ui, "请教手艺", card)
	for offer: Dictionary in offers:
		C.caption(ui, str(offer.get("name", "可交流的手艺")) + " · " + P.number(offer.get("seconds")) + " 秒现场学习", card)
		if offer.get("known", false):
			C.caption(ui, "已经掌握", card); continue
		var command: Variant = offer.get("command")
		if not command is Dictionary or command.get("kind") != "study" or command.get("target_id") != teacher_id or command.get("actor_id", "player") != "player": continue
		var payload: Variant = command.get("payload")
		if not payload is Dictionary or payload.get("learning_source") != "teacher" or payload.get("knowledge_id") != offer.get("knowledge_id") or payload.keys().size() != 2: continue
		var ready: Dictionary = ui.availability(ui.request("study", teacher_id, payload))
		var reason: String = "" if offer.get("can_start") == true and ready.get("ok", false) else P.feedback_text(ready if not ready.get("ok", false) else offer)
		C.primary(ui.add_button("开始请教", func(): ui.execute("study", teacher_id, payload, true), "teaching:" + teacher_id + ":" + str(offer.get("knowledge_id", "")), reason, card))
	C.caption(ui, "受理后回场景学习；只有真实有效工时完成才掌握。离开、取消或中断不会提前授予知识。", card)
