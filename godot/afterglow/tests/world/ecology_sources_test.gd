extends "res://tests/world/ecology_labor.gd"
## Real generated raw source, explicit finite actor/bucket fixture. Normal
## spawn-to-source economic route is A/E's separate actual-source evidence.
const Factory=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Sources=preload("res://scripts/ecology/ecology_sources.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
var active_zone:String="C:water"
func job(kind:String)->Dictionary:
 for c:Dictionary in services.zonework.work_candidates("player"):
  if c.zone_id==active_zone and c.operation==kind:return c
 return {}
func run()->void:
 var profiles:Array=Catalog.profiles_for_content(12);var generated:Dictionary=Factory.generate(713,profiles,Contract.fresh(profiles,12,1).contract)
 check("actual locked12 world loads",world.load_snapshot(generated).ok)
 if not world.has_extension("generation:RH-HOME"):return finish()
 var d:Dictionary=world.extension("generation:RH-HOME").ecology_sources[0];var at:Dictionary=d.use_point
 services={"buildings":Building.new(),"actions":Actions.new(),"production":Production.new(),"terrain":Terrain.new(),"zones":Zones.new(),"ecology":Ecology.new(),"zonework":Work.new()}
 var actor:Dictionary={"id":"player","name":"finite bucket fixture","x":at.x,"y":at.y,"z":at.z,"regionId":"RH-HOME","buildingId":null,"storeyId":null,"hp":100.0,"hunger":100.0,"thirst":100.0,"stamina":100.0,"fatigue":0.0,"pack":{"r34:water_bucket":1,"water":8,"food":8},"intent":null,"relationship":{"consent":true}}
 var configured:=runtime.configure({"world":world,"facts":{"actors":[actor],"stocks":[],"actions":[],"quests":[],"time":0.0,"status":"playing"},"services":services})
 check("source fixture real Runtime configures",configured.ok,configured)
 if not configured.ok:return finish()
 var cx:int=floori(d.location.x*2);var cz:int=floori(d.location.z*2)
 var spec:Dictionary={"kind":"forage","region_id":"RH-HOME","bounds":{"x0":cx-4,"x1":cx+5,"z0":cz-4,"z1":cz+5},"policy":{}}
 check("real source is protected from terrain and has legal adjacent forage cells",command("zone.create",active_zone,{"spec":spec}).ok)
 for _i:int in 4:
  if not labor("draw_raw_water",180):return finish()
 check("four actual draws drain finite four units, bucket reusable",runtime.actor("player").pack.get("r34:raw_water")==4 and runtime.actor("player").pack["r34:water_bucket"]==1 and services.ecology.state().sources[d.id].remaining==0)
 check("empty source offers no fifth actual work",job("draw_raw_water").is_empty())
 var unsafe:Dictionary=command("drink","",{"item_id":"r34:raw_water"})
 check("raw water is never safe drinking output",not unsafe.ok and runtime.actor("player").pack["r34:raw_water"]==4,unsafe)
 step(900)
 var state:Dictionary=services.ecology.state();var observed:Dictionary=Sources.observe(d,state.sources[d.id],runtime.clock())
 check("actual unique clock bounded recharge creates one available raw unit",observed.remaining==1,{"state":state.sources[d.id],"time":runtime.clock(),"observed":observed})
 if not labor("draw_raw_water",180):return finish()
 check("recharged unit taken once without bucket consumption",runtime.actor("player").pack["r34:raw_water"]==5 and runtime.actor("player").pack["r34:water_bucket"]==1)
 var before:Dictionary=services.ecology.state()
 var snapshot:Dictionary=runtime.capture_checkpoint();var encoded:=Store.encode(snapshot);var decoded:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
 check("raw source balances/time/fraction Native saved",decoded.ok,decoded.get("code"))
 if decoded.ok:
  var outer:Dictionary=JSON.parse_string(JSON.parse_string(encoded.text).payload);var canonical:Dictionary=JSON.parse_string(outer.world.payload).world.extensions[Ecology.KEY]
  check("exact canonical raw source restore, no refill by wall clock",Data.json_equal(decoded.capture.world.extensions[Ecology.KEY],canonical) and decoded.capture.world.extensions[Ecology.KEY].sources[d.id].remaining==before.sources[d.id].remaining)
 # A fresh explicit no-bucket context only proves requirements/refusal; no
 # capture is rewritten or published, and it cannot produce raw water.
 var no_bucket:Dictionary=runtime.actor("player");no_bucket.pack.erase("r34:water_bucket");no_bucket.intent=null
 var facts:Dictionary=runtime.facts();facts.actors=[no_bucket]
 var test_context:Dictionary={"world":world,"actor":func(_id:String)->Dictionary:return no_bucket,"facts":func()->Dictionary:return facts,"stock":func(_id:String)->Dictionary:return {},"tool":runtime.tool,"clock":func()->float:return runtime.clock(),"region_is_detailed":func(_id:String)->bool:return true,"spatial":services.buildings,"services":services}
 step(1200)
 facts=runtime.facts();facts.actors=[no_bucket]
 var copy:=Ecology.new();copy.configure(test_context)
 var raw:Array=copy.work_candidates(services.zones.zone_records()[0],"player")
 var water:Array=raw.filter(func(v:Dictionary)->bool:return v.kind=="draw_raw_water")
 var Draft=load("res://scripts/actions/domain_draft.gd");var tx:RefCounted=Draft.new(test_context)
 var result:Dictionary=copy.check_work(tx,water[0],"player") if not water.is_empty() else {"ok":true}
 check("missing reusable bucket reports requirements without authorization",not result.ok and result.code=="REUSABLE_BUCKET_REQUIRED" and result.requirements.reusable=={"r34:water_bucket":1} and result.requirements.cost.is_empty(),result)
 var far:Dictionary=Sources.observe(d,before.sources[d.id],before.sources[d.id].updated_at+86400)
 check("finite cap twelve, no unbounded refill",far.remaining==12 and far.fraction==0 and Sources.observe(d,before.sources[d.id],before.sources[d.id].updated_at-1).is_empty())
 check("source observation/requirements never mutate live authority",services.ecology.state().sources[d.id]==before.sources[d.id] and runtime.actor("player").pack["r34:water_bucket"]==1)
 finish()
