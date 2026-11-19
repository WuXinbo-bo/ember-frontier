extends Node3D
## Disposable render batches. No collision, input, world query or simulation.
var _chunks:Dictionary={}
var _signatures:Dictionary={}
var rebuilds:int=0

static func number(value:Variant)->bool:
	return (value is int or value is float) and is_finite(float(value))

static func cell(value:Variant)->bool:
	if not value is Dictionary:return false
	for axis:String in ["x","y","z"]:
		if not number(value.get(axis)) or float(value[axis])!=floor(float(value[axis])):return false
	return true

static func point(value:Variant)->bool:
	return value is Dictionary and number(value.get("x")) and number(value.get("y")) and number(value.get("z"))

static func chunk_key(region:String,p:Vector3)->String:
	return region+":"+str(floori(p.x/8.0))+":"+str(floori(p.z/8.0))

func clear()->void:
	for key:String in _chunks.keys():_retire(key)

func _retire(key:String)->void:
	var node:Node3D=_chunks.get(key)
	if is_instance_valid(node):remove_child(node);node.queue_free()
	_chunks.erase(key);_signatures.erase(key)

func apply(groups:Dictionary)->void:
	for key:String in _chunks.keys():
		if not groups.has(key):_retire(key)
	for key:String in groups:
		var group:Dictionary=groups[key]
		var signature:String=var_to_str(group.signature)
		if _signatures.get(key)==signature:continue
		_retire(key)
		var root:=Node3D.new();root.name="RegionalBatch";root.position=group.origin;add_child(root)
		for part_key:String in group.parts:
			var part:Dictionary=group.parts[part_key]
			if part.transforms.is_empty():continue
			var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D
			mm.mesh=part.mesh;mm.instance_count=part.transforms.size()
			var bounds:=AABB();var first:bool=true
			for i:int in part.transforms.size():
				mm.set_instance_transform(i,part.transforms[i])
				var box:AABB=part.transforms[i]*part.mesh.get_aabb()
				bounds=box if first else bounds.merge(box);first=false
			mm.custom_aabb=bounds
			var node:=MultiMeshInstance3D.new();node.multimesh=mm
			# Also retain the small submitted bound for headless diagnostics.
			# Dummy RenderingServer does not read instance transforms back.
			node.set_meta("submitted_bounds",bounds)
			node.cast_shadow=part.get("shadow",GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
			root.add_child(node)
		_chunks[key]=root;_signatures[key]=signature;rebuilds+=1

static func append(groups:Dictionary,key:String,origin:Vector3,part_key:String,mesh:Mesh,transform:Transform3D,signature:Variant,shadow:int=GeometryInstance3D.SHADOW_CASTING_SETTING_ON)->void:
	if mesh==null:return
	if not groups.has(key):groups[key]={"origin":origin,"signature":[],"parts":{}}
	var group:Dictionary=groups[key]
	group.signature.append(signature)
	if not group.parts.has(part_key):group.parts[part_key]={"mesh":mesh,"transforms":[],"shadow":shadow}
	var local:Transform3D=transform;local.origin-=origin
	group.parts[part_key].transforms.append(local)

func statistics()->Dictionary:
	var instances:int=0;var batches:int=0
	for node:Node3D in _chunks.values():
		for child:MultiMeshInstance3D in node.get_children():
			instances+=child.multimesh.instance_count;batches+=1
	return {"chunks":_chunks.size(),"batches":batches,"instances":instances,"rebuilds":rebuilds,"collision":false}
