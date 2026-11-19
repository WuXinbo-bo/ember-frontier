extends SceneTree
## Explicit finite fixtures only. All commands, ticks, validation and restores
## use shipping Native/Runtime/domain code; no alternate production authority.
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Modules=preload("res://scripts/modules/module_service.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Factory=preload("res://scripts/production/factory_kernel.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const World=preload("res://scripts/world/world_state.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
var hosts:Array=[]
var serial:int=0
var evidence:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func run()->void:finish()
func opening()->Dictionary:
	var profiles:Dictionary=Assembly.generation_profiles()
	var prepared:Dictionary=Assembly.prepare(Assembly.generate(713,profiles.profiles))
	check("real generated opening prepares",prepared.ok,prepared.get("reason"))
	return prepared.get("capture",{})
func mount(capture:Dictionary,label:String)->Dictionary:
	var host:=Native.new();hosts.append(host)
	var result:Dictionary=host._assemble(capture)
	check(label+" restores through actual Native authority",result.ok,result.get("reason"))
	return result
func command(rt:RefCounted,kind:String,target:String="",payload:Dictionary={},actor_id:String="player",identity:String="")->Dictionary:
	serial+=1
	return rt.command({"kind":kind,"target_id":target,"payload":payload,"actor_id":actor_id,"command_id":identity if not identity.is_empty() else "B:boundary:"+str(serial)})
func tick(rt:RefCounted,steps:int)->void:
	for i:int in steps:rt.tick(0.1)
func put_actor(capture:Dictionary,at:Dictionary)->void:
	var a:=Draft.find(capture.facts.actors,"player")
	a.merge(G.location(at),true);a.intent=null;a.stamina=100.0;a.fatigue=0.0
func port(m:Dictionary,id:String)->Dictionary:return Draft.find(Shape.ports(m,Modules.definition(m.definition_id)),id).location
func relocate(rt:RefCounted,at:Dictionary,label:String)->Dictionary:
	# Only the fixture player's placement changes; inventory/energy/WIP are
	# captured from the preceding real state and must survive actual restore.
	var capture:Dictionary=rt.capture_checkpoint();put_actor(capture,at)
	return mount(capture,label)
func machine_fixture()->Dictionary:
	var capture:=opening()
	if capture.is_empty():return {}
	var ms:Dictionary=capture.world.extensions[Modules.KEY]
	var home:Dictionary=ms.instances.filter(func(m:Dictionary)->bool:return m.region=="RH-HOME" and Modules.definition(m.definition_id).shape=="home")[0]
	for member:Dictionary in home.members:capture.world.entities.erase(member.id)
	ms.instances.erase(home)
	for key:String in ms.source_receipts.keys():
		if ms.source_receipts[key].module_id==home.id:ms.source_receipts.erase(key)
	capture.facts.stocks=capture.facts.stocks.filter(func(s:Dictionary)->bool:return s.get("module_id")!=home.id)
	var m:=Modules.record_for({"id":"B:boundary:machine","definition_id":"r34.module.fuel_woodshop","region":home.region,"position":home.position,"quarter_turn":0,"player_built":false})
	var world:=World.new()
	var loaded:Dictionary=world.load_snapshot(capture.world)
	check("isolated preexisting machine fixture uses real generated terrain",loaded.ok)
	if not loaded.ok:return {}
	var builder:=Modules.building_adapter(world,capture.facts)
	var structures:Dictionary=world.extension("r3:structures")
	if structures.is_empty():structures={"schemaVersion":1,"catalogVersion":1,"instances":[],"storeys":[]}
	var changes:Array=[]
	Modules.append_instance(world,builder,m,Modules.definition(m.definition_id),changes,structures)
	for op:Dictionary in changes:capture.world.entities[op.id]=op.after
	ms.instances.append(m)
	capture.facts.stocks.append_array(Modules.stock_rows(m,Modules.definition(m.definition_id)))
	put_actor(capture,port(m,"work"))
	Draft.find(capture.facts.actors,"player").pack={"log":4,"timber":0}
	return {"capture":capture,"module":m}
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var result:Dictionary={"ok":failed==0,"failed":failed,"checks":checks,"evidence":evidence,"scope":"finite isolated fixtures; real shipping Runtime commands/ticks/Native restore; source or immutable-PCK identity belongs external runner; no OS/VA/FPS acceptance"}
	if not OS.get_cmdline_user_args().is_empty():
		var output:String=OS.get_cmdline_user_args()[0]
		DirAccess.make_dir_recursive_absolute(output)
		var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE)
		if file!=null:file.store_string(JSON.stringify(result,"\t",true,true));file.close()
	print(JSON.stringify(result))
	for host:Node in hosts:host.free()
	quit(0 if failed==0 else 1)
