extends "res://scripts/environment/environment_materials.gd"
var loads:Array=[]
func material(id:String)->StandardMaterial3D:
	var cold:bool=not _cache.has(id);var start:=Time.get_ticks_usec()
	var result:=super.material(id)
	if cold:loads.append({"id":id,"usec":Time.get_ticks_usec()-start})
	return result
