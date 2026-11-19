extends RefCounted
## Display allocations only. Reconcile every allocation against real current stock.
const UiProjection = preload("res://scripts/ui/ui_projection.gd")
var _layouts: Dictionary = {}

func clear() -> void:
	_layouts.clear()

func cells(stock: Dictionary, snapshot: Dictionary) -> Array:
	var entries := UiProjection.entries(stock, snapshot)
	if stock.is_empty() or not stock.get("searched", false):
		return []
	var id := str(stock.id)
	var by_key: Dictionary = {}
	for item in entries: by_key[item.key] = item
	var layout: Array = _layouts.get(id, []).duplicate(true)
	var tools_seen: Dictionary = {}
	for index in range(layout.size()):
		var allocation: Variant = layout[index]
		if not allocation is Dictionary or not by_key.has(allocation.get("key", "")):
			layout[index] = null
		elif str(allocation.key).begins_with("tool:"):
			if tools_seen.has(allocation.key): layout[index] = null
			else: tools_seen[allocation.key] = true
	var amounts: Dictionary = {}
	for item in entries:
		var remaining: float = item.quantity
		var remainder_index := -1
		for index in range(layout.size()):
			if not layout[index] is Dictionary or layout[index].key != item.key: continue
			var desired: Variant = layout[index].get("amount")
			if desired == null:
				if remainder_index < 0: remainder_index = index
				else: layout[index] = null
				continue
			var requested := float(desired)
			if item.step == 1.0: requested = floorf(requested)
			var amount := minf(remaining, maxf(0.0, requested))
			if amount > 0:
				amounts[index] = amount
				remaining -= amount
			else: layout[index] = null
		if remaining > 0:
			if remainder_index < 0:
				remainder_index = layout.find(null)
				if remainder_index < 0:
					remainder_index = layout.size()
					layout.append(null)
				layout[remainder_index] = {"key":item.key, "amount":null}
			amounts[remainder_index] = remaining
		elif remainder_index >= 0: layout[remainder_index] = null
	var last := -1
	for index in range(layout.size()):
		if layout[index] != null: last = index
	var count := maxi(24, int(ceil((last + 2.0) / 6.0)) * 6)
	layout.resize(count)
	_layouts[id] = layout
	var available: Dictionary = {}
	for item in entries: available[item.key] = item.available
	var result: Array = []
	for index in range(layout.size()):
		var item: Dictionary = by_key.get(layout[index].key, {}) if layout[index] is Dictionary else {}
		var quantity: float = amounts.get(index, 0.0)
		var free := minf(quantity, float(available.get(item.get("key", ""), 0.0)))
		if not item.is_empty(): available[item.key] -= free
		result.append({"index":index, "entry":item, "quantity":quantity, "available":free})
	return result

func _freeze(stock: Dictionary, snapshot: Dictionary) -> Array:
	var result: Array = []
	for cell in cells(stock, snapshot):
		result.append(null if cell.entry.is_empty() else {"key":cell.entry.key, "amount":cell.quantity})
	return result

func destination_reason(stock: Dictionary, snapshot: Dictionary, index: int, reference: Dictionary) -> String:
	var current := cells(stock, snapshot)
	if index < 0 or index >= current.size(): return "目的格已改变，请重新选择"
	var entry: Dictionary = current[index].entry
	if not entry.is_empty() and entry.key != UiProjection.reference_key(reference):
		return "跨容器请放入空格或同类物品格"
	return ""

func move(stock: Dictionary, snapshot: Dictionary, source: int, destination: int, amount: float) -> String:
	var current := cells(stock, snapshot)
	if source < 0 or destination < 0 or source >= current.size() or destination >= current.size(): return "格子已改变"
	if source == destination: return ""
	var from: Dictionary = current[source]
	var to: Dictionary = current[destination]
	if from.entry.is_empty() or not is_finite(amount) or amount <= 0 or amount > from.quantity: return "份额已改变，请重新选择"
	if from.entry.step == 1.0 and amount != floorf(amount): return "此物品需按完整数量整理"
	var same: bool = not to.entry.is_empty() and to.entry.key == from.entry.key
	var full: bool = amount == from.quantity
	if not to.entry.is_empty() and not same and not full: return "拆分后请放入空格或同类物品格"
	var layout := _freeze(stock, snapshot)
	if not to.entry.is_empty() and not same:
		var old: Variant = layout[source]
		layout[source] = layout[destination]
		layout[destination] = old
	else:
		layout[source] = null if full else {"key":from.entry.key, "amount":from.quantity - amount}
		layout[destination] = {"key":from.entry.key, "amount":amount + (to.quantity if same else 0.0)}
	_layouts[stock.id] = layout
	cells(stock, snapshot)
	return ""

func transferred(before: Dictionary, snapshot: Dictionary, index: int, amount: float) -> void:
	var layout := _freeze(before, snapshot)
	if index < 0 or index >= layout.size() or layout[index] == null: return
	var remaining := maxf(0.0, float(layout[index].amount) - amount)
	layout[index] = null if remaining <= 0 else {"key":layout[index].key, "amount":remaining}
	_layouts[before.id] = layout

func received(before: Dictionary, before_snapshot: Dictionary, after: Dictionary, after_snapshot: Dictionary, index: int, reference: Dictionary) -> void:
	if before.get("id") != after.get("id") or not destination_reason(before, before_snapshot, index, reference).is_empty(): return
	var old := UiProjection.entry(before, before_snapshot, reference)
	var current := UiProjection.entry(after, after_snapshot, reference)
	var added := float(current.get("quantity", 0.0)) - float(old.get("quantity", 0.0))
	if added <= 0: return
	var layout := _freeze(before, before_snapshot)
	var key := UiProjection.reference_key(reference)
	layout[index] = {"key":key, "amount":added + (float(layout[index].amount) if layout[index] is Dictionary else 0.0)}
	_layouts[before.id] = layout
	cells(after, after_snapshot)
