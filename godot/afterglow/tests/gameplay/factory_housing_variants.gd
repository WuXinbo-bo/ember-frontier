extends "res://tests/modules/normal_module_lifecycle.gd"
## Remaining homes: independent branches from the SAME exact B finite success.
## No grants, capture edits, damage or terrain/actor injection in this driver.
const Cold=preload("res://tests/gameplay/factory_route_cold.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
var options:Dictionary
var active_id:String=""
var branch_results:Array=[]
var baseline_people:Array=[]
var baseline_beds:Array=[]
var baseline_input:String
var hammer:String="r34:generated:RH-HOME:woodwork:tool:hammer"
func send(rt:RefCounted,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	sequence+=1
	var request:Dictionary={"command_id":"E:6.35:housing-variants:%d"%sequence,"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"destination":destination}
	var result:Dictionary=rt.command(request)
	commands.append({"clock":rt.clock(),"request":request.duplicate(true),"code":result.get("code"),"ok":result.get("ok",false),"reason":result.get("reason")})
	return result
func cold(label:String)->bool:
	var packed:Dictionary=Store.encode(live.runtime.capture_checkpoint())
	check(label+" actual native save",packed.get("ok",false))
	if not packed.get("ok",false):return false
	FileAccess.open(outdir+"/"+label+".native.json",FileAccess.WRITE).store_string(packed.text)
	var decoded:Dictionary=Store.decode(packed.text);var native:=Native.new()
	var restored:Dictionary=native._assemble(decoded.capture) if decoded.get("ok",false) else decoded;native.free()
	var oracle:Dictionary=Cold.compare(decoded.capture,restored.runtime,int(options.native_residency_batch)) if restored.get("ok",false) else restored
	check(label+" full facts/world/chunks/revision cold oracle",oracle.get("ok",false),oracle)
	if not oracle.get("ok",false):return false
	live.runtime.retire();live=restored;return true
func choose_home_site(rt:RefCounted,definition:String,id:String)->Dictionary:
	var rejected:Dictionary={}
	# Exact original generated land, no terraforming or substitute geometry.
	for z:int in range(12,55,2):
		for x:int in range(20,55,2):
			var height:Variant=rt.world.surface_height(x,z)
			if height==null:continue
			for q:int in [0,1]:
				var payload:Dictionary={"definition_id":definition,"position":{"x":float(x),"y":float(height),"z":float(z),"regionId":"RH-HOME"},"quarter_turn":q,"source_id":"pack:player","tool_id":hammer}
				var preview:Dictionary=rt._services.modules.preview({"kind":"module.plan","actor_id":"player","target_id":id,"payload":payload})
				if not preview.get("ok",false):rejected[str(preview.get("code"))]=int(rejected.get(str(preview.get("code")),0))+1;continue
				for port:Dictionary in preview.ports:
					if port.purpose!="service":continue
					var route:Dictionary=rt._services.actions.route("player",Geometry.location(rt.actor("player")),port.location)
					if route.get("ok",false):return {"payload":payload,"port":port.location}
	journey.append({"stage":"no proved legal home site","definition_id":definition,"rejected":rejected})
	return {}
func branch(definition:String,expected:int)->bool:
	if live.get("ok",false):live.runtime.retire()
	var decoded:Dictionary=Store.decode(baseline_input);var host:=Native.new()
	live=host._assemble(decoded.capture) if decoded.get("ok",false) else decoded;host.free()
	check(definition+" independent exact original checkpoint mounts",live.get("ok",false))
	if not live.get("ok",false):return false
	var rt:RefCounted=live.runtime
	baseline_people=rt.facts().actors.duplicate(true)
	baseline_beds=rt.world.entities().filter(func(e:Dictionary)->bool:return e.get("data",{}).get("sleeping",false) or e.get("kind")=="bed").duplicate(true)
	var source_home:String=options.source_home_id
	# Disclose the economic trade: lose the old empty warehouse and small home.
	if not dismantle("r34:normal-built-warehouse",hammer,definition+" finite empty warehouse"):return false
	if not dismantle(source_home,hammer,definition+" finite original paid home"):return false
	active_id="E:architecture:variant:"+definition.get_slice(".",2)
	var choice:Dictionary=choose_home_site(rt,definition,active_id)
	check(definition+" actual support/body/ports and complete B route prove a site",not choice.is_empty(),choice)
	if choice.is_empty():return false
	if not care(rt,80):return false
	var walked:Dictionary=walk(rt,choice.port)
	check(definition+" actual original player reaches construction face",walked.get("ok",false),walked.get("reason"))
	if not walked.get("ok",false):return false
	var pack:Dictionary=rt.actor("player").pack.duplicate(true);var tool_before:float=rt.tool(hammer).durability
	var planned:Dictionary=send(rt,"module.plan",active_id,choice.payload)
	var done:Dictionary=progress(rt,600) if planned.get("ok",false) else planned
	var module:Dictionary=live.services.modules.instance(active_id)
	check(definition+" same finite24boards8scrap real40second build pays once",planned.get("ok",false) and done.get("finished",false) and module.get("status")=="operational" and float(pack.get("timber",0))-float(rt.actor("player").pack.get("timber",0))==24 and float(pack.get("scrap",0))-float(rt.actor("player").pack.get("scrap",0))==8 and is_equal_approx(tool_before-float(rt.tool(hammer).durability),6),planned.get("reason"))
	if module.get("status")!="operational":return false
	var row:Dictionary=Draft.find(live.services.residents.housing_projection("player").homes,active_id)
	check(definition+" live E public design capacity equals unique B definition",row.get("usable",false) and row.capacity==expected and rt.factory_snapshot().workforce.housing==live.services.residents.housing_projection("player"),row)
	var service:Dictionary=Draft.find(ModuleShape.ports(module,Modules.definition(definition)),"service")
	walked=walk(rt,service.location)
	var stock:String=module.stock_refs.supplies;var water:float=float(rt.actor("player").pack.get("water",0))
	var put:Dictionary=send(rt,"deposit",stock,{"items":{"water":1}}) if walked.get("ok",false) else walked
	var take:Dictionary=send(rt,"take",stock,{"items":{"water":1}}) if put.get("ok",false) else put
	check(definition+" real service moves only original finite water",take.get("ok",false) and float(rt.actor("player").pack.get("water",0))==water and float(rt.stock(stock).items.get("water",0))==0,{"walk":walked.get("code"),"put":put.get("code"),"take":take.get("code")})
	if not cold(definition.get_slice(".",2)+"-actual-paid"):return false
	rt=live.runtime
	check(definition+" cold keeps original people HP consent and true beds",rt.facts().actors.size()==baseline_people.size() and rt.facts().actors.all(func(a:Dictionary)->bool:return a.hp==Draft.find(baseline_people,a.id).hp and Data.json_equal(a.relationship,Draft.find(baseline_people,a.id).relationship)) and Data.json_equal(baseline_beds,rt.world.entities().filter(func(e:Dictionary)->bool:return e.get("data",{}).get("sleeping",false) or e.get("kind")=="bed")) and Draft.find(live.services.residents.housing_projection("player").homes,active_id).capacity==expected)
	save_scene(rt,definition.get_slice(".",2)+"-final")
	return true
func run()->void:
	var args:=OS.get_cmdline_user_args();outdir=args[0];source_path=args[1];options=JSON.parse_string(FileAccess.get_file_as_string(args[2]));baseline_input=FileAccess.get_file_as_string(source_path)
	check("owner-delivered exact finite input byte identity",FileAccess.get_sha256(source_path)==options.input_sha256)
	if not checks[-1].ok:return finish()
	for spec:Dictionary in options.variants:
		var first:int=checks.size();var ok:bool=branch(str(spec.definition_id),int(spec.capacity))
		branch_results.append({"definition_id":spec.definition_id,"completed":ok,"first_check":first,"last_check":checks.size()-1})
	finish()
func finish()->void:
	var result:Dictionary={"checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size(),"branches":branch_results,"commands":commands,"journey":journey,"scope":"Owner exact finite checkpoint, independent source reload per remaining home. Real controlled reclamation/site proof/walk40s hammer payment/service/full cold. No injected materials, damage, body/need changes or terraforming. Source grandfathered fixtures, if any, must be declared by intake. No population/bed assignment/complete indoor/VA/OS/FPS/package qualification."}
	FileAccess.open(outdir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true));print(JSON.stringify({"checks":checks.size(),"failed":result.failed}));quit(1 if result.failed else 0)
