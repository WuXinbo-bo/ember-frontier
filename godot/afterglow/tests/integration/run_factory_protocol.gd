extends SceneTree
## Shared-host contract counterexamples, not a substitute for real module or OS QA.
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
const World=preload("res://scripts/world/world_state.gd")
const Rural=preload("res://scripts/world/rural_generator.gd")
const Initial=preload("res://scripts/runtime/initial_state.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")
const Factory=preload("res://scripts/runtime/factory_definitions.gd")
const Contracts=preload("res://scripts/runtime/factory_contracts.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Interaction=preload("res://scripts/input/direct_interaction.gd")

class Provider extends RefCounted:
	var calls:int=0
	var reads:int=0
	var steps:int=0
	var validation_denied:bool=false
	var extension_plan:Array=[]
	var public_state:Dictionary={"available":true,"instances":[],"projects":[],"definitions":[]}
	func prepare(_request:Dictionary)->Dictionary:
		calls+=1
		return {"ok":true,"world_changes":extension_plan.duplicate(true),"fact_changes":[],"events":[]}
	func availability(request:Dictionary)->Dictionary:return prepare(request)
	func projection(_actor_id:String)->Dictionary:
		reads+=1
		return public_state
	func advance(_dt:float)->Dictionary:
		steps+=1
		return {"ok":true}
	func validate_extensions(_facts:Dictionary,_overrides:Dictionary={})->Dictionary:
		return {"ok":not validation_denied,"code":"FIXTURE_REJECTED_STATE" if validation_denied else "OK"}

class WaterProvider extends Provider:
	var water_reads:int=0
	var water_state:Variant={"available":true,"sources":[{"id":"fixture:known-water","remaining":7}],"projects":[]}
	func water_projection(_actor_id:String,_source_id:String="")->Variant:
		water_reads+=1
		return water_state

class TeachingProvider extends Provider:
	var teaching_reads:int=0
	var teaching_state:Variant={"available":true,"offers":[{"teacher_id":"repair-resident","knowledge_id":"basic_tool_repair","can_start":false,"reason":"需要靠近居民"}]}
	func teaching_projection(_actor_id:String,_teacher_id:String="")->Variant:
		teaching_reads+=1
		return teaching_state

class ViewProvider extends RefCounted:
	var visible_ids:Array=[]
	func projection(_actor_id:String,id:String="")->Dictionary:
		return {"available":true,"instances":[{"id":id}] if visible_ids.has(id) else []}

class ViewUI extends Control:
	var selection:Variant={}
	func world_view_selection()->Variant:return selection

class ViewRouter extends Node:
	var mode:String="tool"
	func state()->Dictionary:return {"mode":mode}

class ViewPolicy extends RefCounted:
	func can_observe_geometry(_entity:Dictionary,_player:Dictionary)->bool:return false

var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:push_error(label+" "+str(detail))

func fixture(services:Dictionary={})->RefCounted:
	var world:=World.new()
	check("existing world still loads",world.load_snapshot(Rural.generate(713)).ok)
	var at:Dictionary={"x":29.2,"y":0.0,"z":30.25,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	var facts:Dictionary={"actors":[Initial.actor("player","fixture",at,at,{"food":2,"water":2})],"stocks":[],"actions":[],"quests":[],"time":0.0,"status":"playing"}
	var runtime:=Runtime.new()
	check("existing host accepts additive registry",runtime.configure({"world":world,"facts":facts,"services":services}).ok)
	return runtime

func run()->void:
	var output:String=OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	var legacy:RefCounted=fixture()
	var capture:Dictionary=legacy.capture_checkpoint()
	var absent:Dictionary=legacy.factory_snapshot()
	check("unmounted domains never claim a factory is running",not absent.available and absent.modules.instances.is_empty() and not absent.production.available)
	check("query preserves legacy facts and content lock",Data.json_equal(capture,legacy.capture_checkpoint()) and Content.validate_lock(capture.content).ok)
	check("legacy world does not acquire optional water state from a query",not legacy.water_snapshot().available and absent.water.sources.is_empty() and Data.json_equal(capture,legacy.capture_checkpoint()))
	var water_provider:=WaterProvider.new();var water_host:RefCounted=fixture({"modules":water_provider})
	var water_before:Dictionary=water_host.capture_checkpoint();var water:Dictionary=water_host.water_snapshot()
	check("water facade copies only original owner public facts",water.available and water.sources[0].remaining==7 and Data.json_equal(water_before,water_host.capture_checkpoint()))
	water.sources[0].remaining=999
	check("caller cannot mutate water source through public projection",water_host.water_snapshot().sources[0].remaining==7)
	var water_reads:int=water_provider.water_reads
	check("NPC and missing actor cannot trigger player water projection",not water_host.water_snapshot("repair-resident").available and not water_host.water_snapshot("not-an-actor").available and water_provider.water_reads==water_reads)
	water_provider.water_state={"available":true,"sources":{},"projects":[]}
	check("malformed water projection refuses without fabricating supplies",not water_host.water_snapshot().available and not water_host.factory_snapshot().water.available and Data.json_equal(water_before,water_host.capture_checkpoint()))
	check("old worlds do not acquire teaching state or invented teachers",not legacy.teaching_snapshot().available and Data.json_equal(capture,legacy.capture_checkpoint()))
	var teaching_provider:=TeachingProvider.new();var teaching_host:RefCounted=fixture({"production":teaching_provider})
	var teaching_before:Dictionary=teaching_host.capture_checkpoint();var teaching_dto:Dictionary=teaching_host.teaching_snapshot()
	check("teaching facade preserves exact owner restriction without granting knowledge",teaching_dto.available and not teaching_dto.offers[0].can_start and Data.json_equal(teaching_before,teaching_host.capture_checkpoint()))
	teaching_dto.offers[0].can_start=true
	check("UI cannot promote a denied teaching offer through DTO mutation",not teaching_host.teaching_snapshot().offers[0].can_start)
	var teaching_reads:int=teaching_provider.teaching_reads
	check("NPC and missing actor cannot invoke player teaching provider",not teaching_host.teaching_snapshot("repair-resident").available and not teaching_host.teaching_snapshot("missing:actor").available and teaching_provider.teaching_reads==teaching_reads)
	teaching_provider.teaching_state={"available":true,"offers":["invalid"]}
	check("bad teaching DTO refuses without mutating knowledge",not teaching_host.teaching_snapshot().available and Data.json_equal(teaching_before,teaching_host.capture_checkpoint()))
	teaching_host.retire();teaching_reads=teaching_provider.teaching_reads
	check("retired world cannot expose old teacher offers",not teaching_host.teaching_snapshot().available and teaching_provider.teaching_reads==teaching_reads)
	var view_provider:=ViewProvider.new();var view_runtime:RefCounted=fixture({"modules":view_provider})
	var view_ui:=ViewUI.new();var view_router:=ViewRouter.new();var view_input:=Interaction.new()
	view_input.runtime=view_runtime;view_input.world=view_runtime.world;view_input.modules=view_provider;view_input.ui=view_ui;view_input.router=view_router
	var entity:Dictionary={}
	for row:Dictionary in view_runtime.world.entities():
		if row.get("regionId")=="RH-HOME" and row.has("bounds"):entity=row;break
	check("world view fixture uses a real entity with real bounds",not entity.is_empty())
	var view_before:Dictionary=view_runtime.capture_checkpoint()
	view_ui.selection={"kind":"module","id":entity.get("id","")}
	check("UI identity alone cannot reveal an undiscovered module outline",view_input.view_hints().selected.is_empty())
	view_provider.visible_ids=[entity.get("id","")]
	var view_dto:Dictionary=view_input.view_hints()
	check("authorised outline uses exact original bounds without committing",view_dto.selected.get("bounds")==entity.get("bounds") and Data.json_equal(view_before,view_runtime.capture_checkpoint()))
	view_dto.selected.bounds.min.x=99999
	check("presentation cannot mutate selected world geometry",view_input.view_hints().selected.bounds==entity.bounds)
	view_input.view_policy=ViewPolicy.new()
	check("known inventory cannot draw an outline through a hidden room",view_input.view_hints().selected.is_empty())
	view_input.view_policy=null
	view_ui.selection="invalid"
	check("malformed UI selection cannot become a world target",view_input.view_hints().selected.is_empty())
	view_ui.selection={"kind":"module","id":"missing:world-object"};view_provider.visible_ids.append("missing:world-object")
	check("stale selected identity cannot draw a deleted object",view_input.view_hints().selected.is_empty())
	view_input._placement_view_hint={"active":true,"world_revision":view_runtime.world.get_revision(),"preview":{"ok":false,"code":"MODULE_PORT_OCCUPIED","ports":[{"id":"actual:port"}]}}
	check("inactive placement mode never exposes a stale preview",view_input.view_hints().placement.is_empty())
	view_router.mode="module_place"
	var placement:Dictionary=view_input.view_hints().placement
	check("failed preview preserves exact owner result and real service identity",placement.preview.code=="MODULE_PORT_OCCUPIED" and placement.preview.ports[0].id=="actual:port")
	placement.preview.ports.clear()
	check("renderer cannot mutate the prepared placement projection",view_input.view_hints().placement.preview.ports.size()==1)
	view_input._placement_view_hint.world_revision=-1
	check("changed world invalidates a cached placement result",view_input.view_hints().placement.is_empty())
	view_runtime.retire()
	check("retired world clears selected and placement hints",view_input.view_hints().world_id.is_empty() and view_input.view_hints().selected.is_empty())
	view_input.free();view_ui.free();view_router.free()
	check("old item quantities and volume meanings stay intact",Content.item_definition("timber").name=="木料" and Content.quantity_step("stone_m3")==0.001 and Content.quantity_valid("stone_m3",0.125))
	var actions:=Provider.new()
	var production:=Provider.new()
	var modules:=Provider.new()
	var workforce:=Provider.new()
	modules.public_state.instances=[{"id":"fixture:module","state_code":"idle","visuals":{"buffers":[]}}]
	var runtime:RefCounted=fixture({"actions":actions,"production":production,"modules":modules,"workforce":workforce})
	var before:Dictionary=runtime.capture_checkpoint()
	var displayed:Dictionary=runtime.factory_snapshot()
	check("public query contains provider facts without committing",displayed.available and displayed.modules.instances[0].id=="fixture:module" and Data.json_equal(before,runtime.capture_checkpoint()))
	displayed.modules.instances[0].state_code="ruined"
	displayed.definitions.items.water.name="mutated copy"
	check("consumer mutation cannot change provider or core definitions",runtime.factory_snapshot().modules.instances[0].state_code=="idle" and Content.item_definition("water").name=="饮水")
	var reads:int=modules.reads
	check("unknown actor cannot query privileged module facts",not runtime.factory_snapshot("not-an-actor").available and modules.reads==reads)
	for kind:String in ["module.configure","factory.configure","logistics.configure","workforce.configure","settlement.configure"]:
		check("explicit domain receives "+kind,runtime.command({"kind":kind,"actor_id":"player","command_id":"route:"+kind}).ok)
	check("new commands cannot fall through to old actions",actions.calls==0 and modules.calls==1 and production.calls==2 and workforce.calls==2)
	check("duplicate command does not prepare a second time",runtime.command({"kind":"factory.configure","actor_id":"player","command_id":"route:factory.configure"}).ok and production.calls==2)
	for kind:String in ["module.","factory.","logistics.","workforce.","settlement."]:
		check("missing operation rejects "+kind,runtime.command({"kind":kind,"command_id":"invalid:"+kind}).get("code")=="INVALID_COMMAND_SCHEMA")
	check("unmounted new command refuses rather than using legacy provider",legacy.command({"kind":"module.configure","command_id":"missing:module"}).get("code")=="UNAVAILABLE")
	var frozen:Dictionary=runtime.capture_checkpoint()
	modules.extension_plan=[{"op":"extension.set","id":"r34:modules","before_exists":false,"before":null,"after":{"version":99}}]
	check("unknown state version cannot commit through a domain",runtime.command({"kind":"module.configure","command_id":"invalid:state"}).get("code")=="INVALID_FACTORY_STATE" and Data.json_equal(frozen,runtime.capture_checkpoint()))
	modules.extension_plan[0].after.version=1;modules.validation_denied=true
	check("domain schema rejection preserves facts and world atomically",runtime.command({"kind":"module.configure","command_id":"invalid:domain-state"}).get("code")=="FIXTURE_REJECTED_STATE" and Data.json_equal(frozen,runtime.capture_checkpoint()))
	modules.extension_plan.clear();modules.validation_denied=false
	runtime.tick(0.2)
	for i:int in 4:runtime.tick(0)
	check("shared clock advances machine and manual providers exactly once per STEP",production.steps==2 and actions.steps==2 and modules.steps==2 and workforce.steps==2 and is_equal_approx(runtime.clock(),0.2))
	var missing_world:=World.new()
	var restore_source:Dictionary=frozen.world.duplicate(true);restore_source.extensions["r34:modules"]={"version":1}
	check("fixture JSON is structurally valid",missing_world.load_snapshot(restore_source).ok)
	var missing_runtime:=Runtime.new()
	check("restore cannot accept production JSON without its schema owner",missing_runtime.configure({"world":missing_world,"facts":frozen.facts,"services":{}}).get("code")=="MISSING_FACTORY_VALIDATOR")
	var good:Dictionary=Factory.catalog()
	check("formal registry validates without adding fictional stock",Factory.validate_document(good,Content.ITEMS).ok and legacy.facts().stocks.is_empty())
	var duplicate:Dictionary=good.duplicate(true);duplicate.categories.append(duplicate.categories[0].duplicate(true))
	check("duplicate content identity rejects",not Factory.validate_document(duplicate).ok)
	var shadow:Dictionary=good.duplicate(true);shadow.items=[{"id":"timber","name":"different timber","unit":"count","step":1,"stackable":true}]
	check("registry cannot reinterpret old timber",Factory.validate_document(shadow,Content.ITEMS).get("code")=="FACTORY_ITEM_CONFLICT")
	var added:Dictionary=good.duplicate(true);added.items=[{"id":"r34:fixture-part","name":"fixture part","unit":"count","step":1,"stackable":true}]
	check("new namespaced item can validate independently of stock",Factory.validate_document(added,Content.ITEMS).ok)
	added.items[0].step=0.5
	check("fractional count cannot become a new material unit",not Factory.validate_document(added).ok)
	check("machine does not require an imaginary operator",Contracts.primary_state(["missing_operator","running"],"machine")=="running")
	runtime.retire();reads=modules.reads
	check("retired world exposes no stale live modules",not runtime.factory_snapshot().available and modules.reads==reads)
	var report:Dictionary={"scope":"shared Runtime/query isolation/routing/content compatibility counterexamples; no actual module gameplay, package or OS acceptance","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var file:=FileAccess.open(output+"/results.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print(JSON.stringify(report));quit(1 if report.failed else 0)
