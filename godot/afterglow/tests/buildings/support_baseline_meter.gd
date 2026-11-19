extends "res://scripts/buildings/building_service.gd"
var root_hits:=0
var root_misses:=0
func supported(query:RefCounted,v:Dictionary,visited:Dictionary={},terrain_proofs:Dictionary={}) -> bool:
	if visited.is_empty():
		if query.support_roots.has(v.id):root_hits+=1
		else:root_misses+=1
	return super.supported(query,v,visited,terrain_proofs)
func meters()->Dictionary:
	var result:Dictionary={"root_hits":root_hits,"root_misses":root_misses}
	root_hits=0;root_misses=0
	return result
