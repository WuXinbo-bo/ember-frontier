extends "res://tests/buildings/metadata_invalidation_suite.gd"
const Before=preload("res://tests/buildings/support_baseline_reference_meter.gd")
const Candidate=preload("res://tests/buildings/support_baseline_meter.gd")

func create_runtime(capture:Dictionary,reference:bool)->Dictionary:
	var w:=World.new();var loaded:Dictionary=w.load_snapshot(capture.world)
	if not loaded.ok:return loaded
	var b:RefCounted=Before.new() if reference else Candidate.new()
	var services:Dictionary={"buildings":b,"actions":Actions.new(),"production":Production.new(),"terrain":Terrain.new(),"gameplay":Gameplay.new(),"residents":Life.new()}
	var r:=MeterRuntime.new()
	var configured:Dictionary=r.configure({"world":w,"services":services,"facts":capture.facts,"source":capture.get("source",{}),"command_revision":capture.get("command_revision",0),"receipts":capture.get("receipts",{}),"definitions":JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json"))})
	return {"ok":configured.ok,"reason":configured.get("reason"),"world":w,"runtime":r,"building":b,"services":services}

func prime(built:Dictionary)->void:
	super.prime(built)
	var safe:Dictionary=built.building.validate_structures(built.world,built.building.structures(),built.runtime.facts())
	expect("startup-equivalent full safety actually succeeds",safe.ok,safe)
	built.building.meters()

func proof_invalidation(capture:Dictionary)->void:
	for kind:String in ["region","generation","entity","residency","chunk replacement","deep voxel","structure HP"]:
		var built:=create_runtime(capture,false)
		expect("candidate invalidation fixture configures "+kind,built.ok)
		if not built.ok:continue
		prime(built)
		expect("full static proof exists before real "+kind,built.building._support_world==built.world and not built.building._support_roots.is_empty())
		var changes:=safe_changes(built,kind)
		var result:Dictionary=built.runtime._commit({"world_changes":changes,"fact_changes":[]})
		expect("real spatial mutation succeeds but discards support proof "+kind,result.ok and built.building._support_world==null,result)
		built.building.meters()
		var safe:Dictionary=built.building.validate_structures(built.world,built.building.structures(),built.runtime.facts())
		var counts:Dictionary=built.building.meters()
		expect("next query freshly checks every root after "+kind,safe.ok and counts.root_misses==built.building.structures().instances.size(),{"safe":safe,"roots":counts})
	var built:=create_runtime(capture,false);prime(built)
	var prior_revision:int=built.world.get_revision()
	var metadata:Dictionary=built.runtime._commit({"world_changes":[built.building.extension_change("fixture:support-proof",true)],"fact_changes":[]})
	expect("typed metadata preserves only support identity/revision",metadata.ok and built.world.get_revision()==prior_revision+1 and built.building._support_world==built.world and built.building._support_revision==built.world.get_revision())
	built.building.meters()
	var result:Dictionary=built.building.validate_structures(built.world,built.building.structures(),built.runtime.facts())
	expect("metadata proof still performs complete successful spatial validator",result.ok and built.building.meters().root_misses==0)
	var clone:=World.new();clone.load_snapshot(built.world.snapshot())
	built.building.configure({"world":clone,"runtime":built.runtime})
	expect("configure/new-world clears all static support evidence",built.building._support_world==null and built.building._support_roots.is_empty())

func support_removal_gap(capture:Dictionary)->void:
	var results:Dictionary={}
	for name:String in ["reference","production"]:
		var built:=create_runtime(capture,name=="reference");prime(built)
		var selected:Dictionary={}
		for piece:Dictionary in built.building.structures().instances:
			if float(piece.hp)>0 and built.building.geometry.definition(piece).support=="terrain":selected=piece;break
		var box:AABB=built.building.geometry.bounds(selected)
		var at:=box.get_center();at.y=box.position.y-0.01
		var change:=voxel_op(built,at,0)
		expect("real foundation removal starts from solid material "+name,int(change.before)>0 and change.before!=change.after,change)
		var draft:Dictionary=built.world.prepare_changes([change],built.world.get_revision())
		expect("isolated C direct mutation creates a real revision gap "+name,draft.ok and built.world.commit_prepared(draft.capability).ok)
		built.building.meters()
		results[name]=built.building.validate_structures(built.world,built.building.structures(),built.runtime.facts())
		expect("old support cannot survive unannounced physical revision "+name,not results[name].ok and results[name].get("code")=="DEPENDENT" and built.building.meters().root_misses>0,results[name])
	expect("real removed foundation failure and reason equal full original",results.reference==results.production,results)

func sweep_pair()->void:
	var outcomes:Dictionary={}
	for name:String in ["reference","production"]:
		var w:=World.new();w.load_snapshot(Generator.generate(713))
		var b:RefCounted=Before.new() if name=="reference" else Candidate.new()
		var r:=Runtime.new()
		var outside:Dictionary={"x":29.2,"y":0,"z":40.2,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
		var friend:=resident("friend",{"x":25,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
		var f:Dictionary={"time":0.0,"status":"playing","actors":[resident("player",outside),friend],"stocks":[],"actions":[],"quests":[]}
		var services:Dictionary={"buildings":b,"actions":Actions.new(),"production":Production.new()}
		r.configure({"world":w,"facts":f,"services":services})
		var seeded:Dictionary=b.seed_rural(w);var draft:Dictionary=w.prepare_changes(seeded.world_changes,w.get_revision())
		expect("same real rural sweep fixture seeds "+name,draft.ok and w.commit_prepared(draft.capability).ok)
		r.configure({"world":w,"facts":f,"services":services})
		var spatial:Dictionary=b.validate_structures(w,b.structures(),r.facts())
		expect("all support roots actually established before sweep "+name,spatial.ok,spatial)
		var request:Dictionary={"actor_id":"player","kind":"door","target_id":"rural:v1:RH-HOME:old-house:yard-gate","payload":{"operation":"open"}}
		var before:Dictionary=r.capture_checkpoint();var current:Dictionary=r.facts();var rows:Array=[]
		rows.append(b.prepare_door(request,{},current))
		current.actors[1].merge({"x":27.6,"y":0,"z":40,"regionId":"RH-HOME","buildingId":null,"storeyId":null},true)
		rows.append(b.prepare_door(request,{},current))
		current.actors[1].hp=0;rows.append(b.prepare_door(request,{},current))
		current.actors[1].hp=100;current.actors[1].z=43;rows.append(b.prepare_door(request,{},current))
		current.actors[0].hp=0;rows.append(b.prepare_door(request,{},current))
		current.actors[0].hp=100;current.actors[0].x=35;rows.append(b.prepare_door(request,{},current))
		expect("moving living sweep/HP/acting position rechecked "+name,rows[0].ok and not rows[1].ok and rows[1].get("code")=="OCCUPIED" and rows[2].ok and rows[3].ok and not rows[4].ok and not rows[5].ok)
		expect("preflight dynamic failures leave authority untouched "+name,r.capture_checkpoint()==before)
		outcomes[name]=rows
	expect("every dynamic door result/negative reason equals full original",outcomes.reference==outcomes.production)

func run()->void:
	var started:=Time.get_ticks_msec()
	var prepared:Dictionary=Assembly.prepare(Generator.generate_settlement(973339546,Building.generation_profiles()))
	expect("actual rural source prepares",prepared.ok,prepared.get("reason"))
	if prepared.ok:
		rejection_cases(prepared.capture)
		accepted_invalidation(prepared.capture)
		revival_and_revision(prepared.capture)
		proof_invalidation(prepared.capture)
		support_removal_gap(prepared.capture)
	sweep_pair()
	finish(started)
