extends Control
## Catalog diagram from the real definition. This is NOT world placement proof.
var definition: Dictionary = {}
const COLORS := {"input":Color("a9c2a0"),"output":Color("d1bb83"),"fuel":Color("d5a083"),"work":Color("a4b8c3"),"repair":Color("c5a6a3"),"service":Color("cec6b3")}

func configure(value: Dictionary) -> void:
	definition = value.duplicate(true)
	custom_minimum_size = Vector2(220, 145)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	var footprint: Variant = definition.get("footprint", {})
	if not footprint is Dictionary or not footprint.get("min") is Dictionary or not footprint.get("max") is Dictionary: return
	var low := Vector2(float(footprint.min.x), float(footprint.min.z))
	var high := Vector2(float(footprint.max.x), float(footprint.max.z))
	var all_low := low - Vector2.ONE
	var all_high := high + Vector2.ONE
	for port in definition.get("ports", []):
		if port is Dictionary and port.get("position") is Array and port.position.size() == 3:
			var p := Vector2(float(port.position[0]), float(port.position[2]))
			all_low = all_low.min(p - Vector2(0.8, 0.8)); all_high = all_high.max(p + Vector2(0.8, 0.8))
	var scale_ := minf((size.x - 24) / maxf(1, all_high.x - all_low.x), (size.y - 24) / maxf(1, all_high.y - all_low.y))
	var origin := size * 0.5 - (all_low + all_high) * 0.5 * scale_
	draw_rect(Rect2(origin + low * scale_, (high - low) * scale_), Color("303b33"))
	draw_rect(Rect2(origin + low * scale_, (high - low) * scale_), Color("b0b89f"), false, 2)
	for port in definition.get("ports", []):
		if not port is Dictionary or not port.get("position") is Array or port.position.size() != 3: continue
		var p := origin + Vector2(float(port.position[0]), float(port.position[2])) * scale_
		var color: Color = COLORS.get(str(port.get("purpose", "")), Color("cec6b3"))
		draw_circle(p, 5, color)
		var normal: Variant = port.get("normal", [])
		if normal is Array and normal.size() == 3: draw_line(p, p + Vector2(float(normal[0]), float(normal[2])) * 14, color, 2)
