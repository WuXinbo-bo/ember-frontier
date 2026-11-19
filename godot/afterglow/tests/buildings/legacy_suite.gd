extends SceneTree
const World=preload("res://scripts/world/world_state.gd")
const Codec=preload("res://scripts/world/world_codec.gd")
const Building=preload("res://scripts/buildings/building_service.gd")
const Actions=preload("res://scripts/actions/action_service.gd")
const Production=preload("res://scripts/production/production_service.gd")
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
var checks:Array=[]
var failed:=false

func expect(label:String,ok:bool,evidence:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"evidence":evidence})
	if not ok:failed=true;print("FAIL ",label," ",JSON.stringify(evidence))

func _initialize()->void:call_deferred("run")

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():print("Requires preserved actual ordinary v5 path as user arg");quit(2);return
	var raw:=FileAccess.get_file_as_string(args[0])
	var decoded:Dictionary=Codec.decode_checkpoint(raw)
	expect("actual ordinary source decodes without regeneration",decoded.ok,{"code":decoded.get("code"),"source":decoded.get("source")})
	if not decoded.ok:quit(1);return
	var source_state: Dictionary=decoded.state.duplicate(true)
	var source_facts: Dictionary=decoded.extensions["r3:runtime"].duplicate(true)
	var imported: Dictionary=Production.migrate_legacy_tools(decoded.state,source_facts)
	expect("two legacy terrain tools moved to sole production authority",imported.ok and imported.migrated_ids==["world-tool:shovel","world-tool:pickaxe"] and not imported.facts.has("tools"),imported.get("migrated_ids"))
	expect("migration leaves decoded input unchanged",decoded.state==source_state and source_facts==decoded.extensions["r3:runtime"])
	var repeated: Dictionary=Production.migrate_legacy_tools(imported.world,imported.facts)
	expect("tool migration idempotent",repeated.ok and repeated.world==imported.world and repeated.facts==imported.facts and repeated.migrated_ids.is_empty())
	var world:=World.new();expect("decoded legacy cells load",world.load_snapshot(imported.world).ok)
	var building:=Building.new();var actions:=Actions.new();var production:=Production.new();var runtime:=Runtime.new()
	var facts:Dictionary=imported.facts
	var configured:=runtime.configure({"world":world,"services":{"buildings":building,"actions":actions,"production":production},"facts":facts})
	expect("original actors stocks configure without renaming IDs",configured.ok,configured)
	var integrity:Dictionary=building.validate_snapshot(world,facts)
	expect("original domain snapshot references validated",integrity.ok,integrity)
	for old in source_facts.tools:
		var current:Dictionary=runtime.tool(old.id)
		expect("legacy tool fields preserved "+old.id,current.id==old.id and current.holderId==old.holderId and current.durability==old.durability and current.qualities==old.qualities,current)
	var query:RefCounted=building.current_space()
	expect("971 actual structures retained",query.pieces.size()==971,query.pieces.size())
	var errors:Array=[]
	var start:=Time.get_ticks_usec()
	var proofs:Dictionary={}
	for v in query.pieces:
		if not building.supported(query,v,{},proofs):errors.append(v.id)
	expect("actual legacy support rules retained",errors.is_empty(),{"errors":errors,"ms":float(Time.get_ticks_usec()-start)/1000})
	for stair in query.pieces.filter(func(v:Dictionary)->bool:return v.has("stairs")):
		expect("actual stair clear "+stair.id,query.stair_clear(stair))
		var d:Dictionary=building.geometry.definition(stair).stairs
		var p:=Geometry.json_point(Geometry.transform(Vector3(0,0,-0.6),stair));p.merge({"regionId":stair.regionId,"buildingId":stair.buildingId,"storeyId":stair.stairs.fromStoreyId})
		var current:=p.duplicate(true);var good:=true;var problem:Dictionary={}
		for n in range(1,63):
			var next:=Geometry.json_point(Geometry.transform(Vector3(0,0,-0.6+float(n)*(float(d.run)+1.2)/62),stair))
			next.merge({"regionId":stair.regionId,"buildingId":current.buildingId,"storeyId":current.storeyId});next.y=current.y
			var moved:Dictionary=query.direct_move("player",current,next)
			if not moved.ok:good=false;problem={"sample":n,"from":current,"next":next,"result":moved};break
			current=moved.location
			expect("midstair feet supported "+str(stair.quarterTurn)+":"+str(n),not query.standing_point(current).is_empty(),current)
		expect("full actual stair ascent "+str(stair.quarterTurn),good and absf(float(current.y)-float(stair.position.y)-float(d.rise))<0.025 and current.storeyId==stair.stairs.toStoreyId,problem if not good else current)
	# True source residents, HP/permissions and exits, not a hand-built equivalent.
	start=Time.get_ticks_usec()
	var valid:Dictionary=building.validate_structures(world,building.structures(),facts)
	expect("all original residents feet and exits safe",valid.ok,{"code":valid.get("code"),"reason":valid.get("reason"),"ms":float(Time.get_ticks_usec()-start)/1000})
	print(JSON.stringify({"scope":"BBB real preserved ordinary v5 headless migration regression; not FPS/app acceptance","ok":not failed,"checks":checks}))
	quit(1 if failed else 0)
