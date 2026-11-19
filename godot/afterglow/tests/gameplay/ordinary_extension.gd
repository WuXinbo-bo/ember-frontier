extends "res://tests/gameplay/generated_cooperation.gd"
## FX-14 source-level example: one explicitly spawned ordinary identity,
## original finite saw/manual/timber, and existing craft/study variants.
## No opening population, new recipe economy, inventory or clock is added.
const Content=preload("res://scripts/runtime/content_definitions.gd")
var ordinary:String
var saw:String
var craft_target:String
var original_totals:Dictionary
var original_tools:Array=[]
var appearances:Dictionary={}
var sample_steps:Array=[]
var phase_captures:Array=[]

func capture_phase(phase:String)->void:
	var name:String="actual-ordinary-"+phase+"-capture.json"
	write_json(name,runtime.capture_checkpoint())
	phase_captures.append({"phase":phase,"path":output_dir+"/"+name,"actor_id":ordinary})

func totals()->Dictionary:
	var result:Dictionary={}
	for a:Dictionary in runtime.facts().actors:
		for item:String in a.pack:result[item]=float(result.get(item,0))+float(a.pack[item])
	for s:Dictionary in runtime.facts().stocks:
		for item:String in s.items:result[item]=float(result.get(item,0))+float(s.items[item])
	return result

func actor_change(id:String,after:Variant)->Dictionary:
	var before:Dictionary=runtime.actor(id)
	return runtime._commit({"ok":true,"world_changes":[],"fact_changes":[{"collection":"actors","id":id,"before":null if before.is_empty() else before,"after":after}]})

func actor_command(kind:String)->Dictionary:
	seq+=1
	return runtime.command({"command_id":command_prefix+str(seq),"actor_id":ordinary,"kind":kind,"expected_revision":runtime.get_revision()})

func step()->void:
	var positions:Dictionary={}
	for a:Dictionary in runtime.facts().actors:positions[str(a.id)]=Geometry.point(a)
	runtime.tick(0.1);ticks+=1
	var display:Dictionary=runtime.actor_presentation()
	for a:Dictionary in runtime.facts().actors:
		if not positions.has(a.id):continue
		var delta:Vector3=Geometry.point(a)-positions[a.id]
		var speed:float=Movement.RUN_SPEED if display.movement.get(a.id,{}).get("mode")=="run" else Movement.WALK_SPEED
		if Vector2(delta.x,delta.z).length()>speed*0.1+0.001 or absf(delta.y)>0.501:jumps.append({"id":a.id,"delta":[delta.x,delta.y,delta.z],"tick":ticks})
		if a.id==ordinary and delta.length()>0.001 and sample_steps.size()<12:sample_steps.append({"position":Geometry.location(a),"intent":a.intent,"movement":display.movement.get(a.id)})
	if ticks%50==0:write_progress()

func current_order()->Dictionary:
	for o:Dictionary in runtime.world.extension("r3:production").orders:
		if o.actorId==ordinary and o.status in ["active","blocked"]:return o
	return {}

func active_work()->bool:
	var o:Dictionary=current_order()
	return not o.is_empty() and o.kind=="craft" and float(o.elapsed)>0 and float(o.elapsed)<float(o.duration)

func own_holds()->Array:
	return runtime._services.production.all_holds().filter(func(h:Dictionary)->bool:return h.actor_id==ordinary)

func assign()->bool:
	if not perform("ordinary actor accepts existing handle craft variant","job",ordinary,{"job":"craft","work_target_id":craft_target}):return false
	return wait_fact("ordinary actor actually approaches and pays B labor",active_work,500)

