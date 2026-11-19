extends RefCounted
## Versioned closed service homes with genuinely open, physically bounded courts.
## ArchitectureKit owns shared metre-scale construction and render detail.
## Attached galleries rear edge overlaps the main eave, below its roof plane.
## Sealed home shells stay sealed; these porches do not advertise interiors.
const Kit=preload("res://scripts/buildings/architecture_kit.gd")
const IDS=["home_small_porch_v1","home_small_annex_v1","home_small_court_v1","home_medium_long_v1","home_medium_corner_v1","home_medium_twin_v1","home_large_u_v1","home_large_double_v1","home_large_lodge_v1"]
static func supports(d:Dictionary)->bool:
	return d.get("architecture",{}).get("set")=="r34-architecture-30-v1" and str(d.get("id","")).trim_prefix("r34.module.") in IDS and d.get("geometry_version")==str(d.id)+".geometry-v1"
static func parts(d:Dictionary)->Array:
	if not supports(d):return []
	var b:=Kit.new()
	match str(d.id).trim_prefix("r34.module."):
		"home_small_porch_v1":
			b.room("single-home",Vector3(0,0,1.25),5.8,3.6,2.85,1.03,"cream_plaster","home")
			b.lean_to("deep-veranda",Vector3(0,0,-1.10),4.6,2.10,2.30,2.88,"architecture_gray_roof")
			_court(b,3.5,3.5,2.0,0.65)
			_paving(b,"porch-path",Vector3(0,0,-2.7),Vector3(1.8,0.03,1.6))
		"home_small_annex_v1":
			b.room("offset-main",Vector3(-0.65,0,1.22),5.8,3.55,3.0,1.08,"cream_plaster","home")
			b.room("low-side-annex",Vector3(2.5,0,0),2.25,4.8,2.30,0.65,"old_brick","home")
			b.lean_to("offset-entry",Vector3(-0.75,0,-1.15),3.5,2.0,2.23,2.94,"zinc")
			_court(b,4.0,3.5,1.8,0.60)
		"home_small_court_v1":
			b.room("l-main",Vector3(0,0,2.15),8.0,2.9,2.98,1.05,"cream_plaster","home")
			b.room("l-living-wing",Vector3(-3.0,0,-0.75),2.0,3.8,2.54,0.78,"old_brick","home")
			b.lean_to("kitchen-service-canopy",Vector3(2.35,0,-0.25),2.8,2.8,2.20,2.90,"architecture_gray_roof")
			b.box("sealed-stove-chimney",Vector3(3.0,2.75,0.20),Vector3(0.42,2.0,0.44),"old_brick")
			_court(b,4.5,4.0,2.0,0.72)
		"home_medium_long_v1":
			b.room("long-west-home",Vector3(-2.55,0,1.75),5.0,3.6,3.02,1.12,"cream_plaster","home")
			b.room("long-east-home",Vector3(2.50,0,1.75),4.9,3.6,3.02,1.12,"old_brick","home")
			b.lean_to("continuous-veranda",Vector3(0,0,-0.725),9.8,2.25,2.38,3.01,"architecture_gray_roof")
			_court(b,5.5,4.0,2.3,0.68)
		"home_medium_corner_v1":
			b.room("tall-main",Vector3(1.2,0,2.7),7.5,3.6,3.43,1.12,"cream_plaster","home")
			b.room("corner-low-wing",Vector3(-3.65,0,0.45),2.6,7.0,2.65,0.85,"old_brick","home")
			b.lean_to("corner-link",Vector3(-0.25,0,0.20),3.9,2.30,2.38,3.32,"zinc")
			_court(b,5.5,5.0,2.3,0.78)
		"home_medium_twin_v1":
			b.room("twin-west-ridge",Vector3(-3.0,0,1.30),4.7,5.7,3.28,1.14,"cream_plaster","home")
			b.room("twin-east-ridge",Vector3(2.85,0,2.0),4.8,4.8,2.96,1.08,"old_brick","home")
			b.lean_to("shared-link-porch",Vector3(0,0,-0.15),1.7,2.0,2.44,2.94,"architecture_gray_roof")
			_court(b,6.0,5.0,2.5,0.72)
		"home_large_u_v1":
			b.room("u-main",Vector3(0,0,4.30),13.7,3.4,3.50,1.30,"cream_plaster","home")
			b.room("u-west-wing",Vector3(-5.3,0,-0.35),3.1,5.8,2.80,1.00,"old_brick","home")
			b.room("u-east-wing",Vector3(5.3,0,-0.35),3.1,5.8,2.80,1.00,"cream_plaster","home")
			b.lean_to("u-inner-gallery",Vector3(0,0,1.975),6.4,2.15,2.45,3.44,"architecture_gray_roof")
			_court(b,7.5,6.5,2.8,0.86)
			_gate(b,Vector3(0,0,-5.85),2.8,2.6)
		"home_large_double_v1":
			b.room("back-house",Vector3(0,0,5.55),13.8,3.5,3.65,1.3,"cream_plaster","home")
			b.room("front-west-house",Vector3(-4.25,0,-1.55),5.0,3.3,2.90,1.0,"old_brick","home")
			b.room("front-east-house",Vector3(4.25,0,-1.55),5.0,3.3,2.90,1.0,"cream_plaster","home")
			b.shed("through-court-link",Vector3(0,0,-1.55),3.5,3.3,2.55,0.62,"architecture_gray_roof")
			b.lean_to("back-gallery",Vector3(0,0,3.125),10.8,2.25,2.48,3.57,"zinc")
			_court(b,7.5,8.0,2.8,0.90)
		"home_large_lodge_v1":
			b.room("two-storey-main",Vector3(-0.6,0,3.95),13.8,4.5,5.8,1.55,"cream_plaster","home")
			b.room("low-service-wing",Vector3(-6.35,0,-1.4),2.8,5.6,2.8,0.92,"old_brick","home")
			b.lean_to("wide-living-gallery",Vector3(0.7,0,0.875),10.6,2.55,2.6,3.32,"architecture_gray_roof")
			b.shed("laundry-shelter",Vector3(5.8,0,-2.45),3.0,2.4,2.30,0.58,"zinc")
			_court(b,8.5,7.0,3.0,0.86)
	var width:float=float(d.footprint.max.x)-float(d.footprint.min.x)
	var depth:float=float(d.footprint.max.z)-float(d.footprint.min.z)
	_living_details(b,width,depth)
	var steps:Dictionary={"porch":Vector3(0,0,-0.10),"annex":Vector3(-0.65,0,-0.08),"court":Vector3(0,0,1.20),"long":Vector3(-2.55,0,0.50),"corner":Vector3(1.2,0,1.45),"twin":Vector3(2.85,0,0.20),"u":Vector3(0,0,3.30),"double":Vector3(0,0,4.50),"lodge":Vector3(-0.6,0,2.40)}
	var threshold:Vector3=steps[str(d.architecture.variant)]
	for i:int in 2:
		b.box("primary-door-step:"+str(i),threshold+Vector3(0,0.045+float(i)*0.045,-0.35+float(i)*0.28),Vector3(1.16,0.09+float(i)*0.09,0.45),"concrete")
	return b.rows
