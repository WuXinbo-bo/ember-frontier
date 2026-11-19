extends Node
## A presentation-only silhouette. Never cuts undiscovered rooms or changes LOS.
## Native triangle queries use rendered geometry, including batch/door openings.
## B still owns cutaways; this cannot grant actor sight or action permissions.
var camera:Camera3D
var actors:Node3D
var buildings:Node3D
var environment:Node3D
var _meshes:Array[MeshInstance3D]=[]
var _watched:Dictionary={}
var _triangles:Dictionary={}
var _alpha_images:Dictionary={}
var _dirty:=true
var _delay:=0.0
var _blocked:=false
var _last_query_usec:=0
var _last_refresh_usec:=0
var _last_samples:=0
var _last_triangle_queries:=0
var _last_alpha_skips:=0
func configure(view_camera:Camera3D,actor_view:Node3D,building_view:Node3D,environment_view:Node3D=null)->void:
	_release_player()
	_clear_tracking()
	camera=view_camera;actors=actor_view;buildings=building_view;environment=environment_view
	_dirty=true;_delay=0.0;_blocked=false
func _release_player()->void:
	if is_instance_valid(actors) and actors.has_method("set_player_occluded"):actors.set_player_occluded(false)
func _clear_tracking()->void:
	for id:int in _watched:
		var node:Node=_watched[id].get_ref()
		if node==null:continue
		if node.child_entered_tree.is_connected(_mark_dirty):node.child_entered_tree.disconnect(_mark_dirty)
		if node.child_exiting_tree.is_connected(_mark_dirty):node.child_exiting_tree.disconnect(_mark_dirty)
	_watched.clear();_meshes.clear()
	for id:int in _triangles.keys():_discard_mesh(id)
	for id:int in _alpha_images.keys():_discard_texture(id)
func _exit_tree()->void:
	_release_player();_clear_tracking()
func _process(dt:float)->void:
	var measured:int=preload("res://scripts/runtime/frame_costs.gd").begin()
	_profiled_process(dt)
	preload("res://scripts/runtime/frame_costs.gd").end("presentation/player_occlusion.gd",measured)

func _profiled_process(dt:float)->void:
	_delay-=dt
	if not is_instance_valid(camera) or not is_instance_valid(actors) or not is_instance_valid(buildings):
		_release_player();_clear_tracking();_blocked=false;return
	if _delay>0:return
	_delay=0.1
	if _dirty:
		_refresh()
	var player:Node3D=actors.roots.get("player")
	if player==null:_release_player();_blocked=false;return
	var started:int=Time.get_ticks_usec()
	_last_samples=0;_last_triangle_queries=0;_last_alpha_skips=0
	var samples:Array=actors.player_occlusion_samples() if actors.has_method("player_occlusion_samples") else [{"position":player.global_position+Vector3(0,1.1,0),"grace":0.2},{"position":player.global_position+Vector3(0,1.65,0),"grace":0.2}]
	_blocked=_samples_covered(samples.slice(0,5))
	actors.set_player_occluded(_blocked)
	_last_query_usec=Time.get_ticks_usec()-started
func _collect(node:Node)->void:
	_watch(node)
	if node is MeshInstance3D:_meshes.append(node)
	for child:Node in node.get_children():_collect(child)
func _mark_dirty(_child:Node)->void:
	_dirty=true
func _refresh()->void:
	var started:int=Time.get_ticks_usec()
	_meshes.clear();_collect(buildings)
	if is_instance_valid(environment):
		_watch(environment)
		for tree:Node in environment.get_children():
			if not tree is Node3D or not tree.has_meta("world_entity_id"):continue
			_watch(tree)
			for child:Node in tree.get_children():
				# C's real model branch contains only standing tree/stump meshes.
				# Legacy boxes have no model parent; exclude its low ground dressing.
				if child.has_meta("existing_model"):_collect(child)
				elif child is MeshInstance3D and (tree.global_transform.affine_inverse()*child.global_transform*child.get_aabb()).end.y>0.65:_collect(child)
	_dirty=false
	# Retained furniture can replace nested meshes without changing root nodes.
	# Watch only this building view and retire caches with its actual resources.
	for id:int in _watched.keys():
		var node:Node=_watched[id].get_ref()
		if node!=null and (node==buildings or buildings.is_ancestor_of(node) or (is_instance_valid(environment) and (node==environment or environment.is_ancestor_of(node)))):continue
		if node!=null:
			node.child_entered_tree.disconnect(_mark_dirty)
			node.child_exiting_tree.disconnect(_mark_dirty)
		_watched.erase(id)
	var used:Dictionary={}
	for instance:MeshInstance3D in _meshes:
		if instance.mesh!=null:used[instance.mesh.get_instance_id()]=true
	for id:int in _triangles.keys():
		if not used.has(id):_discard_mesh(id)
	# Images are lazy hit-only data, retired at actual subtree changes.
	for id:int in _alpha_images.keys():_discard_texture(id)
	_last_refresh_usec=Time.get_ticks_usec()-started