func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	output_dir=args[0];DirAccess.make_dir_recursive_absolute(output_dir)
	command_prefix="E-extension:"+output_dir.get_base_dir().get_file()+":"
	ordinary="ordinary:E-extension:"+output_dir.get_base_dir().get_file()
	evidence_kind="explicit-one-ordinary-spawn-retained-real-materials-original-tool-and-action-variants"
	host=Client.new()
	if args.size()!=2:check("recorded actual material checkpoint supplied",false);finish();return
	var capture:Variant=JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if not capture is Dictionary or not mount(capture):finish();return
	check("example leaves official three-person opening unchanged",runtime.facts().actors.size()==3 and runtime.actor(ordinary).is_empty())
	original_totals=totals()
	for t:Dictionary in runtime.world.extension("r3:production").tools:original_tools.append(str(t.id))
	for a:Dictionary in runtime.facts().actors:appearances[a.id]=[a.appearance_id,a.body_profile_id]
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json"))
	check("existing ordinary item/action definitions pass public reference validation",Content.validate_catalog(catalog).ok and Content.item_definition("timber").unit=="count" and Content.item_definition("tool_handle").step==1)
	var at:Dictionary=runtime._services.buildings.current_space().standing_point(Geometry.location(runtime.actor("player")))
	check("ordinary spawn uses actual B-supported feet in existing world",not at.is_empty())
	if at.is_empty():finish();return
	var person:Dictionary=Initial.actor(ordinary,"普通扩展示例居民",at,runtime.actor("player").home,{})
	person.thirst=20.0 # Explicit need fixture; all consumed water remains finite.
	check("new ordinary body definition resolves without ID branch",not Content.body_definition(person.body_profile_id).is_empty())
	check("ordinary actor legally added after services configure",actor_change(ordinary,person).ok)
	check("spawn creates no stock tools consent or learned abilities",Data.json_equal(totals(),original_totals) and runtime.actor(ordinary).pack.is_empty() and not runtime.actor(ordinary).relationship.consent)
	appearances[ordinary]=[person.appearance_id,person.body_profile_id]
	var helped:Dictionary=send("help",ordinary,{"items":{"water":1}})
	check("ordinary person receives one original finite water",helped.ok,helped)
	if not helped.ok:finish();return
	if not wait_fact("ordinary decision pays A drink completion",func()->bool:return float(runtime.actor(ordinary).thirst)>63 and float(runtime.actor(ordinary).pack.get("water",0))==0,80):finish();return
	if not wait_fact("ordinary actor starts real autonomous B route",func()->bool:return runtime.actor(ordinary).get("intent") is Dictionary and runtime.actor(ordinary).intent.get("owner")=="residents",120):finish();return
	for i:int in 5:step()
	capture_phase("walking")
	var shown:Dictionary=runtime.actor_presentation()
	check("ordinary motion and stable profile reach real presentation DTO",shown.actors.any(func(a:Dictionary)->bool:return a.id==ordinary and a.appearance_id==appearances[ordinary][0]) and shown.movement.has(ordinary) and not sample_steps.is_empty())
	if not roundtrip("ordinary real autonomous movement"):finish();return
	var position:Dictionary=Geometry.location(runtime.actor(ordinary))
	check("empty ordinary actor removal releases actual E route without clock step",actor_change(ordinary,null).ok and runtime.actor(ordinary).is_empty() and own_holds().is_empty())
	capture_phase("removed")
	check("removed identity leaves presentation and decision facts",not runtime.actor_presentation().movement.has(ordinary) and not runtime.actor_presentation().actors.any(func(a:Dictionary)->bool:return a.id==ordinary))
	person=Initial.actor(ordinary,"普通扩展示例居民",position,runtime.actor("player").home,{})
	check("same ordinary ID re-added with fresh facts and same stable profile",actor_change(ordinary,person).ok and [runtime.actor(ordinary).appearance_id,runtime.actor(ordinary).body_profile_id]==appearances[ordinary])
	capture_phase("readded")
	if not approach(ordinary):finish();return
	if not perform("one actual finite food enables normal voluntary cooperation","help",ordinary,{"items":{"food":1}}):finish();return
	if not perform("ordinary person joins through original invite rule","invite",ordinary):finish();return
	if not wait_fact("ordinary actor earns original physical home-arrived fact",func()->bool:return runtime.actor(ordinary).relationship.get("home_arrived",false),200):finish();return
	if not perform("ordinary member accepts voluntary rest","job",ordinary,{"job":"rest"}):finish();return
	var reversed:Dictionary=runtime.capture_checkpoint();reversed.facts.actors.reverse()
	if not mount(reversed):finish();return
	check("actor array reorder preserves every persisted face and body",runtime.facts().actors.all(func(a:Dictionary)->bool:return [a.appearance_id,a.body_profile_id]==appearances[a.id]))
	if not prepare_work():finish();return
	if not exercise_work():finish();return
	var tools:Array=[]
	for t:Dictionary in runtime.world.extension("r3:production").tools:tools.append(str(t.id))
	tools.sort();original_tools.sort()
	check("entire extension retains exactly original finite tool identities",tools==original_tools)
	check("one completed recipe charges exactly one original timber and creates one handle",float(totals().timber)==float(original_totals.timber)-1 and float(totals().tool_handle)==float(original_totals.tool_handle)+1)
	write_json("extension-evidence.json",{"scope":evidence_kind,"ordinary_id":ordinary,"official_population_changed":false,"original_totals":original_totals,"final_totals":totals(),"tools":tools,"appearances":appearances,"movement_samples":sample_steps,"phase_captures":phase_captures,"actor":runtime.actor(ordinary),"holds":own_holds(),"ticks":ticks})
	finish()

