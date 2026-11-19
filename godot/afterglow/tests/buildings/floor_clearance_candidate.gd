extends "res://tests/buildings/floor_reference/building_space.gd"
## Test-only candidate: prove an entire immutable floor's thin terrain strip
## clear, otherwise retain the exact original per-foot rectangle predicate.
var floor_clearances:Dictionary={}
var clearance_attempts:=0
var clearance_hits:=0
var clearance_fallbacks:=0

func floor_terrain_clear(region:String,surface:Dictionary,volume:AABB)->bool:
	var id:String=surface.piece.id
	if not floor_clearances.has(id):
		if floor_clearances.size()>=8192:floor_clearances.clear()
		var bounds:AABB=surface.bounds
		var strip:=AABB(Vector3(bounds.position.x-0.02,float(surface.elevation)+0.01,bounds.position.z-0.02),Vector3(bounds.size.x+0.04,0.01,bounds.size.z+0.04))
		clearance_attempts+=1
		floor_clearances[id]={"volume":strip,"clear":terrain_clear(region,strip)}
	var proof:Dictionary=floor_clearances[id]
	# Native enclosure guards float precision and the unchanged 1mm floor edge
	# tolerance; only an actually clear SUPERSET can replace the original test.
	if proof.clear and (proof.volume as AABB).encloses(volume):
		clearance_hits+=1
		return true
	clearance_fallbacks+=1
	return terrain_clear(region,volume)

func floor_sample(region:String,x:float,z:float,reference_y:float)->Dictionary:
	for surface:Dictionary in walk_surfaces.get(region,{}).get(Vector2i(floori(x/2),floori(z/2)),[]):
		if absf(float(surface.elevation)-reference_y)>agent.max_step:continue
		var v:Dictionary=surface.piece
		var b:AABB=surface.bounds
		if x>=b.position.x-0.001 and x<=b.end.x+0.001 and z>=b.position.z-0.001 and z<=b.end.z+0.001:
			if floor_terrain_clear(region,surface,AABB(Vector3(x-0.01,v.position.y+0.01,z-0.01),Vector3(0.02,0.01,0.02))):return surface
	var k:Array=[region,floori(x/cell_size),floori(z/cell_size)]
	if not ground_cache.has(k):ground_cache[k]=ground_height(x,z)
	var ground:Variant=ground_cache[k]
	if ground==null or absf(float(ground)-reference_y)>agent.max_step:return {}
	return {"elevation":float(ground),"piece":{}}
