extends "res://tests/world/fixtures/environment_before_refresh_followup.gd"
## Attribution-only timers; never used as before/after performance baseline.
var phase:Dictionary={"ground_usec":0,"ground_calls":0,"tree_usec":0,"tree_calls":0,"ecology_usec":0}
func reset_profile()->void:
	phase={"ground_usec":0,"ground_calls":0,"tree_usec":0,"tree_calls":0,"ecology_usec":0}
func _grounded(p:Vector3,size:Vector2,material:int=-1)->bool:
	var start:int=Time.get_ticks_usec();var result:bool=super._grounded(p,size,material)
	phase.ground_usec+=Time.get_ticks_usec()-start;phase.ground_calls+=1;return result
func _sync_tree(e:Dictionary)->void:
	var start:int=Time.get_ticks_usec();super._sync_tree(e)
	phase.tree_usec+=Time.get_ticks_usec()-start;phase.tree_calls+=1
func _sync_ecology(entities:Array,chunks:Array,force:bool)->void:
	var start:int=Time.get_ticks_usec();super._sync_ecology(entities,chunks,force)
	phase.ecology_usec+=Time.get_ticks_usec()-start
