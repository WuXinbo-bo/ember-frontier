extends "res://tests/gameplay/factory_knowledge_pressure.gd"
## Actual saved delivery continuation; no fixture bodies, materials or events.
var live:RefCounted
var commands:Array=[]
func send(runtime:RefCounted,kind:String,target:String="",payload:Dictionary={},destination:Dictionary={})->Dictionary:
	sequence+=1
	var request:Dictionary={"command_id":"r34:e:shared-review:%d"%sequence,"actor_id":"player","kind":kind,"target_id":target,"payload":payload,"destination":destination}
	var result:Dictionary=runtime.command(request);commands.append({"request":request,"result":result,"time":runtime.clock()});return result
func observe(_runtime:RefCounted)->void:pass
func people(runtime:RefCounted)->Dictionary:return runtime.world.extension(Gameplay.KEY).stories.ST02.people
func experience(runtime:RefCounted,id:String)->Dictionary:return runtime.world.extension(Gameplay.KEY).stories.ST02.get("experiences",{}).get(id,{})
func review_payload(runtime:RefCounted,id:String)->Dictionary:return {"story_id":"ST02","person_id":id,"event_id":experience(runtime,id).get("event_id","")}
func current_story(runtime:RefCounted)->Dictionary:
	for row:Dictionary in runtime._services.workforce.projection().stories:
		if row.id=="ST02":return row
	return {}
func economic(runtime:RefCounted)->Dictionary:
	var c:Dictionary=runtime.capture_checkpoint();c.erase("command_revision");c.erase("receipts");c.facts.erase("ledger");c.facts.erase("log");c.world.extensions.erase(Gameplay.KEY);c.world.erase("revision");return c
func run()->void:
	var args:=OS.get_cmdline_user_args();output_dir=args[0];DirAccess.make_dir_recursive_absolute(output_dir)
	var config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[2]));var made:Dictionary=load_actual(args[1])
	if not made.get("ok",false):return finish()
	var r:RefCounted=made.runtime;live=r
	if config.probe_mode=="negative":return no_experience(r)
	if config.probe_mode=="defense":return defense_history(r)
	var actual:Array=r.facts().ledger.filter(func(e:Dictionary)->bool:return e.kind=="logistics-delivery-completed")
	check("original normal53 source really contains both original people's actual completed deliveries",actual.size()==2 and actual.all(func(e:Dictionary)->bool:return e.items=={"timber":2.0} and not r.stock(e.destination_id).is_empty()))
	step(r)
	save(r,"actual-deliveries-one-step")
	check("actual original event identities gain bounded location-bound shared memories",experience(r,"repair-resident").get("event_id")==actual[0].id and experience(r,"village-resident").get("event_id")==actual[1].id and experience(r,"repair-resident").get("destination_id")==actual[0].destination_id)
	if config.probe_mode=="before":return finish()
	if experience(r,"repair-resident").is_empty():return finish()
	var id:String="repair-resident"
	var wrong:Dictionary=review_payload(r,id);wrong.event_id=experience(r,"village-resident").event_id
	check("another person's actual event cannot be reviewed as this person",not r._services.workforce.availability({"kind":"settlement.read_story","actor_id":"player","target_id":id,"payload":wrong}).ok)
	var far:Dictionary=review_payload(r,id)
	var far_ready:Dictionary=r._services.workforce.availability({"kind":"settlement.read_story","actor_id":"player","target_id":id,"payload":far})
	if far_ready.ok:
		check("real walk away for physical contact negative",walk(r,r.world.extension(Gameplay.KEY).layout.home).get("ok",false))
		far_ready=r._services.workforce.availability({"kind":"settlement.read_story","actor_id":"player","target_id":id,"payload":far})
	check("remote recall cannot bypass original social contact LOS",not far_ready.ok and far_ready.code=="OUT_OF_REACH",far_ready)
	if not social_contact(r,id,false):check("actual social route to original carrier",false);return finish()
	var revoke:Dictionary=send(r,"consent",id,{"enabled":false})
	check("actual carrier may revoke work consent without losing real history",revoke.ok and not r.actor(id).relationship.consent and not experience(r,id).is_empty())
	var before:Dictionary=economic(r);var ledger:int=r.facts().ledger.size();var original:Dictionary=experience(r,id)
	var reviewed:Dictionary=send(r,"settlement.read_story",id,review_payload(r,id))
	check("on-site once-only review accepts real delivery despite work consent withdrawal",reviewed.ok and people(r)[id].get("reviewed",false),reviewed)
	check("review changes no body inventory knowledge production logistics modules geometry simulation or costs",Data.json_equal(before,economic(r)))
	check("review ledger points at exact original person event action and destination",r.facts().ledger.size()==mini(256,ledger+1) and r.facts().ledger.back().kind=="settlement-story-reviewed" and r.facts().ledger.back().event_id==original.event_id and r.facts().ledger.back().person_id==id and r.facts().ledger.back().destination_id==original.destination_id)
	var view:Dictionary=current_story(r)
	check("readable reviewed memory names the actual action and actual destination",str(view.text).contains(original.destination_id) and str(view.text).contains("交付") and view.experiences[id].event_id==original.event_id)
	check("withdrawn consent offers no forced rest job or new reward",view.reward==null and not view.followups.any(func(c:Dictionary)->bool:return c.get("target_id")==id and c.get("kind")=="job"))
	var repeated:Dictionary=send(r,"settlement.read_story",id,review_payload(r,id))
	check("new command cannot award a second review",not repeated.ok and repeated.code=="ALREADY_REVIEWED",repeated)
	var cold:Dictionary=cold_restore(r,"actual-review-withdrawn-cold")
	if not cold.get("ok",false):return finish()
	r=cold.runtime;live=r
	check("withdrawal original event context and once-only review all survive cold",not r.actor(id).relationship.consent and people(r)[id].reviewed and Data.json_equal(experience(r,id),original))
	id="village-resident"
	if not social_contact(r,id,true):check("actual social route to second original carrier",false);return finish()
	var second:Dictionary=send(r,"settlement.read_story",id,review_payload(r,id))
	check("other permanent person has their own actual on-site review",second.ok and people(r)[id].reviewed and people(r)["repair-resident"].reviewed,second)
	view=current_story(r)
	var rest_requests:Array=view.followups.filter(func(c:Dictionary)->bool:return c.get("kind")=="job" and c.get("target_id")==id)
	check("rest followup only describes original permitted job command",rest_requests.size()==1 and rest_requests[0].payload=={"job":"rest"})
	if rest_requests.size()==1:
		var rest:Dictionary=send(r,"job",id,rest_requests[0].payload)
		check("actual optional rest uses original Runtime job transaction",rest.ok and r.actor(id).job=="rest",rest)
	check("view jobs followup is only a real panel request not a gameplay reward",view.followups.any(func(c:Dictionary)->bool:return c.get("panel")=="workforce" and c.get("target_id")==id) and view.reward==null)
	cold=cold_restore(r,"actual-both-reviews-and-original-rest-cold")
	check("two reviews and actual rest preserve all canonical authority",cold.get("ok",false))
	finish()
