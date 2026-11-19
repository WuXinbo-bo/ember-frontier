extends SceneTree
const Plot=preload("res://scripts/generation/architecture_plot_layout.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Modules=preload("res://scripts/modules/module_service.gd")
const World=preload("res://scripts/world/world_state.gd")
const Factory=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Space=preload("res://scripts/buildings/building_space.gd")
const Navigation=preload("res://scripts/buildings/building_navigation.gd")
var checks:Array=[]
var observations:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func run()->void:
	var definitions:Array=Catalog.definitions().filter(func(d:Dictionary)->bool:return d.get("architecture",{}).get("set")=="r34-architecture-30-v1")
	var before:=JSON.stringify(definitions,"",true,true)
	check("actual owner catalog contains exact thirty new definitions",definitions.size()==30)
	var homes:Array=JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[1]))
	var positions:Array=[]
	for i:int in definitions.size():
		positions.append({"id":"plot:"+str(i).pad_zeros(2),"definition_id":definitions[i].id,"region_id":"read-only-layout-laboratory","position":{"x":-96+(i%6)*36,"y":0.5,"z":-72+floori(float(i)/6)*36},"quarter_turn":i%4})
	var start:int=Time.get_ticks_usec();var combined:=Plot.layout(definitions,positions);var usec:int=Time.get_ticks_usec()-start
	check("all thirty spaced uses produce bounded read-only combined layout",combined.ok and combined.plots.size()==30 and combined.world_changes.is_empty(),combined.get("code"))
	if combined.ok:observations.append({"combined_prepare_usec":usec,"plots":combined.plots})
	var reversed:Array=positions.duplicate(true);reversed.reverse()
	check("opposite input order gives identical sorted result",Data.json_equal(combined,Plot.layout(definitions,reversed)))
	for d:Dictionary in definitions:
		var court:Array=[]
		for home:Dictionary in homes:
			if home.id==d.id:court.append(home.court_probe)
		var bad:Array=[]
		for q:int in 4:
			var origin:=Vector3(-13.5,0.5,-26.25)
			var row:=Plot.plot(d,origin,q,court)
			check("actual owner dimensions ports and pads rotate "+str(d.id)+" q"+str(q),row.ok,row.get("code"))
			if not row.ok:continue
			var local:=G.aabb(d.footprint)
			var expected_size:=local.size if q%2==0 else Vector3(local.size.z,local.size.y,local.size.x)
			var exact:bool=G.aabb(row.footprint).size.is_equal_approx(expected_size) and row.approaches.size()==d.ports.reduce(func(total:int,p:Dictionary)->int:return total+p.use_points.size(),0)
			for port:Dictionary in d.ports:
				var source:Array=port.use_points[0];var target:Vector3=origin+G.rotate(Vector3(source[0],source[1],source[2]),q)
				var approach:Dictionary=row.approaches.filter(func(a:Dictionary)->bool:return a.port_id==port.id)[0]
				exact=exact and G.point(approach.use_point)==target and G.point(approach.normal)==G.rotate(Vector3(port.normal[0],port.normal[1],port.normal[2]),q) and approach.width==1.6 and approach.clearance.radius>=0.4 and approach.clearance.height>=1.8
			check("full body apron and exact rotation follow owner facts "+str(d.id)+" q"+str(q),exact)
			check("closed outer ring and no free terrain edit or permit "+str(d.id)+" q"+str(q),row.paths[0].points[0]==row.paths[0].points[-1] and row.paths[0].points.size()==5 and row.terrain_edits.is_empty() and row.permission.begins_with("none"))
			# The ring clears the entire footprint. Service throats have full
			# 1.6m transverse width and the owner's longitudinal body radius;
			# they must clear the real solids, not a fictitious filled building.
			var footprint:=G.aabb(row.footprint);var safe:=true
			for path:Dictionary in row.paths:
				for i:int in path.points.size()-1:
					var a:=G.point(path.points[i]);var b:=G.point(path.points[i+1]);var lo:=a.min(b)-Vector3(.8,0,.8);var hi:=a.max(b)+Vector3(.8,1.8,.8)
					if path.id=="outer-ring":safe=safe and not G.overlap(AABB(lo,hi-lo),footprint)
					else:
						var corridor:=G.aabb(path.clearance_bounds)
						var delta:Vector3=(b-a).normalized();var half:Vector3=Vector3(.4,0,.8) if absf(delta.x)>.5 else Vector3(.8,0,.4)
						safe=safe and corridor.position.is_equal_approx(a.min(b)-half) and corridor.end.is_equal_approx(a.max(b)+half+Vector3(0,1.8,0))
						for part:Dictionary in Shape.parts(d):
							if not part.solid:continue
							var pa:Vector3=origin+G.rotate(G.point(part.center)-G.point(part.size)/2,q);var pb:Vector3=origin+G.rotate(G.point(part.center)+G.point(part.size)/2,q)
							safe=safe and not G.overlap(corridor,AABB(pa.min(pb),pa.max(pb)-pa.min(pb)))
			check("whole width directional throat clears real solid structure "+str(d.id)+" q"+str(q),safe)
			if not safe:bad.append(q)
		check("all four canonical repeat results stable "+str(d.id),Data.json_equal(Plot.plot(d,Vector3.ZERO,0,court),Plot.plot(d,Vector3.ZERO,0,court)))
	check("all owner input dictionaries byte shape unchanged",JSON.stringify(definitions,"",true,true)==before)
	if combined.ok:
		combined.plots[0].architecture.description="mutated detached output"
		check("returned metadata detached from owner catalog",JSON.stringify(definitions,"",true,true)==before)
	var first:Dictionary=definitions[0]
	check("legacy definition rejected rather than guessed",not Plot.plot(Catalog.definition("r34.module.repair_shed_v3"),Vector3.ZERO,0).ok)
	check("unknown rotation and nonfinite origin rejected",not Plot.plot(first,Vector3.ZERO,4).ok and not Plot.plot(first,Vector3(INF,0,0),0).ok)
	var unknown:Array=positions.duplicate(true);unknown[0].definition_id="r34.module.unknown"
	check("unknown definition returns no partial layout",not Plot.layout(definitions,unknown).ok)
	var repeated:Array=[positions[0].duplicate(true),positions[0].duplicate(true)]
	check("duplicate identities rejected",Plot.layout(definitions,repeated).get("code")=="INVALID_ARCHITECTURE_PLACEMENT")
	repeated[1].id="other"
	check("overlapping plot aprons rejected",Plot.layout(definitions,repeated).get("code")=="PLOT_APPROACH_OVERLAP")
	var touching:Array=[positions[0].duplicate(true),positions[0].duplicate(true)];touching[1].id="adjacent";touching[1].position.x+=4
	check("whole reservation detects close neighbouring clearance",Plot.layout(definitions,touching).get("code")=="PLOT_APPROACH_OVERLAP")
	var altered:Dictionary=first.duplicate(true);altered.ports[0].use_points=[[0,0,0]]
	check("service approach placed through building is rejected",Plot.plot(altered,Vector3.ZERO,0).get("code")=="SERVICE_APRON_INTRUDES_FOOTPRINT")
	altered=first.duplicate(true);altered.ports[0].clearance.height=1.0
	check("insufficient real body clearance rejected",not Plot.plot(altered,Vector3.ZERO,0).ok)
	altered=first.duplicate(true);altered.ports[0].normal=[0,0,0]
	check("unknown port direction rejected",not Plot.plot(altered,Vector3.ZERO,0).ok)
	check("invalid court height and position rejected",not Plot.plot(first,Vector3.ZERO,0,[[0,1,0]]).ok and not Plot.plot(first,Vector3.ZERO,0,[[999,0,0]]).ok)
	check("all thirty JSON-decoded integer rotations remain legal",definitions.all(func(d:Dictionary)->bool:return Plot.plot(d,Vector3.ZERO,0).ok))
	verify_saw_access()
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"observations":observations,"scope":"30 exact owner definitions read-only layout/4-way/complete directional throats/negative coordinates/isolation/rejection; actual mid/high saw World draft and original Space/Navigation in explicit bounded flat structural fixture. Not natural generation or paid placement approval."},"\t",true,true))
	print("PLOTS "+str(checks.size())+" failed="+str(failed));quit(0 if failed==0 else 1)

