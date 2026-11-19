extends RefCounted
## Additive geometry2 only: live portals and actual ground-level sleeping bays.
## Upper bunks share a footprint, not an occupancy ID or a fake capacity table.
const G=preload("res://scripts/buildings/building_geometry.gd")
const Data=preload("res://scripts/world/world_data.gd")
static func applies(d:Dictionary)->bool:return d.get("mechanism",{}).get("family")=="home" and d.get("mechanism",{}).get("version")==2 and d.get("geometry_version")==str(d.get("geometry_source_id",""))+".geometry-v2"
static func rooms(parts:Array)->Array:
	var result:Array=[]
	for p:Dictionary in parts:
		if not str(p.id).ends_with(":plinth"):continue
		var center:=G.point(p.center);var size:=G.point(p.size)
		result.append({"id":str(p.id).trim_suffix(":plinth"),"center":G.json_point(Vector3(center.x,0,center.z)),"width":size.x-.6,"depth":size.z-.6})
	return result
static func parts(source:Array)->Array:
	var result:Array=[]
	for original:Dictionary in source:
		var p:Dictionary=original.duplicate(true);var id:String=str(p.id)
		if (id.ends_with(":end:-1") or id.ends_with(":end:-1.0")) and float(p.size.x)>=1.5:
			var center:=G.point(p.center);var size:=G.point(p.size);var shift:float=-.2 if size.x<2.7 else 0.0
			for side:float in [-1,1]:
				var side_width:float=(size.x-1.2)/2-side*shift
				var wall:=p.duplicate(true);wall.id=id+":portal-jamb:"+str(side);wall.center=G.json_point(center+Vector3(shift+side*(.6+side_width/2),0,0));wall.size=G.json_point(Vector3(side_width,size.y,size.z));wall.erase("architecture_detail");result.append(wall)
			var lintel:=p.duplicate(true);lintel.id=id+":portal-lintel";lintel.center=G.json_point(Vector3(center.x+shift,2.2+(size.y-2.2)/2,center.z));lintel.size=G.json_point(Vector3(1.2,size.y-2.2,size.z));lintel.erase("architecture_detail");result.append(lintel)
			continue
		if id.ends_with(":stone-footing") or id.ends_with(":plinth"):
			# Ground itself retains physical support. Avoid a solid 34cm slab
			# across an otherwise valid new doorway and interior body volume.
			p.center.y=-.04;p.size.y=.08;p.solid=false
		if id.begins_with("primary-door-step:"):p.solid=false
		result.append(p)
	return result
static func layout(source:Array,capacity:int)->Array:
	var candidates:Array=[]
	for room:Dictionary in rooms(source):
		var center:=G.point(room.center);var w:float=room.width;var depth:float=room.depth;var rear:Array=[];var columns:Array=[]
		var count:int=floori((w+.08)/2.10)
		if depth>=1.64 and count>0:
			for i:int in count:
				var x:float=center.x+(float(i)-(count-1)*.5)*2.10;var z:float=center.z+depth/2-.51
				rear.append({"room_id":room.id,"position":[x,0,z],"quarter_turn":1,"approach":[x,0,z-.82]})
		if w>=1.54 and depth>=2.10:
			var zs:int=floori((depth+.08)/2.10);var sides:Array=[1.0,-1.0] if w>=2.7 else [1.0]
			for side:float in sides:
				for i:int in zs:
					var x:float=center.x+side*(w/2-.51);var z:float=center.z+(float(i)-(zs-1)*.5)*2.10
					var aisle:float=x-side*.82 if w>=2.7 else center.x-.49
					columns.append({"room_id":room.id,"position":[x,0,z],"quarter_turn":0,"approach":[aisle,0,z]})
		candidates.append_array(columns if columns.size()>rear.size() else rear)
	var result:Array=[];var floor_count:int=mini(capacity,candidates.size())
	for i:int in floor_count:
		var row:Dictionary=candidates[i].duplicate(true);row.level=0;result.append(row)
	for i:int in mini(capacity-result.size(),candidates.size()):
		var row:Dictionary=candidates[i].duplicate(true);row.level=1;result.append(row)
	return result
