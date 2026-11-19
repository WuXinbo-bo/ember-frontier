extends Node3D
## Public-project staging and local activity; no collision or finished capacity.
const Stock=preload("res://scripts/presentation/factory_stock_view.gd")
const Surfaces=preload("res://scripts/presentation/held_tool_view.gd")
static var _surfaces:Dictionary={}
var _work:Node3D
var _damage:MeshInstance3D
var _chips:Array[Node3D]=[]
var _site:Node3D
var _stage_parts:Array[Node3D]=[]
var _site_label:Label3D
var _facade:Node3D
var _project_id:=""
var _stage:=0
var _work_active:=false
var _work_progress:=0.0
var _damage_ratio:=0.0
var _issues:Dictionary={}

func update_construction(row:Dictionary,anchor:Transform3D,ground_anchor:Variant=null)->bool:
	_issues.erase("construction");_work_active=false;_stage=0
	if row.is_empty():
		if _work!=null:_work.visible=false
		if _site!=null:_site.visible=false
		_project_id="";_work_progress=0
		return true
	if not Stock._number(row.get("progress_seconds")) or not Stock._number(row.get("duration_seconds")) or float(row.duration_seconds)<=0 or float(row.progress_seconds)<0 or float(row.progress_seconds)>float(row.duration_seconds) or str(row.get("project_id","")).is_empty() or not row.get("active") is bool:
		return _reject("construction","CONSTRUCTION_PROGRESS_REQUIRED")
	if not anchor.is_finite():return _reject("construction","CONSTRUCTION_ANCHOR_REQUIRED")
	if _work==null:
		_work=Node3D.new();_work.name="LocalWorkChips";add_child(_work)
		for i:int in 3:
			_chips.append(Surfaces.box(_work,Vector3.ZERO,Vector3(0.07,0.02,0.09),"wood"))
	if _site==null:_create_site()
	var base:Transform3D=ground_anchor if ground_anchor is Transform3D else anchor
	if not base.is_finite():return _reject("construction","CONSTRUCTION_ANCHOR_REQUIRED")
	_project_id=str(row.project_id)
	_work_progress=float(row.progress_seconds)
	var phase:String=str(row.get("phase",""))
	var pending:bool=_work_progress<float(row.duration_seconds) and phase not in ["completed","cancelled"]
	_work_active=bool(row.active) and str(row.get("paused_reason","")).is_empty() and str(row.get("paused_code","")).is_empty() and phase not in ["paused","approaching"] and _work_progress>0 and pending
	_work.global_transform=anchor
	_work.visible=_work_active
	# Site equipment appears only after real labor has started. Approaching
	# workers still carry the reserved source goods; no delivered stock is faked.
	_site.global_transform=base
	_facade.global_transform=anchor
	var operation:String=str(row.get("operation",row.get("phase","")))
	_site.visible=pending and _work_progress>0 and operation in ["restore","repair","build","upgrade"]
	var ratio:float=clampf(_work_progress/float(row.duration_seconds),0,1)
	_stage=1+mini(2,floori(ratio*3)) if _site.visible else 0
	for part:Node3D in _stage_parts:part.visible=int(part.get_meta("work_stage",1))<=_stage
	_site_label.text=str({"restore":"修复","repair":"维修","build":"建造","upgrade":"升级"}.get(operation,"施工"))+" "+str(roundi(ratio*100))+"%"+(" · 施工中" if _work_active else " · 暂停")
	_site.set_meta("project_id",_project_id);_site.set_meta("progress_seconds",_work_progress)
	for i:int in _chips.size():
		var motion_phase:float=fposmod(_work_progress*0.8+float(i)*0.21,1.0)
		_chips[i].position=Vector3((float(i)-1.0)*0.16,0.08-motion_phase*0.3,motion_phase*0.22)
		_chips[i].rotation=Vector3(motion_phase*2.0,motion_phase*3.0,motion_phase)
	return true

func _site_piece(at:Vector3,size:Vector3,stage:int=1)->Node3D:
	var part:Node3D=Surfaces.box(_site,at,size,"wood")
	part.set_meta("work_stage",stage);_stage_parts.append(part)
	return part

