extends RefCounted
## Presentation only. Existing HP and completed orders are the sole damage /
## repair facts; no added condition field, clock, inventory or random damage.
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const MeshBuilder=preload("res://scripts/buildings/building_mesh.gd")
const FAMILIES={"old_brick":"brick","cream_plaster":"plaster","wood_floor":"wood","plywood":"wood","roof_tile":"roof","zinc":"zinc","mint_paint":"paint"}

static func history(service:RefCounted)->Dictionary:
	var result:Dictionary={}
	var state:Variant=service.context.world.extension("r3:structure-orders")
	for order:Dictionary in state.get("orders",[]) if state is Dictionary else []:
		if order.get("status")!="completed" or order.get("kind") not in ["repair","place"]:continue
		var id:String=order.targetId
		if not result.has(id):result[id]={}
		result[id][order.kind]=true
	return result

static func condition(piece:Dictionary,maximum:float,orders:Dictionary)->String:
	if float(piece.get("hp",0))<maximum:return "damaged"
	if orders.get(piece.id,{}).get("repair",false):return "repaired"
	return baseline(piece,orders)

static func baseline(piece:Dictionary,orders:Dictionary)->String:
	if orders.get(piece.id,{}).get("place",false):return "intact"
	var finish:Dictionary=piece.get("presentation",{})
	var explicit:String=str(finish.get("condition",""))
	if explicit in ["intact","aged"]:return explicit
	# The original rural houses/profiles are authored weathered buildings.
	# This selects patina only and never implies reduced HP or past repair.
	return "aged" if finish.has("profile_id") or str(piece.get("buildingId","")).begins_with("rural:v1:") else "intact"

static func id_for(base:String,state:String)->String:
	return "b_"+str(FAMILIES[base])+"_"+state if FAMILIES.has(base) else base

static func baseline_material(view:Node3D,piece:Dictionary,base:String,orders:Dictionary)->String:
	var id:=id_for(base,baseline(piece,orders))
	view.material(id)
	return id

static func detail_quad(builder:RefCounted,part:AABB,transform:Transform3D,id:String,extent:Vector2,top:bool)->void:
	# Crop the declared full-canvas UV onto each real solid. In particular a
	# window/door aperture or stepped roof never gets bridged by a decal plane.
	var middle:Vector3=part.get_center()
	var low:Vector2;var high:Vector2;var origin:Vector2
	if top:
		origin=Vector2(middle.x,middle.z)-extent/2
		low=Vector2(maxf(part.position.x,origin.x),maxf(part.position.z,origin.y))
		high=Vector2(minf(part.end.x,origin.x+extent.x),minf(part.end.z,origin.y+extent.y))
	else:
		origin=Vector2(middle.x,middle.y)-extent/2
		low=Vector2(maxf(part.position.x,origin.x),maxf(part.position.y,origin.y))
		high=Vector2(minf(part.end.x,origin.x+extent.x),minf(part.end.y,origin.y+extent.y))
	if high.x<=low.x or high.y<=low.y:return
	var uv:=Rect2((low-origin)/extent,(high-low)/extent)
	if top:
		var y:=part.end.y+0.002
		builder.quad([Vector3(low.x,y,low.y),Vector3(high.x,y,low.y),Vector3(high.x,y,high.y),Vector3(low.x,y,high.y)],Vector3.UP,transform,id,-1,uv)
	else:
		for side:float in [-1.0,1.0]:
			var z:float=(part.end.z if side>0 else part.position.z)+side*0.002
			builder.quad([Vector3(low.x,low.y,z),Vector3(high.x,low.y,z),Vector3(high.x,high.y,z),Vector3(low.x,high.y,z)],Vector3(0,0,side),transform,id,-1,uv)

static func add_details(view:Node3D,root:Node3D,orders:Dictionary,region_ids:Array=[])->void:
	for piece:Dictionary in view.service.structures().instances:
		if not region_ids.is_empty() and not region_ids.has(str(piece.regionId)):continue
		if float(piece.hp)<=0:continue
		var definition:Dictionary=view.service.geometry.definition(piece)
		if definition.kind in ["door","cabinet","workbench","stairs"]:continue
		var base:String=view.original_surface(piece,definition)
		if not FAMILIES.has(base):continue
		var state:=condition(piece,float(definition.maxHp),orders)
		if state not in ["damaged","repaired"]:continue
		var material_id:=id_for(base,state)
		var decal_id:="b_"+str(FAMILIES[base])+ ("_damage_detail" if state=="damaged" else "_repair_detail")
		view.material(material_id);view.material(decal_id)
		var builder:=MeshBuilder.new();var transform:Transform3D=view.xform(piece)
		var top:bool=definition.kind in ["roof","floor","foundation"]
		var largest:=AABB();var area:float=-1
		for raw:Dictionary in definition.solids:
			var part:=Geometry.aabb(raw)
			if top:
				# Roof underside/edge stays timber. Only its real upper surfaces
				# get tile/zinc state; floor keeps the original 12mm visual skin.
				var y:=part.end.y+(0.012 if definition.kind!="roof" else 0.0)+0.001
				builder.quad([Vector3(part.position.x,y,part.position.z),Vector3(part.end.x,y,part.position.z),Vector3(part.end.x,y,part.end.z),Vector3(part.position.x,y,part.end.z)],Vector3.UP,transform,material_id,-1,Rect2(Vector2.ZERO,Vector2(part.size.x,part.size.z)/float(view.manifest.textures[material_id].tile_meters)))
				part.position.y=y-part.size.y
			else:builder.box(part.grow(0.001),transform,material_id,float(view.manifest.textures[material_id].tile_meters))
			var candidate:float=part.size.x*(part.size.z if top else part.size.y)
			if candidate>area:largest=part;area=candidate
		if area<=0:continue
		var physical:Array=view.manifest.textures[decal_id].uv.meters_xy
		detail_quad(builder,largest,transform,decal_id,Vector2(physical[0],physical[1]),top)
		var node:=MeshInstance3D.new();node.mesh=builder.mesh(view.materials);node.set_meta("piece",piece);node.set_meta("state",state);node.set_meta("state_material",material_id);node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for key:String in view.static_nodes:
			var host:MeshInstance3D=view.static_nodes[key]
			if piece.id in host.get_meta("piece_ids",[]):node.set_meta("state_batch",key);break
		if not node.has_meta("state_batch"):node.free();continue
		root.add_child(node)
