extends RefCounted
## Shared metre kit: p is ground-centre, width X/depth Z, eave above p.y.
## Roof ridge follows X. All details are one derived recipe per assembly.
const G=preload("res://scripts/buildings/building_geometry.gd")
const DETAIL_VERSION:="r34-architecture-detail-v1"
var rows:Array=[]

func box(id:String,p:Vector3,size:Vector3,material:String,solid:bool=true)->Dictionary:
	var row:Dictionary={"id":id,"center":G.json_point(p),"size":G.json_point(size),"material":material,"solid":solid,"atlas_cell":-1}
	rows.append(row);return row

func roof(id:String,p:Vector3,width:float,depth:float,eave:float,rise:float,material:String="architecture_gray_roof",gable:String="")->void:
	var size:=Vector3(width,rise+0.18,depth)
	var row:=box(id,p+Vector3(0,eave+size.y/2,0),size,material)
	row.roof_mesh={"version":"r34-gable-roof-mesh-v1","local_size":G.json_point(size),"rise":rise,"thickness":0.11,"gable":not gable.is_empty(),"gable_material":gable,"gable_inset":0.38,"trim_material":"b_wood_aged","open_frame":gable.is_empty()}
	row.architecture_detail={"version":DETAIL_VERSION,"kind":"gable_roof","local_size":G.json_point(size),"rise":rise}
	var details:Array=[];var beams:Array=[]
	# Fascia, purlins and exposed rake rafters, continuous components not tiles.
	for z:float in [-depth/2+0.09,depth/2-0.09]:
		details.append(_box_item(p+Vector3(0,eave+0.015,z),Vector3(width,0.18,0.15),"b_wood_aged"))
	for x:float in [-width/2+0.11,width/2-0.11]:
		for sign_z:float in [-1,1]:
			beams.append(_beam_item(p+Vector3(x,eave+0.03,sign_z*(depth/2-0.04)),p+Vector3(x,eave+rise+0.03,0),0.14))
	# Visible gable tie, king post and paired diagonal infill under both ends.
	for x:float in [-width/2+0.34,width/2-0.34]:
		details.append(_box_item(p+Vector3(x,eave+0.10,0),Vector3(0.17,0.18,depth-0.68),"b_wood_aged"))
		beams.append(_beam_item(p+Vector3(x,eave+0.12,0),p+Vector3(x,eave+rise-0.08,0),0.12))
		for z:float in [-depth*0.30,depth*0.30]:beams.append(_beam_item(p+Vector3(x,eave+0.10,z),p+Vector3(x,eave+rise-0.10,0),0.10))
	var count:int=maxi(2,ceili(width/0.85))
	for index:int in count+1:
		var x:float=lerpf(-width/2+0.18,width/2-0.18,float(index)/count)
		for sign_z:float in [-1,1]:
			beams.append(_beam_item(p+Vector3(x,eave-0.055,sign_z*(depth/2-0.08)),p+Vector3(x,eave+rise-0.06,0),0.075))
	detail(id+":joinery",details,beams)