func _watch(node:Node)->void:
	var id:int=node.get_instance_id()
	if _watched.has(id):return
	node.child_entered_tree.connect(_mark_dirty);node.child_exiting_tree.connect(_mark_dirty)
	_watched[id]=weakref(node)
func _discard_mesh(id:int)->void:
	var cached:Dictionary=_triangles.get(id,{})
	if cached.is_empty():return
	var source:Mesh=cached.source.get_ref()
	if source!=null:source.changed.disconnect(_discard_mesh.bind(id))
	_triangles.erase(id)
func _triangle_mesh(source:Mesh)->TriangleMesh:
	var id:int=source.get_instance_id()
	if not _triangles.has(id):
		_triangles[id]={"source":weakref(source),"shape":source.generate_triangle_mesh()}
		source.changed.connect(_discard_mesh.bind(id))
	return _triangles[id].shape
func _samples_covered(samples:Array)->bool:
	if samples.is_empty():return false
	var rays:Array=[]
	var bounds:AABB
	for sample:Dictionary in samples:
		var target:Vector3=sample.position
		var origin:=camera.project_ray_origin(camera.unproject_position(target))
		if rays.is_empty():bounds=AABB(origin,Vector3.ZERO)
		bounds=bounds.expand(origin).expand(target)
		rays.append({"origin":origin,"target":target,"grace":sample.grace})
	# Include boxes grazing an edge of the broad phase. Every candidate still
	# runs the same exact segment and triangle queries in the original order.
	bounds=bounds.grow(0.001)
	var candidates:Array=[]
	for instance:MeshInstance3D in _meshes:
		if not is_instance_valid(instance) or not instance.is_visible_in_tree() or instance.mesh==null:continue
		var transform:Transform3D=instance.global_transform
		var box:AABB=transform*instance.get_aabb()
		if bounds.intersects(box):candidates.append({"instance":instance,"transform":transform,"bounds":box})
	for ray:Dictionary in rays:
		_last_samples+=1
		if _covered_ray(ray.origin,ray.target,float(ray.grace),candidates):return true
	return false

func _covered(target:Vector3,grace:float=0.2)->bool:
	return _samples_covered([{"position":target,"grace":grace}])

func _covered_ray(origin:Vector3,target:Vector3,grace:float,candidates:Array)->bool:
	for entry:Dictionary in candidates:
		var box:AABB=entry.bounds
		if box.intersects_segment(origin,target)==null:continue
		var mesh:MeshInstance3D=entry.instance
		var transform:Transform3D=entry.transform
		# A door opening and gaps between batched walls do not occlude.
		var triangles:TriangleMesh=_triangle_mesh(mesh.mesh)
		if triangles==null or is_zero_approx(transform.basis.determinant()):continue
		var inverse:Transform3D=transform.affine_inverse()
		var from:Vector3=inverse*origin;var end:Vector3=inverse*target
		var step:Vector3=(end-from).normalized()*0.0001
		# Walk through cutout holes to a real opaque face behind them. Bound
		# native hits per sample/mesh; exhaustion fails open for presentation.
		for attempt:int in 16:
			_last_triangle_queries+=1
			var hit:Dictionary=triangles.intersect_segment(from,end)
			if hit.is_empty():break
			if (transform*hit.position).distance_to(target)<=grace:break
			if _opaque_hit(mesh,hit):return true
			_last_alpha_skips+=1
			from=Vector3(hit.position)+step
			if (end-from).dot(step)<=0:break
	return false

