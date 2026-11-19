extends "res://tests/buildings/domain_suite.gd"
## Actual native ArrayMesh/GLB/material/cutaway checks; no screenshot claim.
const MeshBuilder=preload("res://scripts/buildings/building_mesh.gd")
const Details=preload("res://scripts/buildings/building_details.gd")

func content_fixture(view:Node3D,initial:Dictionary,stock_id:String,items:Dictionary,searched:bool=true)->MeshInstance3D:
	# Explicit rendering fixture in an existing real ground-drop stock. Source
	# records, live production and original assets remain untouched.
	var facts:=initial.duplicate(true)
	for stock:Dictionary in facts.stocks:
		stock.searched=stock.id==stock_id and searched
		if stock.id==stock_id:stock.items=items.duplicate(true)
	runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}})
	view.update_contents()
	for node:MeshInstance3D in view.get_node("Contents").get_children():
		if node.get_meta("piece",{}).get("id")==stock_id:return node
	return null

func surface_cells(mesh:Mesh,material:Material)->Array:
	var cells:Array=[]
	for surface in mesh.get_surface_count():
		if mesh.surface_get_material(surface)!=material:continue
		for uv:Vector2 in mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV]:
			var column:=int(floor(uv.x*4));var row:=int(floor(uv.y*4))
			if column not in range(4) or row not in range(4):return [-1]
			var low:=Vector2(column,row)*0.25+Vector2.ONE*(8.0/1024)
			var high:=Vector2(column+1,row+1)*0.25-Vector2.ONE*(8.0/1024)
			if uv.x<low.x-0.00001 or uv.y<low.y-0.00001 or uv.x>high.x+0.00001 or uv.y>high.y+0.00001:return [-1]
			var cell:=column+row*4
			if not cells.has(cell):cells.append(cell)
	cells.sort()
	return cells

func semantic_contents(view:Node3D,initial:Dictionary)->void:
	var drops:Array=initial.stocks.filter(func(s:Dictionary)->bool:return str(s.get("structureId","")).is_empty())
	if drops.is_empty():expect("actual empty ground stock exists for render fixture",false);return
	var id:String=drops[0].id
	var node:=content_fixture(view,initial,id,{"water":1})
	expect("actual water mesh binds protected A02 cell 3",node!=null and surface_cells(node.mesh,view.materials.grocery_atlas)==[3])
	node=content_fixture(view,initial,id,{"food":2})
	expect("actual two food meshes bind protected A02 cells 4 and 8",node!=null and surface_cells(node.mesh,view.materials.grocery_atlas)==[4,8])
	node=content_fixture(view,initial,id,{"book_woodwork":1})
	expect("actual woodworking book mesh binds protected A01 cell 0",node!=null and surface_cells(node.mesh,view.materials.book_atlas)==[0])
	node=content_fixture(view,initial,id,{"book_tool_repair":1})
	expect("actual repair book mesh binds protected A01 cell 1",node!=null and surface_cells(node.mesh,view.materials.book_atlas)==[1])
	node=content_fixture(view,initial,id,{"scrap":1})
	expect("actual scrap mesh uses metal and 0.12 by 0.06 by 0.18 metres",node!=null and mesh_contains(node,view.materials.painted_metal) and not mesh_contains(node,view.materials.grocery_atlas) and node.mesh.get_aabb().size.distance_to(Vector3(0.12,0.06,0.18))<0.00001)
	expect("zero stock produces no decorative content",content_fixture(view,initial,id,{"scrap":0,"water":0})==null)
	expect("unsearched stock reveals no hidden contents",content_fixture(view,initial,id,{"scrap":1,"water":1},false)==null)
	runtime.configure({"world":world,"facts":initial,"services":{"buildings":building,"actions":actions,"production":production}})
	view.update_contents();view.update_visibility()
func bindings(root:Node,materials:Dictionary,counts:Dictionary={},shown:bool=true)->Dictionary:
	if root is Node3D:shown=shown and root.visible
	if root is MeshInstance3D and root.mesh!=null:
		for n in root.mesh.get_surface_count():
			var material:Material=root.get_active_material(n)
			for id in materials:
				if materials[id]!=material:continue
				if not counts.has(id):counts[id]={"bound_surfaces":0,"visible_surfaces":0}
				counts[id].bound_surfaces+=1
				if shown:counts[id].visible_surfaces+=1
	for child in root.get_children():bindings(child,materials,counts,shown)
	return counts
func mesh_contains(root:Node,material:Material)->bool:
	if root is MeshInstance3D and root.mesh!=null:
		for n in root.mesh.get_surface_count():
			if root.mesh.surface_get_material(n)==material:return true
	for child in root.get_children():
		if mesh_contains(child,material):return true
	return false