func lean_to(id:String,p:Vector3,width:float,depth:float,front_eave:float,back_eave:float,material:String="architecture_gray_roof")->void:
	# A complete open porch with one true plane: -Z front is low, +Z is high.
	# The caller places the rear edge against its main roof, no false gable.
	assert(back_eave>front_eave and front_eave>1.8)
	var beams:Array=[]
	for z:float in [-depth/2+0.28,depth/2-0.28]:
		var h:float=lerpf(front_eave,back_eave,(z+depth/2)/depth)
		for x:float in [-width/2+0.30,width/2-0.30]:
			box(id+":foot:%s:%s"%[x,z],p+Vector3(x,0.17,z),Vector3(0.36,0.34,0.36),"stone_masonry")
			box(id+":post:%s:%s"%[x,z],p+Vector3(x,h/2,z),Vector3(0.20,h,0.20),"b_wood_aged")
			beams.append(_beam_item(p+Vector3(x,h-0.6,z),p+Vector3(x-signf(x)*0.52,h-0.10,z),0.12))
		box(id+":header:"+str(z),p+Vector3(0,h-0.08,z),Vector3(width-0.40,0.18,0.20),"b_wood_aged")
	var size:=Vector3(width,back_eave-front_eave+0.18,depth)
	var row:=box(id+":roof",p+Vector3(0,front_eave+size.y/2,0),size,material)
	row.architecture_detail={"version":DETAIL_VERSION,"kind":"lean_roof","local_size":G.json_point(size),"rise":back_eave-front_eave}
	for x:float in [-width/2+0.10,width/2-0.10]:beams.append(_beam_item(p+Vector3(x,front_eave, -depth/2),p+Vector3(x,back_eave,depth/2),0.16))
	detail(id+":joinery",[],beams)

func wall(id:String,p:Vector3,size:Vector3,material:String,normal:Vector3,style:String="home",door:bool=false)->void:
	var row:=box(id,p,size,material)
	var width:float=size.z if absf(normal.x)>0.5 else size.x
	var openings:Array=[]
	if width>=1.7:
		if door:openings.append({"x":0.0,"bottom":0.0,"width":minf(1.16,width-0.5),"height":minf(2.05,size.y-0.22),"type":"door","panel":"b_wood_aged"})
		elif style!="blank":
			var count:int=clampi(floori(width/2.3),1,4)
			for i:int in count:
				openings.append({"x":(float(i)-(count-1)*0.5)*width/count,"bottom":0.95,"width":minf(1.02,width/count-0.42),"height":minf(1.05,size.y-1.18),"type":"window","panel":"architecture_window"})
	if size.y>4.5 and style.begins_with("home") and width>=1.7:
		var count:int=clampi(floori(width/2.3),1,6)
		for i:int in count:
			openings.append({"x":(float(i)-(count-1)*0.5)*width/count,"bottom":3.50,"width":minf(1.02,width/count-0.42),"height":minf(1.12,size.y-3.72),"type":"window","panel":"architecture_window"})
	row.architecture_detail={"version":DETAIL_VERSION,"kind":"wall","local_size":G.json_point(size),"normal":G.json_point(normal),"openings":openings}

func room(id:String,p:Vector3,width:float,depth:float,eave:float,rise:float,material:String,style:String)->void:
	var w:float=width-0.76;var d:float=depth-0.76;var t:float=0.24
	box(id+":stone-footing",p+Vector3(0,0.10,0),Vector3(w+0.20,0.20,d+0.20),"well_stone")
	box(id+":plinth",p+Vector3(0,0.25,0),Vector3(w+0.12,0.18,d+0.12),"old_brick")
	for sign_x:float in [-1,1]:
		wall(id+":side:"+str(sign_x),p+Vector3(sign_x*(w/2-t/2),eave/2,0),Vector3(t,eave,d),material,Vector3(sign_x,0,0),style)
	for sign_z:float in [-1,1]:
		wall(id+":end:"+str(sign_z),p+Vector3(0,eave/2,sign_z*(d/2-t/2)),Vector3(w-t*2,eave,t),material,Vector3(0,0,sign_z),style,sign_z<0)
	var items:Array=[]
	for x:float in [-w/2+0.07,w/2-0.07]:
		for z:float in [-d/2+0.07,d/2-0.07]:items.append(_box_item(p+Vector3(x,eave/2,z),Vector3(0.18,eave,0.18),"b_wood_aged"))
	for z:float in [-d/2,d/2]:items.append(_box_item(p+Vector3(0,eave-0.20,z),Vector3(w+0.10,0.18,0.12),"b_wood_aged"))
	for z:float in [-d/2,d/2]:items.append(_box_item(p+Vector3(0,0.365,z),Vector3(w+0.18,0.075,0.18),"stone_masonry"))
	for x:float in [-w/2,w/2]:items.append(_box_item(p+Vector3(x,0.365,0),Vector3(0.18,0.075,d+0.18),"stone_masonry"))
	if eave>4.5 and style.begins_with("home"):
		for z:float in [-d/2,d/2]:items.append(_box_item(p+Vector3(0,3.05,z),Vector3(w+0.10,0.22,0.16),"b_wood_aged"))
	detail(id+":timber-frame",items)
	roof(id+":roof",p,width,depth,eave,rise,"architecture_gray_roof",material)

