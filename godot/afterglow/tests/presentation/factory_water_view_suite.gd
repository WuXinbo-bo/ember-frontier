extends SceneTree
## Post22 SOURCE presentation contract probes, not a normal route or VA.
const View=preload("res://scripts/presentation/factory_water_view.gd")
const Factory=preload("res://scripts/presentation/factory_view.gd")
const Contracts=preload("res://scripts/runtime/factory_contracts.gd")
var checks:Array=[]
var geometry:Array=[]

class Authority extends RefCounted:
	var world:RefCounted=RefCounted.new()
	var snapshot:Dictionary={}
	var paused:=false
	func factory_snapshot()->Dictionary:return snapshot.duplicate(true)
	func is_paused()->bool:return paused

func _initialize()->void:call_deferred("run")

func expect(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))

func entity(direction:float=1.0)->Dictionary:
	return {"id":"RH-HOME:emergency-water","kind":"prop","position":{"x":12.0,"y":1.0,"z":8.0},"data":{"water_source_id":"RH-HOME:emergency-water","water_use_point":{"x":12.0+1.2*direction,"y":1.5,"z":8.0}}}

func dto(status:String="needs_repair",remaining:int=48)->Dictionary:
	return {"available":true,"sources":[{"id":"RH-HOME:emergency-water","discovered":true,"status":status,"remaining":remaining,"project_id":"","location":{"x":12.0,"y":1.0,"z":8.0}}],"projects":[]}

func job(operation:String="repair",progress:float=.25)->Dictionary:
	var value:Dictionary=dto("needs_repair" if operation=="repair" else "ready")
	value.sources[0].project_id="project1"
	value.projects=[{"id":"project1","source_id":"RH-HOME:emergency-water","actor_id":"player","operation":operation,"progress_seconds":progress,"duration_seconds":16.0 if operation=="repair" else 12.0,"effective_work":.1,"status":"active","paused_reason":""}]
	return value

func stream(fixture:Node3D)->bool:return fixture.get_node("Assembly/stream").visible