func verify_saw_access()->void:
	var source:Dictionary=Factory.generate(713,Catalog.profiles(),Contract.fresh(Catalog.profiles(),8,1).contract)
	for key:String in source.chunks:
		var c:Vector3i=Data.coord(key);var cells:PackedInt32Array=source.chunks[key].cells.duplicate()
		for y:int in 16:
			for z:int in 16:
				for x:int in 16:cells[x+16*(z+16*y)]=2 if c.y*16+y<0 else 0
		source.chunks[key].cells=cells
	source.entities={}
	var world:=World.new();check("explicit bounded saw structural fixture loads",world.load_snapshot(source).ok)
	var building:=Modules.building_adapter(world,{"actors":[],"stocks":[]})
	for id:String in ["r34.module.sawmill_mid_v1","r34.module.sawmill_high_v1"]:
		var d:=Catalog.definition(id)
		check("owner work and tooth retain original .85m separation "+id,is_equal_approx(float(d.machine_work_point[2])-float(d.ports.filter(func(p:Dictionary)->bool:return p.id=="work")[0].position[2]),.85))
		var bad:Dictionary=d.duplicate(true);bad.ports.filter(func(p:Dictionary)->bool:return p.id=="work")[0].clearance.radius=.6
		check("owner larger body cannot be hidden by transverse width "+id,not Plot.plot(bad,Vector3.ZERO,0).ok)
		for q:int in 4:
			var instance:=Modules.record_for({"id":"C:plot:"+id+":"+str(q),"definition_id":id,"region":"RH-HOME","position":{"x":32,"y":0,"z":32},"quarter_turn":q})
			var changes:Array=[];var structures:Dictionary={"schemaVersion":1,"catalogVersion":1,"instances":[],"storeys":[]}
			Modules.append_instance(world,building,instance,d,changes,structures)
			var draft:=world.prepare_changes(changes,world.get_revision())
			var safe:Dictionary=building.validate_world_draft(draft.view,{"actors":[],"stocks":[]},changes) if draft.ok else draft
			check("original World/Building validates saw draft "+id+" q"+str(q),safe.ok,safe)
			if not safe.ok:
				if draft.ok:world.discard_prepared(draft.capability)
				continue
			var query:=Space.new();query.agent.radius=.4;query.agent.height=1.8
			query.configure(draft.view,structures,building.geometry,func(_a:Variant,_b:Variant,_c:Variant,_d:Variant)->Variant:return null)
			var layout:=Plot.plot(d,Vector3(32,0,32),q);var routes:Array=[]
			if layout.ok:
				for path:Dictionary in layout.paths:
					for i:int in path.points.size()-1:
						var a:Dictionary=path.points[i].merged({"regionId":"RH-HOME","buildingId":null,"storeyId":null})
						var b:Dictionary=path.points[i+1].merged({"regionId":"RH-HOME","buildingId":null,"storeyId":null})
						var route:=Navigation.new().plan(query,"player",a,b)
						routes.append({"path":path.id,"stand":not query.standing_point(b).is_empty(),"direct_walk":direct_walk(query,a,b),"route":route.ok,"code":route.get("code")})
			check("entire original navigation and body-proved direct throats "+id+" q"+str(q),layout.ok and not routes.is_empty() and routes.all(func(r:Dictionary)->bool:return r.stand and r.direct_walk and r.route),routes)
			# Real solid saw bed is not bypassed by accepting an open eave.
			var bed:Dictionary=draft.view.entity(instance.id+":part:saw-bed")
			var into:=G.json_point(G.aabb(bed.bounds).get_center());into.y=0;into.regionId="RH-HOME";into.buildingId=null;into.storeyId=null
			check("real saw-bed occupied standing point remains rejected "+id+" q"+str(q),query.standing_point(into).is_empty())
			world.discard_prepared(draft.capability)

func direct_walk(query:RefCounted,a:Dictionary,b:Dictionary)->bool:
	# Original walk deliberately refuses a single request longer than 16m.
	# Prove the same complete collinear route in <=8m requests, without
	# treating that API limit as a blocked building or routing around it.
	var count:int=maxi(1,ceili(G.point(a).distance_to(G.point(b))/8.0));var current:=a
	for i:int in range(1,count+1):
		var p:Dictionary=a.duplicate(true);p.x=lerpf(a.x,b.x,float(i)/count);p.z=lerpf(a.z,b.z,float(i)/count)
		if not query.walk("player",current,p).ok:return false
		current=p
	return true
