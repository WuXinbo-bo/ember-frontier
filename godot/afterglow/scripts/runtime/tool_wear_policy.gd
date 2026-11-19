extends RefCounted
const VERSION_FIELDS: Array[String] = ["content_version"]
## Generation 21 keeps the legacy tool record shape for stock proofs and saves.
## Tool wear no longer applies. Buildings and other damageable objects are separate.
static func enabled(world: RefCounted) -> bool:
	if world == null: return true
	var source: Variant = world.extension_fields("generation:factory-r34", VERSION_FIELDS) if world.has_method("extension_fields") else world.extension("generation:factory-r34")
	return not source is Dictionary or int(source.get("content_version", 0)) < 21

static func restore_on_load(capture: Dictionary) -> Dictionary:
	var extensions: Dictionary = capture.world.get("extensions", {})
	if int(extensions.get("generation:factory-r34", {}).get("content_version", 0)) < 21:
		return capture
	var tools: Variant = extensions.get("r3:production", {}).get("tools", [])
	if not tools is Array or not tools.any(needs_reset): return capture
	var next := capture.duplicate(true)
	for tool: Variant in next.world.extensions["r3:production"].tools:
		if needs_reset(tool): tool.durability = 100.0
	return next

static func needs_reset(tool: Variant) -> bool:
	if not tool is Dictionary: return false
	var value: Variant = tool.get("durability")
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) < 100.0