func prepare_work()->bool:
	if not approach(ordinary):return false
	for t:Dictionary in runtime.world.extension("r3:production").tools:
		if t.kind=="hand_saw" and t.holderId=="pack:player":saw=t.id
	check("ordinary example uses one existing original finite saw",not saw.is_empty() and float(runtime.tool(saw).durability)>0)
	if saw.is_empty():return false
	if not perform("actual saw manual timber transferred without new item IDs","deposit","pack:"+ordinary,{"items":{"book_woodwork":1,"timber":1},"tool_ids":[saw]}):return false
	var study:Array=runtime.work_targets().filter(func(t:Dictionary)->bool:return t.work_payload.get("action_kind")=="study" and runtime.world.extension("r3:production").records.any(func(r:Dictionary)->bool:return r.id==t.actual_target_id and r.holderId=="pack:"+ordinary))
	check("existing book becomes ordinary actor actual study candidate",study.size()==1)
	if study.size()!=1:return false
	if not perform("ordinary actor uses existing study action variant","job",ordinary,{"job":"craft","work_target_id":study[0].id}):return false
	if not wait_fact("ordinary actor earns knowledge from actual original record",func()->bool:return runtime.world.extension("r3:production").knowledge.get(ordinary,[]).has("basic_woodwork"),500):return false
	if not perform("stop ordinary study repeating via existing rest assignment","job",ordinary,{"job":"rest"}):return false
	var targets:Array=runtime.work_targets().filter(func(t:Dictionary)->bool:return t.work_payload.get("recipe_id")=="make_handle" and runtime.world.entity(str(t.actual_target_id)).get("regionId")=="RH-HOME")
	check("existing home bench exposes original ordinary craft variation",targets.size()==1,targets)
	if targets.size()!=1:return false
	craft_target=targets[0].id
	var points:Array=runtime._services.buildings.use_points(str(targets[0].actual_target_id))
	if points.is_empty():return false
	# Reach the real station BEFORE starting the short eight-second job.
	# Chasing the worker afterward can let it legitimately finish first.
	return walk(points[0],"player actually reaches ordinary worker station before conflict checks")

