extends RefCounted
## Permanent public appearance IDs only; no name-based or arbitrary skin guess.
const P = preload("res://scripts/ui/ui_projection.gd")
const C = preload("res://scripts/ui/ui_composition.gd")
const Images = preload("res://scripts/ui/ui_images.gd")
const Icons = preload("res://scripts/ui/ui_icons.gd")
const PORTRAITS := {
	"village_linxia_v14":"res://themes/portraits/village_linxia_v14.png",
	"village_chentuo_v14":"res://themes/portraits/village_chentuo_v14.png",
	"r1_resident_commuter":"res://themes/portraits/r1_resident_commuter.png",
	"r1_resident_neighbor":"res://themes/portraits/r1_resident_neighbor.png",
	"r1_resident_shopkeeper":"res://themes/portraits/r1_resident_shopkeeper.png"
}

static func portrait(actor: Dictionary) -> Texture2D:
	var path := str(PORTRAITS.get(str(actor.get("appearance_id", "")), ""))
	return Images.texture(path)

static func header(ui, parent: Node, actor: Dictionary, width: int = 48) -> void:
	C.image_row(ui, parent, portrait(actor), str(actor.get("name", "幸存者")), (profile(actor) + " · " if not profile(actor).is_empty() else "") + P.activity_text(actor), roundi(width * ui.text_scale))

static func profile(actor: Dictionary) -> String:
	var parts: PackedStringArray = []
	var age: Variant = actor.get("age_years")
	if age is int or age is float: parts.append(str(roundi(float(age))) + "岁")
	var roles := {"scout_hauler":"探索与运输", "woodworker_repair":"木工与修复"}
	var role := str(actor.get("role", actor.get("role_id", "")))
	if roles.has(role): parts.append(roles[role])
	return " · ".join(parts)

static func hud_title(actor: Dictionary) -> String:
	var text := str(actor.get("name", "同伴"))
	var details := profile(actor)
	return text + (" · " + details if not details.is_empty() else "") + "\n" + P.activity_text(actor)

static func needs(actor: Dictionary) -> String:
	var parts: PackedStringArray = []
	for spec in [["hp","生命"],["stamina","体力"],["thirst","饮水"],["hunger","饱食"],["fatigue","疲劳"]]:
		var value: Variant = actor.get(spec[0])
		if value is int or value is float:
			if spec[0] in ["hp", "stamina"] or (float(value) >= 70 if spec[0] == "fatigue" else float(value) <= 30): parts.append(spec[1] + " " + P.stat_number(value))
	return " · ".join(parts)

static func decision_text(decision: Dictionary) -> String:
	var reason := str(decision.get("reason", ""))
	var names := {"no_eligible_work":"当前没有可执行岗位", "actor_missing":"人物暂不可用", "incapacitated":"失能，无法工作", "consent_revoked":"已撤回工作同意", "stale_or_invalid_target":"原工作目标已失效", "immediate_threat":"正在应对近身威胁", "safe_handoff_required":"等待安全交接原货物", "player_assignment":"按你的安排工作", "finish_carried_delivery":"先送达随身货物", "carried_goods_need_valid_receiver":"保管原货物，等待可接收库存", "best_eligible_work":"正前往可执行岗位", "assignment_invalid":"安排的岗位当前不可执行", "emergency_not_qualified":"当前不能承担紧急岗位", "defend":"前往守备位置", "hunger":"先解决饥饿", "thirst":"先补充饮水", "fatigue":"先休息恢复", "rest":"先休息恢复", "eat":"先进食", "drink":"先饮水", "medicine":"先处理伤势"}
	if names.has(reason): return str(names[reason])
	var translated := P.reason_text(reason)
	return translated if translated != reason or reason.contains(" ") or reason.contains("，") else "当前行动条件尚未满足"

static func cargo(ui, parent: Node, actor_id: String) -> void:
	# Only the published original holder; never infer cargo from task amounts.
	var pack := P.stock(ui.snapshot, "pack:" + actor_id)
	var tasks: Array = ui.factory.get("logistics", {}).get("tasks", [])
	var carrying := tasks.any(func(task): return task is Dictionary and task.get("actor_id") == actor_id and task.get("phase") == "deliver" and task.get("status") not in ["completed", "cancelled"])
	if carrying:
		C.caption(ui, "携货中 · 原货仍由本人保管，停等或改派不会自动退回来源。", parent)
		if not pack.is_empty() and pack.get("searched", false): ui.item_row(pack.get("items", {}), "实际随身", parent)
