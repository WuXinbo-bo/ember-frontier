extends "res://tests/gameplay/factory_survival.gd"
## Projection fixtures exercise visibility only; never grant supplies or cure.
const Gameplay=preload("res://scripts/runtime/factory_gameplay.gd")
func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output);host=Native.new()
	var profiles:Dictionary=Assembly.generation_profiles()
	check("actual B profiles available for alert visibility",profiles.ok,profiles)
	if not profiles.ok:return finish()
	var generated:Dictionary=Assembly.generate(713,profiles.profiles)
	var opening:Dictionary=Assembly.prepare(generated)
	check("actual opening available for alert visibility",opening.ok,opening)
	if not opening.ok:return finish()
	if not mount(opening.capture):return finish()
	var before:Dictionary=runtime.capture_checkpoint()
	var fresh:Dictionary=runtime._services.workforce.projection("*")
	check("fresh public workforce omits unknown people and map site",fresh.members.size()==1 and fresh.members[0].actor_id=="player" and fresh.people.size()==1 and fresh.regional_event.sites.is_empty() and fresh.alerts.is_empty())
	check("fresh map only exposes actual player rather than unknown world layout",fresh.map_markers.size()==1 and fresh.map_markers[0].id=="player" and not fresh.regional_event.defense.has("encounter_positions"))
	check("reading public workforce cannot mark discoveries or alter facts",Data.json_equal(before,runtime.capture_checkpoint()))
	var fixture:Dictionary=opening.capture.duplicate(true)
	for a:Dictionary in fixture.facts.actors:
		if a.id=="repair-resident":a.relationship.member=true;a.relationship.consent=true;a.thirst=20
		if a.id=="village-resident":a.hp=0
	var event:Dictionary=fixture.world.extensions[Gameplay.KEY];var site:Dictionary=event.layout.regional_sites[0]
	event.regional_objectives={site.id:{"site_id":site.id,"surveyed":true,"risk_accepted":false,"corridor_clear":false,"surveyed_at":0.0,"started_at":0.0}}
	event.event_ids.append("fixture:alert-cause");event.regional_events.append({"id":"fixture:alert-cause","kind":"fixture-route-commit","time":0.0})
	event.defense={"status":"warning","site_id":site.id,"warning_id":"fixture:alert-warning","warning_at":0.0,"arrival_at":300.0,"warning_remaining":300.0,"cause_event_id":"fixture:alert-cause","actors":[],"encounter_positions":site.encounter_positions.duplicate(true)}
	if not mount(fixture):return finish()
	before=runtime.capture_checkpoint()
	var view:Dictionary=runtime._services.workforce.projection("*")
	check("known member urgent need and actual warning become stable alerts",view.alerts.size()==2 and view.alerts.any(func(a:Dictionary)->bool:return a.key=="repair-resident:NEED_WATER" and a.object_id=="repair-resident") and view.alerts.any(func(a:Dictionary)->bool:return a.object_id==site.id and a.reason_code=="DEFENSE_WARNING" and a.episode_id=="fixture:alert-warning"))
	check("unknown incapacitated resident never leaks through alerts or members",not view.alerts.any(func(a:Dictionary)->bool:return a.object_id=="village-resident") and not view.members.any(func(a:Dictionary)->bool:return a.actor_id=="village-resident"))
	check("surveyed site appears without exposing enemy IDs",view.regional_event.sites.size()==1 and view.alerts.all(func(a:Dictionary)->bool:return not str(a).contains("infected:")))
	check("known map contains only player actual member and surveyed site",view.map_markers.size()==3 and view.map_markers.all(func(m:Dictionary)->bool:return m.id in ["player","repair-resident",site.id]) and not view.regional_event.defense.has("encounter_positions"))
	check("each alert has direct object reason severity and actual location",view.alerts.all(func(a:Dictionary)->bool:return a.has_all(["key","object_id","reason_code","severity","location","title","detail"]) and a.location is Dictionary))
	view.alerts.clear();view.members.clear();view.regional_event.sites.clear()
	var again:Dictionary=runtime._services.workforce.projection("*")
	check("projection mutation cannot dismiss or cure original risks",again.alerts.size()==2 and Data.json_equal(before,runtime.capture_checkpoint()))
	var blocked:Dictionary=fixture.duplicate(true);blocked.world.extensions[Gameplay.KEY].defense.status="awaiting_execution";blocked.world.extensions[Gameplay.KEY].defense.warning_remaining=0;blocked.world.extensions[Gameplay.KEY].defense.spawn_error={"code":"NO_FEET","reason":"真实脚点无效"}
	if not mount(blocked):return finish()
	var pending:Dictionary=runtime._services.workforce.projection("*")
	check("bad encounter point reports blocked unresolved episode rather than victory",pending.alerts.any(func(a:Dictionary)->bool:return a.reason_code=="DEFENSE_SPAWN_BLOCKED" and a.episode_id=="fixture:alert-warning" and a.detail.contains("真实脚点无效")) and runtime.world.extension(Gameplay.KEY).defense.status=="awaiting_execution")
	finish()
func finish()->void:
	var report:Dictionary={"scope":"Pure known-member/site alerts and visibility with explicit needs/warning fixtures; no discovery/risk/inventory mutations, read-state owner remains A; not OS/VA/package","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":report.failed}));host.free();quit(1 if report.failed else 0)