func exercise_work()->bool:
	if not assign():return false
	var o:Dictionary=current_order()
	var paid_wear:float=float(runtime.tool(saw).durability)
	var stock_before:Dictionary=runtime.actor(ordinary).pack.duplicate(true)
	capture_phase("working")
	check("ordinary real order owns original material tool and station",runtime._services.production.reserved("pack:"+ordinary,"timber")==1 and runtime._services.production.tool_unavailable(saw) and own_holds().any(func(h:Dictionary)->bool:return h.intent_id==o.id))
	check("player already has actual contact with active ordinary worker",near_person(ordinary))
	var before:Dictionary=runtime.capture_checkpoint()
	var denied:Dictionary=send("take","pack:"+ordinary,{"tool_ids":[saw]})
	check("actual reserved ordinary saw cannot be taken for a second action",not denied.ok and Data.json_equal(before,runtime.capture_checkpoint()),denied)
	if denied.ok:return false
	if not perform("voluntary rest pauses original ordinary work","job",ordinary,{"job":"rest"}):return false
	for i:int in 3:step()
	check("pause retains order and standard hold without extra output",runtime.actor(ordinary).has("suspended_work") and not current_order().is_empty() and runtime._services.production.tool_unavailable(saw) and Data.json_equal(runtime.actor(ordinary).pack,stock_before))
	capture_phase("paused-work")
	if not roundtrip("ordinary real paused B work and standard holds"):return false
	var cancelled:Dictionary=actor_command("cancel")
	check("ordinary cancellation releases B hold without refund or free product",cancelled.ok and current_order().is_empty() and not runtime._services.production.tool_unavailable(saw) and Data.json_equal(runtime.actor(ordinary).pack,stock_before) and float(runtime.tool(saw).durability)<=paid_wear,cancelled)
	if not cancelled.ok or not assign():return false
	var person:Dictionary=runtime.actor(ordinary);var held:Dictionary=person.duplicate(true);person.hp=0.0
	check("ordinary no-tick incapacity cancels actual work in same A commit",actor_change(ordinary,person).ok and runtime.actor(ordinary).intent==null and current_order().is_empty() and own_holds().is_empty())
	check("incapacity preserves original cargo tool face skills and paid labor",Data.json_equal(runtime.actor(ordinary).pack,held.pack) and runtime.tool(saw).holderId=="pack:"+ordinary and runtime.actor(ordinary).skills==held.skills and runtime.actor(ordinary).appearance_id==appearances[ordinary][0])
	capture_phase("incapacitated")
	if not roundtrip("ordinary actual work interrupted without tick"):return false
	person=runtime.actor(ordinary);person.hp=100.0;person.job="rest";person.work_target_id="";person.work_payload={}
	check("explicit HP recovery retains person and does not revive old work",actor_change(ordinary,person).ok and runtime.actor(ordinary).intent==null and own_holds().is_empty())
	capture_phase("recovered")
	if not assign():return false
	if not wait_fact("ordinary same executor finishes exactly one finite handle",func()->bool:return float(runtime.actor(ordinary).pack.get("tool_handle",0))==1,600):return false
	if not perform("stop after the one actual ordinary product","job",ordinary,{"job":"rest"}):return false
	check("original recipe awards only its existing crafting increment",float(runtime.actor(ordinary).skills.crafting)==1.0)
	capture_phase("completed")
	if not roundtrip("ordinary completed real product and unchanged tool identity"):return false
	for i:int in 12:step()
	check("restored completed ordinary action never duplicates material or product",float(runtime.actor(ordinary).pack.get("tool_handle",0))==1 and float(runtime.actor(ordinary).pack.get("timber",0))==0)
	if not approach(ordinary):return false
	var items:Dictionary={}
	for item:String in runtime.actor(ordinary).pack:
		if float(runtime.actor(ordinary).pack[item])>0:items[item]=runtime.actor(ordinary).pack[item]
	if not perform("original tools records and output legally return before removal","take","pack:"+ordinary,{"items":items,"tool_ids":[saw]}):return false
	before=runtime.capture_checkpoint()
	denied=actor_change(ordinary,null)
	check("learned ordinary identity removal preserves knowledge by explicit refusal",not denied.ok and denied.get("code")=="ACTOR_KNOWLEDGE_RETIRE_REQUIRED" and Data.json_equal(before,runtime.capture_checkpoint()),denied)
	if not perform("ordinary member explicitly revokes cooperation","consent",ordinary,{"enabled":false}):return false
	denied=send("job",ordinary,{"job":"craft","work_target_id":craft_target})
	check("ordinary revoked permission blocks new work without special identity",not denied.ok and denied.code=="NO_CONSENT" and own_holds().is_empty(),denied)
	capture_phase("consent-revoked")
	return roundtrip("ordinary final revoked consent conserved knowledge and finite supplies")
