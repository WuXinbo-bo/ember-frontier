extends SceneTree
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Village=preload("res://scripts/modules/village_geometry.gd")
const Restore=preload("res://scripts/modules/module_restoration.gd")
const Upgrade=preload("res://scripts/modules/module_upgrade.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Builder=preload("res://scripts/buildings/building_mesh.gd")
const Detail=preload("res://scripts/buildings/architecture_detail_mesh.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool)->void:
	checks.append({"name":label,"ok":ok})
	if not ok:push_error(label)
func run()->void:
	check("catalog validates alongside historical immutable definitions",Catalog.validate().ok)
	check("new content13 receives three opening profiles",Catalog.profiles_for_content(13).filter(func(d:Dictionary)->bool:return str(d.id).begins_with("r35.module.")).size()==3)
	check("content12 never receives village definitions",Catalog.profiles_for_content(12).all(func(d:Dictionary)->bool:return not str(d.id).begins_with("r35.module.")))
	for suffix:String in ["village_home","village_warehouse","village_workshop","village_home_expanded","village_warehouse_expanded","village_sawmill"]:
		var d:=Catalog.definition("r35.module."+suffix);var p:Array=Shape.parts(d)
		check(suffix+" owns explicit nonempty geometry",not p.is_empty())
		var v:Dictionary={"id":"test:"+suffix,"position":{"x":20,"y":0,"z":20},"quarter_turn":0,"region":"RH-HOME","geometry_version":d.geometry_version,"owner":"home-residents","config":{}}
		if d.has("village_restoration"):
			v.restoration=Restore.village_initial(d)
			var broken:Array=Shape.entities(v,d);v.restoration.completed=true;var repaired:Array=Shape.entities(v,d)
			check(suffix+" structural repair restores missing actual entities",repaired.size()>broken.size())
			check(suffix+" restoration carries nonzero finite material cost",not Restore.cost(v).is_empty() and Restore.duration(v)>0)
			check(suffix+" provides explicit expansion target",Upgrade.options(d).size()==1)
		for q:int in 4:
			v.quarter_turn=q;var entities:Array=Shape.entities(v,d)
			check(suffix+" rotation "+str(q)+" produces valid bounded solids",entities.all(func(e:Dictionary)->bool:return G.aabb(e.bounds).has_volume() and G.aabb(e.bounds).position.is_finite()))
		if d.shape=="home":
			var beds:Array=Village.beds(v,d)
			check(suffix+" has exact real bed entities",beds.size()==int(d.mechanism.beds) and beds.all(func(e:Dictionary)->bool:return e.data.sleeping and e.data.prepared and e.data.module_bed.version==2))
		if d.shape=="woodshop":
			var blades:Array=p.filter(func(row:Dictionary)->bool:return row.has("architecture_detail") and row.architecture_detail.has("discs"))
			check("sawmill owns visible toothed cutting blade",blades.size()==1)
			if blades.size()==1:
				var builder:=Builder.new();var part:Dictionary=blades[0].duplicate(true);part.architecture_detail.quarter_turn=0
				check("toothed blade generates real mesh triangles",Detail.add(builder,part,{}) and not builder.groups.is_empty())
				check("front cutting group has contrasting original zinc blade",part.material=="zinc" and part.architecture_detail.discs[0].material=="zinc" and absf(float(part.center.z)+1.28)<.001)
				var safe:bool=true;var footprint:AABB=G.aabb(d.footprint)
				for group:Dictionary in p.filter(func(row:Dictionary)->bool:return str(row.id).begins_with("sawmill-feed-bed") or str(row.id).begins_with("sawmill-trestle:") or row.id=="mill-toothed-blade"):
					var volume:=AABB(G.point(group.center)-G.point(group.size)/2,G.point(group.size))
					if not footprint.encloses(volume):safe=false
					for port:Dictionary in d.ports:
						for at:Array in port.use_points:
							if G.overlap(volume,AABB(Vector3(at[0]-.4,at[1],at[2]-.4),Vector3(.8,1.8,.8))):safe=false
				check("front cutting group fits paid footprint and clears all service bodies",safe)
	var style=preload("res://scripts/modules/village_style.gd")
	var mill:Dictionary=Catalog.definition("r35.module.village_sawmill")
	var blade:Array=Shape.parts(mill).filter(func(part:Dictionary)->bool:return part.id=="mill-toothed-blade")
	check("new mill dynamic cutting anchor matches its real blade center",blade.size()==1 and G.point(blade[0].center).is_equal_approx(Vector3(mill.machine_work_point[0],mill.machine_work_point[1],mill.machine_work_point[2])))
	for family:String in ["sawmill","warehouse"]:
		for tier:String in ["low","mid","high"]:
			var d:=Catalog.definition("r34.module."+family+"_"+tier+"_v1.mechanism-v2");var source:Array=Shape.parts(d)
			var v:Dictionary={"config":{}}
			check(family+" "+tier+" old instance keeps exact previous parts",style.parts(v,d,source)==source)
			v.config.village_style_v1=1;var enhanced:Array=style.parts(v,d,source)
			check(family+" "+tier+" new13 receives visible use-specific fixtures",enhanced.size()>source.size())
			if family=="sawmill":
				var cutting:Array=enhanced.filter(func(row:Dictionary)->bool:return row.id in ["village-style:toothed-blade","village-style:bow-saw-teeth"])
				check("sawmill "+tier+" styled cutting steel uses original zinc surface",cutting.size()==1 and cutting[0].material=="zinc")
			var clear:bool=true
			for part:Dictionary in enhanced.slice(source.size()):
				if not part.solid:continue
				var volume:=AABB(G.point(part.center)-G.point(part.size)/2,G.point(part.size))
				for port:Dictionary in d.ports:
					for at:Array in port.use_points:
						var body:=AABB(Vector3(at[0]-.4,at[1],at[2]-.4),Vector3(.8,1.8,.8))
						if G.overlap(volume,body):clear=false
			check(family+" "+tier+" all actual service feet retain body clearance",clear)
	var result:Dictionary={"checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size(),"scope":"Definition, native mesh, physical parts, four orientations and real bed metadata. Gameplay transaction and visual inspection are separate integration checks."}
	print(JSON.stringify(result))
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():
		DirAccess.make_dir_recursive_absolute(args[0]);FileAccess.open(args[0]+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	quit(0 if result.failed==0 else 1)
