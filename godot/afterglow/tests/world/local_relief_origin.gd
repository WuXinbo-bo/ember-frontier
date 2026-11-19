extends SceneTree
## Actual v7 PNG ROI to saved-cell/control attribution; detached diagnostics.
const Store=preload("res://scripts/storage/native_store.gd")
const State=preload("res://scripts/world/world_state.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Generator=preload("res://scripts/world/settlement_generator.gd")
const Relief=preload("res://scripts/world/local_relief.gd")
const Queries=preload("res://scripts/terrain/terrain_queries.gd")
var checks:Array=[]
var rows:Array=[]
var pad_evidence:Array=[]
var grids:Dictionary={}
var plans:Dictionary={}
var noises:Dictionary={}
var roads:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error(label+" "+str(detail))
func vector(a:Array)->Vector3:return Vector3(a[0],a[1],a[2])
func xyz(v:Vector3)->Array:return [v.x,v.y,v.z]
func prepare_grids(world:RefCounted)->void:
	for region:Dictionary in world.regions():
		var plan:Dictionary=world.extension("generation:"+str(region.id))
		if plan.is_empty():continue
		var id:String=plan.region_id;plans[id]=plan;roads[id]=Generator._road_index(plan)
		var noise:FastNoiseLite=Generator._noise(int(plan.seed));noises[id]=noise
		var coord:=Vector2i(int(plan.region_coord.x),int(plan.region_coord.z));var lands:Array=[]
		for z in range(coord.y-1,coord.y+2):
			for x in range(coord.x-1,coord.x+2):lands.append_array(Relief.landforms(Generator._landforms(Vector2i(x,z),noise),noise))
		for parcel:Dictionary in plan.parcels:
			var rect:Array=parcel.pad.xz;var base_samples:Array=[];var edge_samples:Array=[]
			for z in range(floori(rect[1]),ceili(rect[3])+1,2):
				for x in range(floori(rect[0]),ceili(rect[2])+1,2):base_samples.append(Relief._base(noise,x,z))
			for i in 17:
				var t:float=i/16.0
				edge_samples.append_array([Relief._base(noise,lerpf(rect[0],rect[2],t),rect[1]),Relief._base(noise,lerpf(rect[0],rect[2],t),rect[3]),Relief._base(noise,rect[0],lerpf(rect[1],rect[3],t)),Relief._base(noise,rect[2],lerpf(rect[1],rect[3],t))])
			base_samples.sort();edge_samples.sort()
			pad_evidence.append({"seed":int(plan.seed),"parcel":parcel.id,"pad":parcel.pad,"interior_base_min_median_max":[base_samples[0],base_samples[base_samples.size()/2],base_samples[-1]],"edge_base_min_median_max":[edge_samples[0],edge_samples[edge_samples.size()/2],edge_samples[-1]],"front_port":parcel.entrance_ports[0]})
		var variants:Dictionary={}
		for mode:String in ["same","without_landforms","without_pads","natural_only"]:
			var copy:Dictionary=plan.duplicate(true)
			if mode in ["without_pads","natural_only"]:copy.grade_controls=[]
			Relief.prepare(copy,noise,[] if mode in ["without_landforms","natural_only"] else lands)
			variants[mode]=copy
		var rebuilt:Array=variants.same.height.natural_surface.height_half_metres;var persisted:Array=plan.height.natural_surface.height_half_metres
		var mismatches:Array=[]
		for i in mini(rebuilt.size(),persisted.size()):
			if not Data.json_equal(rebuilt[i],persisted[i]):mismatches.append({"index":i,"rebuilt":rebuilt[i],"persisted":persisted[i]})
		check("same v7 reconstruction exact persisted 1225 levels "+str(int(world.identity().seed))+id,Data.json_equal(rebuilt,persisted),{"rebuilt_count":rebuilt.size(),"persisted_count":persisted.size(),"rebuilt_element_type":typeof(rebuilt[0]),"persisted_element_type":typeof(persisted[0]),"exact_numeric_mismatches":mismatches})
		grids[id]={"variants":variants,"lands":lands}
func region_at(world:RefCounted,x:float,z:float)->String:
	for region:Dictionary in world.regions():
		if Data.contains(region.bounds,{"x":x,"y":0,"z":z}):return str(region.id)
	return ""
func sample(world:RefCounted,x:float,z:float)->Dictionary:
	var id:String=region_at(world,x,z)
	if not plans.has(id):return {"x":x,"z":z,"known":false}
	var plan:Dictionary=plans[id];var noise:FastNoiseLite=noises[id];var heights:Dictionary={}
	for mode:String in grids[id].variants:heights[mode]=Relief.height(grids[id].variants[mode],x,z)
	var active_lands:Array=[];var active_pads:Array=[]
	for land:Dictionary in grids[id].lands:
		var distance:float=Relief._rect_distance(x,z,land.xz)
		if distance<4.0:active_lands.append({"id":land.id,"use":land.use,"xz":land.xz,"target_y":land.height,"distance":distance})
	for pad:Dictionary in plan.grade_controls:
		var distance:float=Relief._rect_distance(x,z,pad.xz)
		if distance<Relief.PAD_LIMIT:active_pads.append({"xz":pad.xz,"target_y":pad.height,"distance":distance})
	var result:Dictionary=Generator._sample(plan,noise,x,z,false,roads[id])
	return {"x":x,"z":z,"known":true,"region":id,"authority_y":world.surface_height(x,z),"sample_y":result.height,"material":result.material,"natural_float":Relief._base(noise,x,z),"grid_y":heights,"road_grade_y":Generator._road_grade(plan,noise,x,z),"active_landforms":active_lands,"active_pads":active_pads}
func ray_hit(world:RefCounted,camera:Dictionary,pixel:Vector2)->Dictionary:
	var basis:=Basis.from_euler(vector(camera.rotation_xyz));var center:Vector3=vector(camera.position_xyz)
	var size:float=camera.size;var width:=1280.0;var height:=800.0
	var origin:Vector3=center+basis.x*((pixel.x/width-0.5)*size*width/height)+basis.y*((0.5-pixel.y/height)*size)
	var direction:Vector3=-basis.z
	var a:Vector3=origin+direction*((19.999-origin.y)/direction.y);var b:Vector3=origin+direction*((-3.999-origin.y)/direction.y)
	var hit:Dictionary=Queries.pick(world,a,b)
	if not hit.is_empty() and hit.get("normal") is Vector3:
		hit.position=xyz(a+direction*float(hit.distance));hit.normal=xyz(hit.normal)
	return hit
func locate(world:RefCounted,seed:int,view:String,root_path:String,targets:Array)->void:
	var folder:String=root_path+"/seed%d-local-relief-v7-"%seed+view
	var metadata:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"/results.json"));var actual:Dictionary=metadata.frames[0].state
	check("ROI uses actual frame camera and original saved identity "+str(seed)+view,actual.camera.size==24 and Data.json_equal(actual.viewport,[1280,800]) and actual.world_revision==2 and actual.world.worldId==world.identity().worldId,{"actual":{"size":actual.camera.size,"viewport":actual.viewport,"world_revision":actual.world_revision,"worldId":actual.world.worldId},"expected":{"size":24,"viewport":[1280,800],"world_revision":2,"worldId":world.identity().worldId},"viewport_element_types":[typeof(actual.viewport[0]),typeof(1280)]})
	for target:Array in targets:
		var picked:Dictionary={};var pixel:=Vector2(target[0],target[1])
		for dz:int in [0,-2,2,-5,5,-9,9]:
			for dx:int in [0,-2,2,-5,5,-9,9]:
				var hit:Dictionary=ray_hit(world,actual.camera,pixel+Vector2(dx,dz))
				if not hit.get("unknown",true) and hit.get("normal",[0,1,0])[1]==0:
					picked={"pixel":[pixel.x+dx,pixel.y+dz],"hit":hit};break
			if not picked.is_empty():break
		if picked.is_empty():rows.append({"seed":seed,"view":view,"requested_pixel":target,"side_face_found":false});continue
		var cell:Dictionary=picked.hit.cell;var normal:Vector3=vector(picked.hit.normal);var center:=Vector3((cell.x+0.5)*0.5,0,(cell.z+0.5)*0.5)
		var left:Dictionary=sample(world,center.x,center.z);var right:Dictionary=sample(world,center.x+normal.x*0.5,center.z+normal.z*0.5);var differences:Dictionary={}
		if left.known and right.known:
			differences.authority=float(right.authority_y)-float(left.authority_y)
			for mode:String in left.grid_y:differences[mode]=float(right.grid_y[mode])-float(left.grid_y[mode])
		var profile:Array=[]
		for i in range(-12,14):profile.append(sample(world,center.x+normal.x*i*0.5,center.z+normal.z*i*0.5))
		rows.append({"seed":seed,"view":view,"requested_pixel":target,"side_face_found":true,"source_frame":folder+"/T0.png","picked":picked,"solid_side":left,"outward_side":right,"cross_step_m":differences,"normal_profile_half_metre":profile})
