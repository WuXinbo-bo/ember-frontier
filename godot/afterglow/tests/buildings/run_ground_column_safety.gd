extends SceneTree
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Current=preload("res://scripts/buildings/building_space.gd")
const Original=preload("res://tests/buildings/saved_route_reference/building_space.gd")
var checks:Array=[]
func check(label:String,ok:bool,detail:Variant=null)->void:checks.append({"name":label,"ok":ok,"detail":detail})
func _initialize()->void:call_deferred("run")
func run()->void:
	var args:=OS.get_cmdline_user_args();var output:String=args[0]
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]))
	var native:=Native.new();var built:Dictionary=native._assemble(decoded.capture);native.free()
	check("actual saved-state assembly",built.get("ok",false))
	if not built.get("ok",false):print(JSON.stringify({"checks":checks}));quit(1);return
	var rt:RefCounted=built.runtime;var b:RefCounted=rt._services.buildings;var w:RefCounted=built.world
	var before:Dictionary=rt.capture_checkpoint();var q:=Current.new();var old:=Original.new()
	q.configure(w,b.structures(),b.geometry,b.permission);old.configure(w,b.structures(),b.geometry,b.permission)
	var mismatches:Array=[];var n:int=0
	# Actual resident/outside columns, negative floor/modulo, exact cell edges,
	# partial config Y bounds, unknown columns and void all compare scalar values.
	for x:int in range(-33,130,3):
		for z:int in range(-33,130,3):
			for delta:float in [0.0,0.00001,0.49999]:
				var a:Variant=old.ground_height(x*0.5+delta,z*0.5+delta)
				var c:Variant=q.ground_height(x*0.5+delta,z*0.5+delta)
				if a!=c or q.ground_height(x*0.5+delta,z*0.5+delta)!=a:mismatches.append([x,z,delta,a,c])
				n+=1
	check("all exact/hot native columns equal frozen preimage",mismatches.is_empty(),{"queries":n,"mismatches":mismatches})
	var original_min:int=q.min_cell_y;var original_max:int=q.max_cell_y
	for bounds:Vector2i in [Vector2i(-7,39),Vector2i(0,1),Vector2i(1,1),Vector2i(-3,3)]:
		var clipped:=Current.new();var clipped_old:=Original.new()
		clipped.configure(w,b.structures(),b.geometry,b.permission);clipped_old.configure(w,b.structures(),b.geometry,b.permission)
		clipped.min_cell_y=bounds.x;clipped.max_cell_y=bounds.y;clipped_old.min_cell_y=bounds.x;clipped_old.max_cell_y=bounds.y
		check("partial/empty exact Y domain "+str(bounds),clipped.ground_height(16.0,7.5)==clipped_old.ground_height(16.0,7.5))
	q.min_cell_y=original_min;q.max_cell_y=original_max
	var x:int=32;var z:int=15;var y:int=1;var at:Vector2=Vector2(x*0.5,z*0.5)
	var old_height:Variant=q.ground_height(at.x,at.y)
	check("actual original support plane",old_height==0.5,old_height)
	# Explicit terrain counterexample only: authoritative prepare without commit.
	# A real separate immutable draft must not inherit any ground-height answer.
	var change:Dictionary={"op":"voxel.set","cell":{"x":x,"y":y,"z":z},"before":w.cell_at(x,y,z),"after":1}
	var prepared:Dictionary=w.prepare_changes([change],w.get_revision())
	check("real isolated voxel draft",prepared.ok)
	if prepared.ok:
		var child:=Current.new();var child_old:=Original.new()
		child.configure(prepared.view,b.structures(),b.geometry,b.permission);child_old.configure(prepared.view,b.structures(),b.geometry,b.permission)
		check("changed draft starts without borrowed column proof",child.ground_columns.is_empty())
		check("draft sees exact changed height and parent retains own proof",child.ground_height(at.x,at.y)==1.0 and child.ground_height(at.x,at.y)==child_old.ground_height(at.x,at.y) and q.ground_height(at.x,at.y)==old_height)
		check("same authoritative world revision invalidates current_space after commit",w.commit_prepared(prepared.capability).ok and b.current_space().ground_height(at.x,at.y)==1.0)
		var fresh:RefCounted=b.current_space();var again:=Original.new();again.configure(w,b.structures(),b.geometry,b.permission)
		check("new revision exact support uses changed voxel",fresh.body_location({"regionId":"RH-HOME","x":at.x,"y":0.5,"z":at.y})==again.body_location({"regionId":"RH-HOME","x":at.x,"y":0.5,"z":at.y}))
		var undo:Dictionary=w.prepare_changes([change.merged({"before":1,"after":change.before},true)],w.get_revision())
		check("real undo gets fresh original height",undo.ok and w.commit_prepared(undo.capability).ok and b.current_space().ground_height(at.x,at.y)==old_height)
	var after:Dictionary=rt.capture_checkpoint()
	check("fixture changes no actors/stocks/receipts/simulation",Data.json_equal(before.facts,after.facts) and Data.json_equal(before.receipts,after.receipts) and Data.json_equal(before.simulation,after.simulation))
	check("bounded column cache",q.ground_columns.size()<=16384)
	var report:Dictionary={"checks":checks,"scope":"exact scalar ground proof and isolated terrain mutation counterexamples, explicit fixture not normal economic journey; no FPS/OS claim"}
	FileAccess.open(output+"/detail.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print(JSON.stringify(report));rt.retire();quit(0 if checks.all(func(c:Dictionary)->bool:return c.ok) else 1)
