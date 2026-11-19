extends "res://tests/buildings/domain_suite.gd"
## Existing C/B/A assembly, multiple generated buildings at their real heights.
## Isolated in-memory observations/codec; no formal app, player route or VA.
const Assembly=preload("res://scripts/runtime/settlement_assembly.gd")
const Policy=preload("res://scripts/presentation/interior_view_policy.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
var coverage:Array=[]

func run()->void:
	var started:int=Time.get_ticks_msec()
	for seed:int in [713,2026]:
		var result:Dictionary=Assembly.prepare(Assembly.generate(seed,Building.generation_profiles()))
		expect("real generated composition accepted seed "+str(seed),result.ok,{"code":result.get("code"),"reason":result.get("reason")})
		if not result.ok:continue
		if not install_capture(result.capture,seed):continue
		var query:RefCounted=building.current_space()
		var before:Dictionary=runtime.capture_checkpoint()
		var observations:Dictionary=inspect_rooms(query,seed)
		expect("generated policy reads leave all authority unchanged seed "+str(seed),Data.json_equal(before,runtime.capture_checkpoint()))
		var encoded:Dictionary=Store.encode(before)
		var decoded:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
		expect("native codec retains generated world seed "+str(seed),decoded.ok,decoded.get("reason"))
		if not decoded.ok or not install_capture(decoded.capture,seed):continue
		query=building.current_space()
		var restored:Dictionary=projection_at(query,observations.stations)
		expect("all building room cuts and roof groups survive native codec seed "+str(seed),Data.json_equal(observations.projections,restored),{"rooms":restored.size()})
		expect("read-only restoration never reseeds buildings or stocks seed "+str(seed),building.prepare_generation(world).code=="ALREADY_SEEDED")
		missing_roof(query,seed)
	finish(started)

func install_capture(capture:Dictionary,seed:int)->bool:
	var loaded:Dictionary=world.load_snapshot(capture.world)
	var installed:Dictionary=runtime.configure({"world":world,"facts":capture.facts,"services":{"buildings":building,"actions":actions,"production":production}}) if loaded.ok else loaded
	expect("same authority loads generated presentation fixture seed "+str(seed),installed.ok,installed.get("reason"))
	return installed.ok

func wall_set(policy:RefCounted,query:RefCounted)->Array:
	var ids:Array=[]
	for piece:Dictionary in query.pieces:
		if policy.cut_wall(piece):ids.append(piece.id)
	ids.sort();return ids

func projection(policy:RefCounted,query:RefCounted,at:Dictionary)->Dictionary:
	var hidden:Array=[]
	for roof:Dictionary in policy._rooms.roofs:
		if roof.regionId==at.regionId and roof.buildingId==at.buildingId and roof.storeyId==at.storeyId and not policy.base_visible(roof,"roof"):hidden.append(roof.id)
	hidden.sort()
	return {"room_id":policy.statistics().room_id,"cuts":wall_set(policy,query),"hidden_roofs":hidden}

func inspect_rooms(query:RefCounted,seed:int)->Dictionary:
	var policy:=Policy.new();policy.configure(query)
	var rooms:Dictionary={};var buildings:Dictionary={};var elevations:Dictionary={}
	for roof:Dictionary in policy._rooms.roofs:
		var feet:Dictionary=query.standing_point(policy._rooms.room_point(roof))
		if feet.is_empty() or feet.get("buildingId")!=roof.buildingId or feet.get("storeyId")!=roof.storeyId:continue
		var key:String=str(roof.buildingId)+"|"+str(policy._rooms.component_at(feet))
		if not rooms.has(key):rooms[key]=[]
		rooms[key].append(feet);buildings[roof.buildingId]=true;elevations[str(feet.y)]=true
	expect("all five actual generated buildings supply supported room stations seed "+str(seed),buildings.size()==5,{"buildings":buildings.keys(),"elevations":elevations.keys()})
	expect("generated interior observations retain nonzero varied elevations seed "+str(seed),elevations.size()>1 and elevations.keys().any(func(y:String)->bool:return float(y)!=0.0),elevations.keys())
	var unstable:Array=[];var roof_errors:Array=[];var foreign_errors:Array=[];var stations:Dictionary={};var projections:Dictionary={};var count:int=0;var supported_count:int=0
	for key:String in rooms:
		var points:Array=rooms[key];var first:Dictionary=points[0]
		policy.sample(first,count*200);count+=1;policy.sample(first,count*200)
		var expected:Dictionary=projection(policy,query,first)
		stations[key]=first.duplicate(true);projections[key]=expected
		for at:Dictionary in points:
			supported_count+=1
			count+=1;policy.sample(at,count*200)
			if not Data.json_equal(expected,projection(policy,query,at)):unstable.append(at)
			for roof:Dictionary in policy._rooms.roofs:
				if roof.regionId!=at.regionId:continue
				if roof.buildingId==at.buildingId and roof.storeyId==at.storeyId and policy.base_visible(roof,"roof"):roof_errors.append(roof.id)
				elif roof.buildingId!=at.buildingId and not policy.base_visible(roof,"roof"):foreign_errors.append(roof.id)
	expect("every supported station keeps structural room cuts stable seed "+str(seed),unstable.is_empty(),{"stations":supported_count,"rooms":rooms.size(),"unstable":unstable})
	expect("occupied generated storey hides its complete pitched roof seed "+str(seed),roof_errors.is_empty(),roof_errors)
	expect("generated cutaway leaves other buildings intact seed "+str(seed),foreign_errors.is_empty(),foreign_errors)
	coverage.append({"seed":seed,"buildings":buildings.keys(),"room_groups":rooms.size(),"stations":supported_count,"floor_elevations":elevations.keys()})
	return {"stations":stations,"projections":projections}

func projection_at(query:RefCounted,stations:Dictionary)->Dictionary:
	var result:Dictionary={};var policy:=Policy.new();policy.configure(query);var now:int=0
	for key:String in stations:
		var at:Dictionary=stations[key]
		now+=200;policy.sample(at,now);now+=200;policy.sample(at,now)
		result[key]=projection(policy,query,at)
	return result

func missing_roof(query:RefCounted,seed:int)->void:
	var policy:=Policy.new();policy.configure(query)
	var roof:Dictionary={};var at:Dictionary={}
	for candidate:Dictionary in policy._rooms.roofs:
		at=query.standing_point(policy._rooms.room_point(candidate))
		if not at.is_empty() and at.get("buildingId")==candidate.buildingId:roof=candidate.duplicate(true);break
	expect("generated roof hole fixture has real supported feet seed "+str(seed),not roof.is_empty())
	if roof.is_empty():return
	# Explicit isolated damaged-roof facts through B's entity/extension adapter.
	# This is not a claim that a player dismantling route was performed.
	roof.hp=0.0;roof.version=int(roof.version)+1
	var structures:Dictionary=building.structures()
	for i:int in structures.instances.size():
		if structures.instances[i].id==roof.id:structures.instances[i]=roof
	var changes:Array=building.changes_for(structures,[roof],[])
	var draft:Dictionary=world.prepare_changes(changes,world.get_revision())
	var safe:Dictionary=building.validate_world_draft(draft.view,runtime.facts(),changes) if draft.ok else draft
	expect("actual C/B accepts isolated damaged roof facts seed "+str(seed),safe.ok,safe.get("reason"))
	if not safe.ok:
		if draft.ok:world.discard_prepared(draft.capability)
		return
	expect("damaged roof fixture commits once seed "+str(seed),world.commit_prepared(draft.capability).ok)
	query=building.current_space();policy.configure(query);policy.sample(at,0)
	var before:Dictionary=runtime.capture_checkpoint()
	var remaining:Array=policy._rooms.roofs.filter(func(v:Dictionary)->bool:return v.buildingId==roof.buildingId and v.storeyId==roof.storeyId)
	expect("standing under real missing tile keeps all remaining storey roofs open seed "+str(seed),not remaining.is_empty() and remaining.all(func(v:Dictionary)->bool:return not policy.base_visible(v,"roof")),{"roof_id":roof.id,"standing":at,"remaining":remaining.size()})
	expect("missing tile projection preserves damaged facts seed "+str(seed),Data.json_equal(before,runtime.capture_checkpoint()))

func finish(started:int)->void:
	print("DDD_GENERATED_INTERIOR "+JSON.stringify({"scope":"real rural-2 C/B/A composition and native in-memory codec; not formal app/player route/VA","ok":failures.is_empty(),"checks":checks,"failures":failures,"coverage":coverage,"elapsed_ms":Time.get_ticks_msec()-started}))
	quit(0 if failures.is_empty() else 1)
