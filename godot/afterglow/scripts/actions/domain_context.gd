extends RefCounted
## Weak host bindings prevent Runtime -> service -> Callable(Runtime) reference cycles.
static func isolate(value: Dictionary, include_spatial: bool = true) -> Dictionary:
	var result := {"world": value.world, "definitions": value.get("definitions", {})}
	if include_spatial: result.spatial = value.get("spatial")
	var runtime: Variant = value.get("runtime")
	if runtime is RefCounted:
		var host: WeakRef = weakref(runtime)
		result.actor = func(id: String) -> Dictionary: return host.get_ref().actor(id) if host.get_ref() != null else {}
		result.stock = func(id: String) -> Dictionary: return host.get_ref().stock(id) if host.get_ref() != null else {}
		result.tool = func(id: String) -> Dictionary: return host.get_ref().tool(id) if host.get_ref() != null else {}
		result.facts = func() -> Dictionary: return host.get_ref().facts() if host.get_ref() != null else {}
		result.scenario = func() -> String:
			var runtime_host:Variant=host.get_ref()
			return runtime_host.scenario() if runtime_host!=null and runtime_host.has_method("scenario") else str(runtime_host.facts().get("scenario","")) if runtime_host!=null else ""
		result.draft_snapshot = func() -> Dictionary:
			var runtime_host:Variant=host.get_ref()
			return runtime_host._draft_facts_snapshot() if runtime_host!=null and runtime_host.has_method("_draft_facts_snapshot") else runtime_host.facts() if runtime_host!=null else {}
		result.clock = func() -> float: return host.get_ref().clock() if host.get_ref() != null else 0.0
		result.prepare_life = func(request:Dictionary,actor_state:Dictionary,facts_state:Dictionary)->Dictionary:
			var runtime_host:Variant=host.get_ref()
			return runtime_host.prepare_life(request,actor_state,facts_state) if runtime_host!=null else {"ok":false,"code":"UNAVAILABLE","reason":"生活运行时已关闭"}
		result.facts_diff = func(before:Dictionary,after:Dictionary)->Array:
			var runtime_host:Variant=host.get_ref()
			return runtime_host.facts_diff(before,after) if runtime_host!=null and runtime_host.has_method("facts_diff") else []
		result.region_is_detailed = func(id:String)->bool:
			var runtime_host:Variant=host.get_ref()
			return runtime_host!=null and runtime_host.has_method("region_is_detailed") and runtime_host.region_is_detailed(id)
		result.available = func()->bool:return host.get_ref()!=null
		result.movement_budget = func(id: String, dt: float, mode: String = "walk") -> Dictionary:
			var bound_runtime: Variant = host.get_ref()
			return bound_runtime.movement_budget(id, dt, mode) if bound_runtime != null and bound_runtime.has_method("movement_budget") else {"ok":false,"code":"UNAVAILABLE","reason":"权威移动能力尚不可用"}
	else:
		for key in ["actor", "stock", "tool", "facts", "clock"]: result[key] = value[key]
		if value.get("scenario") is Callable:result.scenario=value.scenario
		if value.get("draft_snapshot") is Callable:result.draft_snapshot=value.draft_snapshot
		if value.get("movement_budget") is Callable: result.movement_budget = value.movement_budget
		if value.get("region_is_detailed") is Callable:result.region_is_detailed=value.region_is_detailed
	return result
