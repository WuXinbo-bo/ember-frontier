extends RefCounted
## Revision counters fence commands; they are not visible page content. Commands
## still reacquire the current snapshot and owner preflight before submitting.
const COUNTERS := ["revision", "world_revision", "runtime_revision", "command_revision"]

static func display_hash(value: Variant) -> int:
	if not value is Dictionary: return hash(value)
	# Strip only the envelope and named public section fences. Keep the large
	# arrays/catalogue shared and use Godot's native hash, not a script recursion
	# over every item/recipe on every display refresh.
	var view: Dictionary = value.duplicate()
	for key: String in COUNTERS: view.erase(key)
	for key: String in ["modules","production","workforce","logistics","handbook","regions","alerts"]:
		if not view.get(key) is Dictionary: continue
		var section: Dictionary = view[key].duplicate()
		for counter: String in COUNTERS: section.erase(counter)
		view[key] = section
	return hash(view)