func unsupported_roof_edges(view:Node3D)->Dictionary:
	var hidden:Array=[];var checked:=0
	var query:RefCounted=building.current_space()
	for node:MeshInstance3D in view.static_nodes.values():
		if node.get_meta("role")!="roof" or not node.visible:continue
		var roof:Dictionary=node.get_meta("piece")
		for wall:Dictionary in query.support_neighbors(roof).wall:
			checked+=1
			var full:=false
			for candidate:MeshInstance3D in view.static_nodes.values():
				if candidate.get_meta("role")!="wall" or not candidate.visible:continue
				if candidate.get_meta("piece_ids",[candidate.get_meta("piece").id]).has(wall.id):full=true;break
			if not full:hidden.append({"roof":roof.id,"wall":wall.id})
	return {"checked":checked,"hidden":hidden}

func run()->void:
	var started:=Time.get_ticks_msec()
	expect("actual rural world loads",world.load_snapshot(Generator.generate(713)).ok)
	var outside:Dictionary={"x":30,"y":0,"z":43,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	initialize_at(outside)
	var seeded:Dictionary=building.seed_rural(world)
	var draft:Dictionary=world.prepare_changes(seeded.world_changes,world.get_revision())
	expect("actual structures seed",draft.ok and world.commit_prepared(draft.capability).ok)
	initialize_at(outside,[],seeded.initial_stocks)
	var p:Dictionary=Production.empty_state();p.tools=seeded.initial_tools;p.records=seeded.initial_records
	draft=world.prepare_changes([building.extension_change(Production.KEY,p)],world.get_revision())
	expect("actual finite production registered",draft.ok and world.commit_prepared(draft.capability).ok)
	var original:=world.snapshot();var original_facts:=runtime.facts()
	var view:Node3D=building.create_view({"runtime":runtime})
	var home:="rural:v1:RH-HOME:old-house"
	var front:=home+":front-door"
	var roof_visible:=0;var skins:=0;var missing_materials:Array=[]
	for node in view.static_nodes.values():
		var piece:Dictionary=node.get_meta("piece")
		if piece.get("buildingId")==home and node.get_meta("role")=="roof" and node.visible:roof_visible+=1
		if piece.get("buildingId")==home and node.get_meta("role")=="floor":
			var bounds:AABB=node.mesh.get_aabb()
			if absf(bounds.end.y-0.012)<0.001:skins+=1
		for n in node.mesh.get_surface_count():
			if node.mesh.surface_get_material(n)==null:missing_materials.append(str(node.name))
	expect("exterior retains actual complete home roof",roof_visible>0)
	expect("interior floor skin separated from terrain by 12mm",skins>0)
	expect("actual static geometry has assigned materials",missing_materials.is_empty(),missing_materials)
	expect("unseen interior furniture stays hidden from exterior",not view.objects[home+":sleeping-place"].visible and not view.objects[home+":kitchen"].visible)
	var outside_bindings:=bindings(view,view.materials,{})
	var facts:=runtime.facts();facts.actors[0].merge({"x":18,"y":0,"z":36,"regionId":"RH-HOME","buildingId":home,"storeyId":home+":ground"},true)
	runtime.configure({"world":world,"facts":facts,"services":{"buildings":building,"actions":actions,"production":production}})
	view.update_visibility()
	var visible_roof:=0;var visible_floor:=0;var wrong_door_cap:=false;var wrong_door_trim:=false;var door_cap_count:=0;var entry_frames:=0
	for node in view.static_nodes.values():
		var piece:Dictionary=node.get_meta("piece")
		if piece.get("buildingId")!=home:continue
		if node.get_meta("role")=="roof" and node.visible:visible_roof+=1
		if node.get_meta("role")=="floor" and node.visible:visible_floor+=1
		if piece.id==front and node.get_meta("role")=="entry" and node.visible:entry_frames+=1
		if piece.id==front and node.get_meta("role")=="cap":
			door_cap_count+=1
			for surface in node.mesh.get_surface_count():
				for vertex in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					if vertex.x>18.21 and vertex.x<19.79 and vertex.y<0.66 and absf(vertex.z-38)<0.11:wrong_door_cap=true
		if piece.id==front and node.get_meta("role")=="wall":
			for surface in node.mesh.get_surface_count():
				if node.mesh.surface_get_material(surface)!=view.materials.wood_floor:continue
				for vertex in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					if vertex.x>18.21 and vertex.x<19.79 and vertex.y>0.02 and vertex.y<0.141 and absf(vertex.z-38)>0.11:wrong_door_trim=true
	expect("interior cutaway keeps floor and covers unseen adjacent rooms",visible_roof>0 and visible_roof<roof_visible and visible_floor>0,{"outside":roof_visible,"inside":visible_roof})
	var roof_edges:=unsupported_roof_edges(view)
	expect("opaque retained room roofs keep their actual supporting walls",roof_edges.checked>0 and roof_edges.hidden.is_empty(),roof_edges)
	expect("front cutaway removes the whole leaf without a short substitute",not view.doors[front].has("cut") and not view.doors[front].full.visible)
	expect("cut doorway retains only the actual entry outline with no wall cap",entry_frames>0 and door_cap_count==0 and not wrong_door_cap)
	expect("door base trim does not create a board across the opening",not wrong_door_trim)
	expect("unknown other side of partition hides sleeping place",not view.objects[home+":sleeping-place"].visible)
	expect("same room actual cabinet remains visible",view.objects[home+":storage"].visible)
	var inside_facts:=runtime.facts()
	for point:Vector2 in [Vector2(18,36),Vector2(12,35.5),Vector2(12,29.5),Vector2(20,29.5),Vector2(30,43)]:
		var feet:Dictionary=building.current_space().standing_point({"x":point.x,"y":0,"z":point.y,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
		expect("cutaway station is physically clear "+str(point),not feet.is_empty())
		if feet.is_empty():continue
		var at:=inside_facts.duplicate(true);at.actors[0].merge(feet,true)
		expect("actual cutaway station configures "+str(point),runtime.configure({"world":world,"facts":at,"services":{"buildings":building,"actions":actions,"production":production}}).ok)
		view.update_visibility()
		var retained:=unsupported_roof_edges(view)
		expect("moving room cutaway retains actual roof supports "+str(point),retained.checked>0 and retained.hidden.is_empty(),retained)
	runtime.configure({"world":world,"facts":inside_facts,"services":{"buildings":building,"actions":actions,"production":production}})
	view.update_visibility()
	# Surface contract: 4x4 atlas rows and protected borders must not bleed.
	var mb:=MeshBuilder.new();mb.box(AABB(Vector3.ZERO,Vector3.ONE),Transform3D.IDENTITY,"atlas",1,5)
	var uvs:PackedVector2Array=mb.groups.atlas.uv
	expect("atlas cell 5 uses integer second row and guard band",Array(uvs).all(func(v:Vector2)->bool:return v.x>=0.2578 and v.x<=0.4922 and v.y>=0.2578 and v.y<=0.4922))
	var distinct:=MeshBuilder.new();distinct.box(AABB(Vector3.ZERO,Vector3(2,0.4,2)),Transform3D.IDENTITY,"side",1.6,-1,"top",2)
	expect("floor top and foundation sides use separate material groups",distinct.groups.has("top") and distinct.groups.has("side") and distinct.groups.top.v.size()==4 and distinct.groups.side.v.size()==20)
	var decal:=MeshBuilder.new();Details.ground_decal(decal,Transform3D.IDENTITY,"threshold",Vector3(0,0.006,0),Vector2(1.45,0.65))
	expect("actual threshold decal remains above floor skin",Array(decal.groups.threshold.v).all(func(v:Vector3)->bool:return v.y>0.012 and v.y<0.025))
	var full_damage:=MeshBuilder.new();var cut_damage:=MeshBuilder.new()
	Details.damaged_leaf(full_damage);Details.damaged_leaf(cut_damage,0.65)
	var full_group:Dictionary=full_damage.groups.damaged_wood;var cut_group:Dictionary=cut_damage.groups.damaged_wood
	var exact_damage_uv:=true
	for group:Dictionary in [full_group,cut_group]:
		for i in group.v.size():
			var vertex:Vector3=group.v[i];var uv:Vector2=group.uv[i]
			if absf(uv.x-(vertex.x-0.475)/0.65)>0.00001 or absf(uv.y-(1-(vertex.y-0.225)/0.65))>0.00001 or absf(absf(vertex.z)-0.048)>0.00001:exact_damage_uv=false
	expect("D11 full 0.65m canvas and cutaway retain exact unclamped UV mapping",full_group.v.size()==8 and cut_group.v.size()==8 and exact_damage_uv and Array(cut_group.v).all(func(v:Vector3)->bool:return v.y<=0.65))
	# This legacy D11 fixture is not attached to a real mesh in this scene.
	# Explicit catalogue inspection must request its demand-loaded resource.
	var damage_material:StandardMaterial3D=view.material("damaged_wood")
	expect("D11 is real alpha blend on original unchanged 1024 RGBA resource",damage_material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA and damage_material.albedo_texture.get_size()==Vector2(1024,1024))
	var inside_bindings:=bindings(view,view.materials,{})
	expect("actual material bindings recorded for both derived camera states",outside_bindings.get("b_roof_aged",{}).get("visible_surfaces",0)>0 and inside_bindings.get("wood_floor",{}).get("visible_surfaces",0)>0,{"outside":outside_bindings,"inside":inside_bindings,"instantiated_models":view.models.keys(),"static_batches":view.static_nodes.size()})
	semantic_contents(view,runtime.facts())
	expect("presentation never changes actual world or gameplay facts",world.snapshot()==original and runtime.facts().stocks==original_facts.stocks)
	view.free()
	finish(started)