func run()->void:
	var args:=OS.get_cmdline_user_args()
	for index in 2:
		var seed:int=[12,713][index];var path:String=args[index+1];var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(path));check("actual original v7 capture decodes "+str(seed),decoded.ok)
		if not decoded.ok:continue
		var original:Dictionary=decoded.capture.world;var before:PackedByteArray=var_to_bytes(original);var world:=State.new();check("read-only authority accepts v7 cells "+str(seed),world.load_snapshot(original).ok)
		grids.clear();plans.clear();noises.clear();roads.clear();prepare_grids(world)
		locate(world,seed,"field-forest",args[3],[[516,408],[579,367],[646,308],[765,340],[849,263],[477,540],[970,429]])
		locate(world,seed,"village",args[3],[[715,646],[839,653],[1057,720],[130,568]])
		check("ROI reconstruction does not edit saved authority "+str(seed),before==var_to_bytes(original) and world.get_revision()==1)
	rows.append({"pad_evidence":pad_evidence})
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"details":{"scope":"Actual-PNG pixel to authoritative terrain DDA and detached identical-algorithm control ablations. Nonterrain occluders ignored. No new render, playable ablation, app/import/export, old matrix, default/VA or performance qualification.","rows":rows}},"\t",true,true)+"\n")
	print(JSON.stringify({"checks":checks.size(),"failed":failed,"localized":rows.filter(func(r:Dictionary)->bool:return r.get("side_face_found",false)).size()}));quit(1 if failed else 0)
