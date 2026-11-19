extends "run_factory_ui.gd"
## Isolated real regional risk fixture; no production display writes.
## Keeps exact pre-stability evidence from the old factory145 assertion.
## Relative base keeps a frozen external harness on its adjacent corrected
## fixture, instead of accidentally inheriting the old test inside a PCK.
var observations: Array = []

func check(name: String, ok: bool, detail: Variant = null) -> void:
	if name in ["actual warning and remaining time are displayed from sole clock", "published alarm detail is visible without private state lookup"]:
		observations.append({"stage":"early-risk-banner" if name.begins_with("actual warning") else "published-stable-alert", "ok":ok, "clock":runtime.clock(), "public_alerts":F.alerts(ui.factory), "display_state":runtime.world.extension("r34:display"), "defense":runtime.world.extension(Gameplay.KEY).defense, "rendered_text":text_in(ui._body)})
	super.check(name, ok, detail)

func run() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,800)
	var profiles: Dictionary = Assembly.generation_profiles()
	var prepared: Dictionary = Assembly.prepare(Assembly.generate(713,profiles.profiles)) if profiles.get("ok",false) else profiles
	check("normal C4 actual regional boundary capture prepares",prepared.get("ok",false),prepared.get("reason"))
	if not prepared.get("ok",false):return finish()
	host=TestClient.new();root.add_child(host)
	await regional_controls(prepared.capture)
	if observations.is_empty():check("original regional boundary was reached",false);return finish()
	var early: Dictionary=observations[0]
	var stable: Dictionary=observations[1] if observations.size()>1 else {}
	var state: Dictionary=runtime.world.extension(Gameplay.KEY)
	var site_id: String=str(state.defense.get("site_id",""))
	var warning_id: String=str(early.defense.get("warning_id",""))
	var alerts: Array=F.alerts(ui.factory).filter(func(row:Dictionary)->bool:return row.get("object_id")==site_id)
	var pending: Array=early.display_state.get("active",[]).filter(func(row:Dictionary)->bool:return row.get("object_id")==site_id)
	check("early actual warning is pending not a missing consumer row",early.defense.status=="warning" and early.public_alerts.is_empty() and pending.size()==1 and pending[0].get("pending",false))
	check("early risk and real countdown remain visible before list stability",early.rendered_text.contains("有效预告余时") and early.rendered_text.contains("风险承诺 · 已确认"))
	check("bounded wait uses at least one real simulation second",not stable.is_empty() and float(stable.clock)-float(early.clock)>=1.0 and float(stable.clock)-float(early.clock)<=2.01, {"early":early.clock,"stable":stable.get("clock")})
	check("stable published detail is consumed verbatim by same UI",not alerts.is_empty() and not str(alerts[0].get("detail","")).is_empty() and text_in(ui._body).contains(str(alerts[0].get("detail",""))))
	check("stability does not recreate risk cause or clear actual obstruction",runtime.world.extension(Gameplay.KEY).defense.warning_id==warning_id and runtime.world.extension(Gameplay.KEY).defense.cause_event_id==early.defense.get("cause_event_id") and not runtime.world.extension(Gameplay.KEY).regional_objectives[site_id].corridor_clear)
	check("same episode and source survive stability and codec restoration",not alerts.is_empty() and pending.size()==1 and alerts[0].id==pending[0].id and alerts[0].episode_id==pending[0].episode_id and not alerts[0].get("pending",true))
	var before:Dictionary=runtime.capture_checkpoint()
	for index in 4:runtime.factory_snapshot()
	ui.refresh();await flush()
	check("queries and UI refresh cannot accelerate clock or write authority",Data.json_equal(before,runtime.capture_checkpoint()))
	finish()

func finish() -> void:
	var failed: int=checks.filter(func(row:Dictionary):return not row.ok).size()
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failed":failed,"observed":observations,"scope":"actual normal C4 assembly with explicit regional checkpoint relocation fixture, real survey/risk commands and clock-driven public alarm stability. Not normal walking journey, immutable PCK, OS, visual or performance qualification."},"\t",true,true));file.close()
	if is_instance_valid(host):host.free()
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
