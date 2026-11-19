extends RefCounted
## Existing textures only. Each detail is derived from its actual host/fact.
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const MeshBuilder=preload("res://scripts/buildings/building_mesh.gd")
const FLOOR_SKIN := 0.012

static func cabinet_joinery(builder:RefCounted,bounds:AABB,textures:Dictionary)->void:
	# Real existing cabinet: inset doors, framed edges, plinth and metal pulls.
	# All details stay WITHIN its authoritative volume; no new inventory/slots,
	# usable furniture, collision, animation or image assets are invented.
	var low:=bounds.position;var size:=bounds.size
	var w:=size.x;var h:=size.y;var d:=size.z
	var rows:Array=[
		[Vector3(0.04,0.09,0.008),Vector3(w-0.08,h-0.18,0.016),"mint_paint"],
		[Vector3(0.015,0.07,0.0),Vector3(0.055,h-0.09,0.035),"wood_floor"],
		[Vector3(w-0.07,0.07,0.0),Vector3(0.055,h-0.09,0.035),"wood_floor"],
		[Vector3(w/2-0.018,0.09,0.0),Vector3(0.036,h-0.18,0.035),"wood_floor"],
		[Vector3(0.015,h-0.075,0.0),Vector3(w-0.03,0.055,0.035),"wood_floor"],
		[Vector3(0.015,0.07,0.0),Vector3(w-0.03,0.06,0.035),"wood_floor"],
		[Vector3(0.0,h-0.045,0.0),Vector3(w,0.045,d),"wood_floor"],
		[Vector3(0.025,0.0,0.025),Vector3(w-0.05,0.075,d-0.05),"wood_floor"],
		[Vector3(w/2-0.105,h*0.49,0.0),Vector3(0.05,0.14,0.044),"painted_metal"],
		[Vector3(w/2+0.055,h*0.49,0.0),Vector3(0.05,0.14,0.044),"painted_metal"]]
	for row:Array in rows:
		builder.box(AABB(low+row[0],row[1]),Transform3D.IDENTITY,row[2],float(textures[row[2]].tile_meters))

static func wall_decal(builder:RefCounted,transform:Transform3D,material:String,center:Vector2,size:Vector2,side:float=1.0)->void:
	var x:=center.x-size.x/2;var y:=center.y-size.y/2;var z:=side*0.104
	builder.quad([Vector3(x,y,z),Vector3(x+size.x,y,z),Vector3(x+size.x,y+size.y,z),Vector3(x,y+size.y,z)],Vector3(0,0,side),transform,material)

static func ground_decal(builder:RefCounted,transform:Transform3D,material:String,center:Vector3,size:Vector2,cell:int=-1)->void:
	var x:=center.x-size.x/2;var z:=center.z-size.y/2
	# Keep threshold/wear/work-state decals above the derived floor skin.
	var y:=center.y+FLOOR_SKIN
	builder.quad([Vector3(x,y,z),Vector3(x+size.x,y,z),Vector3(x+size.x,y,z+size.y),Vector3(x,y,z+size.y)],Vector3.UP,transform,material,cell)

static func aged_wall(builder:RefCounted,v:Dictionary,transform:Transform3D,kind:String)->void:
	var rural:bool=str(v.get("buildingId","")).contains("rural:v1") or v.get("presentation",{}).has("profile_id")
	if not rural:return
	if v.get("definitionId")=="porch_post":return
	var old_home:bool=str(v.get("buildingId","")).ends_with(":old-house") or v.get("presentation",{}).get("family_id")=="homestead"
	# Stable, sparse weathering. Never a fake repair/order/collectible indicator.
	var variant:=posmod(str(v.id).hash(),11)
	if kind in ["wall","corner"]:
		for side in [-1.0,1.0]:
			wall_decal(builder,transform,"wall_dust",Vector2(0,0.27),Vector2(2.0,0.5),side)
			if old_home and variant==6:wall_decal(builder,transform,"damp",Vector2(0.15,0.42),Vector2(0.8,0.75),side)
	if kind=="window":
		if old_home and variant<4:wall_decal(builder,transform,"rust_runoff",Vector2(0,0.67),Vector2(0.7,0.35))
		for x in [-0.53,0.53]:
			builder.box(AABB(Vector3(x-0.12,0.95,-0.15),Vector3(0.24,1.15,0.025)),transform,"textile_atlas",1,4 if old_home else 5)
	if kind=="door":ground_decal(builder,transform,"threshold",Vector3(0,0.006,0),Vector2(1.45,0.65))