static func bed_entity(v:Dictionary,index:int,slot:Dictionary,at:Dictionary,bounds:AABB,room_box:AABB,prepared:bool)->Dictionary:
	var p:Array=slot.position;var mattress:Vector3=Vector3(p[0],.56+float(slot.level)*1.02,p[2]);var surface:Vector3=G.point(v.position)+G.rotate(mattress,int(v.quarter_turn));var approach:Array=slot.approach;var foot:Vector3=G.point(v.position)+G.rotate(Vector3(approach[0],0,approach[2]),int(v.quarter_turn))
	var q:int=posmod(int(v.quarter_turn)+int(slot.quarter_turn),4)
	return {"id":str(v.id)+":bed:v2:"+str(index),"kind":"prop","regionId":v.region,"position":G.json_point(G.point(v.position)+G.rotate(Vector3(p[0],0,p[2]),int(v.quarter_turn))),"bounds":G.json_box(bounds),"revision":0,"blocksTerrain":true,"supportBounds":[],"data":{"module_id":v.id,"module_geometry_version":v.geometry_version,"module_bed":{"version":2,"index":index,"level":slot.level,"quarter_turn":q,"head_direction":G.json_point(G.rotate(Vector3.BACK,q)),"surface":G.json_point(surface),"normal":{"x":0,"y":1,"z":0},"approach":at.merged(G.json_point(foot),true),"room_id":str(v.id)+":"+str(slot.room_id),"room_bounds":G.json_box(room_box)},"sleeping":true,"prepared":prepared,"owner":v.owner,"solid":true,"opaque":false,"quarterTurn":q}}
static func room_box(v:Dictionary,room:Dictionary)->AABB:
	var center:=G.point(room.center);var half:=Vector3(float(room.width)/2,0,float(room.depth)/2)
	var a:Vector3=G.point(v.position)+G.rotate(center-half,int(v.quarter_turn));var b:Vector3=G.point(v.position)+G.rotate(center+half+Vector3(0,2.2,0),int(v.quarter_turn))
	return AABB(a.min(b),a.max(b)-a.min(b))
static func metadata(v:Dictionary,part:Dictionary,rooms_state:Array)->Dictionary:
	for room:Dictionary in rooms_state:
		if not str(part.id).begins_with(str(room.id)+":"):continue
		var role:String="trim";var normal:=Vector3.ZERO
		if part.has("roof_mesh") or str(part.id).ends_with(":roof") or str(part.id).ends_with(":roof:joinery"):role="roof"
		elif str(part.id).contains(":end:") or str(part.id).contains(":side:"):
			role="wall"
			var direction:Vector3=G.point(part.center)-G.point(room.center)
			normal=Vector3(signf(direction.x),0,0) if str(part.id).contains(":side:") else Vector3(0,0,signf(direction.z))
		return {"version":2,"room_id":str(v.id)+":"+str(room.id),"bounds":G.json_box(room_box(v,room)),"role":role,"normal":G.json_point(G.rotate(normal,int(v.quarter_turn)))}
	return {}
static func entities(v:Dictionary,d:Dictionary,original:Array)->Array:
	if not applies(d):return []
	var result:Array=[];var room_rows:Array=rooms(original)
	for slot:Dictionary in layout(original,int(d.mechanism.beds)):
		var p:Array=slot.position;var center:=Vector3(p[0],float(slot.level)*1.02,p[2]);var q:int=int(slot.quarter_turn)
		var a:Vector3=center+G.rotate(Vector3(-.49,.10,-1.01),q);var b:Vector3=center+G.rotate(Vector3(.49,.74,1.01),q)
		var local:=AABB(a.min(b),a.max(b)-a.min(b));var lo:=G.point(v.position)+G.rotate(local.position,int(v.quarter_turn));var hi:=G.point(v.position)+G.rotate(local.end,int(v.quarter_turn))
		var room:Dictionary=room_rows.filter(func(r:Dictionary)->bool:return r.id==slot.room_id)[0]
		var at:Dictionary={"regionId":v.region,"buildingId":null,"storeyId":null}
		result.append(bed_entity(v,result.size(),slot,at,AABB(lo.min(hi),lo.max(hi)-lo.min(hi)),room_box(v,room),true))
	return result
