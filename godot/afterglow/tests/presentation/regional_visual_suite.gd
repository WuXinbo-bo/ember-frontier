extends SceneTree
## Finite explicit DTO consumer tests. Not ecology-owner/OS/GPU/VA acceptance.
const Planning=preload("res://scripts/presentation/planning_visual.gd")
const Ecology=preload("res://scripts/presentation/ecology_visual.gd")
var checks:Array=[]
var failures:Array=[]
func expect(label:String,ok:bool,detail:Variant={})->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:failures.append(label)
func _initialize()->void:call_deferred("run")
func crop(id:String,x:int=0,kind:String="crop")->Dictionary:
	return {"id":id,"region_id":"region:a","location":{"x":x*.5+.25,"y":.5,"z":.25,"regionId":"region:a"},"cell":{"x":x,"y":1,"z":0},"kind":kind,"crop_id":"potato","tree_id":"broadleaf","stage":"seedling","moisture":0,"fertility":2,"known":true,"resident":true,"visible":true,"revision":1}
func visible_materials(view:Node3D)->Array:
	var names:Array=[]
	for chunk:Node3D in view._batch.get_children():
		for part:MultiMeshInstance3D in chunk.get_children():
			for i:int in part.multimesh.mesh.get_surface_count():names.append(part.multimesh.mesh.surface_get_material(i).resource_name)
	return names