static func bed_textiles(parent:Node3D,e:Dictionary,materials:Dictionary)->void:
	if not e.get("data",{}).get("prepared",false):return
	var builder:=MeshBuilder.new()
	builder.box(AABB(Vector3(-0.54,0.73,-0.84),Vector3(1.08,0.025,1.22)),Transform3D.IDENTITY,"textile_atlas",1,0)
	builder.box(AABB(Vector3(-0.43,0.74,0.48),Vector3(0.86,0.08,0.32)),Transform3D.IDENTITY,"textile_atlas",1,1)
	var node:=MeshInstance3D.new();node.name="PreparedBedding";node.mesh=builder.mesh(materials);parent.add_child(node)

static func damaged_leaf(builder:RefCounted,height:float=2.2)->void:
	# D11 full 0.65m square canvas on each physical wooden face. The shortened
	# cutaway clips the same canvas/UVs rather than shrinking the whole decal.
	var low:=0.225;var high:=minf(0.875,height)
	if high<=low:return
	var fraction:float=(high-low)/0.65
	var uv:=Rect2(0,1-fraction,1,fraction)
	for side in [-1.0,1.0]:
		var z:float=side*0.048
		builder.quad([Vector3(0.475,low,z),Vector3(1.125,low,z),Vector3(1.125,high,z),Vector3(0.475,high,z)],Vector3(0,0,side),Transform3D.IDENTITY,"damaged_wood",-1,uv)

static func state_details(service:RefCounted,materials:Dictionary,state_view:Node3D=null)->Node3D:
	var root:=Node3D.new();root.name="StateDetails"
	var orders:Variant=service.context.world.extension("r3:structure-orders")
	for o in orders.get("orders",[]) if orders is Dictionary else []:
		if o.get("status")!="completed" or o.get("kind") not in ["repair","move"]:continue
		var v:Dictionary=service.instance(str(o.targetId))
		if v.is_empty() or float(v.hp)<=0:continue
		var builder:=MeshBuilder.new()
		var visible_piece:Dictionary=v
		var transform:=Transform3D(Basis(Vector3.UP,-int(v.quarterTurn)*PI/2),Geometry.point(v.position))
		if o.kind=="repair":
			var definition:Dictionary=service.geometry.definition(v)
			var kind:String=definition.kind
			if state_view!=null and preload("res://scripts/buildings/building_surface_state.gd").FAMILIES.has(state_view.original_surface(v,definition)):continue
			if kind in ["wall","corner","window"]:wall_decal(builder,transform,"repaired_plaster",Vector2(0,1.1),Vector2(0.8,0.85))
			elif kind=="door":
				# Attach to the actual hinged leaf in building_view, not its former plane.
				continue
			else:ground_decal(builder,transform,"board_patch",Vector3(0,0.012,0),Vector2(0.7,0.7))
		else:
			if not o.get("origin") is Dictionary:continue
			var origin:Dictionary=v.duplicate(true);origin.position=o.origin.position
			visible_piece=origin
			transform.origin=Geometry.point(origin.position)
			ground_decal(builder,transform,"moved_trace",Vector3(0,0.009,0),Vector2(1.6,1.2))
		var node:=MeshInstance3D.new();node.mesh=builder.mesh(materials);node.set_meta("piece",visible_piece);node.set_meta("wall_attached",o.kind=="repair" and service.geometry.definition(v).kind in ["wall","corner","window"]);node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(node)
	var p:Variant=service.context.world.extension("r3:production")
	var seen:Dictionary={}
	for o in p.get("orders",[]) if p is Dictionary else []:
		if o.get("status")!="completed" or o.get("kind")!="craft" or o.get("targetId") not in ["saw_timber","make_handle"] or seen.has(o.get("stationId")):continue
		var v:Dictionary=service.instance(str(o.get("stationId","")))
		if v.is_empty() or float(v.hp)<=0:continue
		seen[v.id]=true
		var builder:=MeshBuilder.new();var transform:=Transform3D(Basis(Vector3.UP,-int(v.quarterTurn)*PI/2),Geometry.point(v.position))
		ground_decal(builder,transform,"sawdust",Vector3(0,0.007,-0.7),Vector2(1.2,0.8))
		var node:=MeshInstance3D.new();node.mesh=builder.mesh(materials);node.set_meta("piece",v);node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(node)
	return root
