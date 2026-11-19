extends SceneTree
## Exact old/current authority comparison on an actual saved world.
const Before=preload("res://tests/world/fixtures/candidate_view16.gd")
const Current=preload("res://scripts/world/world_state.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(name:String,ok:bool)->void:
	checks.append({"name":name,"ok":ok})
	if not ok:push_error(name)
func run()->void:
	var args:=OS.get_cmdline_user_args();var output:String=args[0]
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]))
	check("actual saved world decodes",decoded.ok)
	if not decoded.ok:return finish(output,[])
	var before:=Before.new();var current:=Current.new()
	check("same complete old/current source loads",before.load_snapshot(decoded.capture.world).ok and current.load_snapshot(decoded.capture.world).ok)
	var original:Dictionary=current.snapshot();var revision:int=current.get_revision()
	var entity:Dictionary=current.entities()[0];var next:Dictionary=entity.duplicate(true);next["projection_probe"]={"value":1}
	var residency:Dictionary=before.prepare_region_residency(str(current.region_ids()[0]),false,revision,64)
	check("same real storage change prepares",residency.ok and not residency.world_changes.is_empty())
	var cases:Array=[{"name":"extension","changes":[{"op":"extension.set","id":"test:projection17","before_exists":false,"before":null,"after":{"nested":[{"value":1}]}}]}, {"name":"entity","changes":[{"op":"entity.put","id":entity.id,"before_exists":true,"before":entity,"after":next}]}]
	if residency.ok:cases.append({"name":"storage64","changes":residency.world_changes})
	var rows:Array=[]
	for fixture:Dictionary in cases:
		var times:Array=[[],[]]
		for round_index in 8:
			for side:int in ([0,1] if round_index%2==0 else [1,0]):
				var w:RefCounted=before if side==0 else current
				var began:int=Time.get_ticks_usec()
				var tx:Dictionary=w.prepare_changes(fixture.changes,revision)
				times[side].append(Time.get_ticks_usec()-began)
				check("same real candidate accepted "+str(fixture.name)+"/"+str(round_index)+"/"+str(side),tx.ok)
				if tx.ok:w.discard_prepared(tx.capability)
				# Dispose this candidate outside both timings; otherwise the next
				# side pays for destroying the old side's large detached graph.
				tx.clear()
		var a:Dictionary=before.prepare_changes(fixture.changes,revision);var b:Dictionary=current.prepare_changes(fixture.changes,revision)
		check("complete candidate and receipt identical "+str(fixture.name),a.ok and b.ok and Data.json_equal(a.view.snapshot(),b.view.snapshot()) and Data.json_equal(a.changes,b.changes))
		before.discard_prepared(a.capability);current.discard_prepared(b.capability)
		rows.append({"case":fixture.name,"before_usec":times[0],"after_usec":times[1]})
	check("all uncommitted candidates leave full authority unchanged",Data.json_equal(current.snapshot(),original) and Data.json_equal(before.snapshot(),original))
	var tx:Dictionary=current.prepare_changes(cases[0].changes,revision)
	var projected:RefCounted=tx.view;var expected:Dictionary=projected.snapshot()
	var reader:Callable=projected.get("_reader")
	check("reflective reader cannot invoke getters setters or initialization",reader.call("get",["_state"])==null and reader.call("set",["_state",{}])==null and reader.call("_init",[{}])==null)
	check("lambda exposes no backing through bound arguments or owner",reader.get_bound_arguments().is_empty() and (reader.get_object()==null or reader.get_object() is Script))
	# Every exported mutable aggregate is a detached projection, including packed
	# arrays. Query methods still read the candidate after these modifications.
	var chunk_id:String=current.chunk_keys()[0]
	var chunk:Dictionary=projected.chunk(chunk_id);chunk.cells.fill(999)
	var snapshot:Dictionary=projected.snapshot();snapshot.chunks[chunk_id].cells.fill(999)
	var extension:Dictionary=projected.extension("test:projection17");extension.nested[0].value=999
	var requested:Array[String]=["nested"]
	var fields:Dictionary=projected.extension_fields("test:projection17",requested);fields.nested[0].value=999
	var entities:Array=projected.entities();entities[0].position.x=999
	var regions:Array=projected.regions();regions[0].bounds.min.x=999
	check("all aggregate getters retain full candidate isolation",Data.json_equal(projected.snapshot(),expected))
	projected._state.chunks[chunk_id].cells.fill(999)
	projected._state.extensions["test:projection17"].nested[0].value=999
	check("legacy mutable state still edits its own projection",projected.extension("test:projection17").nested[0].value==999)
	check("legacy mutable state cannot edit authority/capability",Data.json_equal(current.snapshot(),original) and current.commit_prepared(tx.capability).ok and Data.json_equal(current.snapshot(),expected))
	# Keep a borrowed view alive across subsequent commits and same-revision load.
	var retained:Dictionary=current.prepare_changes([],current.get_revision())
	var retained_view:RefCounted=retained.view;var retained_snapshot:Dictionary=retained_view.snapshot()
	current.discard_prepared(retained.capability)
	var changed:Dictionary=current.entity(str(entity.id));changed["projection_probe"]={"value":2}
	var change:Dictionary=current.prepare_changes([{"op":"entity.put","id":entity.id,"before_exists":true,"before":current.entity(str(entity.id)),"after":changed}],current.get_revision())
	check("later entity commit succeeds",change.ok and current.commit_prepared(change.capability).ok)
	check("borrowed old projection survives later commit exact",Data.json_equal(retained_view.snapshot(),retained_snapshot))
	current.load_snapshot(original)
	check("borrowed old projection survives snapshot replacement exact",Data.json_equal(retained_view.snapshot(),retained_snapshot))
	retained_view._state={"revision":-55}
	check("legacy state setter replaces projection only",retained_view.get_revision()==-55 and Data.json_equal(current.snapshot(),original))
	finish(output,rows)
func finish(output:String,rows:Array)->void:
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"rows":rows,"scope":"Alternating same-input old16/current World prepare CPU; complete candidate/receipt equality and aggregate/legacy escape/old-view lifetime isolation. No FPS claim."},"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed,"rows":rows}));quit(1 if failed else 0)