func run()->void:
	var planning:=Planning.new();root.add_child(planning);planning.set_process(false)
	var preview:Dictionary={"ok":true,"schema":"afterglow-work-zones-v1","region_id":"region:a","cells":[{"x":0,"y":0,"z":0},{"x":1,"y":0,"z":0}],"excluded":[{"cell":{"x":2,"y":1,"z":0},"code":"PROTECTED"}]}
	var original:String=var_to_str(preview);planning.set_preview(preview)
	expect("two true adjacent preview cells have six outer edges and one excluded cross",planning.statistics().counts.get("valid")==2 and planning.statistics().instances==8,planning.statistics())
	expect("no authority data mutation",var_to_str(preview)==original)
	var rebuilds:int=planning.statistics().rebuilds
	planning.set_preview(preview)
	expect("unchanged authoritative preview reuses mesh batches",planning.statistics().rebuilds==rebuilds)
	var rendered:Node3D=planning._batch.get_child(0)
	var submitted:AABB=rendered.get_child(0).get_meta("submitted_bounds")
	expect("submitted border uses actual half metre standing cell height",is_equal_approx(submitted.position.y,.017),{"scope":"CPU mesh bounds of exact submitted transforms; dummy native readback unavailable","bounds":str(submitted)})
	planning.set_preview({"ok":false,"bounds":{"x0":0,"x1":10,"z0":0,"z1":10},"cells":preview.cells})
	expect("rejected preview and UI rectangle cannot imply legal land",planning.statistics().instances==0)
	planning.set_preview(preview);planning.clear_preview()
	expect("cancel removes disposable preview nodes",planning.statistics().chunks==0)
	planning.set_selected("zone:1")
	planning.sync({"available":true,"schema":"afterglow-work-zones-v1","selection":{"id":"zone:1","enabled":true,"region_id":"region:a","cells":preview.cells}})
	expect("selected zone consumes exact authoritative cells",planning.statistics().counts.get("selected")==2)
	planning.sync({"available":false})
	expect("unavailable selection hides old zone",planning.statistics().chunks==0)
	var ecology:=Ecology.new();root.add_child(ecology);ecology.set_process(false)
	var a:Dictionary=crop("crop:1");var b:Dictionary=crop("crop:2",32);b.crop_id="bean"
	var dto:Dictionary={"available":true,"revision":1,"visuals":[a,b]}
	original=var_to_str(dto);ecology.sync(dto)
	var first:Dictionary=ecology.statistics()
	expect("real stages create two local plant soil batches",first.available and first.chunks==2 and first.visuals.size()==2 and first.instances>8,first)
	expect("display does not grow consume water or mutate the DTO",var_to_str(dto)==original)
	rebuilds=first.rebuilds
	ecology.sync(dto)
	expect("identical ecology snapshot rebuilds no chunks",ecology.statistics().rebuilds==rebuilds)
	dto.revision=999
	ecology.sync(dto)
	expect("unrelated world revision cannot rebuild plants",ecology.statistics().rebuilds==rebuilds)
	a.stage="growing";a.revision=2
	ecology.sync(dto)
	expect("one changed plant rebuilds only its local chunk",ecology.statistics().rebuilds==rebuilds+1)
	var dry:Dictionary=ecology.statistics();a.moisture=3;a.revision=3
	ecology.sync(dto)
	expect("water state changes soil without fabricated water volume",ecology.statistics().instances==dry.instances and ecology.statistics().visuals[0].moisture==3)
	a.known=false;ecology.sync(dto)
	expect("unknown facts are not rendered",ecology.statistics().chunks==1 and ecology.statistics().visuals.size()==1)
	a.known=true;a.resident=false;ecology.sync(dto)
	expect("cold pages retire exact plant chunk",ecology.statistics().chunks==1)
	a.resident=true;a.visible=false;ecology.sync(dto)
	expect("explicit hidden projection never reveals plants",ecology.statistics().chunks==1)
	a.visible=true;a.stage="mature";ecology.sync(dto)
	expect("mature state comes only from owner stage",ecology.statistics().visuals[0].stage=="mature")
	a.stage="harvested";ecology.sync(dto)
	var sources:Array=visible_materials(ecology)
	expect("harvest removes mature species cutout and keeps actual residue",not sources.has("C:quality:potato_mature") and sources.has("C:quality:c08_straw_fibres"),sources)
	var rice:Dictionary=crop("rice:1");rice.crop_id="rice";rice.stage="mature"
	ecology.sync({"available":true,"visuals":[rice]})
	expect("rice uses exact existing material cutout",ecology.statistics().available and ecology._quality.failures.is_empty(),ecology.statistics())
	for species:String in ["potato","bean"]:
		for stage:String in ["seedling","growing","mature"]:
			var planted:Dictionary=crop("image:"+species+stage);planted.crop_id=species;planted.stage=stage
			ecology.sync({"available":true,"visuals":[planted]})
			expect("bind exact new stage image "+species+stage,visible_materials(ecology).has("C:quality:"+species+"_"+stage) and ecology.statistics().issues.is_empty())
	var water:Dictionary={"id":"source:well","region_id":"region:a","location":{"x":0,"y":.5,"z":0,"regionId":"region:a"},"kind":"water_source","stage":"available","capacity":12,"remaining":4,"recharge_seconds":120,"revision":0,"known":true,"resident":true,"visible":true,"visual_owner":"ecology"}
	original=var_to_str(water);ecology.sync({"available":true,"visuals":[water]})
	var source_parts:int=ecology.statistics().instances
	expect("actual source count DTO creates one supported well",source_parts==45 and ecology.statistics().visuals[0].remaining==4,ecology.statistics())
	expect("displaying real source awards no water or recharge",var_to_str(water)==original)
	water.remaining=0;water.stage="recharging";ecology.sync({"available":true,"visuals":[water]})
	expect("empty real source removes only available water surface",ecology.statistics().instances==source_parts-1 and ecology.statistics().visuals[0].remaining==0)
	var tree:Dictionary=crop("tree:1",0,"tree")
	tree.visual_owner="ecology"
	ecology.sync({"available":true,"visuals":[tree]})
	expect("real planted sapling uses existing native model material",ecology.statistics().instances>0 and ecology._models.failures.is_empty(),ecology.statistics())
	var mesh_root:Node3D=ecology._batch.get_child(0);var highest:float=-INF
	for node:MultiMeshInstance3D in mesh_root.get_children():
		var box:AABB=node.get_meta("submitted_bounds")
		highest=maxf(highest,box.end.y)
	expect("submitted sapling geometry is .45m above actual root",absf(highest-.95)<.015,{"highest":highest,"scope":"CPU exact source mesh and submitted transform, not GPU readback"})
	tree.visual_owner="environment";ecology.sync({"available":true,"visuals":[tree]})
	expect("environment-owned tree does not double draw",ecology.statistics().instances==0)
	ecology.sync({"available":true,"visuals":[rice,rice]})
	expect("duplicate ecology identities reject whole snapshot",not ecology.statistics().available and ecology.statistics().instances==0)
	rice.moisture=-1;ecology.sync({"available":true,"visuals":[rice]})
	expect("bad moisture cannot substitute default real state",not ecology.statistics().available)
	ecology.sync({"available":false})
	expect("unmounted provider retires all ecological geometry",ecology.statistics().chunks==0)
	planning.free();ecology.free();await process_frame
	var result:Dictionary={"scope":"finite public DTO consumer, no owner workflow or renderer/OS/VA/FPS qualification","checks":checks,"failures":failures}
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if not args.is_empty():
		var file:=FileAccess.open(args[0],FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("DDD_REGIONAL_VISUAL ",JSON.stringify({"checks":checks.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