static func navigation(v:Dictionary,d:Dictionary,original:Array)->Array:
	var points:Array=[]
	if not applies(d):return points
	for room:Dictionary in rooms(original):
		if float(room.width)<1.5:continue
		var c:=G.point(room.center);var shift:float=-.2 if float(room.width)<2.7 else 0.0
		for dx:float in [-.3,0,.3]:
			for dz:float in [-.65,.65]:points.append(_at(v,Vector3(c.x+shift+dx,0,c.z-float(room.depth)/2-.12+dz)))
	for slot:Dictionary in layout(original,int(d.mechanism.beds)):
		if int(slot.level)==0:points.append(_at(v,Vector3(slot.approach[0],0,slot.approach[2])))
	return points
static func _at(v:Dictionary,local:Vector3)->Dictionary:
	return G.json_point(G.point(v.position)+G.rotate(local,int(v.quarter_turn))).merged({"regionId":v.region,"buildingId":null,"storeyId":null})
static func occupied(v:Dictionary,facts:Dictionary)->bool:
	var ids:Dictionary={}
	for member:Dictionary in v.members:
		if str(member.id).begins_with(str(v.id)+":bed:"):ids[member.id]=true
	for a:Dictionary in facts.get("actors",[]):
		if float(a.get("hp",0))<=0 or not a.get("intent") is Dictionary:continue
		var intent:Dictionary=a.intent
		if ids.has(intent.get("target_id")) or ids.has(intent.get("resident_goal",{}).get("target_id")):return true
	return false
static func set_usable(host:RefCounted,tx:RefCounted,v:Dictionary,usable:bool)->void:
	for member:Dictionary in v.members:
		var e:Dictionary=host.context.world.entity(str(member.id))
		if e.get("data",{}).get("module_bed",{}).get("version")!=2 or e.data.get("sleeping",false)==usable:continue
		var after:Dictionary=e.duplicate(true);after.data.sleeping=usable;after.revision=int(e.get("revision",0))+1
		tx.extra.append({"op":"entity.put","id":e.id,"before_exists":true,"before":e,"after":after})

static func opening_enabled(v:Dictionary,d:Dictionary)->bool:
	return v.get("config",{}).get("opening_bed_v1")==1 and d.id in ["r34.module.home_roadside_v3","r34.module.home_court_v3"]
static func opening_parts(v:Dictionary,d:Dictionary,source:Array)->Array:
	if not opening_enabled(v,d) or d.id!="r34.module.home_roadside_v3":return source
	# Only the explicit fresh-source attachment has this wider existing porch;
	# old v1/v2 houses and their saved silhouettes keep the exact original parts.
	var rows:Array=source.filter(func(p:Dictionary)->bool:return not str(p.id).begins_with("road-entry-porch:"))
	var porch:=preload("res://scripts/modules/module_quality_geometry.gd").new()
	porch.shed("road-entry-porch",Vector3(-.66,0,-1.43),3.0,1.14,2.20,.39)
	rows.append_array(porch.rows);return rows
static func opening_entities(v:Dictionary,d:Dictionary)->Array:
	if not opening_enabled(v,d):return []
	var p:=Vector3(-.66,0,-1.49) if d.id=="r34.module.home_roadside_v3" else Vector3(.98,0,-.84)
	var slot:Dictionary={"position":[p.x,0,p.z],"quarter_turn":1,"level":0,"approach":[p.x,0,p.z-.82],"room_id":"opening-porch:v1"}
	var lo:Vector3=G.point(v.position)+G.rotate(p+Vector3(-1.01,.1,-.49),int(v.quarter_turn));var hi:Vector3=G.point(v.position)+G.rotate(p+Vector3(1.01,.74,.49),int(v.quarter_turn))
	var room:Dictionary={"center":G.json_point(p),"width":3.0,"depth":1.8}
	var bed:=bed_entity(v,0,slot,_at(v,Vector3.ZERO),AABB(lo.min(hi),lo.max(hi)-lo.min(hi)),room_box(v,room),false)
	bed.id=str(v.id)+":bed:opening:v1";bed.data.opening_bed_version=1
	return [bed]