static func _paving(b:RefCounted,id:String,p:Vector3,size:Vector3)->void:
	# Surface dressing has no body/support authority over the underlying terrain.
	b.box(id,p+Vector3(0,0.015,0),size,"concrete",false)
static func _court(b:RefCounted,half_width:float,half_depth:float,gap:float,height:float)->void:
	var edge:float=half_width-0.22;var front:float=-half_depth+0.22
	var run:float=edge-gap/2
	for side:float in [-1.0,1.0]:
		var x:float=side*(gap/2+run/2)
		b.box("court-stone-foot:"+str(side),Vector3(x,0.10,front),Vector3(run+0.02,0.20,0.34),"concrete")
		b.box("court-front:"+str(side),Vector3(x,(height+0.18)/2,front),Vector3(run,height-0.18,0.25),"old_brick")
		b.box("court-coping:"+str(side),Vector3(x,height+0.055,front),Vector3(run+0.06,0.11,0.35),"concrete")
		b.box("court-side:"+str(side),Vector3(side*edge,height/2,front+0.92),Vector3(0.25,height,1.85),"old_brick")
		b.box("court-side-coping:"+str(side),Vector3(side*edge,height+0.055,front+0.92),Vector3(0.35,0.11,1.9),"concrete")
		for end:float in [gap/2+0.12,edge]:
			b.box("court-pier:%s:%s"%[side,end],Vector3(side*end,(height+0.15)/2,front),Vector3(0.28,height+0.15,0.30),"old_brick")
			b.box("court-pier-cap:%s:%s"%[side,end],Vector3(side*end,height+0.20,front),Vector3(0.35,0.10,0.37),"concrete")
	_paving(b,"court-entrance",Vector3(0,0,front+0.5),Vector3(gap-0.2,0.03,1.3))
static func _gate(b:RefCounted,p:Vector3,width:float,height:float)->void:
	# Open yard gate: >=2m body opening, not a fake operable door or portal.
	for side:float in [-1.0,1.0]:b.box("yard-gate-pier:"+str(side),p+Vector3(side*(width/2+0.12),height/2,0),Vector3(0.24,height,0.30),"old_brick")
	b.roof("yard-gate-cap",p,width+0.8,0.85,height,0.40,"architecture_gray_roof","")

static func _living_details(b:RefCounted,width:float,depth:float)->void:
	# Seat sits beside the front boundary, clear of the central 1.6m passage.
	var x:float=-width*0.28;var z:float=-depth/2+0.85
	b.box("yard-bench-seat",Vector3(x,0.46,z),Vector3(1.35,0.12,0.48),"b_wood_aged")
	for side:float in [-1.0,1.0]:b.box("yard-bench-leg:"+str(side),Vector3(x+side*0.48,0.21,z),Vector3(0.15,0.42,0.36),"old_brick")
	b.box("yard-bench-back",Vector3(x,0.75,z-0.19),Vector3(1.35,0.48,0.10),"b_wood_aged")
