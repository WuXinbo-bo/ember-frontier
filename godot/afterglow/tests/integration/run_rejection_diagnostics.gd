extends SceneTree
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
const World=preload("res://scripts/world/world_state.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const Buildings=preload("res://scripts/buildings/building_service.gd")
const Data=preload("res://scripts/world/world_data.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var w:=World.new();assert(w.load_snapshot(Rural.generate(713)).ok)
	var r:=Runtime.new()
	# Isolated invalid-standing fixture recreates the safety failure, not a
	# claimed reproduction of the live gameplay warning. Never touches a save.
	var a:Dictionary={"id":"player","name":"isolated diagnostics","x":29.2,"y":8.0,"z":30.25,"regionId":"RH-HOME","buildingId":null,"storeyId":null,"hp":100.0,"hunger":90.0,"thirst":90.0,"stamina":80.0,"fatigue":0.0,"pack":{},"intent":null}
	assert(r.configure({"world":w,"facts":{"actors":[a],"stocks":[],"actions":[],"quests":[],"time":0.0,"status":"playing"},"services":{"buildings":Buildings.new()}}).ok)
	var before:Dictionary=r.capture_checkpoint()
	var revision:int=w.get_revision()
	var plan:Dictionary={"ok":true,"world_changes":[{"op":"extension.set","id":"r33:diagnostic-fixture","before_exists":false,"before":null,"after":{"version":1}}],"fact_changes":[],"events":[]}
	var receipt:Dictionary=r._commit(plan)
	var context:Dictionary=r._rejection_context("gameplay",plan,receipt)
	var checks:Array=[{"name":"real safety rejection retained","ok":not receipt.ok and receipt.code=="SPATIAL_REJECTED"},{"name":"failure has exact actor/current/draft feet and scene identity","ok":context.world.seed==713 and context.actors[0].before.y==8.0 and context.spatial_diagnostic.actors[0].current_feet.is_empty() and context.spatial_diagnostic.actors[0].draft_feet.is_empty()},{"name":"diagnostic is safe JSON evidence","ok":Data.json_value(context)},{"name":"rejected draft and facts remain unchanged","ok":w.get_revision()==revision and w.extension("r33:diagnostic-fixture")==null and r.capture_checkpoint()==before}]
	var report:Dictionary={"scope":"isolated real rejected transaction evidence only; not reproduction of build8 gameplay warning or OS acceptance","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size(),"context":context}
	var f:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t",true,true));f.close()
	print(JSON.stringify(report));quit(1 if report.failed else 0)
