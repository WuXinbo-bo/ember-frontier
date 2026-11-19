extends SceneTree
## EXPLICIT bounded flat laboratory with finite declared supplies/actor setup.
## Every operation uses original Runtime/Draft, original damage cause and costs.
## Not a natural paid-world journey or actual hostile attack claim.
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Modules=preload("res://scripts/modules/module_service.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Generator=preload("res://scripts/world/factory_generator.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
var checks:Array=[]
var observations:Array=[]
var sequence:=0
var out:String
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
func send(rt:RefCounted,kind:String,id:String,payload:Dictionary={})->Dictionary:
	sequence+=1
	return rt.command({"command_id":"B:architecture:fixture:"+str(sequence),"actor_id":"player","kind":kind,"target_id":id,"payload":payload})
func advance(rt:RefCounted,modules:RefCounted,seconds:float)->bool:
	for i:int in ceili(seconds*10):
		var p:Dictionary=modules.advance(.1)
		if not p.ok:return false
		if not rt._commit(p).ok:return false
	return true
func mount(capture:Dictionary)->Dictionary:
	var n:=Native.new();var m:=n._assemble(capture);n.free();return m
func run()->void:
	out=OS.get_cmdline_user_args()[0]
	var opening:=Assembly.prepare(Generator.generate(713,Catalog.profiles()))
	check("fixture base original generated assembly",opening.ok,opening.get("reason"))
	if not opening.ok:return finish()
	var base:Dictionary=opening.capture.duplicate(true)
	# Isolated 32x32 flat test patch, explicitly NOT unchanged natural terrain.
	for key:String in base.world.chunks:
		var c:Vector3i=Data.coord(key)
		if c.x not in [3,4,5,6] or c.z not in [3,4,5,6]:continue
		var cells:PackedInt32Array=base.world.chunks[key].cells.duplicate()
		for y:int in 16:
			for z:int in 16:
				for x:int in 16:cells[x+16*(z+16*y)]=2 if c.y*16+y<0 else 0
		base.world.chunks[key].cells=cells
	for id:String in base.world.entities.keys():
		var e:Dictionary=base.world.entities[id]
		if G.aabb(e.bounds).intersects(AABB(Vector3(24,-1,24),Vector3(32,20,32))):base.world.entities.erase(id)
	var variants:Array=Catalog.definitions().filter(func(d:Dictionary)->bool:return d.has("architecture"))
	check("all thirty registered for lifecycle coverage",variants.size()==30)
	if OS.get_cmdline_user_args().has("residential-only"):variants=variants.filter(func(d:Dictionary)->bool:return d.architecture.family=="home")
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("r34.module."):variants=variants.filter(func(d:Dictionary)->bool:return d.id==arg)
	for d:Dictionary in variants:
		var label:String=str(d.id);var capture:Dictionary=base.duplicate(true);var site:=Modules.record_for({"id":"B:life:"+label,"definition_id":label,"region":"RH-HOME","position":{"x":40,"y":0,"z":40},"quarter_turn":0})
		var port:Dictionary=Shape.ports(site,d)[0].location;var player:=Draft.find(capture.facts.actors,"player")
		player.x=port.x;player.y=port.y;player.z=port.z;player.regionId=port.regionId;player.buildingId=null;player.storeyId=null;player.intent=null;player.stamina=100;player.fatigue=0
		player.pack={"timber":100,"scrap":40,"log":4,"food":3,"water":3,"r34:salvaged_drive_unit":1}
		var production:Dictionary=capture.world.extensions["r3:production"];var hammer:=Draft.find(production.tools,"r34:generated:RH-HOME:woodwork:tool:hammer")
		if hammer.is_empty():
			for t:Dictionary in production.tools:
				if t.kind=="hammer":hammer=t;break
		hammer.holderId="pack:player";hammer.durability=100
		var m:=mount(capture);check("finite declared fixture restores "+label,m.get("ok",false),m.get("reason"))
		if not m.get("ok",false):continue
		var rt:RefCounted=m.runtime;var modules:RefCounted=m.services.modules
		var payload:Dictionary={"definition_id":label,"position":{"x":40,"y":0,"z":40,"regionId":"RH-HOME"},"quarter_turn":0,"source_id":"pack:player","tool_id":hammer.id}
		var snapshot:Dictionary=rt.capture_checkpoint();var invalid:=payload.duplicate(true);invalid.position.y=.5
		var rejected:Dictionary=modules.preview({"kind":"module.plan","actor_id":"player","target_id":site.id,"payload":invalid})
		check("unsupported raised footprint refuses purely "+label,not rejected.ok and Data.json_equal(snapshot,rt.capture_checkpoint()))
		var plan:=send(rt,"module.plan",site.id,payload)
		check("original plan reserves finite exact cost and empty buffers "+label,plan.ok and rt.actor("player").pack==player.pack and rt.facts().stocks.filter(func(s:Dictionary)->bool:return s.get("module_id")==site.id).all(func(s:Dictionary)->bool:return s.items.is_empty()),plan.get("code"))
		if not plan.ok:rt.retire();continue
		var done:=advance(rt,modules,float(d.build_seconds)+.2);var built:Dictionary=modules.instance(site.id)
		var paid:bool=done and built.status=="operational" and Data.json_equal(built.paid_cost,d.build_cost)
		for item:String in d.build_cost:paid=paid and float(rt.actor("player").pack.get(item,0))==float(player.pack.get(item,0))-float(d.build_cost[item])
		check("real hammer pays once and assembles members "+label,paid and built.members.size()>3,{"status":built.status,"members":built.members.size()})
		if not paid:rt.retire();continue
		var before:Dictionary=rt.actor("player").pack.duplicate(true)
		var hit:Dictionary=rt._commit(modules.prepare_damage(site.id,32,"B:architecture:explicit-damage:"+label))
		check("explicit fixture original damage marks module unavailable "+label,hit.ok and modules.instance(site.id).hp==float(d.hp)-32)
		if d.architecture.family=="home":check("damage removes new design housing usability "+label,modules.housing_projection("player").homes.any(func(h:Dictionary)->bool:return h.id==site.id and not h.usable))
		var repair:=send(rt,"module.repair",site.id,{"source_id":"pack:player","tool_id":hammer.id});var fixed:bool=repair.ok and advance(rt,modules,8.2)
		check("original repair material labor restores exact geometry "+label,fixed and modules.instance(site.id).hp==d.hp and float(before.timber)-float(rt.actor("player").pack.timber)==2 and float(before.scrap)-float(rt.actor("player").pack.scrap)==1 and Data.json_equal(modules.instance(site.id).paid_cost,d.build_cost),repair.get("code"))
		var encoded:=Store.encode(rt.capture_checkpoint());var decoded:=Store.decode(encoded.text) if encoded.ok else encoded;var cold:=mount(decoded.capture) if decoded.get("ok",false) else decoded
		check("canonical cold retains repaired members and cost "+label,cold.get("ok",false) and Data.json_equal(cold.runtime.capture_checkpoint().facts,decoded.capture.facts) and Data.json_equal(cold.world.snapshot().extensions,decoded.capture.world.extensions),cold.get("reason"))
		if not cold.get("ok",false):rt.retire();continue
		rt.retire();rt=cold.runtime;modules=cold.services.modules
		var prior:Dictionary=rt.actor("player").pack.duplicate(true);var dismantle:=send(rt,"module.dismantle",site.id,{"source_id":"pack:player","output_id":"pack:player","tool_id":hammer.id});var gone:bool=dismantle.ok and advance(rt,modules,12.2)
		var retired:Dictionary=modules.instance(site.id)
		check("original empty-cache dismantle retires all real members "+label,gone and retired.status=="dismantled" and retired.members.all(func(member:Dictionary)->bool:return cold.world.entity(member.id).is_empty()),dismantle.get("code"))
		var after:Dictionary=rt.actor("player").pack.duplicate(true);var second:=send(rt,"module.dismantle",site.id,{"source_id":"pack:player","output_id":"pack:player","tool_id":hammer.id})
		check("recovery cannot repeat "+label,not second.ok and Data.json_equal(after,rt.actor("player").pack))
		# Rebuilding requires the same real stamina budget as first construction.
		var rested:=send(rt,"rest","")
		if rested.ok:
			for step:int in 150:
				rt.tick(.1)
				if rt.actor("player").get("intent")==null:break
		check("original timed rest funds rebuild labor "+label,rested.ok and float(rt.actor("player").stamina)>=float(d.build_seconds)*1.2,rested.get("code"))
		var rebuilt:=send(rt,"module.plan",str(site.id)+":rebuilt",payload);var rebuilt_ok:bool=rebuilt.ok and advance(rt,modules,float(d.build_seconds)+.2)
		check("new stable identity rebuilds same real footprint "+label,rebuilt_ok and modules.instance(str(site.id)+":rebuilt").status=="operational" and modules.instance(site.id).status=="dismantled",rebuilt.get("code"))
		observations.append({"id":label,"members":built.members.size(),"cost":d.build_cost,"explicit_damage":32,"paid_before_dismantle":prior,"recovery":retired.get("recovery_settlement",{}),"rebuilt":rebuilt_ok})
		if encoded.ok:FileAccess.open(out+"/"+label.replace(".","_")+".native.json",FileAccess.WRITE).store_string(encoded.text)
		rt.retire()
	finish()
func finish()->void:
	var result:Dictionary={"checks":checks,"observations":observations,"scope":"Explicit flat32m fixture, declared finite pack/tools and initial player station; original authority/commands/payment/hammer/damage32/repair/canonical cold/dismantle/rebuild. No natural economy, true enemy combat, renderer/PCK/VA/FPS claim."}
	FileAccess.open(out+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));var ok:bool=checks.all(func(c:Dictionary)->bool:return c.ok)
	print("LIFECYCLE30 "+str(checks.size())+" "+str(ok));quit(0 if ok else 1)