func finish()->void:
	if live!=null:save(live,"shared-review-final")
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var report:Dictionary={"checks":checks,"failed":failed,"sources":sources,"commands":commands,"fixed_steps":ticks,"simulated_seconds":ticks*0.1,"scope":"Actual own22 normal53 original two completed deliveries, immutable23 plus exact E source overlay. No injected events, items, bodies, position, capture or second clock. Bounded function only; no OS VA FPS long-time qualification."}
	FileAccess.open(output_dir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)

func no_experience(r:RefCounted)->void:
	step(r)
	check("real prechoice normal source has no delivery or cooperative combat history",experience(r,"repair-resident").is_empty() and experience(r,"village-resident").is_empty())
	var request:Dictionary={"kind":"settlement.read_story","actor_id":"player","target_id":"repair-resident","payload":{"story_id":"ST02","person_id":"repair-resident","event_id":"not-a-real-event"}}
	var ready:Dictionary=r._services.workforce.availability(request)
	check("no real shared event offers no review or fake location",not ready.ok and ready.code=="SHARED_EXPERIENCE_REQUIRED" and current_story(r).commands.is_empty(),ready)
	var stable:Dictionary=r.capture_checkpoint();r._services.workforce.availability(request);r._services.workforce.projection()
	check("negative queries do not mutate authority",Data.json_equal(stable,r.capture_checkpoint()))
	var cold:Dictionary=cold_restore(r,"normal-no-experience-cold")
	check("absence of shared history survives exact cold",cold.get("ok",false))
	finish()
func defense_history(r:RefCounted)->void:
	var actual:Array=r.facts().ledger.filter(func(e:Dictionary)->bool:return e.kind=="combat-hit" and e.get("actor_id") in ["village-resident","repair-resident"])
	check("source is real original G3 actual companion combat against original infected",actual.size()==2 and r.facts().ledger.all(func(e:Dictionary)->bool:return e.kind!="logistics-delivery-completed"))
	step(r)
	for event:Dictionary in actual:
		var memory:Dictionary=experience(r,event.actor_id)
		check("original actual cooperative hit has own identity target and real position "+str(event.actor_id),memory.get("event_id")==event.id and memory.get("action")=="defense" and memory.get("target_id")==event.target_id and Data.json_equal(memory.location,event.position.merged({"regionId":r.actor(event.actor_id).regionId})))
	var before:Dictionary=r.capture_checkpoint();r._services.workforce.projection()
	check("combat memory projection does not stop or rewrite original fight",Data.json_equal(before,r.capture_checkpoint()))
	var cold:Dictionary=cold_restore(r,"actual-original-cooperative-defense-memory")
	check("original live combat plus shared memories preserves full canonical cold",cold.get("ok",false))
	finish()
