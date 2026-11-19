extends "res://tests/modules/run_stock_layout.gd"
## Reuse only original pure bay/body checks for six NEW geometry definitions.
## No stock is granted and no old green gameplay journey is repeated.
func run()->void:
	for d:Dictionary in Catalog.definitions().filter(func(row:Dictionary)->bool:return row.get("geometry_family_version",1)==2):
		var before:Dictionary=d.duplicate(true);var expected:int=0
		for b:Dictionary in d.buffer_specs:expected+=b.limits.size()
		for ruined:bool in [false,true]:
			var plan:=Layout.local_plan(d,ruined);var invalid:Array=[];var volumes:Array=[]
			check("all finite stock types have independent slots "+d.id+str(ruined),plan.size()==expected,{"expected":expected,"actual":plan.size()})
			for key:String in plan:
				var local:Dictionary=plan[key];var extent:=Vector3(local.extent[0],local.extent[1],local.extent[2]);var at:=G.point(local.position)
				var box:=Layout._bounds(at,int(local.quarter_turn),extent);var supported:bool=false
				if local.support=="ground":
					for pad:Array in d.foundation.pad_rectangles:
						if absf(box.position.y)<0.001 and box.position.x>=float(pad[0])-0.001 and box.position.z>=float(pad[1])-0.001 and box.end.x<=float(pad[2])+0.001 and box.end.z<=float(pad[3])+0.001:supported=true
				else:
					for part:Dictionary in Shape.parts(d):
						var fixed:=AABB(G.point(part.center)-G.point(part.size)/2,G.point(part.size))
						if part.solid and absf(fixed.end.y-box.position.y)<0.001 and fixed.position.x<=box.position.x+0.001 and fixed.end.x>=box.end.x-0.001 and fixed.position.z<=box.position.z+0.001 and fixed.end.z>=box.end.z-0.001:supported=true
				if not supported:invalid.append(key+":no_real_support")
				if not ruined:
					for part:Dictionary in Shape.parts(d):
						var fixed:=AABB(G.point(part.center)-G.point(part.size)/2,G.point(part.size))
						if part.solid and box.grow(-0.002).intersects(fixed):invalid.append(key+":intersects:"+str(part.id))
				for port:Dictionary in d.ports:
					for use:Array in port.use_points:
						var point:=Vector3(use[0],use[1],use[2]);var dx:float=point.x-clampf(point.x,box.position.x,box.end.x);var dz:float=point.z-clampf(point.z,box.position.z,box.end.z)
						if Vector2(dx,dz).length()<float(port.clearance.radius)-0.001:invalid.append(key+":blocks_body:"+str(port.id))
				for prior:Dictionary in volumes:
					if box.grow(-0.001).intersects(prior.bounds):invalid.append(key+":overlaps:"+str(prior.id))
				volumes.append({"id":key,"bounds":box})
				if key.ends_with(":log"):measurements.append({"definition":d.id,"ruined":ruined,"log_length_m":extent.z*0.92,"diameter_m":minf(extent.x,extent.y)/3.2})
			check("support solids usepoint bodies and bays stay disjoint "+d.id+str(ruined),invalid.is_empty(),invalid)
			for turn:int in 4:
				var v:=Modules.record_for({"id":"B:stock:fixture","definition_id":d.id,"region":"RH-HOME","position":{"x":36,"y":1.5,"z":36},"quarter_turn":turn});v.status="ruined" if ruined else "operational"
				var valid:=true
				for b:Dictionary in d.buffer_specs:
					for item:String in b.limits:
						var bay:=Layout.bay(v,d,b.id,item)
						if bay.is_empty():valid=false;continue
						var source:Dictionary=plan[b.id+":"+item];var actual:=Vector3(bay.anchor.position[0],bay.anchor.position[1],bay.anchor.position[2])
						valid=valid and actual.is_equal_approx(G.point(Shape.at(v,G.point(source.position)))) and int(bay.anchor.quarter_turn)==posmod(turn+int(source.quarter_turn),4)
				check("world metre anchor rotates exactly once "+d.id+str(ruined)+" q"+str(turn),valid)
		check("catalog and pinned geometry are never mutated "+d.id,Data.json_equal(before,d))
	var ok:bool=checks.all(func(c:Dictionary)->bool:return c.ok)
	var out:String=OS.get_cmdline_user_args()[0]
	var f:=FileAccess.open(out+"/results.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"ok":ok,"checks":checks,"measurements":measurements,"scope":"Only six new definitions: original stock-layout/actual parts support, occupancy and use point checks; not actual full inventory/economy or VA."},"\t"));f.close()
	print("QUALITY STOCK "+str(checks.size())+" "+str(ok));quit(0 if ok else 1)
