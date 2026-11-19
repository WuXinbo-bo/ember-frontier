extends RefCounted
## Content 17 adds footprints without changing historical definitions.
const PREFIX="r37.module."
const WORKSHOP=PREFIX+"workshop"
const WAREHOUSE=PREFIX+"warehouse"
const WAREHOUSE_UPGRADE=PREFIX+"warehouse_upgrade"
const SAWMILL=PREFIX+"sawmill"
const YARD=PREFIX+"stockyard"
const CHOICES=[YARD,WAREHOUSE,SAWMILL,PREFIX+"water",PREFIX+"kitchen",PREFIX+"artisan",PREFIX+"cottage"]

static func derive(rows:Array)->Array:
	var sources:Dictionary={}
	for row:Dictionary in rows:sources[row.id]=row
	var specs:Array=[
		[WORKSHOP,"r35.module.village_workshop.opening-v15","手工作坊","workshop",3.0,3.0,2.95],
		[WAREHOUSE,"r35.module.village_warehouse","仓棚","warehouse",3.0,4.0,3.0],
		[WAREHOUSE_UPGRADE,"r35.module.village_warehouse_expanded","分区仓棚","warehouse_upgrade",3.0,4.0,3.0],
		[SAWMILL,"r35.module.village_sawmill","锯木站","sawmill",4.0,4.0,3.3],
		[YARD,"r35.module.village_warehouse","堆料场","stockyard",2.0,3.0,1.15],
		[PREFIX+"water","r34.module.water_low_v1.mechanism-v2","净水站","water",3.0,3.0,2.8],
		[PREFIX+"kitchen","r34.module.canteen_low_v1.mechanism-v2","厨房","kitchen",3.0,3.0,2.8],
		[PREFIX+"artisan","r34.module.artisan_low_v1.mechanism-v2","工具作坊","workshop",3.0,3.0,2.95],
		[PREFIX+"cottage","r35.module.village_home","小宿屋","cottage",4.0,4.0,3.6],
	]
	var result:Array=[]
	for spec:Array in specs:
		var d:Dictionary=sources[spec[1]].duplicate(true)
		var x:float=spec[4]/2.0;var z:float=spec[5]/2.0
		for key:String in ["architecture","geometry_source_id","design_id","bench_offset"]:d.erase(key)
		d.merge({"id":spec[0],"geometry_version":spec[0]+".geometry-v1","name":spec[2],"compact_kind":spec[3],"geometry_family_version":4,"visual_family":"old-village","footprint":{"min":{"x":-x,"y":0,"z":-z},"max":{"x":x,"y":spec[6],"z":z}},"foundation":{"top_offset":0,"pad_rectangles":[[-x-.5,-z-.5,x+.5,z+.5]],"max_slope":0},"dimensions_status":"compact-village-v17"},true)
		d.village_geometry={"version":1,"kind":"village_sawmill" if d.id==SAWMILL else spec[3]}
		d.design_id=d.id
		for p:Dictionary in d.ports:
			var n:Array=p.normal;var old:Array=p.position
			var use:Array=[n[0]*(x+.9) if n[0]!=0 else clampf(old[0],-x+.5,x-.5),0,n[2]*(z+.9) if n[2]!=0 else clampf(old[2],-z+.5,z-.5)]
			p.position=use;p.use_points=[use.duplicate()]
		d.mechanism.upgrade_to=[]
		if d.id==WAREHOUSE:d.mechanism.upgrade_to=[WAREHOUSE_UPGRADE]
		else:d.erase("village_restoration")
		if d.shape=="manual":d.bench_offset=[0,0,-.60]
		if d.id==SAWMILL:d.machine_work_point=[0,1.10,-.95]
		if d.id==YARD:
			d.build_cost={"log":4};d.build_seconds=8
			d.buffer_specs[0].limits={"log":24,"timber":32,"scrap":16}
		if d.id==PREFIX+"cottage":
			d.mechanism.beds=2;d.build_cost={"timber":12,"scrap":4}
		result.append(d)
	return result
