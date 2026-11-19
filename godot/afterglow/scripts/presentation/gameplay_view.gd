extends Node3D
## A device on one real workbench, with state derived from the same authority.
## poi_relay.glb is a full shelter/antenna POI: retain it for that use, never
## shrink it into a tabletop radio. No suitable standalone device GLB exists.
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const Surfaces=preload("res://scripts/presentation/held_tool_view.gd")
const Village=preload("res://scripts/runtime/village_progression.gd")
const PANEL_PATH="res://data/gameplay/radio-panel.png"
# Source city_workbench tabletop is 1.02m; version-1 authority top is 1m.
# Its 1.845m rear rack is not a tabletop. This is a visual skin offset only.
const WORKBENCH_TOP_SKIN:float=0.02
var runtime:RefCounted
var _spatial:WeakRef
var _radio:Node3D
var _panel:StandardMaterial3D
var _led:StandardMaterial3D
var _station_id:=""
var _delay:=0.0
var _bound_world:int=0
func configure(value:RefCounted,spatial:RefCounted=null) -> void:
	var world_id:int=value.world.get_instance_id() if value!=null and value.world!=null else 0
	if runtime!=value or _bound_world!=world_id:_retire_device()
	runtime=value
	_bound_world=world_id
	_spatial=weakref(spatial) if spatial!=null else null
	_delay=0.0
	if _radio!=null:_radio.visible=false
func _retire_device()->void:
	if is_instance_valid(_radio):
		remove_child(_radio);_radio.queue_free()
	_radio=null;_panel=null;_led=null;_station_id=""
func _can_observe(entity:Dictionary,actor:Dictionary)->bool:
	var service:RefCounted=_spatial.get_ref() if _spatial!=null else null
	if service==null or actor.is_empty():return false
	var piece:Dictionary=service.instance(str(entity.id))
	if piece.is_empty():return false
	var from:Dictionary=Geometry.location(actor)
	var target:Dictionary=Geometry.location(piece)
	if target.buildingId!=null and (target.buildingId!=from.buildingId or target.storeyId!=from.storeyId):return false
	# B sight owns real partition/residency/opaque boundaries. A region label
	# is not a wall, and this consumer does not replace sight with hand reach.
	# line_clear takes feet locations and supplies its eye height exactly once.
	return service.current_space().line_clear(from,target,str(entity.id))
func _process(dt:float) -> void:
	var measured:int=preload("res://scripts/runtime/frame_costs.gd").begin()
	_profiled_process(dt)
	preload("res://scripts/runtime/frame_costs.gd").end("presentation/gameplay_view.gd",measured)

