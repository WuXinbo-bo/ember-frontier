extends SceneTree
const Client=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
class Fixture extends Client:
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
var checks:Array=[]
var output:String
var host:Fixture
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:push_error(label+" "+str(detail))
func run()->void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	host=Fixture.new();host.controls_path=output+"/controls.json";host.store=Store.new(output+"/saves");root.add_child(host)
	check("real old finite fixture builds",host._new_rural(713).ok)
	var capture:Dictionary=host.runtime.capture_checkpoint()
	var ready:Dictionary=await host._mount_ready(capture)
	check("formal near-physics promotion succeeds",ready.ok and host._terrain_view.statistics().budgeted_edits,ready)
	host.runtime.set_paused(false)
	var r:RefCounted=host.runtime;var p:Dictionary=r.actor("player")
	check("promoted world actually consumes near readiness",r.spatial_readiness().ready)
	var x:int=floori((float(p.x)+2.0)/0.5);var z:int=floori((float(p.z)+2.0)/0.5);var y:=-1
	var before:int=host.world.cell_at(x,y,z)
	var changed:Dictionary=r._commit({"world_changes":[{"op":"voxel.set","cell":{"x":x,"y":y,"z":z},"before":before,"after":0}]})
	check("real terrain edit commits with unchanged body safety",changed.ok,changed)
	var gate:Dictionary=r.spatial_readiness()
	check("logical edit retires stale collision until actual rebuild",not gate.ready and not gate.physics_ready,gate)
	var clock:float=r.clock();var hunger:float=r.actor("player").hunger
	r.tick(0.25)
	check("waiting geometry preserves accepted time but advances no costs",r.clock()==clock and r.actor("player").hunger==hunger and is_equal_approx(r.simulation_budget().backlog_seconds,0.25))
	check("late tool/life input cannot pass stale physical neighborhood",r.command({"kind":"eat","actor_id":"player","command_id":"wait:eat"}).code=="NOT_READY")
	var deadline:int=Time.get_ticks_msec()+20000
	while not r.spatial_readiness().ready and Time.get_ticks_msec()<deadline:await process_frame
	check("bounded C stages reach real geometry and physics readiness",r.spatial_readiness().ready,host._terrain_view.statistics())
	for i:int in 5:r.tick(0)
	check("accepted debt resumes exactly after collision ready",is_equal_approx(r.clock()-clock,0.2) and is_equal_approx(r.simulation_budget().backlog_seconds,0.05))
	check("normal life command then works through same authority",r.command({"kind":"eat","actor_id":"player","command_id":"ready:eat"}).ok)
	finish()
func finish()->void:
	var report:Dictionary={"scope":"source/headless actual mesh/shape/physics frames and runtime input gate; explicit finite edit fixture; no OS/performance claim","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var f:=FileAccess.open(output+"/results.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t",true,true));f.close();print(JSON.stringify(report));if host!=null:host.free()
	quit(1 if report.failed else 0)
