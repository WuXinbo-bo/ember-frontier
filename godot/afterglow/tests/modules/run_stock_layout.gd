extends SceneTree
## Real owner DTO -> real D consumer, with explicit finite stock fixtures.
## No renderer, save slot, import/export or normal-economy qualification.
const Modules=preload("res://scripts/modules/module_service.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Layout=preload("res://scripts/modules/module_stock_layout.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Generator=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const View=preload("res://scripts/presentation/factory_view.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
var checks:Array=[]
var measurements:Array=[]
func _initialize()->void:call_deferred("run")
func check(name:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+name+" "+str(detail))
func run()->void:
	for d:Dictionary in Catalog.definitions():
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
	for version:int in [2,3]:
		var lock:Dictionary=Contract.fresh(Catalog.profiles(),version)
		var generated:Dictionary=Assembly.prepare(Generator.generate(713,Catalog.profiles(),lock.contract))
		check("actual content opening "+str(version),generated.ok,generated.get("reason"))
		if not generated.ok:continue
		var source:Dictionary=generated.capture.duplicate(true)
		for v:Dictionary in source.world.extensions[Modules.KEY].instances:
			if v.region!="RH-HOME":continue
			for b:Dictionary in Catalog.definition(v.definition_id).buffer_specs:
				for stock:Dictionary in source.facts.stocks:
					if stock.id!=v.stock_refs[b.id]:continue
					stock.searched=true;stock.items=b.limits.duplicate(true)
		var home:Dictionary=source.world.extensions[Modules.KEY].instances.filter(func(v:Dictionary)->bool:return v.region=="RH-HOME" and Catalog.definition(v.definition_id).shape=="home")[0]
		var use:Dictionary=Shape.ports(home,Catalog.definition(home.definition_id))[0].location
		var player:=Draft.find(source.facts.actors,"player");player.x=use.x;player.y=use.y;player.z=use.z;player.regionId=home.region
		var host:=Native.new();var mounted:Dictionary=host._assemble(source)
		check("finite full-stock fixture passes original Native validators "+str(version),mounted.ok,mounted.get("reason"))
		if not mounted.ok:host.free();continue
		var before:Dictionary=mounted.runtime.capture_checkpoint();var view:=View.new();root.add_child(view);view.configure(mounted.runtime)
		check("same public snapshot drives actual stock consumer "+str(version),view.statistics().required_errors.is_empty() and not view.statistics().buffers.is_empty(),view.statistics().required_errors)
		var actual:Dictionary={};var visible:bool=true
		for row:Dictionary in mounted.runtime.factory_snapshot().modules.instances:
			for b:Dictionary in row.visuals.buffers:actual[row.id+":"+b.id]=b.actual
		for row:Dictionary in view.statistics().buffers:
			visible=visible and actual.get(row.module_id+":"+row.buffer_id,-1)==row.stock.actual and row.stock.visible_parts==9
		check("only true full quantities produce full proxies "+str(version),visible)
		var terrain_ok:=true;var meshes_ok:=true;var mesh_issues:Array=[]
		for module:Dictionary in mounted.runtime.factory_snapshot().modules.instances:
			var definition:Dictionary=Catalog.definition(module.definition_id);var plan:=Layout.local_plan(definition)
			for b:Dictionary in module.visuals.buffers:
				var anchor:Dictionary=module.visuals.anchors[b.anchor_id];var p:=Vector3(anchor.position[0],anchor.position[1],anchor.position[2]);var extent:=Vector3(b.extent[0],b.extent[1],b.extent[2])
				var box:=Layout._bounds(p,int(anchor.quarter_turn),extent)
				if plan[b.id].support=="ground":terrain_ok=terrain_ok and mounted.services.buildings.current_space().terrain_supports(module.region,box)
				var stock:Node3D=view._buffers[module.id][b.id]
				var bottom:=INF
				for mesh:MeshInstance3D in stock.get_children():
					if not mesh.visible:continue
					var bounds:AABB=mesh.global_transform*mesh.get_aabb()
					bottom=minf(bottom,bounds.position.y)
					if not box.grow(0.001).encloses(bounds):mesh_issues.append({"module":module.id,"buffer":b.id,"issue":"outside_bay","world_bounds":G.json_box(bounds),"bay":G.json_box(box)})
					meshes_ok=meshes_ok and box.grow(0.001).encloses(bounds)
				if absf(bottom-p.y)>=0.001:mesh_issues.append({"module":module.id,"buffer":b.id,"issue":"unsupported_bottom","gap":bottom-p.y})
				meshes_ok=meshes_ok and absf(bottom-p.y)<0.001
		check("real generated terrain supports every ground bay "+str(version),terrain_ok)
		check("actual consumer mesh fits world bay and touches its true support "+str(version),meshes_ok,mesh_issues)
		check("real consumer and repeated layout queries never mutate authority "+str(version),Data.json_equal(before,mounted.runtime.capture_checkpoint()))
		var copy:=Layout.local_plan(Catalog.definitions()[0]);copy.clear()
		check("caller cannot poison cached layout "+str(version),not Layout.local_plan(Catalog.definitions()[0]).is_empty())
		var rt:RefCounted=mounted.runtime;var stock_id:String=home.stock_refs.supplies;var food:float=rt.stock(stock_id).items.food
		var taken:Dictionary=rt.command({"kind":"take","command_id":"B:stock:empty","actor_id":"player","target_id":stock_id,"payload":{"items":{"food":food}}});view.sync()
		check("actual take empties display with zero phantom goods "+str(version),taken.ok and view._buffers[home.id]["supplies:food"].statistics().visible_parts==0,taken.get("code"))
		var deposited:Dictionary=rt.command({"kind":"deposit","command_id":"B:stock:one","actor_id":"player","target_id":stock_id,"payload":{"items":{"food":1}}});view.sync()
		check("actual single item shows only the low band "+str(version),deposited.ok and view._buffers[home.id]["supplies:food"].statistics().visible_parts==1,deposited.get("code"))
		var cold_host:=Native.new();var restored:Dictionary=cold_host._assemble(rt.capture_checkpoint())
		check("quantity and stable metre bays survive actual cold assembly "+str(version),restored.ok and Data.json_equal(restored.services.modules.projection(),mounted.services.modules.projection()),restored.get("reason"))
		var manual:Dictionary=mounted.services.modules.state().instances.filter(func(v:Dictionary)->bool:return v.region=="RH-HOME" and Catalog.definition(v.definition_id).shape=="manual")[0]
		var old_stock:String=manual.stock_refs.tools;var items:Dictionary=rt.stock(old_stock).items.duplicate(true)
		var damage:Dictionary=rt._commit(mounted.services.modules.prepare_damage(manual.id,1000,"B:stock:ruin"));view.sync()
		var ruined:Dictionary=mounted.services.modules.instance(manual.id)
		check("actual ruin rebinds original quantities to ground cargo without shelf ghosts "+str(version),damage.ok and ruined.status=="ruined" and ruined.stock_refs.tools!=old_stock and rt.stock(ruined.stock_refs.tools).items==items and view.statistics().required_errors.is_empty() and view._buffers[manual.id]["tools:timber"].global_position.y==manual.position.y,damage.get("code"))
		cold_host.free()
		view.free();host.free()
	var ok:bool=checks.all(func(c:Dictionary)->bool:return c.ok)
	print(JSON.stringify({"ok":ok,"checks":checks,"measurements":measurements,"scope":"real owner/native/source geometry and D consumer; explicit stock fixture, no OS/VA/performance acceptance"}));quit(0 if ok else 1)
