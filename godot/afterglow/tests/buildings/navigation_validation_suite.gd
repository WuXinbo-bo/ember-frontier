extends "res://tests/buildings/domain_suite.gd"
const Navigation=preload("res://scripts/buildings/building_navigation.gd")
class ControlledNavigation extends "res://scripts/buildings/building_navigation.gd":
	var reject_all:=false
	var evaluated:Dictionary={}
	func edge(a:int,b:int)->Dictionary:
		var key:=str(a)+":"+str(b)
		if evaluated.has(key):return evaluated[key]
		# Explicit directed-cost fixture for the native graph strategy. Actual
		# body/terrain/door predicates are tested by cold legacy/NPC suites.
		var ok:bool=not reject_all and (a!=0 or b==71)
		evaluated[key]={"ok":ok,"steps":[{"kind":"move","to":nodes[b]}] if ok else []}
		return evaluated[key]

func graph_fixture(reject_all:bool=false)->RefCounted:
	var nav:=ControlledNavigation.new();nav.reject_all=reject_all
	nav.space=preload("res://scripts/buildings/building_space.gd").new()
	nav.graph=Navigation.FilteredGraph.new();nav.graph.owner_query=weakref(nav)
	for i in 72:
		var p:Dictionary={"x":0.0 if i==0 else 1.0 if i==1 else 0.5,"y":0.0,"z":0.0 if i<2 else float(i-1),"regionId":"fixture","buildingId":null,"storeyId":null}
		nav.nodes.append(p);nav.graph.add_point(i,Geometry.point(p))
	for i in range(2,72):nav.graph.connect_points(0,i);nav.graph.connect_points(i,1)
	return nav

func run()->void:
	var started:=Time.get_ticks_msec();var nav:RefCounted=graph_fixture()
	var route:Dictionary=nav.verified_path()
	expect("unproven short candidates never escape exact edge validation",route.ok and route.steps.size()==2 and route.steps[0].to==nav.nodes[71] and route.steps[1].to==nav.nodes[1],route)
	expect("dense rejection switches to original native eager filter",nav.graph.neighbor_filter_enabled and nav.search_passes==65,nav.search_passes)
	expect("failed direction removal retains independent reverse edge",not nav.graph.are_points_connected(0,2,false) and nav.graph.are_points_connected(2,0,false))
	var denied:RefCounted=graph_fixture(true);var failure:Dictionary=denied.verified_path()
	expect("all invalid alternatives return rejection after exact fallback",not failure.ok and denied.graph.neighbor_filter_enabled and denied.search_passes==65,failure)
	finish(started)