func run()->void:
	var authority:=Authority.new();var world_id:int=authority.world.get_instance_id()
	var parent:=Node3D.new();root.add_child(parent)
	parent.position=Vector3(400,20,-800);parent.rotation.y=.7
	var fixture:Node3D=View.create_fixture(entity(),world_id);parent.add_child(fixture)
	fixture.position=Vector3(12,1,8)
	expect("one visible unknown body without balance",fixture.get_meta("water_state")=="unknown" and fixture.get_child_count()==1 and not fixture.has_meta("remaining") and not stream(fixture))
	expect("no physics authority nodes",physics_count(fixture)==0)
	expect("tap faces real use point plus X",(fixture.get_node("Assembly").basis*Vector3.BACK).distance_to(Vector3.RIGHT)<.00001)
	var opposite:Node3D=View.create_fixture(entity(-1),world_id+1);parent.add_child(opposite)
	expect("tap follows real use point minus X",(opposite.get_node("Assembly").basis*Vector3.BACK).distance_to(Vector3.LEFT)<.00001)
	expect("static geometry reused per fixture",fixture.get_node("Assembly/body").mesh==opposite.get_node("Assembly/body").mesh)
	probe_mesh(fixture)
	export_state(fixture,"unknown")
	var snapshot:Dictionary=job();var original:Dictionary=snapshot.duplicate(true)
	View.sync_tree(self,world_id,snapshot)
	expect("repair visibly follows actual phase",fixture.get_meta("water_state")=="needs_repair" and fixture.get_meta("work_phase")==.25 and not stream(fixture))
	export_state(fixture,"repairing")
	expect("other world remains unknown",opposite.get_meta("water_state")=="unknown")
	expect("public DTO never mutated",snapshot==original)
	var rotation:Vector3=fixture.get_node("Assembly/loose").rotation
	View.sync_tree(self,world_id,snapshot)
	expect("same progress has no autonomous animation",fixture.get_node("Assembly/loose").rotation==rotation)
	snapshot=job("repair",.5);View.sync_tree(self,world_id,snapshot)
	expect("different real progress changes fitting",fixture.get_node("Assembly/loose").rotation!=rotation)
	View.sync_tree(self,world_id,dto("ready"))
	expect("completed repair swaps actual parts",not fixture.get_node("Assembly/loose").visible and fixture.get_node("Assembly/repaired").visible and not stream(fixture))
	export_state(fixture,"repaired")
	snapshot=job("draw");View.sync_tree(self,world_id,snapshot)
	expect("effective real draw opens valve and water",stream(fixture) and fixture.get_node("Assembly/lever").rotation.x>0)
	export_state(fixture,"drawing")
	for reason:String in ["paused","operator_not_at_water","output_full","region_paused","water_source_missing"]:
		snapshot=job("draw");snapshot.projects[0].paused_reason=reason;snapshot.projects[0].status="paused" if reason=="paused" else "blocked"
		View.sync_tree(self,world_id,snapshot)
		expect("no water on actual stop "+reason,not stream(fixture) and is_equal_approx(fixture.get_node("Assembly/lever").rotation.x,.2))
	snapshot=job("draw");snapshot.projects[0].effective_work=0.0;View.sync_tree(self,world_id,snapshot)
	expect("no stream for scheduled work without progress",not stream(fixture))
	View.sync_tree(self,world_id,dto("ready",0))
	expect("empty has no water or stock proxy",fixture.get_meta("water_state")=="empty" and not stream(fixture) and not fixture.has_meta("remaining"))
	expect("empty parks intact repaired lever and closes real outlet",fixture.get_node("Assembly/lever").visible and is_zero_approx(fixture.get_node("Assembly/lever").rotation.x) and fixture.get_node("Assembly/cap").visible and not fixture.get_node("Assembly/loose").visible)
	export_state(fixture,"empty")
	View.sync_tree(self,world_id,{"available":false})
	expect("lost projection hides work and preserves physical repair",not fixture.get_meta("public_known") and not stream(fixture) and fixture.get_node("Assembly/repaired").visible and not fixture.get_node("Assembly/cap").visible)
	probe_invalid(fixture,world_id)
	var factory:Node3D=Factory.new();root.add_child(factory);factory.set_process(false)
	authority.snapshot={"available":true,"schema":Contracts.SCHEMA,"version":Contracts.VERSION,"world_id":"public-world","modules":{"available":false},"water":job("draw")}
	factory.configure(authority)
	expect("real factory consumer syncs water with unavailable modules",stream(fixture) and not stream(opposite))
	authority.paused=true;factory.sync()
	expect("global pause closes stale last effective stream",not stream(fixture))
	authority.paused=false;factory.sync()
	expect("resume reuses actual progress only",stream(fixture))
	authority.snapshot.water={"available":true,"sources":[],"projects":[]};factory.sync()
	expect("undiscovered empty source DTO hides water",not stream(fixture) and not fixture.get_meta("public_known"))
	authority.snapshot.water=job("draw");factory.sync();factory.configure(null)
	expect("runtime detach clears old world work",not stream(fixture))
	factory.configure(authority);factory.free()
	expect("consumer exit clears live physical work",not stream(fixture))
	parent.remove_child(fixture);fixture.free()
	expect("released node leaves scene group",get_nodes_in_group(View.GROUP).size()==1)
	var rebuilt:Node3D=View.create_fixture(entity(),world_id);parent.add_child(rebuilt)
	expect("rebuilt physical node has no stale work state",not stream(rebuilt) and rebuilt.get_meta("water_state")=="unknown")
	View.sync_tree(self,world_id,dto("ready",0))
	expect("revisit consumes restored public state without refill",rebuilt.get_meta("water_state")=="empty" and not stream(rebuilt))
	var bad:Dictionary=entity();bad.data.erase("water_use_point")
	expect("missing use point rejected instead of guessed",View.create_fixture(bad,world_id)==null)
	bad=entity();bad.data.water_source_id="other"
	expect("wrong entity identity rejected",View.create_fixture(bad,world_id)==null)
	expect("zero world identity rejected",View.create_fixture(entity(),0)==null)
	var args:PackedStringArray=OS.get_cmdline_user_args()
	var failures:Array=checks.filter(func(v:Dictionary)->bool:return not v.ok)
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"post22 source overlay, synthetic public DTO fixture; no normal route/OS/VA/FPS"},"\t"))
	FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(geometry))
	print("WT01_VIEW "+str(checks.size())+" checks / "+str(failures.size())+" failures")
	parent.free();quit(0 if failures.is_empty() else 1)

