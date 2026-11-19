extends RefCounted
## Hierarchical native AStar over C's real shared faces. Edges reuse B's
## existing local body/door/stair planner; region metadata is never a portal.
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
var query:RefCounted
var actor_id:String
var nodes:Array=[]
var pairs:Dictionary={}
var edges:Dictionary={}
var graph:=AStar3D.new()

func add(at:Dictionary)->int:
	nodes.append(at.duplicate(true));var id:=nodes.size()-1
	graph.add_point(id,Geometry.point(at));return id

func plan(space:RefCounted,actor:String,from:Dictionary,to:Dictionary)->Dictionary:
	query=space;actor_id=actor
	if not query.world.has_method("continuous_outdoor_neighbors"):return bad("连续邻接尚未装配")
	var start:Dictionary=query.standing_point(from);var finish:Dictionary=query.standing_point(to)
	if start.is_empty() or finish.is_empty() or Geometry.point(start).distance_to(Geometry.point(from))>0.025:return bad("起终点无合法身体支撑")
	add(start);add(finish)
	var seen:Dictionary={};var queue:Array=[str(from.regionId)];var faces:Array=[]
	while not queue.is_empty():
		var region:String=queue.pop_front()
		if seen.has(region):continue
		if seen.size()>=16:return bad("连续地区搜索超过有限预算")
		seen[region]=true
		for link:Dictionary in query.world.continuous_outdoor_neighbors(region):
			if not seen.has(link.to_region_id):queue.append(str(link.to_region_id));faces.append(link)
	if not seen.has(str(to.regionId)):return bad("实际生成地区之间没有连续共享面")
	var unique:Dictionary={}
	for link:Dictionary in faces:
		var key:=str([link.from_region_id,link.to_region_id])
		var reverse:=str([link.to_region_id,link.from_region_id])
		if unique.has(reverse):continue
		unique[key]=true
		for pair:Array in crossings(link,start,finish):
			var a:=add(pair[0]);var b:=add(pair[1])
			graph.connect_points(a,b);pairs[str(a)+":"+str(b)]=true;pairs[str(b)+":"+str(a)]=true
	for i in nodes.size():
		for j in range(i+1,nodes.size()):
			if nodes[i].regionId==nodes[j].regionId:graph.connect_points(i,j)
	# Optimistic topology is never safety evidence. Failed directed local edges
	# are removed, with a fixed work bound; all accepted steps are original B
	# proofs, including both sides of each C resident boundary.
	for attempt in 96:
		var ids:=graph.get_id_path(0,1)
		if ids.is_empty():return bad("连续路径被真实墙门地形或权限阻断")
		var valid:=true
		for n in range(1,ids.size()):
			var key:=str(ids[n-1])+":"+str(ids[n])
			if not edges.has(key):edges[key]=query.route(actor_id,nodes[ids[n-1]],nodes[ids[n]])
			if not edges[key].ok:graph.disconnect_points(ids[n-1],ids[n],false);valid=false;break
		if not valid:continue
		var steps:Array=[]
		for n in range(1,ids.size()):steps.append_array(edges[str(ids[n-1])+":"+str(ids[n])].steps)
		return {"ok":true,"steps":steps,"regions":seen.keys(),"visited":edges.size()}
	return bad("连续路径局部证明达到有界预算")

func crossings(link:Dictionary,start:Dictionary,finish:Dictionary)->Array:
	var result:Array=[];var face:Dictionary=link.face
	var axis:String=face.axis;var tangent:String="z" if axis=="x" else "x"
	var low:float=face.min[tangent]+0.6;var high:float=face.max[tangent]-0.6
	if high<=low:return result
	var projected:=clampf((float(start[tangent])+float(finish[tangent]))/2,low,high)
	var candidates:Array=[projected,clampf(float(start[tangent]),low,high),clampf(float(finish[tangent]),low,high),(low+high)/2,lerpf(low,high,0.25),lerpf(low,high,0.75)]
	for n in range(1,14):candidates.append(clampf(projected+n*2,low,high));candidates.append(clampf(projected-n*2,low,high))
	var bounds:Dictionary=query.world.region(str(link.from_region_id)).bounds
	var sign:=1.0 if is_equal_approx(float(bounds.max[axis]),float(face.coordinate)) else -1.0
	var checked:Dictionary={}
	for coordinate:float in candidates:
		if checked.has(coordinate):continue
		checked[coordinate]=true
		var a:Dictionary={"regionId":str(link.from_region_id),"buildingId":null,"storeyId":null,"x":0.0,"y":0.0,"z":0.0}
		a[axis]=float(face.coordinate)-sign*0.34;a[tangent]=coordinate
		var b:=a.duplicate(true);b.regionId=str(link.to_region_id);b[axis]=float(face.coordinate)+sign*0.34
		var ground_a:Variant=query.world.surface_height(a.x,a.z);var ground_b:Variant=query.world.surface_height(b.x,b.z)
		if ground_a==null or ground_b==null:continue
		a.y=float(ground_a);b.y=float(ground_b)
		var feet_a:Dictionary=query.standing_point(a);var feet_b:Dictionary=query.standing_point(b)
		if feet_a.is_empty() or feet_b.is_empty() or feet_a.get("buildingId")!=null or feet_b.get("buildingId")!=null:continue
		var proof:Dictionary=query.world.continuous_outdoor_step(feet_a,feet_b)
		if not proof.ok or not query.walk(actor_id,feet_a,feet_b,true).ok:continue
		result.append([feet_a,feet_b])
		if result.size()>=8:break
	return result

static func bad(reason:String)->Dictionary:return {"ok":false,"code":"UNREACHABLE","reason":reason,"steps":[]}
