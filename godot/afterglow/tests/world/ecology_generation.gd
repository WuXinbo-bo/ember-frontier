extends SceneTree
const Factory=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Policy=preload("res://scripts/world/factory_zone_production.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const World=preload("res://scripts/world/world_state.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Space=preload("res://scripts/buildings/building_service.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Modules=preload("res://scripts/modules/module_service.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
var checks:Array=[];var rows:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
 checks.append({"label":label,"ok":ok,"detail":detail})
 if not ok:print("FAIL ",label," ",detail)
func commit(w:RefCounted,changes:Array)->Dictionary:
 var d:Dictionary=w.prepare_changes(changes,w.get_revision())
 return w.commit_prepared(d.capability) if d.ok else d
func run()->void:
 var profiles:Array=Catalog.profiles_for_content(10)
 var old:Dictionary=Contract.fresh(profiles,10,1);var fresh:Dictionary=Contract.fresh(profiles,12,1)
 check("explicit 12 and exact new policy only",old.ok and fresh.ok and fresh.contract.zone_production_policy==Policy.POLICY and not old.contract.has("zone_production_policy"),fresh.get("code"))
 check("paused11 remains rejected",not Contract.fresh(profiles,11,1).ok)
 if not fresh.ok:return finish()
 var a:Dictionary=fresh.contract.duplicate(true);a.erase("zone_production_policy");a.content_version=10
 check("12 geometry terrain profile lock is byte-identical stable10 base",Data.json_equal(a,old.contract))
 for seed:int in [713,2026]:
  var previous:Dictionary=Factory.generate(seed,profiles,old.contract);var source:Dictionary=Factory.generate(seed,profiles,fresh.contract)
  check("new source12 generation "+str(seed),source.get("ok",true) and source.has("chunks"),source.get("code"))
  if not source.has("chunks"):continue
  check("all actual terrain buffers equal stable10 "+str(seed),var_to_bytes(source.chunks)==var_to_bytes(previous.chunks))
  var w:=World.new();check("new full world validates "+str(seed),w.load_snapshot(source).ok)
  var additions:Dictionary=Policy.opening_additions(w)
  check("one finite S03 addition only "+str(seed),additions.ok and additions.additions.size()==1 and additions.additions[0].items==Policy.START_ITEMS,additions)
  var bag:Dictionary=additions.additions[0] if additions.ok else {}
  var registration:Dictionary=Modules.new().prepare_generation(w)
  check("B original registration accepts exact independent bag "+str(seed),registration.ok,registration.get("code"))
  if registration.ok:
   var initial:Array=registration.initial_stocks.filter(func(v:Dictionary)->bool:return v.id==bag.source_id)
   check("one finite bag stock owner/search and quantities "+str(seed),initial.size()==1 and initial[0].owner==null and not initial[0].searched and initial[0].items==Policy.START_ITEMS)
   var supplies:Array=registration.initial_stocks.filter(func(v:Dictionary)->bool:return v.id=="r34:generated:RH-VILLAGE:store:stock:supplies")
   check("S03 original whitelist never receives new seeds "+str(seed),supplies.size()==1 and supplies[0].items=={"food":6,"water":6,"scrap":3})
   check("true original CAS module registration "+str(seed),commit(w,registration.world_changes).ok)
   var b:=Space.new();b.configure({"world":w,"facts":func()->Dictionary:return {"actors":[]},"actor":func(_id:String)->Dictionary:return {},"stock":func(_id:String)->Dictionary:return {},"tool":func(_id:String)->Dictionary:return {},"clock":func()->float:return 0.0})
   var q:RefCounted=b.current_space();var feet:Dictionary=q.standing_point(bag.use_point)
   var instance:Dictionary=Draft.find(w.extension(Modules.KEY).instances,"r34:generated:RH-VILLAGE:store")
   var ports:Array=Shape.ports(instance,Modules.definition(instance.definition_id));var from:Dictionary=ports[0].use_points[0]
   var route:Dictionary=q.route("player",from,feet) if not feet.is_empty() else {"ok":false}
   check("real module geometry supported bag feet, B route and contact "+str(seed),not feet.is_empty() and route.ok and q.contact_clear(feet,bag.position.merged({"regionId":"RH-VILLAGE"},true),bag.entity_id),{"feet":feet,"route":route})
   var repeated:Dictionary=Modules.new().prepare_generation(w)
   check("original receipt prevents second bag stock or refill "+str(seed),repeated.ok and repeated.initial_stocks.is_empty() and w.extension(Modules.KEY).source_receipts[bag.receipt_id].stock_ids==[bag.source_id])
  var assembled:Dictionary=Assembly.prepare(source)
  check("A real finite normal Assembly accepts stock and sole receipt "+str(seed),assembled.ok,assembled.get("code"))
  if assembled.ok:
   FileAccess.open(OS.get_cmdline_user_args()[0]+".seed"+str(seed)+".capture.json",FileAccess.WRITE).store_string(JSON.stringify(assembled.capture,"\t",true,true))
  for coord:Vector2i in [Vector2i(1,0),Vector2i(0,1),Vector2i(-1,-1)]:
   var peripheral:Dictionary=Factory.plan_region(seed,coord,profiles,fresh.contract)
   check("peripheral never gets opening seed bag/raw source "+str(seed)+str(coord),peripheral.ok and peripheral.plan.module_seeds.all(func(v:Dictionary)->bool:return not v.has("zone_production_additions")) and peripheral.plan.ecology_sources.is_empty(),peripheral.get("code"))
  var sources:Array=w.entities().filter(func(e:Dictionary)->bool:return e.kind=="raw_water_source")
  check("one real source, stable old entities "+str(seed),sources.size()==1 and previous.entities.keys().all(func(id:String)->bool:return source.entities[id]==previous.entities[id]))
  if sources.size()==1:
   var descriptor:Dictionary=sources[0].data.raw_water_source
   check("raw source finite cap bounded refill separate from WT01 "+str(seed),descriptor.capacity==12 and descriptor.initial_units==4 and descriptor.recharge_seconds==120 and source.extensions["generation:RH-HOME"].water_sources==previous.extensions["generation:RH-HOME"].water_sources)
   var b:=Space.new();b.configure({"world":w,"facts":func()->Dictionary:return {"actors":[]},"actor":func(_id:String)->Dictionary:return {},"stock":func(_id:String)->Dictionary:return {},"tool":func(_id:String)->Dictionary:return {},"clock":func()->float:return 0.0})
   var q:RefCounted=b.current_space();var feet:Dictionary=q.standing_point(descriptor.use_point)
   check("source has real body-supported contact feet "+str(seed),not feet.is_empty() and q.contact_clear(feet,descriptor.location.merged({"regionId":descriptor.region_id},true),sources[0].id),descriptor)
  check("old10 has no invented seed/source addition "+str(seed),not previous.extensions["generation:RH-VILLAGE"].module_seeds.any(func(v:Dictionary)->bool:return v.has("zone_production_additions")) and previous.entities.values().all(func(e:Dictionary)->bool:return e.kind!="raw_water_source"))
  var token:Dictionary=w.extension_token("C:test");var proposed:Dictionary={"op":"extension.set","id":"C:test","before_exists":false,"before":null,"after":{"revision":0,"v":1}}
  var prepared:Dictionary=w.prepare_changes([proposed],w.get_revision());check("prepare leaves authority token unchanged",prepared.ok and w.extension_token("C:test")==token)
  var committed:Dictionary=w.commit_prepared(prepared.capability)
  check("successful exact extension commit advances authority token",committed.ok and w.extension_token("C:test").extension==token.extension+1)
  var other:Dictionary=w.extension_token("C:other");token=w.extension_token("C:test")
  var changed:Dictionary=proposed.duplicate(true);changed.before_exists=true;changed.before=w.extension("C:test");changed.after={"revision":0,"v":2}
  check("same self revision cannot reuse schema token",commit(w,[changed]).ok and w.extension_token("C:test").extension==token.extension+1 and w.extension_token("C:other")==other)
  token=w.extension_token("C:test");changed.before=w.extension("C:test");changed.after=changed.before.duplicate(true)
  check("successful no-op request still invalidates validation token",commit(w,[changed]).ok and w.extension_token("C:test").extension==token.extension+1)
  token=w.extension_token("C:test");changed.before={"bad":true}
  check("failed prepare does not advance token",not w.prepare_changes([changed],w.get_revision()).ok and w.extension_token("C:test")==token)
  var snap:Dictionary=w.snapshot();check("load invalidates token generation without persistence",w.load_snapshot(snap).ok and w.extension_token("C:test").generation==token.generation+1 and not snap.has("extension_epochs"))
  rows.append({"seed":seed,"additions":additions,"sources":sources})
 finish()
func finish()->void:
 var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
 FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"rows":rows,"scope":"C content12 deterministic source/unchanged old terrain and authority-token source qualification only; not normal economic route/PCK/VA/FPS"},"\t",true,true))
 print("ECOLOGY_GENERATION ",checks.size()," failed=",failed);quit(0 if failed==0 else 1)
