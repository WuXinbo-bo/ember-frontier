extends "res://tests/world/ecology_lifecycle.gd"
## Same actual forestry labor, adding only full JSON Runtime restoration at
## both checkpoints. Original lifecycle evidence remains separately archived.
const FactoryServices=preload("res://scripts/runtime/factory_services.gd")
func capture_roundtrip(label:String)->bool:
 if not super.capture_roundtrip(label):return false
 var encoded:Dictionary=Store.encode(runtime.capture_checkpoint());var decoded:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
 if not decoded.ok:return false
 FileAccess.open(OS.get_cmdline_user_args()[0]+"."+("tree" if label.begins_with("actual forestry") else "crop")+".native.json",FileAccess.WRITE).store_string(encoded.text)
 var w:=World.new();var host:=Runtime.new()
 check(label+" complete cold World loads",w.load_snapshot(decoded.capture.world).ok)
 var attached:Dictionary=FactoryServices.attach({"buildings":Building.new(),"actions":Actions.new(),"production":Production.new(),"terrain":Terrain.new()},decoded.capture)
 var context:Dictionary=decoded.capture.duplicate(true);context.world=w;context.services=attached.services
 var result:Dictionary=host.configure(context)
 check(label+" full Runtime cold validates JSON stage/cycle/ID",result.ok,result)
 host.retire()
 return result.ok
