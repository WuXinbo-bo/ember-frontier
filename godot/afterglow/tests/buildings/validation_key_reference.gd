extends "res://scripts/buildings/building_service.gd"
const PreviousDoorProjection=preload("res://scripts/buildings/building_door_projection.gd")
## Exact prior identity check, before replacing whole-state JSON serialization
## with native Dictionary equality. Both variants use the same spatial rules.
func validation_space(view:RefCounted,data:Dictionary,staged:Dictionary)->RefCounted:
	if view!=context.world:return space(view,data,staged)
	var key:=str(view.get_instance_id())+":"+str(view.get_revision())+":"+JSON.stringify(data,"",true,true)
	if _validation_space==null or key!=_validation_key:
		var base:RefCounted=_space if _space!=null and _space_world==view and _space_revision==view.get_revision() else null
		var door:Dictionary=PreviousDoorProjection.changed_door(base.state,data) if base!=null else {}
		if not door.is_empty():
			var owner_ref:WeakRef=weakref(self)
			var can_open:Callable=func(a:String,t:String,k:String,p:Dictionary)->Variant:return owner_ref.get_ref().permission(a,t,k,p,staged) if owner_ref.get_ref()!=null else "运行时已关闭"
			_validation_space=PreviousDoorProjection.project(base,data,door,can_open)
		else:_validation_space=space(view,data,staged)
		_validation_key=key
	else:
		var owner_ref:WeakRef=weakref(self)
		_validation_space.permission=func(a:String,t:String,k:String,p:Dictionary)->Variant:return owner_ref.get_ref().permission(a,t,k,p,staged) if owner_ref.get_ref()!=null else "运行时已关闭"
	return _validation_space
