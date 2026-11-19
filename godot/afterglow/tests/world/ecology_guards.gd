extends "res://tests/world/ecology_cold_work.gd"
## New-source negative guards against original immutable actual tree save.
## Explicit overrides are never committed and cannot gain cached authority.
const Draft=preload("res://scripts/actions/domain_draft.gd")
func run()->void:
 var args:=OS.get_cmdline_user_args();var raw:=FileAccess.get_file_as_string(args[1]);var decoded:Dictionary=Store.decode(raw)
 check("actual forestry cycle Native decodes untouched",decoded.ok)
 if not decoded.ok:return finish()
 check("actual full tree cold Runtime accepts JSON integer-valued cycle",mount(decoded.capture))
 if checks[-1].ok!=true:return finish()
 check("actual original bounded warm",warm_region("RH-HOME"))
 var ecology:Dictionary=world.extension(Ecology.KEY);var before:Dictionary=runtime.capture_checkpoint()
 var trees:Array=ecology.plants.values().filter(func(p:Dictionary)->bool:return p.kind=="tree" and p.stage=="seedling" and p.cycle==1)
 check("fixture is actual new tree cycle one",trees.size()==1)
 if trees.size()!=1:return finish()
 var tree:Dictionary=trees[0]
 for bad:Variant in [true,-1,.5,NAN,INF,"1",null]:
  var invalid:Dictionary=ecology.duplicate(true);invalid.plants[tree.id].cycle=bad
  var result:Dictionary=services.ecology.validate_extensions(runtime.facts(),{Ecology.KEY:invalid})
  check("invalid tree cycle remains rejected "+str(bad),not result.ok,result)
 for bad:Variant in [null,0,{},[{"id":tree.id,"at":NAN,"revision":0}]]:
  var invalid:Dictionary=ecology.duplicate(true);invalid.due=bad
  var result:Dictionary=services.ecology.validate_extensions(runtime.facts(),{Ecology.KEY:invalid})
  check("malformed due never gains schema proof "+str(bad),not result.ok,result)
 var beds:Array=ecology.plants.values().filter(func(p:Dictionary)->bool:return p.kind=="crop")
 var p:Dictionary=beds[0];var job:Dictionary={"id":"C:guard:wrong-ground","kind":"water","target_id":Rules.plant_id(p.region_id,p.cell.merged({"y":p.cell.y+1},true)),"cell":p.cell.merged({"y":p.cell.y+1},true),"location":p.location.duplicate(true),"target":p.location.duplicate(true),"revision":p.revision,"crop_id":p.crop_id}
 var result:Dictionary=services.ecology.check_work(Draft.new(services.zonework.context),job,"player")
 check("real different cell still rejected after numeric JSON compatibility",not result.ok and result.code=="ECOLOGY_GROUND_CHANGED",result)
 job.cell.y=.5
 result=services.ecology.check_work(Draft.new(services.zonework.context),job,"player")
 check("fractional job cell rejected without rounding",not result.ok and result.code=="INVALID_ECOLOGY_CELL",result)
 check("all negative overrides leave actual facts/save/authority unchanged",Data.json_equal(before,runtime.capture_checkpoint()) and FileAccess.get_file_as_string(args[1])==raw)
 finish()
