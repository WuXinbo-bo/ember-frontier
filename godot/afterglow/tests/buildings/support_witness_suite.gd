extends "res://tests/buildings/domain_suite.gd"
## Adversarial topology isolates cycle/ancestry/slab semantics; actual-city
## geometry and authority are separately exercised by legacy/cold comparison.
class Topology extends "res://scripts/buildings/building_space.gd":
	var adjacency:Dictionary={}
	var sample_map:Dictionary={}
	var ground:=true
	func bounds(_v:Dictionary)->AABB:return AABB(Vector3.ZERO,Vector3.ONE)
	func support_neighbors(v:Dictionary)->Dictionary:return adjacency.get(v.id,{"wall":[],"slab":[]})
	func support_walls(v:Dictionary)->Array:return support_neighbors(v).wall
	func support_slabs(v:Dictionary)->Array:return support_neighbors(v).slab
	func terrain_supports(_region:String,_footprint:AABB)->bool:return ground
class ReferenceSupport extends "res://tests/buildings/cold_reference/building_service.gd":
	func surface_support_samples(query:RefCounted,v:Dictionary,_b:AABB)->Array:return query.sample_map.get(v.id,[])
class CandidateSupport extends "res://scripts/buildings/building_service.gd":
	func surface_support_samples(query:RefCounted,v:Dictionary,_b:AABB)->Array:return query.sample_map.get(v.id,[])

func fixture(service:RefCounted,ground:bool=true)->RefCounted:
	service.geometry.configure({"structure_definitions":{"floor":{"kind":"floor","support":"wall-top"},"foundation":{"kind":"foundation","support":"terrain"},"wall":{"kind":"wall","support":"surface"}}})
	var q:=Topology.new();q.geometry=service.geometry;q.ground=ground
	for id in ["a","b","c","d","e","f","ground","beam","broken-beam"]:
		var v:Dictionary={"id":id,"hp":100,"position":{"x":0,"y":0,"z":0},"definitionId":"foundation" if id=="ground" else "wall" if "beam" in id else "floor","regionId":"fixture","storeyId":"fixture:level"}
		q.by_id[id]=v;q.pieces.append(v)
	q.adjacency={"a":{"wall":[],"slab":[q.by_id.b]},"b":{"wall":[],"slab":[q.by_id.c]},"c":{"wall":[q.by_id.ground],"slab":[]},"d":{"wall":[],"slab":[q.by_id.a]},"e":{"wall":[],"slab":[q.by_id.f]},"f":{"wall":[],"slab":[q.by_id.e]}}
	q.sample_map={"beam":[{"ground":false,"pieces":[q.by_id.a]}],"broken-beam":[{"ground":false,"pieces":[q.by_id.a]},{"ground":false,"pieces":[q.by_id.e]}]}
	return q

func run()->void:
	var started:=Time.get_ticks_msec();var old:=ReferenceSupport.new();var candidate:=CandidateSupport.new()
	var oq:RefCounted=fixture(old);var nq:RefCounted=fixture(candidate)
	expect("three slabs with direct final wall support remain legal",candidate.supported(nq,nq.by_id.a) and old.supported(oq,oq.by_id.a))
	expect("warm proof cannot exceed incoming slab budget",not candidate.supported(nq,nq.by_id.d) and not old.supported(oq,oq.by_id.d))
	expect("warm proof cannot pass an ancestor dependency cycle",not candidate.supported(nq,nq.by_id.a,{"ground":true}) and not old.supported(oq,oq.by_id.a,{"ground":true}))
	expect("mutually unsupported slabs stay unsupported",not candidate.supported(nq,nq.by_id.e) and not old.supported(oq,oq.by_id.e))
	expect("every footprint sample must have independent real support",not candidate.supported(nq,nq.by_id["broken-beam"]) and not old.supported(oq,oq.by_id["broken-beam"]))
	var mismatches:Array=[];var comparisons:=0
	var ids:Array=nq.by_id.keys()
	# Warm successful AND/OR proofs, then exercise every subset of the actual
	# ancestors in reversed order. This includes self, dependency, irrelevant
	# slab-budget, cycle and failed-then-successful cases.
	for i in ids.size():candidate.supported(nq,nq.by_id[ids[i]])
	for mask in range(1<<ids.size()):
		var visited:Dictionary={}
		for i in ids.size():
			if mask&(1<<i):visited[ids[i]]=true
		for i in range(ids.size()-1,-1,-1):
			var id:String=ids[i];comparisons+=1
			var before:bool=old.supported(oq,oq.by_id[id],visited,{})
			var after:bool=candidate.supported(nq,nq.by_id[id],visited,{})
			if before!=after and mismatches.size()<20:mismatches.append({"id":id,"visited":visited.duplicate(),"before":before,"after":after})
	expect("all 4608 warmed ancestry combinations equal frozen original",comparisons==4608 and mismatches.is_empty(),mismatches)
	var changed:RefCounted=fixture(candidate,false);var changed_old:RefCounted=fixture(old,false)
	expect("new terrain projection cannot inherit positive witnesses",not candidate.supported(changed,changed.by_id.a) and not old.supported(changed_old,changed_old.by_id.a))
	finish(started)
