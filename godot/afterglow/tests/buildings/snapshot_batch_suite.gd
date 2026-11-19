extends "res://tests/buildings/legacy_suite.gd"
const Original=preload("res://tests/buildings/snapshot_batch_reference.gd")
const Candidate=preload("res://scripts/buildings/building_snapshot.gd")
class MeteredView extends "res://scripts/world/world_view.gd":
	var entity_reads:=0
	var entity_lists:=0
	var region_reads:=0
	func entity(id:String)->Dictionary:entity_reads+=1;return super.entity(id)
	func entities(region:String="")->Array:entity_lists+=1;return super.entities(region)
	func region(id:String)->Dictionary:region_reads+=1;return super.region(id)

var catalog:Dictionary
var base_world:Dictionary
var base_facts:Dictionary
var invalid_rows:Array=[]

func compare(label:String,snapshot:Dictionary,facts:Dictionary,valid:bool=false,structure_check:bool=true,production_check:bool=true)->void:
	var a:=MeteredView.new(snapshot.duplicate(true));var b:=MeteredView.new(snapshot.duplicate(true))
	var before:=snapshot.duplicate(true);var facts_before:=facts.duplicate(true)
	var old:Dictionary=Original.validate(a,facts,catalog,structure_check,production_check)
	var result:Dictionary=Candidate.validate(b,facts,catalog,structure_check,production_check)
	expect(label+" original outcome and error preserved",result==old and result.ok==valid,{"old":old,"new":result})
	expect(label+" no input mutation",snapshot==before and facts==facts_before and a.snapshot()==before and b.snapshot()==before)
	if label=="complete actual971":
		expect("all971 entity references still inspected with one list",a.entity_reads-b.entity_reads==971 and b.entity_lists==1,{"old_entity":a.entity_reads,"new_entity":b.entity_reads,"old_lists":a.entity_lists,"new_lists":b.entity_lists})
		expect("region reads deduplicate only within one invocation",a.region_reads>b.region_reads+900,{"old":a.region_reads,"new":b.region_reads})
	if not valid:invalid_rows.append({"label":label,"code":result.code,"reason":result.reason})

func edit_piece(label:String,field:String,value:Variant)->void:
	var capture:=base_world.duplicate(true)
	capture.extensions["r3:structures"].instances[0][field]=value
	compare(label,capture,base_facts)

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var raw:=FileAccess.get_file_as_string(args[0]);var decoded:=Codec.decode_checkpoint(raw)
	expect("preserved source decodes",decoded.ok)
	var imported:=Production.migrate_legacy_tools(decoded.state,decoded.extensions["r3:runtime"])
	expect("preserved source migrates",imported.ok)
	var w:=World.new();w.load_snapshot(imported.world)
	var b:=Building.new();var r:=Runtime.new()
	expect("actual runtime configures",r.configure({"world":w,"facts":imported.facts,"services":{"buildings":b,"actions":Actions.new(),"production":Production.new()}}).ok)
	catalog=b.source_catalog;base_world=w.snapshot();base_facts=r.facts()
	compare("complete actual971",base_world,base_facts,true)
	for flags:Array in [[false,false],[false,true],[true,false]]:compare("original check flags "+str(flags),base_world,base_facts,true,flags[0],flags[1])
	for row:Array in [["geometryVersion",999],["definitionId","missing:definition"],["hp",-1],["hp",100000],["version",-1],["version",1.5],["quarterTurn",-1],["quarterTurn",1.5],["position",{"x":null,"y":0,"z":0}],["regionId","missing:region"],["storeyId","missing:storey"]]:edit_piece(str(row),row[0],row[1])
	var snapshot:=base_world.duplicate(true);snapshot.extensions["r3:structures"].instances.append(snapshot.extensions["r3:structures"].instances[0].duplicate(true));compare("duplicate structure ID",snapshot,base_facts)
	snapshot=base_world.duplicate(true);snapshot.extensions["r3:structures"].storeys[0].buildingId="";compare("invalid level owner",snapshot,base_facts)
	snapshot=base_world.duplicate(true);snapshot.extensions["r3:structures"].storeys[0].regionId="missing:region";compare("invalid level region",snapshot,base_facts)
	snapshot=base_world.duplicate(true);snapshot.extensions["r3:structures"].storeys[0].elevation="bad";compare("invalid level height",snapshot,base_facts)
	var first:Dictionary=base_world.extensions["r3:structures"].instances[0]
	snapshot=base_world.duplicate(true);snapshot.entities.erase(first.id);compare("missing actual entity",snapshot,base_facts)
	for field:String in ["kind","regionId","position","data"]:
		snapshot=base_world.duplicate(true)
		var value:Variant={"x":-999,"y":0,"z":0} if field=="position" else {} if field=="data" else "not-original"
		snapshot.entities[first.id][field]=value;compare("entity mismatch "+field,snapshot,base_facts)
	snapshot=base_world.duplicate(true)
	var orphan:Dictionary=snapshot.entities[first.id].duplicate(true);orphan.id="orphan:actual-structure";snapshot.entities[orphan.id]=orphan
	compare("orphan structure entity",snapshot,base_facts)
	for field:String in ["open","locked","blocked","swing"]:
		snapshot=base_world.duplicate(true)
		for v:Dictionary in snapshot.extensions["r3:structures"].instances:
			if v.has("door"):
				v.door[field]=0 if field=="swing" else "bad";break
		compare("invalid door "+field,snapshot,base_facts)
	snapshot=base_world.duplicate(true)
	for v:Dictionary in snapshot.extensions["r3:structures"].instances:
		if v.has("door"):v.door.open=true;v.door.locked=true;break
	compare("open and locked door",snapshot,base_facts)
	for field:String in ["fromStoreyId","toStoreyId"]:
		snapshot=base_world.duplicate(true)
		for v:Dictionary in snapshot.extensions["r3:structures"].instances:
			if v.has("stairs"):v.stairs[field]="missing:level";break
		compare("invalid stairs "+field,snapshot,base_facts)
	var facts:=base_facts.duplicate(true);facts.stocks.append(facts.stocks[0].duplicate(true));compare("duplicate stock",base_world,facts)
	facts=base_facts.duplicate(true);facts.tools=[];compare("second tools table",base_world,facts)
	facts=base_facts.duplicate(true);facts.stocks[0].structureId="missing:parent";compare("missing furniture parent",base_world,facts)
	# Independent consecutive invocations must read a new view after region,
	# entity, or structure changes, not reuse an earlier successful answer.
	compare("valid after negative invocations",base_world,base_facts,true)
	snapshot=base_world.duplicate(true);snapshot.regions.erase(str(first.regionId));compare("region removed after positive",snapshot,base_facts)
	compare("positive after region removal",base_world,base_facts,true)
	expect("original source bytes remain",FileAccess.get_file_as_string(args[0])==raw)
	print(JSON.stringify({"ok":not failed,"checks":checks,"negative_cases":invalid_rows,"scope":"single-call aggregate read dedup equivalence; preserved971 with current formal production, complete malformed snapshots and per-call invalidation, not OS qualification"}))
	quit(1 if failed else 0)
