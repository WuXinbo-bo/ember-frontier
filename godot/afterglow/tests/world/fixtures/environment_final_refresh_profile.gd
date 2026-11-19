extends "res://tests/world/fixtures/environment_before_final_refresh.gd"
## Attribution only: inclusive timers intentionally excluded from comparison.
var phase:Dictionary={}
func reset_profile()->void:phase={"ground_usec":0,"ground_calls":0,"tree_usec":0,"tree_calls":0,"ecology_usec":0,"blocked_usec":0,"blocked_calls":0}
func _grounded(p:Vector3,size:Vector2,material:int=-1)->bool:
	var started:int=Time.get_ticks_usec();var result:bool=super._grounded(p,size,material)
	if not phase.is_empty():phase.ground_usec+=Time.get_ticks_usec()-started;phase.ground_calls+=1
	return result
func _sync_tree(e:Dictionary)->void:
	var started:int=Time.get_ticks_usec();super._sync_tree(e)
	if not phase.is_empty():phase.tree_usec+=Time.get_ticks_usec()-started;phase.tree_calls+=1
func _sync_ecology(entities:Array,chunks:Array,force:bool)->void:
	var started:int=Time.get_ticks_usec();super._sync_ecology(entities,chunks,force)
	if not phase.is_empty():phase.ecology_usec+=Time.get_ticks_usec()-started
func _ecology_blocked(bounds:Dictionary)->bool:
	var started:int=Time.get_ticks_usec();var result:bool=super._ecology_blocked(bounds)
	if not phase.is_empty():phase.blocked_usec+=Time.get_ticks_usec()-started;phase.blocked_calls+=1
	return result
