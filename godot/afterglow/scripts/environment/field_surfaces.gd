extends RefCounted
## Initial surface layout persisted once; current cells always decide visibility.
static func layout(plan:Dictionary,heights:PackedInt32Array,tops:PackedInt32Array)->Dictionary:
	var chunks:Dictionary={}
	var ox:int=int(plan.region_coord.x)*128;var oz:int=int(plan.region_coord.z)*128
	for z in 128:
		for x in 128:
			var index:int=x+128*z;var material:int=tops[index]
			if material not in [1,2]:continue
			var wx:float=(ox+x+0.5)*0.5;var wz:float=(oz+z+0.5)*0.5;var texture:=""
			for land:Dictionary in plan.landforms:
				if land.use not in ["field","field-bank"] or material!=int(land.material):continue
				if wx>=land.xz[0] and wx<land.xz[2] and wz>=land.xz[1] and wz<land.xz[3]:texture="c05_dry_tilled_soil" if land.use=="field" else "c07_earthen_bund"
			if texture.is_empty():continue
			var y:int=heights[index]-1
			var key:="%d,%d,%d"%[floori(float(ox+x)/16),floori(float(y)/16),floori(float(oz+z)/16)]
			if not chunks.has(key):chunks[key]=[]
			var rows:Array=chunks[key]
			if not rows.is_empty() and rows[-1][2]==ox+x and rows[-1][1]==oz+z and rows[-1][3]==y and rows[-1][4]==material and rows[-1][5]==texture:rows[-1][2]+=1
			else:rows.append([ox+x,oz+z,ox+x+1,y,material,texture])
	return {"version":1,"chunks":chunks,"semantics":"immutable initial visual support runs; never authoritative terrain, no moisture/growth/stock"}

static func capture(world:RefCounted,key:String)->Dictionary:
	var chunk:Dictionary=world.chunk(key)
	if chunk.is_empty() or not chunk.resident:return {"groups":{},"supports":[]}
	var coord:Vector3i=preload("res://scripts/world/world_data.gd").coord(key)
	var center:Dictionary={"x":(coord.x+0.5)*8.0,"y":0.0,"z":(coord.z+0.5)*8.0}
	var region:Dictionary=world.region_at(center)
	if region.is_empty():return {"groups":{},"supports":[]}
	# Capturing one chunk never consumes the region's heights, resources,
	# roads or parcels. Read the same detached visual layout without cloning
	# the entire persisted generation plan for every empty/upper chunk.
	var fields:Array[String]=["field_surfaces"]
	var plan:Variant=world.extension_fields("generation:"+str(region.id),fields) if world.has_method("extension_fields") else world.extension("generation:"+str(region.id))
	if not plan is Dictionary:return {"groups":{},"supports":[]}
	var rows:Array=plan.get("field_surfaces",{}).get("chunks",{}).get(key,[])
	var groups:Dictionary={};var supports:Array=[]
	for row:Array in rows:
		var z:int=row[1];var y:int=row[3];var material:int=row[4];var id:String=row[5]
		for x in range(row[0],row[2]):
			if not world.is_cell_known(x,y+1,z) or world.cell_at(x,y,z)!=material or world.cell_at(x,y+1,z)!=0:continue
			if not groups.has(id):groups[id]={"v":PackedVector3Array(),"n":PackedVector3Array(),"u":PackedVector2Array(),"i":PackedInt32Array()}
			var g:Dictionary=groups[id];var first:int=g.v.size();var h:float=(y+1)*0.5+0.008
			for corner:Vector2 in [Vector2(x,z),Vector2(x+1,z),Vector2(x+1,z+1),Vector2(x,z+1)]:
				g.v.append(Vector3(corner.x*0.5,h,corner.y*0.5));g.n.append(Vector3.UP);g.u.append(corner*0.5)
			for i in [0,1,2,0,2,3]:g.i.append(first+i)
			supports.append([x,y,z,material])
	return {"groups":groups,"supports":supports}

static func build(world:RefCounted,key:String,quality:RefCounted)->MeshInstance3D:
	return upload(capture(world,key),key,quality)

static func upload(data:Dictionary,key:String,quality:RefCounted)->MeshInstance3D:
	var groups:Dictionary=data.groups;var supports:Array=data.supports
	if groups.is_empty():return null
	var mesh:=ArrayMesh.new()
	for id:String in groups:
		var g:Dictionary=groups[id];var a:Array=[];a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX]=g.v;a[Mesh.ARRAY_NORMAL]=g.n;a[Mesh.ARRAY_TEX_UV]=g.u;a[Mesh.ARRAY_INDEX]=g.i
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a);mesh.surface_set_material(mesh.get_surface_count()-1,quality.material(id))
	var item:=MeshInstance3D.new();item.mesh=mesh;item.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	item.set_meta("terrain_chunk",key);item.set_meta("actual_support_cells",supports)
	return item
