extends SceneTree
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const View=preload("res://scripts/world/world_view.gd")
var checks:Array=[]
var costs:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool)->void:
	checks.append({"name":label,"ok":ok})
	if not ok:push_error(label)
func run()->void:
	var profile:Dictionary=Assembly.generation_profiles(14)
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,profile.profiles,14))
	var node:=Native.new();var made:Dictionary=node._assemble(prepared.capture);node.free()
	check("actual content14 native runtime assembles",made.get("ok",false))
	if not made.get("ok",false):return finish()
	var runtime:RefCounted=made.runtime;var world:RefCounted=runtime.world
	var player:Dictionary=runtime.actor("player")
	var volumes:Array=[G.json_box(AABB(G.point(player)-Vector3(28,4,28),Vector3(56,32,56))),world.region("RH-HOME").bounds,G.json_box(AABB(Vector3(10000,0,10000),Vector3.ONE))]
	for i:int in volumes.size():
		var expected:Array=world.entities_in_bounds(volumes[i]).filter(func(e:Dictionary)->bool:return e.get("data",{}).has("raw_water_source"))
		check("ordered source query equals full detached query "+str(i),world.entities_with_data_in_bounds(volumes[i],"raw_water_source")==expected)
	var sources:Array=world.entities_with_data_in_bounds(volumes[1],"raw_water_source")
	check("actual home has a raw water source",not sources.is_empty())
	if not sources.is_empty():
		var first:Dictionary=world.entity(str(sources[0].id))
		sources[0].data.clear();sources.clear()
		check("source return never exposes authority dictionaries",world.entities_with_data_in_bounds(volumes[1],"raw_water_source")[0]==first)
	check("unknown data field returns no entities",world.entities_with_data_in_bounds(volumes[1],"fixture:unknown").is_empty())
	# Compile the immediately preceding production implementation for a local
	# same-input comparison. Only the query selection differs; no copied engine.
	var source:String=FileAccess.get_file_as_string("res://scripts/ecology/ecology_service.gd")
	var changed:String=" var sources:Array=context.world.entities_with_data_in_bounds(box,\"raw_water_source\") if context.world.has_method(\"entities_with_data_in_bounds\") else context.world.entities_in_bounds(box)\n for entity:Dictionary in sources:"
	check("baseline transformation targets exactly the new query",source.count(changed)==1)
	var baseline:=GDScript.new();baseline.source_code=source.replace(changed," for entity:Dictionary in context.world.entities_in_bounds(box):")
	var compiled:Error=baseline.reload()
	check("immediate previous ecology projection compiles",compiled==OK)
	if compiled==OK:
		var ecology:RefCounted=runtime.domain_service("ecology")
		var old:RefCounted=baseline.new();old.configure(ecology.context)
		var before:Dictionary=runtime.capture_checkpoint()
		check("complete ecology visuals equal previous production query",ecology.presentation_projection()==old.presentation_projection())
		check("both projections preserve every authoritative fact",runtime.capture_checkpoint()==before)
		var began:int=Time.get_ticks_usec()
		for i:int in 20:old.presentation_projection()
		costs.previous_20_usec=Time.get_ticks_usec()-began
		began=Time.get_ticks_usec()
		for i:int in 20:ecology.presentation_projection()
		costs.filtered_20_usec=Time.get_ticks_usec()-began
	# Non-world fixture also proves exact bounds/order/null-field semantics.
	var fake:RefCounted=View.new({"entities":{"a":{"id":"a","bounds":volumes[0],"data":{"raw_water_source":null}},"b":{"id":"b","bounds":volumes[0],"data":{}},"c":{"id":"c","bounds":volumes[2],"data":{"raw_water_source":{}}}}})
	check("presence filter preserves null descriptors and excludes outside bounds",fake.entities_with_data_in_bounds(volumes[0],"raw_water_source").map(func(e:Dictionary)->String:return e.id)==["a"])
	runtime.retire();finish()
func finish()->void:
	var args:=OS.get_cmdline_user_args();var output:String=args[0] if not args.is_empty() else "user://water-projection14"
	DirAccess.make_dir_recursive_absolute(output)
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"costs":costs,"scope":"Same-input actual content14 ecology projection and detached ordered entity subset; CPU query timing only, not rendered FPS."},"\t",true,true))
	print(JSON.stringify({"suite":"water-projection14","checks":checks.size(),"failed":failed,"costs":costs}));quit(1 if failed else 0)
