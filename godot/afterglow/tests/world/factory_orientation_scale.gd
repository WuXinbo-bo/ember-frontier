extends "res://tests/world/factory_scale.gd"
## Current explicit4/1 full finite-world evidence, separate from historical2.
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Roundtrip=preload("res://tests/world/fixtures/observed_coordinate_roundtrip.gd")
var before_digests:Dictionary={}
var before_plans:Dictionary={}
var restore_differences:Array=[]

func first_difference(a:Variant,b:Variant,path:String="plan")->Dictionary:
	if a is Dictionary and b is Dictionary:
		for key:Variant in a:
			if not b.has(key):return {"path":path+"."+str(key),"reason":"missing restored key"}
			var child:Dictionary=first_difference(a[key],b[key],path+"."+str(key))
			if not child.is_empty():return child
		if a.size()!=b.size():return {"path":path,"reason":"dictionary key count changed"}
	elif a is Array and b is Array:
		if a.size()!=b.size():return {"path":path,"before_size":a.size(),"after_size":b.size()}
		for i:int in a.size():
			var child:Dictionary=first_difference(a[i],b[i],path+"["+str(i)+"]")
			if not child.is_empty():return child
	elif a!=b:return {"path":path,"before":a,"after":b,"before_type":typeof(a),"after_type":typeof(b),"absolute_error":absf(float(a)-float(b)) if (a is int or a is float) and (b is int or b is float) else null}
	return {}

func region_digest(world:RefCounted,id:String)->Dictionary:
	var result:Dictionary=super.region_digest(world,id)
	var plan:Dictionary=world.extension("generation:"+id)
	var lock:Dictionary=world.extension(Factory.CONFIG_KEY)
	result.content4=lock.get("content_version")==4 and lock.get("story_clue_version")==1 and lock.get("parcel_orientation")=="road-court-v1"
	result.oriented_parcels=plan.parcels.size()
	result.whole_parcels_oriented=plan.parcels.all(func(p:Dictionary)->bool:return p.orientation.policy=="road-court-v1" and p.quarter_turn==1 and not p.entrance_ports.is_empty() and not p.npc_anchors.is_empty())
	if not before_digests.has(id):
		before_digests[id]=result.duplicate(true);before_plans[id]=plan
	else:
		var boundary:Dictionary=Roundtrip.compare(int(world.identity().seed),id,before_plans[id],plan)
		if not boundary.differences.is_empty() or not Data.json_equal(before_digests[id],result):restore_differences.append({"region":id,"before_digest":before_digests[id],"restored_digest":result,"bounded_roundtrip":boundary,"plans_json_equal":Data.json_equal(before_plans[id],plan)})
	return result

func run()->void:
	profiles=Catalog.profiles()
	var configured:Dictionary=Contract.fresh(profiles,4,1)
	check("current real profile catalogue resolves explicit4/1 policy",configured.ok)
	if not configured.ok:return finish()
	policy=configured.contract
	var first:Dictionary=build(false)
	check("current4 legal exploration reaches exact finite24-region lattice",first.ok and first.regions==24 and first.chunks==6144,first.get("reason"))
	if not first.ok:return finish()
	check("all24 current plans retain explicit immutable4/1 and complete transformed parcels",first.fingerprints.values().all(func(v:Dictionary)->bool:return v.content4 and v.whole_parcels_oriented),first.fingerprints)
	check("current4 every region keeps six spaces and unique entity ownership",first.six_spaces_all_resident_unique_entities)
	check("current4 full positive negative shared boundaries preserve ports and half-metre steps",first.adjacent_seams_ok and first.adjacent_seams==38,first.adjacent_seams)
	check("current4 finite capacity refuses25th without changing existing facts",first.capacity_refused)
	check("current4 decoded persistent24-region world restores strictly exactly",first.save_ok and first.decoded_restore_exact,{"code":first.save_code,"payload_bytes":first.payload_bytes})
	check("current4 bounded_roundtrip uses only exact indexed observations and unchanged Vector components",restore_differences.all(func(row:Dictionary)->bool:return row.bounded_roundtrip.ok),restore_differences)
	check("current4 pre-save locked worker remains valid at exact capacity boundary",first.future_locked_worker_code=="GENERATION_CAPACITY",first.future_locked_worker_code)
	var forward_differences:Array=restore_differences.duplicate(true)
	before_digests.clear();before_plans.clear();restore_differences.clear()
	var second:Dictionary=build(true)
	check("current4 opposite legal exploration reaches same actual24-region limit",second.ok and second.regions==24 and second.chunks==6144,second.get("reason"))
	if second.ok:
		check("current4 forward reverse preserve every exact raster plan lock and transformed parcel",Data.json_equal(first.fingerprints,second.fingerprints) and first.route!=second.route)
		check("current4 reverse keeps real seams ownership and capacity safety",second.six_spaces_all_resident_unique_entities and second.adjacent_seams_ok and second.capacity_refused)
		check("current4 reverse decoded persistent world restores strictly exactly",second.save_ok and second.decoded_restore_exact)
		check("current4 reverse bounded_roundtrip uses only exact approved leaves",restore_differences.all(func(row:Dictionary)->bool:return row.bounded_roundtrip.ok),restore_differences)
	costs={"forward":first,"reverse":second,"restore_differences":{"forward":forward_differences,"reverse":restore_differences},"scope":"current actual4/1 profiles, C24-region6144-chunk voxel/plan/native-codec scope; no actual B module registration/NPC/economy/render/RSS or package/performance acceptance; inherited generate_usec field is zero because historical runner used absent keys, use full_data_path_usec only"}
	finish()