func probe_invalid(fixture:Node3D,world_id:int)->void:
	var cases:Dictionary={}
	var value:Dictionary=job("draw");value.sources.append(value.sources[0].duplicate(true));cases.duplicate_source=value
	value=job("draw");value.sources[0].location.x+=.1;cases.moved_source=value
	value=job("draw");value.sources[0].remaining=49;cases.overflow=value
	value=job("draw");value.sources[0].remaining=0;cases.empty_draw=value
	value=job("draw");value.sources[0].discovered=false;cases.undiscovered=value
	value=job("draw");value.projects[0].source_id="other";cases.wrong_source=value
	value=job("draw");value.projects[0].actor_id="npc";cases.wrong_actor=value
	value=job("draw");value.projects[0].duration_seconds=1.0;cases.fake_duration=value
	value=job("draw");value.projects[0].progress_seconds=NAN;cases.nan_progress=value
	value=job("draw");value.projects[0].effective_work=INF;cases.infinite_work=value
	value=job("draw");value.projects.append(value.projects[0].duplicate(true));cases.duplicate_project=value
	for label:String in cases:
		View.sync_tree(self,world_id,cases[label])
		expect("invalid projection closes valve "+label,not stream(fixture) and not fixture.get_meta("projection_issue").is_empty())

func physics_count(node:Node)->int:
	var total:int=1 if node is CollisionObject3D or node is CollisionShape3D else 0
	for child:Node in node.get_children():total+=physics_count(child)
	return total

func probe_mesh(fixture:Node3D)->void:
	var all_bound:=true;var all_finite:=true;var winding:=true;var surfaces:int=0;var triangles:int=0
	for part:MeshInstance3D in fixture.get_node("Assembly").get_children():
		for surface:int in part.mesh.get_surface_count():
			surfaces+=1
			var a:Array=part.mesh.surface_get_arrays(surface);var vertices:PackedVector3Array=a[Mesh.ARRAY_VERTEX];var ns:PackedVector3Array=a[Mesh.ARRAY_NORMAL];var uv:PackedVector2Array=a[Mesh.ARRAY_TEX_UV];var indices:PackedInt32Array=a[Mesh.ARRAY_INDEX]
			var points:Array=[]
			for i:int in vertices.size():
				var point:Vector3=part.transform*vertices[i];points.append([point.x,point.y,point.z])
				all_bound=all_bound and point.x>=-.60001 and point.x<=.60001 and point.y>=-.00001 and point.y<=1.40001 and point.z>=-.60001 and point.z<=.60001
				all_finite=all_finite and point.is_finite() and ns[i].is_finite() and is_finite(uv[i].x) and is_finite(uv[i].y) and absf(ns[i].length()-1)<.0001
			for i:int in range(0,indices.size(),3):
				triangles+=1
				var cross:Vector3=(vertices[indices[i+1]]-vertices[indices[i]]).cross(vertices[indices[i+2]]-vertices[indices[i]])
				winding=winding and cross.length_squared()>1e-14 and cross.normalized().dot(ns[indices[i]])<-.99
	expect("all actual geometry inside B collision AABB",all_bound)
	expect("all vertices UV and unit normals finite",all_finite)
	expect("nondegenerate clockwise faces",winding)
	expect("bounded merged draw surfaces",surfaces<=12,{"surfaces":surfaces,"triangles":triangles})
	var paint:StandardMaterial3D=View.materials().paint
	expect("existing tank paint bound at one metre with mipmaps",paint.get_meta("source_resource")==View.PAINT and paint.get_meta("tile_meters")==1.0 and paint.albedo_texture.get_image().has_mipmaps())

func export_state(fixture:Node3D,label:String)->void:
	var surfaces:Array=[]
	for part:MeshInstance3D in fixture.get_node("Assembly").get_children():
		if not part.visible:continue
		for surface:int in part.mesh.get_surface_count():
			var a:Array=part.mesh.surface_get_arrays(surface);var vertices:Array=[];var normals:Array=[];var uv:Array=[]
			for i:int in a[Mesh.ARRAY_VERTEX].size():
				var point:Vector3=part.transform*a[Mesh.ARRAY_VERTEX][i];var normal:Vector3=part.basis*a[Mesh.ARRAY_NORMAL][i]
				vertices.append([point.x,point.y,point.z]);normals.append([normal.x,normal.y,normal.z]);uv.append([a[Mesh.ARRAY_TEX_UV][i].x,a[Mesh.ARRAY_TEX_UV][i].y])
			var material:StandardMaterial3D=part.mesh.surface_get_material(surface)
			surfaces.append({"part":str(part.name),"vertices":vertices,"normals":normals,"uv":uv,"indices":Array(a[Mesh.ARRAY_INDEX]),"material":material.get_meta("source_resource",""),"color":[material.albedo_color.r,material.albedo_color.g,material.albedo_color.b,material.albedo_color.a]})
	geometry.append({"state":label,"surfaces":surfaces,"scope":"actual visible local mesh buffers; CPU projection only"})
