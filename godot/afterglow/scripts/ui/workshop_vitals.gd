extends Control
## Retained vector HUD. All bars are display-only views of published actor facts.
const Palette = preload("res://scripts/ui/ui_theme.gd")
var values: Dictionary = {}
var _basis: Array = []
var scale_factor := 1.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(240, 81)

func set_display_scale(value: float) -> void:
	if is_equal_approx(value,scale_factor): return
	scale_factor = value
	custom_minimum_size = Vector2(0,81*value)
	queue_redraw()

func present(actor: Dictionary, movement: Dictionary) -> void:
	var basis := [actor.get("hp"), actor.get("stamina"), movement.get("stamina_max", 100), actor.get("hunger"), actor.get("thirst"), actor.get("fatigue"), actor.get("wounds", []).size() if actor.get("wounds") is Array else 0]
	if basis == _basis: return
	_basis = basis
	values = {"hp":basis[0], "stamina":basis[1], "stamina_max":basis[2], "hunger":basis[3], "thirst":basis[4], "fatigue":basis[5], "wounds":basis[6]}
	tooltip_text = "生命 %s · 体力 %s / %s\n饱食 %s · 饮水 %s · 疲劳 %s · 伤势 %s" % basis
	queue_redraw()

func _value(value: Variant) -> String:
	return str(roundi(float(value))) if value is int or value is float else "—"

func _draw() -> void:
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE*scale_factor)
	var font: Font = get_theme_default_font()
	var width := maxf(95, size.x / scale_factor - 39)
	for spec: Array in [["hp", "生命", 100.0, Palette.RUST, 11.0], ["stamina", "体力", values.get("stamina_max", 100), Palette.MOSS, 36.0]]:
		var y: float = spec[4]
		var color: Color = spec[3]
		if spec[0] == "hp":
			draw_colored_polygon(PackedVector2Array([Vector2(3,y-2),Vector2(7,y-5),Vector2(11,y-2),Vector2(15,y-5),Vector2(19,y-2),Vector2(19,y+2),Vector2(11,y+9),Vector2(3,y+2)]), color)
		else:
			draw_colored_polygon(PackedVector2Array([Vector2(12,y-7),Vector2(5,y+1),Vector2(10,y+1),Vector2(8,y+9),Vector2(17,y-1),Vector2(12,y-1)]), color)
		var track := Rect2(31, y - 2, width, 10)
		draw_style_box(Palette.box(Palette.RAISED, Color.TRANSPARENT, 0), track)
		var value: Variant = values.get(spec[0])
		var maximum: float = maxf(1, float(spec[2])) if spec[2] is int or spec[2] is float else 100.0
		if value is int or value is float:
			draw_style_box(Palette.box(color, Color.TRANSPARENT, 0), Rect2(track.position, Vector2(width * clampf(float(value) / maximum, 0, 1), 10)))
		var caption: String = str(spec[1]) + " " + _value(value)
		if spec[0] == "stamina": caption += " / " + _value(spec[2])
		draw_string(font, Vector2(32, y+10), caption, HORIZONTAL_ALIGNMENT_CENTER, width, 11, Palette.INK)
	var names := [["hunger","饱食"],["thirst","饮水"],["fatigue","疲劳"]]
	var cell := size.x / scale_factor / 3.0
	for i: int in range(names.size()):
		var id: String = names[i][0]
		var value: Variant = values.get(id)
		var warning: bool = (value is int or value is float) and (float(value) >= 70 if id == "fatigue" else float(value) <= 30)
		var x := i * cell
		draw_circle(Vector2(x+5,68), 3, Palette.RUST if warning else Palette.MOSS)
		draw_string(font, Vector2(x+13,72), str(names[i][1])+" "+_value(value), HORIZONTAL_ALIGNMENT_LEFT, cell-14, 11, Palette.RUST if warning else Palette.SECONDARY)
