extends SceneTree
## Read-only reconstruction. Screen mapping is inferred, never capture telemetry.
const Generator=preload("res://scripts/world/settlement_generator.gd")
const Buildings=preload("res://scripts/buildings/building_service.gd")
const State=preload("res://scripts/world/world_state.gd")
const Queries=preload("res://scripts/terrain/terrain_queries.gd")
const Mesher=preload("res://scripts/terrain/terrain_mesher.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Store=preload("res://scripts/storage/native_store.gd")
var checks:Array=[]
var evidence:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label)
func face_area(data:Dictionary)->Dictionary:
	var result:Dictionary={}
	for g:Dictionary in data.groups.values():
		for i in range(0,g.vertices.size(),4):
			var a:Vector3=g.vertices[i];var b:Vector3=g.vertices[i+1];var c:Vector3=g.vertices[i+2]
			var normal:Vector3=g.normals[i]
			var key:=str([g.material,normal,a.dot(normal)])
			result[key]=float(result.get(key,0.0))+(b-a).cross(c-a).length()
	return result
func run()->void:
	var world:=State.new();var source:Dictionary=Generator.generate(713,Buildings.generation_profiles())
	check("rural2 snapshot loads without touching active save",world.load_snapshot(source).ok)
	var readonly:="res://../../work/r3-3-bbb/sixth-active-readonly-capture-visual.json"
	var original_bytes:PackedByteArray=FileAccess.get_file_as_bytes(readonly)
	var original_sha:=HashingContext.new();original_sha.start(HashingContext.HASH_SHA256);original_sha.update(original_bytes)
	var capture_sha:String=original_sha.finish().hex_encode()
	var captured:Dictionary=Store.decode(original_bytes.get_string_from_utf8())
	check("actual readonly sixth native envelope and world checksum decode",captured.ok,capture_sha)
	if not captured.ok:quit(1);return
	var actual:Dictionary=captured.capture.world.duplicate(true)
	# Native restore intentionally starts cold. Warm this isolated local copy
	# for mesh derivation only; never save it or touch user://saves/active.
	for c:Dictionary in actual.chunks.values():c.resident=true
	check("readonly captured voxel buffers match original rural2 generation",actual.chunks.keys().all(func(key:String)->bool:return PackedInt32Array(actual.chunks[key].cells)==PackedInt32Array(source.chunks[key].cells)))
	world.load_snapshot(actual)
	var focus:=Vector3(27,5.7,35.6);var offset:=Vector3(24,29,31)
	var back:=offset.normalized();var right:=Vector3.UP.cross(back).normalized();var up:=back.cross(right)
	var rays:Array=[];var keys:Dictionary={}
	for pixel:Vector2 in [Vector2(1280,245),Vector2(1420,280),Vector2(1420,535),Vector2(1507,575),Vector2(1570,625),Vector2(1500,900)]:
		var origin:=focus+offset+right*((pixel.x-817.0)*24.0/1021.25)-up*((pixel.y-598.625)*24.0/1021.25)
		var hit:=Queries.pick(world,origin,origin-back*180)
		var row:Dictionary={"pixel":[pixel.x,pixel.y],"hit":hit}
		if hit.has("cell"):
			var p:Dictionary=hit.cell;var point:=Vector3((p.x+0.5)*0.5,(p.y+1)*0.5,(p.z+0.5)*0.5)
			row.world_cell_top=[point.x,point.y,point.z]
			row.pad_constraints=[]
			for pad:Dictionary in world.extension("generation:RH-HOME").grade_controls:
				var distance:float=Generator._rect_distance(point.x,point.z,pad.xz)
				row.pad_constraints.append({"pad":pad.xz,"height":pad.height,"distance":distance,"minimum_grade":float(pad.height)-distance*0.25})
			keys[Data.key(Data.cell_chunk(Vector3i(p.x,p.y,p.z),16))]=true
		rays.append(row)
	evidence={"image":"work/r3-3/native-sixth-visual/generated-village-first-observation.png","capture_parameters_from_A":{"player":[27,5,35.6],"camera_offset":[24,29,31],"orthographic_size":24},"inferred_only":{"seed":713,"world_id":"rural:v2:713","snapshot_revision":0,"game_image_rect":[0,88,1634,1021.25],"camera_focus_settled":true},"caution":"No screenshot-time world snapshot/revision or Retina crop telemetry. Ray cells are candidate correspondences, not verified capture IDs. Current mapgen and complete pad footprint must match source6 SHA.","rays":rays,"meshes":[]}
	for key:String in keys:
		var greedy:Dictionary=Mesher.build(world,key,true);var simple:Dictionary=Mesher.build(world,key,false)
		var parity:bool=face_area(greedy)==face_area(simple)
		var valid:=true
		for g:Dictionary in greedy.groups.values():
			for i in range(0,g.indices.size(),3):
				var a:Vector3=g.vertices[g.indices[i]];var b:Vector3=g.vertices[g.indices[i+1]];var c:Vector3=g.vertices[g.indices[i+2]]
				valid=valid and (b-a).cross(c-a).length_squared()>0 and (b-a).cross(c-a).normalized().dot(g.normals[g.indices[i]])< -0.999
		check("candidate mesh exact exposed-plane area/winding "+key,parity and valid,{"greedy_quads":greedy.quads,"unit_quads":simple.quads})
		evidence.meshes.append({"key":key,"greedy_quads":greedy.quads,"unit_quads":simple.quads,"plane_area_exact":parity,"clockwise_valid":valid})
	var plan:Dictionary=world.extension("generation:RH-HOME");var scan:Array=[]
	for z:float in [25.25,30.25,35.25,40.25]:
		var row:Array=[]
		for x:float in [26.25,28.25,30.25,32.25,34.25,36.25,38.25,40.25]:row.append(world.surface_height(x,z))
		scan.append({"z":z,"x_from":26.25,"x_step":2.0,"actual_surface_y":row})
	evidence.terrace_scan=scan
	evidence.readonly_native_capture={"path":readonly,"sha256":capture_sha,"identity":world.identity(),"world_revision":world.get_revision(),"saved_actor":captured.capture.facts.actors.filter(func(a:Dictionary)->bool:return a.id=="player"),"caution":"Captured save is actual source6 but not screenshot-time player state. Screenshot rays/crop stay inferred. Local residency warmed solely to inspect unchanged cell bytes."}
	evidence.root_cause="The shared rectangular pad grade envelope deliberately extends 0.25m/m lower bounds outside every pad; snapping at 0.5m creates parallel 2m treads and corner stair silhouettes. This is authored cell geometry, not evidence of missing greedy faces. Does not classify Metal shadow darkness."
	check("same actual pad creates repeated 0.5m treads east of home",scan[0].actual_surface_y.slice(1,6)==scan[1].actual_surface_y.slice(1,6))
	check("readonly input file remains exact original bytes",FileAccess.get_file_as_bytes(readonly)==original_bytes)
	var failed:=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	var result:Dictionary={"checks":checks,"failed":failed,"evidence":evidence,"scope":"headless readonly diagnostic, no formal image/render or save acceptance"}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));quit(1 if failed else 0)