func _profiled_process(dt:float) -> void:
	if runtime!=null and runtime.world.get_instance_id()!=_bound_world:
		configure(runtime,_spatial.get_ref() if _spatial!=null else null)
	_delay-=dt
	if _delay>0 or runtime==null:return
	_delay=0.2
	var fields:Array[String]=["radio","defense"]
	var state:Variant=runtime.world.extension_fields("r33:gameplay",fields) if runtime.world.has_method("extension_fields") else runtime.world.extension("r33:gameplay")
	if not state is Dictionary:
		_retire_device()
		return
	var id:String=str(state.get("radio",{}).get("station_id",""))
	# The old village starts with a visibly broken device, before any repair
	# command has reserved the station. Its location is the actual handwork port.
	if id.is_empty():
		var layout_fields:Array[String]=["layout"]
		var opening:Variant=runtime.world.extension_fields("r34:gameplay",layout_fields) if runtime.world.has_method("extension_fields") else runtime.world.extension("r34:gameplay")
		if opening is Dictionary and Village.enabled(opening.get("layout",{})):id=Village.radio_station(runtime.world)
	if id.is_empty() and state.get("defense",{}).get("status")=="cleared":
		for candidate:Dictionary in runtime.world.entities("RH-HOME"):
			if candidate.get("definitionId")=="workbench":id=candidate.id;break
	var entity:Dictionary=runtime.world.entity(id) if not id.is_empty() else {}
	# A restored station reference must still identify a live, real workbench.
	if entity.get("definitionId")!="workbench" or float(entity.get("data",{}).get("structure",{}).get("hp",0))<=0:
		_retire_device()
		return
	var service:RefCounted=_spatial.get_ref() if _spatial!=null else null
	var piece:Dictionary=service.instance(id) if service!=null else {}
	var definition:Dictionary=service.geometry.definition(piece) if not piece.is_empty() else {}
	if definition.is_empty():
		_retire_device()
		return
	if _radio==null:_create()
	_station_id=id;_radio.visible=_can_observe(entity,runtime.actor("player"))
	var top:float=0.0
	for solid:Dictionary in definition.get("solids",[]):top=maxf(top,float(solid.max.y))
	_radio.position=Geometry.transform(Vector3(0,top+WORKBENCH_TOP_SKIN,0),piece)
	var approach:Vector3=Geometry.point(definition.usePoints[0])
	approach=Geometry.rotate(approach,int(piece.get("quarterTurn",0)))
	_radio.rotation.y=atan2(approach.x,approach.z)
	_radio.set_meta("world_entity_id",id)
	var status:String=str(state.get("radio",{}).get("status","unrepaired"))
	var actor:Dictionary=runtime.actor("player")
	var operation:String=str(actor.get("intent",{}).get("operation","")) if actor.get("intent") is Dictionary and actor.intent.get("owner")=="gameplay" else ""
	var cell:int=3 if status=="connected" else 2 if operation=="transmit" else 1 if status=="repaired" else 0
	if _panel.albedo_texture!=null:_panel.uv1_offset=Vector3((cell*256+8)/1024.0,8/256.0,0)
	var color:Color=[Color("3e4547"),Color("cf9a4d"),Color("68c7be"),Color("80bd78")][cell]
	_led.albedo_color=color;_led.emission=color;_led.emission_enabled=cell>0
	_led.emission_energy_multiplier=0.6+0.25*sin(runtime.clock()*9.0) if cell==2 else 0.55
	_radio.set_meta("radio_state",status);_radio.set_meta("panel_cell",cell)
func _create()->void:
	_radio=Node3D.new();_radio.name="WorkbenchRadio";add_child(_radio)
	Surfaces.box(_radio,Vector3(0,0.16,0),Vector3(0.52,0.32,0.26),"metal")
	var dark:=StandardMaterial3D.new();dark.albedo_color=Color("303b3d");dark.roughness=0.84
	var bezel:=Surfaces.box(_radio,Vector3(-0.075,0.18,0.134),Vector3(0.27,0.19,0.012),"metal");bezel.material_override=dark
	var face:=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2(0.24,0.16);face.mesh=quad
	_panel=StandardMaterial3D.new();_panel.roughness=0.8
	if ResourceLoader.exists(PANEL_PATH):
		_panel.albedo_texture=load(PANEL_PATH);_panel.uv1_scale=Vector3(240/1024.0,240/256.0,1)
		_panel.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS;_panel.texture_repeat=false
	else:_panel.albedo_color=Color("65706a")
	face.material_override=_panel;face.position=Vector3(-0.075,0.18,0.142);_radio.add_child(face)
	for y:float in [0.12,0.24]:
		var knob:=MeshInstance3D.new();var cylinder:=CylinderMesh.new();cylinder.top_radius=0.026;cylinder.bottom_radius=0.026;cylinder.height=0.027;cylinder.radial_segments=8
		knob.mesh=cylinder;knob.material_override=dark;knob.rotation.x=PI/2;knob.position=Vector3(0.17,y,0.145);_radio.add_child(knob)
	_led=StandardMaterial3D.new();var led:=Surfaces.box(_radio,Vector3(0.17,0.29,0.14),Vector3(0.018,0.018,0.01),"metal");led.material_override=_led
	Surfaces.box(_radio,Vector3(-0.2,0.6,-0.08),Vector3(0.012,0.58,0.012),"metal")
	var handle:=Surfaces.box(_radio,Vector3(0,0.36,0),Vector3(0.25,0.025,0.04),"metal");handle.material_override=dark
func statistics()->Dictionary:
	return {"station_id":_station_id,"radio_visible":_radio!=null and _radio.visible,"panel_registered":_panel!=null and _panel.albedo_texture!=null,"panel_cell":_radio.get_meta("panel_cell",-1) if _radio!=null else -1}