func shed(id:String,p:Vector3,width:float,depth:float,eave:float,rise:float,surface:String="zinc")->void:
	var beams:Array=[]
	for x:float in [-width/2+0.32,width/2-0.32]:
		for z:float in [-depth/2+0.32,depth/2-0.32]:
			var base:Vector3=p+Vector3(x,0,z)
			box(id+":foot:%s:%s"%[x,z],base+Vector3(0,0.18,0),Vector3(0.36,0.36,0.36),"old_brick")
			box(id+":post:%s:%s"%[x,z],base+Vector3(0,eave/2,0),Vector3(0.20,eave,0.20),"b_wood_aged")
			var sx:float=-signf(x);var sz:float=-signf(z)
			beams.append(_beam_item(base+Vector3(0,eave-0.65,0),base+Vector3(sx*0.57,eave-0.10,0),0.12))
			beams.append(_beam_item(base+Vector3(0,eave-0.65,0),base+Vector3(0,eave-0.10,sz*minf(0.57,depth*0.3)),0.12))
	for z:float in [-depth/2+0.32,depth/2-0.32]:box(id+":header:"+str(z),p+Vector3(0,eave-0.10,z),Vector3(width-0.44,0.20,0.22),"b_wood_aged")
	detail(id+":braces",[],beams)
	roof(id+":roof",p,width,depth,eave,rise,surface)

func detail(id:String,boxes:Array,beams:Array=[])->void:
	if boxes.is_empty() and beams.is_empty():return
	var lo:=Vector3(INF,INF,INF);var hi:Vector3=-lo
	for item:Dictionary in boxes:
		var c:=G.point(item.center);var s:=G.point(item.size)
		lo=lo.min(c-s/2);hi=hi.max(c+s/2)
	for item:Dictionary in beams:
		var a:=G.point(item.a);var b:=G.point(item.b);var direction:Vector3=b-a
		var y:Vector3=direction.normalized();var x:=Vector3.UP.cross(y).normalized()
		if x.length()<0.5:x=Vector3.RIGHT
		var z:Vector3=x.cross(y).normalized()
		var half:Vector3=(x.abs()+z.abs())*float(item.thickness)/2+y.abs()*direction.length()/2
		lo=lo.min((a+b)/2-half);hi=hi.max((a+b)/2+half)
	var size:Vector3=hi-lo
	var row:=box(id,(lo+hi)/2,size,"b_wood_aged",false)
	var local_boxes:Array=boxes.duplicate(true);var local_beams:Array=beams.duplicate(true)
	for item:Dictionary in local_boxes:item.center=G.json_point(G.point(item.center)-lo)
	for item:Dictionary in local_beams:
		item.a=G.json_point(G.point(item.a)-lo);item.b=G.json_point(G.point(item.b)-lo)
	row.architecture_detail={"version":DETAIL_VERSION,"kind":"details","local_size":G.json_point(size),"boxes":local_boxes,"beams":local_beams}

func _box_item(center:Vector3,size:Vector3,material:String)->Dictionary:
	return {"center":G.json_point(center),"size":G.json_point(size),"material":material}
func _beam_item(a:Vector3,b:Vector3,thickness:float,material:String="b_wood_aged")->Dictionary:
	return {"a":G.json_point(a),"b":G.json_point(b),"thickness":thickness,"material":material}
