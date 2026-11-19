extends "res://tests/world/ecology_labor.gd"
## The original D labor save is read byte-for-byte, never normalized by this
## fixture. Overrides below are isolated malformed-schema counterexamples.
const FactoryServices=preload("res://scripts/runtime/factory_services.gd")
func run()->void:
 var args:=OS.get_cmdline_user_args();var raw:String=FileAccess.get_file_as_string(args[1])
 var decoded:Dictionary=Store.decode(raw)
 check("original actual labor Native decodes unchanged",decoded.ok,decoded.get("code"))
 if not decoded.ok:return finish()
 check("original actual labor World loads",world.load_snapshot(decoded.capture.world).ok)
 services={"buildings":Building.new(),"actions":Actions.new(),"production":Production.new(),"terrain":Terrain.new()}
 var attached:Dictionary=FactoryServices.attach(services,decoded.capture)
 check("A actual factory service composition attaches",attached.ok,attached.get("code"))
 if not attached.ok:return finish()
 services=attached.services
 var context:Dictionary=decoded.capture.duplicate(true);context.world=world;context.services=services
 var configured:Dictionary=runtime.configure(context)
 check("actual JSON labor save configures full new Runtime without conversion",configured.ok,configured)
 if not configured.ok:return finish()
 var ec:Dictionary=world.extension(Ecology.KEY);var id:String=ec.plants.keys()[0]
 check("real JSON field types retained",typeof(ec.plants[id].seed_reserved)==TYPE_FLOAT and typeof(ec.plants[id].moisture)==TYPE_FLOAT and typeof(ec.plants[id].fertility)==TYPE_FLOAT)
 check("full owner proof accepts unchanged canonical JSON",services.ecology.validate_extensions(runtime.facts()).ok)
 var before:Dictionary=world.snapshot()
 for field:String in ["seed_reserved","moisture","fertility"]:
  var maximum:int=1 if field=="seed_reserved" else 3
  for value:Variant in [true,false,-1,maximum+1,.5,NAN,INF,-INF,"1",null]:
   var invalid:Dictionary=ec.duplicate(true);invalid.plants[id][field]=value
   var result:Dictionary=services.ecology.validate_extensions(runtime.facts(),{Ecology.KEY:invalid})
   check("reject malformed "+field+" "+str(value),not result.ok and result.code=="INVALID_ECOLOGY_PLANT",result)
  for value:Variant in [0,0.0,maximum,float(maximum)]:
   var valid:Dictionary=ec.duplicate(true);valid.plants[id][field]=value
   if field=="seed_reserved" and value==1:
    valid.plants[id].stage="harvested";valid.plants[id].next_at=-1.0;valid.due=[];valid.next_due=-1.0
   check("accept exact integer boundary "+field+" "+str(value),services.ecology.validate_extensions(runtime.facts(),{Ecology.KEY:valid}).ok)
 check("schema counterexamples cannot alter original world/save",Data.json_equal(world.snapshot(),before) and FileAccess.get_file_as_string(args[1])==raw)
 # Continue and save the actual recovered Runtime; no extension cast or edit.
 runtime.tick(.1)
 check("restored Runtime actually continues its unique clock",runtime.clock()>float(decoded.capture.facts.time))
 var saved:Dictionary=Store.encode(runtime.capture_checkpoint());var second:Dictionary=Store.decode(saved.text) if saved.ok else saved
 check("recovered actual Runtime checkpoint re-encodes/decodes",second.ok,second.get("code"))
 if second.ok:
  var w:=World.new();var r:=Runtime.new();check("second cold World loads",w.load_snapshot(second.capture.world).ok)
  var fresh:Dictionary=FactoryServices.attach({"buildings":Building.new(),"actions":Actions.new(),"production":Production.new(),"terrain":Terrain.new()},second.capture)
  var ctx:Dictionary=second.capture.duplicate(true);ctx.world=w;ctx.services=fresh.services
  var restored:Dictionary=r.configure(ctx)
  check("second cold full Runtime keeps actual plant/seed/heap identity",restored.ok and Data.json_equal(w.extension(Ecology.KEY),second.capture.world.extensions[Ecology.KEY]),restored)
  r.retire()
 finish()
