extends SceneTree
const Data=preload("res://scripts/world/world_data.gd")
const Terrain=preload("res://scripts/terrain/terrain_service.gd")
const Definitions=preload("res://scripts/runtime/content_definitions.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool)->void:
	checks.append({"label":label,"ok":ok})
	if not ok:push_error("FAIL "+label)
func run()->void:
	check("all seven real material definitions resolve through A units",Terrain.validate_material_definitions().ok)
	for item:String in ["soil_m3","stone_m3","gravel_m3"]:
		var definition:=Definitions.item_definition(item)
		check("actual half-metre cell volume exact "+item,definition.unit=="m3" and Definitions.quantity_valid(item,0.125) and Definitions.quantity_valid(item,0.000125))
		definition.unit="count"
		check("descriptor projection detached "+item,Definitions.item_definition(item).unit=="m3")
	for value:Variant in ["unknown_m3","timber",42]:
		var invalid:=Data.MATERIALS.duplicate(true);invalid[2].item=value
		check("formal material cannot use unknown/count/bad reference "+str(value),Terrain.validate_material_definitions(invalid).code=="INVALID_MATERIAL_ITEM")
	var missing:=Data.MATERIALS.duplicate(true);missing[2].erase("item")
	check("diggable material needs an actual quantity definition",not Terrain.validate_material_definitions(missing).ok)
	var service:=Terrain.new()
	var intent:Dictionary={"schema_version":1,"id":"test:definition","source_id":"pack:player","cost":{"soil_m3":0.125},"owner":"terrain","kind":"terrain","request":{"command_id":"test:definition","actor_id":"player","kind":"terrain","payload":{"tool_id":"tool:shovel","edit":{"operation":"fill","material":2,"cells":[{"x":0,"y":0,"z":0}]}}},"elapsed":0.0,"duration":1.5,"tool_id":"tool:shovel","held":true}
	check("real v1 terrain intent consumes definition",service.validate_intent(intent).ok)
	for cost:Dictionary in [{"not-a-formal-item":0.125},{"timber":0.125},{"soil_m3":NAN},{"soil_m3":-0.125}]:
		var bad:=intent.duplicate(true);bad.cost=cost
		check("bad formal cost rejected "+str(cost),not service.validate_intent(bad).ok)
	var legacy:=intent.duplicate(true);legacy.erase("schema_version");legacy.cost={"old-custom_m3":0.123456789}
	check("explicit historical v0 quantity retained without rounding",service.validate_intent(legacy).ok and legacy.cost["old-custom_m3"]==0.123456789)
	var result:Dictionary={"checks":checks,"failed":checks.filter(func(c:Dictionary):return not c.ok).size(),"scope":"Real C material/intent consumers of A immutable definitions; no item registry, balancing, inventory replacement or m3 rounding. Actual router/cost route checked separately."}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));quit(1 if result.failed else 0)
