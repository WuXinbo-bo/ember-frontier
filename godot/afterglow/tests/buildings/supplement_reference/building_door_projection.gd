extends RefCounted
## A single unchanged-positive-HP door may reuse STATIC indices of the same
## immutable world revision. Leaf/LOS, permissions and all movement proofs are
## fresh. Any other structure/storey/metadata change uses the full projection.
const Space=preload("res://tests/buildings/supplement_reference/building_space.gd")

static func changed_door(before:Dictionary,after:Dictionary)->Dictionary:
	var a:=before.duplicate(false);var b:=after.duplicate(false)
	a.erase("instances");b.erase("instances")
	if a!=b:return {}
	var old:Array=before.get("instances",[]);var next:Array=after.get("instances",[])
	if old.size()!=next.size():return {}
	var changed:Dictionary={}
	for i in old.size():
		if old[i]==next[i]:continue
		if not changed.is_empty() or not old[i].get("door") is Dictionary or not next[i].get("door") is Dictionary or float(old[i].get("hp",0))<=0:return {}
		var original:Dictionary=old[i].duplicate(false);var replacement:Dictionary=next[i].duplicate(false)
		for key:String in ["door","version"]:original.erase(key);replacement.erase(key)
		if original!=replacement:return {}
		changed=next[i]
	return changed

static func updated_index(index:Dictionary,region:String,id:String,value:Dictionary,wrapped:bool=false)->Dictionary:
	var result:=index.duplicate(false)
	if not result.has(region):return result
	var buckets:Dictionary=result[region].duplicate(false);result[region]=buckets
	for key in buckets:
		var values:Array=buckets[key];var copy:Array=[]
		for i in values.size():
			var piece:Dictionary=values[i].piece if wrapped else values[i]
			if piece.id!=id:continue
			if copy.is_empty():copy=values.duplicate(false)
			if wrapped:
				var entry:Dictionary=copy[i].duplicate(false);entry.piece=value;copy[i]=entry
			else:copy[i]=value
		if not copy.is_empty():buckets[key]=copy
	return result

static func project(base:RefCounted,data:Dictionary,updated:Dictionary,permission:Callable)->RefCounted:
	var child:=Space.new()
	child.world=base.world;child.geometry=base.geometry;child.permission=permission
	child.state=data.duplicate(true);child.pieces=child.state.instances
	# Derived from this exact draft; never carry a flight proof or an actor rule.
	child.stair_pieces=child.pieces.filter(func(v:Dictionary)->bool:return v.has("stairs"))
	child.agent=base.agent.duplicate(true)
	for name:String in ["cell_size","chunk_cells","min_cell_y","max_cell_y"]:child.set(name,base.get(name))
	var value:Dictionary={}
	for piece:Dictionary in child.pieces:
		if piece.id==updated.id:value=piece;break
	child.by_id=base.by_id.duplicate(false);child.by_id[value.id]=value
	child.piece_bounds=base.piece_bounds.duplicate(false)
	child.sight_boxes=base.sight_boxes.duplicate(false);child.sight_boxes[value.id]=child.geometry.boxes(value,"sight")
	child.solid_entities=base.solid_entities.duplicate(false);child.entity_buckets=base.entity_buckets.duplicate(false)
	child.surfaces=base.surfaces.duplicate(false)
	for i in child.surfaces.size():
		if child.surfaces[i].id==value.id:child.surfaces[i]=value
	child.piece_buckets=updated_index(base.piece_buckets,value.regionId,value.id,value)
	child.surface_buckets=updated_index(base.surface_buckets,value.regionId,value.id,value)
	child.walk_surfaces=updated_index(base.walk_surfaces,value.regionId,value.id,value,true)
	child.support_wall_index=updated_index(base.support_wall_index,value.regionId,value.id,value,true)
	child.support_slab_index=updated_index(base.support_slab_index,value.regionId,value.id,value,true)
	# Use original collider order/tokens, including its exact candidate ordering.
	# Rebuild only buckets touched by the old/new moving leaf or its frame.
	child.colliders=base.colliders.duplicate(false)
	var boxes:Array=child.geometry.boxes(value);var cursor:=0;var touched:Dictionary={}
	for i in child.colliders.size():
		var entry:Dictionary=child.colliders[i]
		if entry.instance.id!=value.id:continue
		var box:AABB=boxes[cursor];cursor+=1
		for volume:AABB in [entry.bounds,box]:
			for x in range(floori(volume.position.x/2),floori(volume.end.x/2)+1):
				for z in range(floori(volume.position.z/2),floori(volume.end.z/2)+1):touched[Vector2i(x,z)]=true
		child.colliders[i]={"instance":value,"bounds":box,"token":entry.token}
	child.buckets=base.buckets.duplicate(false)
	var region:Dictionary=base.buckets.get(value.regionId,{}).duplicate(false);child.buckets[value.regionId]=region
	for key:Vector2i in touched:
		var entries:Array=[]
		for entry:Dictionary in child.colliders:
			if entry.instance.regionId!=value.regionId:continue
			var b:AABB=entry.bounds
			if key.x>=floori(b.position.x/2) and key.x<=floori(b.end.x/2) and key.y>=floori(b.position.z/2) and key.y<=floori(b.end.z/2):entries.append(entry)
		if entries.is_empty():region.erase(key)
		else:region[key]=entries
	# Only geometry-independent terrain/support evidence is reusable. HP,
	# topology and world revision were proved equal above; no route, actor,
	# door sweep, LOS, body-blocker or stair-clear result is carried forward.
	for name:String in ["chunk_cache","cell_cache","terrain_cache","voxel_clear_cache","ground_cache","support_cache","support_roots","support_witnesses"]:
		child.set(name,base.get(name).duplicate(false))
	return child