func _create_site()->void:
	_site=Node3D.new();_site.name="TemporaryRepairStaging";add_child(_site)
	# A compact work rack beside the public entrance, never a replacement shell.
	for side:float in [-0.55,0.55]:
		_site_piece(Vector3(side,0.63,0.14),Vector3(0.09,1.26,0.09))
		_site_piece(Vector3(side,0.06,0.14),Vector3(0.28,0.12,0.56))
	_site_piece(Vector3(0,1.13,0.14),Vector3(1.36,0.12,0.1))
	for i:int in 3:_site_piece(Vector3(0,0.06+i*0.065,-0.2),Vector3(1.2,0.06,0.16))
	var brace:Node3D=_site_piece(Vector3(0,0.65,0.14),Vector3(1.42,0.075,0.09),2);brace.rotation.z=0.65
	_site_piece(Vector3(0,0.77,0.14),Vector3(1.22,0.16,0.1),2)
	_site_piece(Vector3(0,0.49,0.14),Vector3(1.22,0.16,0.1),3)
	_site_piece(Vector3(0,0.21,0.14),Vector3(1.22,0.16,0.1),3)
	_facade=Node3D.new();_facade.name="TemporaryWallPatches";_facade.top_level=true;_site.add_child(_facade)
	# Additive narrow repair battens beside the entrance, never across its
	# center or a finished wall/collision. Each band follows paid project work.
	for stage:int in [1,2,3]:
		var patch:Node3D=_site_piece(Vector3(1.25,0.1+float(stage-1)*0.25,-0.025),Vector3(0.7,0.15,0.045),stage)
		patch.reparent(_facade,false)
	_site_label=Label3D.new();_site_label.name="ActualRepairProgress";_site_label.position=Vector3(0,1.65,0)
	_site_label.font_size=32;_site_label.pixel_size=0.007;_site_label.outline_size=5
	_site_label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;_site.add_child(_site_label)

func update_damage(row:Dictionary,anchor:Transform3D,surface_id:String)->bool:
	_issues.erase("damage");_damage_ratio=0
	if _damage!=null:_damage.visible=false
	if row.is_empty():return true
	if not Stock._number(row.get("hp")) or not Stock._number(row.get("max_hp")) or float(row.max_hp)<=0 or float(row.hp)<0 or float(row.hp)>float(row.max_hp):return _reject("damage","DAMAGE_HP_REQUIRED")
	# B owns the ruined exterior; never put a second intact damage plate on it.
	if float(row.hp)==0 or row.get("state_code")=="ruined" or float(row.hp)==float(row.max_hp):return true
	if not anchor.is_finite():return _reject("damage","DAMAGE_SURFACE_ANCHOR_REQUIRED")
	var material:StandardMaterial3D=_surface(surface_id)
	if material==null:return _reject("damage","DAMAGE_SURFACE_NOT_BOUND")
	if _damage==null:
		_damage=MeshInstance3D.new();_damage.name="LocalDamageDetail"
		var mesh:=QuadMesh.new();mesh.size=Vector2.ONE*float(material.get_meta("tile_meters"))
		_damage.mesh=mesh;_damage.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(_damage)
	else:_damage.mesh.size=Vector2.ONE*float(material.get_meta("tile_meters"))
	_damage.material_override=material
	_damage_ratio=1.0-float(row.hp)/float(row.max_hp)
	# Keep physical texture scale; change alpha coverage without stretching grain.
	_damage.transparency=1.0-clampf(_damage_ratio*1.8,0.15,1.0)
	_damage.global_transform=anchor
	_damage.global_position+=anchor.basis.z.normalized()*0.006
	_damage.visible=true
	_damage.set_meta("hp",row.hp);_damage.set_meta("max_hp",row.max_hp)
	_damage.set_meta("surface_id",surface_id)
	return true

static func _surface(id:String)->StandardMaterial3D:
	if _surfaces.has(id):return _surfaces[id]
	# Explicit approved detail keys only; a full opaque wall texture is not a decal.
	if id not in ["b_wood_damage_detail","b_brick_damage_detail","b_plaster_damage_detail","b_roof_damage_detail","b_zinc_damage_detail","b_paint_damage_detail"]:return null
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/asset_manifest.json"))
	var definition:Dictionary=manifest.get("textures",{}).get(id,{})
	if definition.is_empty() or not Stock._number(definition.get("tile_meters")):return null
	var source:Texture2D=load(str(definition.resource))
	if source==null:return null
	var image:Image=source.get_image()
	if image==null:return null
	if image.is_compressed():image.decompress()
	if not image.has_mipmaps():image.generate_mipmaps()
	var material:=StandardMaterial3D.new();material.albedo_texture=ImageTexture.create_from_image(image)
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.texture_repeat=false;material.roughness=0.95
	material.set_meta("tile_meters",float(definition.tile_meters));material.set_meta("source_resource",str(definition.resource))
	_surfaces[id]=material
	return material

func _reject(kind:String,code:String)->bool:
	_issues[kind]=code
	if kind=="construction":
		if _work!=null:_work.visible=false
		if _site!=null:_site.visible=false
		_work_active=false;_stage=0
	if kind=="damage" and _damage!=null:_damage.visible=false
	return false

func hide_projection()->void:
	_work_active=false;_damage_ratio=0;_stage=0
	if _work!=null:_work.visible=false
	if _site!=null:_site.visible=false
	if _damage!=null:_damage.visible=false

func statistics()->Dictionary:
	return {"construction_active":_work_active,"progress_seconds":_work_progress,"project_id":_project_id,"construction_stage":_stage,"staging_visible":_site!=null and _site.visible,"damage_ratio":_damage_ratio,"damage_visible":_damage!=null and _damage.visible,"issues":_issues.duplicate(true),"owns_scaffold_or_ruin":false,"scope":"temporary project staging only; no physical shell, inventory or operational capacity"}