func _opaque_hit(instance:MeshInstance3D,hit:Dictionary)->bool:
	var source:Mesh=instance.mesh;var cached:Dictionary=_triangles[source.get_instance_id()]
	if not cached.has("surfaces"):
		var surfaces:Array=[];var first:int=0
		for i:int in source.get_surface_count():
			var arrays:Array=source.surface_get_arrays(i)
			var count:int=arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX]!=null and not arrays[Mesh.ARRAY_INDEX].is_empty() else arrays[Mesh.ARRAY_VERTEX].size()
			surfaces.append({"first":first,"count":count/3,"arrays":arrays,"surface":i});first+=count/3
		cached.surfaces=surfaces
	var face:int=int(hit.get("face_index",-1))
	for row:Dictionary in cached.surfaces:
		if face<row.first or face>=row.first+row.count:continue
		var material:Material=instance.get_active_material(row.surface)
		if not material is BaseMaterial3D:return true
		if material.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED:return true
		# Blended/hash surfaces have no stable opaque pixel-depth contract.
		if material.transparency not in [BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR,BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS]:return false
		var alpha:float=material.albedo_color.a
		if material.albedo_texture!=null:
			var arrays:Array=row.arrays;var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
			if uv.is_empty():return false
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			var first:int=(face-int(row.first))*3
			var a:int=indices[first] if not indices.is_empty() else first
			var b:int=indices[first+1] if not indices.is_empty() else first+1
			var c:int=indices[first+2] if not indices.is_empty() else first+2
			var v0:Vector3=vertices[b]-vertices[a];var v1:Vector3=vertices[c]-vertices[a];var v2:Vector3=Vector3(hit.position)-vertices[a]
			var divisor:float=v0.dot(v0)*v1.dot(v1)-v0.dot(v1)*v0.dot(v1)
			if absf(divisor)<0.000000000001:return false
			var y:float=(v1.dot(v1)*v2.dot(v0)-v0.dot(v1)*v2.dot(v1))/divisor
			var z:float=(v0.dot(v0)*v2.dot(v1)-v0.dot(v1)*v2.dot(v0))/divisor
			var point:Vector2=uv[a]*(1-y-z)+uv[b]*y+uv[c]*z
			point=point*Vector2(material.uv1_scale.x,material.uv1_scale.y)+Vector2(material.uv1_offset.x,material.uv1_offset.y)
			alpha*=_texture_alpha(material.albedo_texture,point,material.texture_repeat,material.texture_filter in [BaseMaterial3D.TEXTURE_FILTER_NEAREST,BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS])
		return alpha>=(material.alpha_scissor_threshold if material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else 0.99)
	return false

func _texture_alpha(texture:Texture2D,uv:Vector2,repeat:bool,nearest:bool)->float:
	var id:int=texture.get_instance_id()
	if not _alpha_images.has(id):
		var image:Image=texture.get_image()
		if image==null:return 0.0
		if image.is_compressed() and image.decompress()!=OK:return 0.0
		_alpha_images[id]={"source":weakref(texture),"image":image}
		texture.changed.connect(_discard_texture.bind(id))
	var image:Image=_alpha_images[id].image
	var x:float=uv.x*image.get_width()-0.5;var y:float=uv.y*image.get_height()-0.5
	if nearest:return _alpha_pixel(image,roundi(x),roundi(y),repeat)
	return lerpf(lerpf(_alpha_pixel(image,floori(x),floori(y),repeat),_alpha_pixel(image,floori(x)+1,floori(y),repeat),fposmod(x,1)),lerpf(_alpha_pixel(image,floori(x),floori(y)+1,repeat),_alpha_pixel(image,floori(x)+1,floori(y)+1,repeat),fposmod(x,1)),fposmod(y,1))

func _alpha_pixel(image:Image,x:int,y:int,repeat:bool)->float:
	return image.get_pixel(posmod(x,image.get_width()) if repeat else clampi(x,0,image.get_width()-1),posmod(y,image.get_height()) if repeat else clampi(y,0,image.get_height()-1)).a

func _discard_texture(id:int)->void:
	if not _alpha_images.has(id):return
	var source:Texture2D=_alpha_images[id].source.get_ref()
	if source!=null:source.changed.disconnect(_discard_texture.bind(id))
	_alpha_images.erase(id)

func statistics()->Dictionary:
	return {"player_occluded":_blocked,"occluder_meshes":_meshes.size(),"triangle_resources":_triangles.size(),"alpha_images":_alpha_images.size(),"query":"native-render-triangles","only_player":true,"authority_changes":false,"sample_limit":5,"query_hz":10,"last_samples":_last_samples,"last_query_usec":_last_query_usec,"last_refresh_usec":_last_refresh_usec,"last_triangle_queries":_last_triangle_queries,"last_alpha_skips":_last_alpha_skips,"alpha_scope":"base-level UV/filter/scissor; actual renderer mip/depth still requires normal-camera review"}
