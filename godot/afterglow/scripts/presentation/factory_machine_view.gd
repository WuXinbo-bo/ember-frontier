extends Node3D
## Moving subassembly at B's world anchor. Never a second machine/producer.
const Surfaces=preload("res://scripts/presentation/held_tool_view.gd")
const Stock=preload("res://scripts/presentation/factory_stock_view.gd")
var _blade:MeshInstance3D
var _crank:Node3D
var _chips:Array[MeshInstance3D]=[]
var _active:=false
var _progress:=0.0
var _phase:=""
var _issue:=""
var _kind:=""

func update(row:Dictionary)->bool:
	var kind:String=str(row.get("kind",""))
	if kind not in ["saw","reciprocating_saw"]:return _reject("MECHANISM_NOT_BOUND")
	for key:String in ["progress_seconds","duration_seconds","effective_work"]:
		if not Stock._number(row.get(key)):return _reject("MECHANISM_PROGRESS_REQUIRED")
	if float(row.duration_seconds)<=0 or float(row.progress_seconds)<0 or float(row.effective_work)<0:return _reject("INVALID_MECHANISM_PROGRESS")
	if _blade==null:_create()
	_kind=kind;_phase=str(row.get("phase",""))
	_progress=float(row.progress_seconds)
	_active=bool(row.get("active",false)) and float(row.effective_work)>0 and str(row.get("paused_reason","")).is_empty()
	# Actual batch effective seconds, never delta/wall-clock fake work.
	var angle:float=_progress*TAU*1.8
	_blade.position.x=sin(angle)*0.11
	_crank.rotation.z=angle
	for i:int in _chips.size():
		_chips[i].visible=_active
		_chips[i].position=Vector3(0.10+0.035*i,-0.07-fposmod(_progress*0.35+float(i)*0.07,0.2),0.04*(i%2))
	visible=true;_issue=""
	return true

func _reject(code:String)->bool:
	visible=false;_active=false;_issue=code
	return false

func hide_projection()->void:
	visible=false;_active=false

func _create()->void:
	# G0 candidate: contact origin is blade tooth line; moving part stays within
	# 0.72x0.40x0.30m. B owns fixed bed, guards, engine, foundation and buffers.
	_blade=Surfaces.box(self,Vector3.ZERO,Vector3(0.48,0.045,0.018),"metal")
	_crank=Node3D.new();_crank.position=Vector3(0,-0.14,-0.1);add_child(_crank)
	Surfaces.box(_crank,Vector3.ZERO,Vector3(0.28,0.035,0.035),"metal")
	for i:int in 3:
		var chip:MeshInstance3D=Surfaces.box(self,Vector3.ZERO,Vector3(0.012,0.008,0.018),"wood")
		_chips.append(chip)

func statistics()->Dictionary:
	return {"kind":_kind,"active":_active and visible,"progress_seconds":_progress,"phase":_phase,"issue":_issue,"owned_fixed_shell":false,"effective_clock_only":true}
