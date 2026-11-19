extends SceneTree
## Read-only recorder contract. Injected samples are explicitly synthetic;
## neither these values nor this short headless run qualify a real soak.
const Client=preload("res://scripts/runtime/native_client.gd")
const Metrics=preload("res://scripts/presentation/native_performance.gd")
const Data=preload("res://scripts/world/world_data.gd")
class Fixture extends Client:
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool)->void:
	checks.append({"name":label,"ok":ok})
	if not ok:push_error(label)
func run()->void:
	var output:String=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	var host:=Fixture.new();host.controls_path=output+"/controls.json";root.add_child(host)
	check("actual isolated source authority mounts",host._new_rural(713).ok)
	var metrics:=Metrics.new();host.add_child(metrics);metrics.configure(host.runtime,func()->Dictionary:return {"fixture":true,"queued":2,"worker":1});metrics.set_process(false)
	check("minute monitoring is opt-in for ordinary runs",not metrics._soak_monitor)
	var before:Dictionary=host.runtime.capture_checkpoint()
	metrics._trend_start_usec=Time.get_ticks_usec();metrics._trend_mark_usec=metrics._trend_start_usec
	metrics._trend_frames.assign([16.0,18.0,275.0]);metrics._trend_active_usec=309000;metrics._trend_excluded_usec=90000
	metrics.reset("synthetic-counter-contract")
	check("normal fixed-scene window reset does not erase wall trend",metrics._trend_frames.size()==3 and metrics._trend_active_usec==309000 and metrics._trend_excluded_usec==90000)
	var row:Dictionary=metrics._trend_report("synthetic-fixture-not-soak")
	check("read-only record keeps world process and scene identity",row.pid==OS.get_process_id() and row.world==host.world.identity() and row.session==metrics._session)
	check("full synthetic stall is reported without clamping",row.frame.count==3 and row.frame.max==275 and row.frame.p99==275 and row.over250==1)
	check("active and excluded durations remain separate",row.active_ms==309 and row.excluded_ms==90 and not row.complete_minute)
	check("queue and memory observations are present without changing policy",row.region_scheduler=={"fixture":true,"queued":2,"worker":1} and row.has("static_memory") and row.has("nodes") and row.has("orphan_nodes"))
	check("scene resources count actual live geometry without inventing RSS",row.scene_resources.meshes>0 and row.scene_resources.materials>0 and row.scene_resources.shapes>0 and row.scene_resources.nodes>row.scene_resources.meshes)
	var extra_mesh:=MeshInstance3D.new();extra_mesh.mesh=BoxMesh.new();host.add_child(extra_mesh)
	var second_mesh:=MeshInstance3D.new();second_mesh.mesh=extra_mesh.mesh;host.add_child(second_mesh)
	var counts:Dictionary=metrics._scene_resources()
	check("shared resource instances count once",counts.meshes==row.scene_resources.meshes+1 and counts.nodes==row.scene_resources.nodes+2)
	extra_mesh.free();second_mesh.free()
	check("released scene resource references return to baseline",metrics._scene_resources().meshes==row.scene_resources.meshes)
	check("next trend interval starts empty",metrics._trend_frames.is_empty() and metrics._trend_active_usec==0 and metrics._trend_excluded_usec==0)
	check("recording leaves complete authority unchanged",host.runtime.capture_checkpoint()==before)
	# This exceeds the actual truncated23 console row. Retain every byte in
	# the explicit isolated output, while ordinary recorder use writes nothing.
	row.region_scheduler={"oversized_synthetic_provenance":"region-state-".repeat(2000)}
	var full:Dictionary=row.duplicate(true)
	check("ordinary recorder does not create performance files",metrics._evidence_directory.is_empty() and metrics._emit_record("R3.3 synthetic recorder ",row).is_empty() and not DirAccess.dir_exists_absolute(output+"/metrics"))
	metrics._evidence_directory=output+"/metrics"
	var artifact:Dictionary=metrics._emit_record("R3.3 synthetic recorder ",row)
	check("explicit QA record writes complete oversized provenance with checksum",artifact.has("path") and artifact.get("bytes",0)>20000 and FileAccess.get_sha256(artifact.path)==artifact.get("sha256",""))
	var decoded:Variant=JSON.parse_string(FileAccess.get_file_as_string(artifact.get("path","")))
	check("complete artifact exactly preserves scene counters and full stall",decoded is Dictionary and Data.json_equal(decoded,full) and decoded.frame.max==275 and not decoded.complete_minute)
	var next:Dictionary=metrics._emit_record("R3.3 synthetic recorder ",row)
	check("later record never overwrites prior measurement",next.get("path","")!=artifact.path and FileAccess.get_sha256(next.get("path",""))==artifact.sha256 and FileAccess.get_sha256(artifact.path)==artifact.sha256)
	check("evidence projection preserves original and authority",Data.json_equal(row,full) and host.runtime.capture_checkpoint()==before)
	var report:Dictionary={"scope":"synthetic recorder contract only, actual isolated source authority; not elapsed-wall-time, OS, performance or long-soak qualification","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var f:=FileAccess.open(output+"/results.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t",true,true));f.close();host.free();print(JSON.stringify(report));quit(1 if report.failed else 0)
