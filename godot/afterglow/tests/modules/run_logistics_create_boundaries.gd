extends "res://tests/modules/factory_boundary_fixture.gd"
## Real logistics.create admission and actual workforce claims. Queued work
## itself promises no capacity: only the existing claimed-task reservation does.
var base:Dictionary={}
var source_id:String="B:create:finite-source"
var destination_id:String=""
var limit:int=0
var receiver:Dictionary={}
func attempt(label:String,capture:Dictionary,items:Variant,expected:String,actor_id:String="player",source:String="",destination:String="")->Dictionary:
	var mounted:=mount(capture,label)
	if not mounted.ok:return {}
	var rt:RefCounted=mounted.runtime;var before:Dictionary=rt.capture_checkpoint()
	var result:=command(rt,"logistics.create","",{"source_id":source_id if source.is_empty() else source,"destination_id":destination_id if destination.is_empty() else destination,"items":items},actor_id)
	var accepted:bool=expected=="OK"
	check(label+" returns exact admission outcome",result.ok==accepted and (accepted or result.get("code")==expected),result)
	if not accepted:check(label+" rejection preserves full authority and finite goods",Data.json_equal(before,rt.capture_checkpoint()))
	else:
		var l:Dictionary=rt.world.extension(Factory.LOGISTICS)
		check(label+" only creates one queued task without transferring or reserving",l.tasks.size()==1 and l.tasks[0].status=="queued" and l.reservations.is_empty() and Data.json_equal(before.facts.stocks,rt.facts().stocks) and Data.json_equal(before.facts.actors,rt.facts().actors))
	return mounted
func run()->void:
	base=opening()
	if base.is_empty():finish();return
	var m:Dictionary=base.world.extensions[Modules.KEY].instances.filter(func(v:Dictionary)->bool:return Modules.definition(v.definition_id).shape=="manual" and v.region=="RH-HOME")[0]
	destination_id=m.stock_refs.tools
	var d:Dictionary=Modules.definition(m.definition_id)
	limit=int(Draft.find(d.buffer_specs,"tools").limits.timber)
	receiver=port(m,"work")
	Draft.find(base.facts.stocks,destination_id).searched=true
	Draft.find(base.facts.stocks,destination_id).items.timber=limit-2
	base.facts.stocks.append({"id":source_id,"items":{"timber":8,"log":2},"owner":"home-residents","searched":true,"location":receiver.duplicate(true)})
	var worker:=Draft.find(base.facts.actors,"repair-resident")
	worker.merge(G.location(receiver),true);worker.intent=null;worker.pack={};worker.job="rest";worker.householdId=null
	worker.relationship.member=false;worker.relationship.consent=false;worker.relationship.home_arrived=false
	attempt("nonmember lacks shared logistics authority",base,{"timber":1},"LOGISTICS_PERMISSION","repair-resident")
	var denied:Dictionary=base.duplicate(true)
	worker=Draft.find(denied.facts.actors,"repair-resident");worker.relationship.member=true
	attempt("membership without consent grants no logistics authority",denied,{"timber":1},"LOGISTICS_PERMISSION","repair-resident")
	denied=base.duplicate(true);Draft.find(denied.facts.stocks,source_id).owner="unrelated:owner"
	attempt("foreign source owner refuses real create",denied,{"timber":1},"INVALID_LOGISTICS_ENDPOINT")
	denied=base.duplicate(true)
	var foreign:Dictionary={"id":"B:create:foreign-destination","items":{},"owner":"unrelated:owner","searched":true,"location":receiver}
	denied.facts.stocks.append(foreign)
	attempt("foreign destination owner refuses real create",denied,{"timber":1},"INVALID_LOGISTICS_ENDPOINT","player","",foreign.id)
	for id:String in [source_id,destination_id]:
		denied=base.duplicate(true);Draft.find(denied.facts.stocks,id).searched=false
		attempt("unsearched endpoint refuses "+id,denied,{"timber":1},"INVALID_LOGISTICS_ENDPOINT")
	attempt("self transfer refuses",base,{"timber":1},"INVALID_LOGISTICS_ENDPOINT","player",source_id,source_id)
	attempt("pack endpoint refuses",base,{"timber":1},"INVALID_LOGISTICS_ENDPOINT","player",source_id,"pack:player")
	attempt("actual destination filter refuses log",base,{"log":1},"BUFFER_FILTER")
	for value:Variant in [0,-1,0.5,"1"]:attempt("illegal amount "+str(value),base,{"timber":value},"INVALID_LOGISTICS_ITEMS")
	attempt("empty items refuse",base,{},"INVALID_LOGISTICS_ITEMS")
	attempt("exact destination room accepts",base,{"timber":2},"OK")
	attempt("one over destination room refuses",base,{"timber":3},"BUFFER_FULL")
	denied=base.duplicate(true);Draft.find(denied.facts.stocks,destination_id).items.timber=limit
	attempt("actual completely full destination refuses",denied,{"timber":1},"BUFFER_FULL")
	# Exercise the actual owned-task reservation through B's formal executor.
	var claimed:Dictionary=base.duplicate(true)
	worker=Draft.find(claimed.facts.actors,"repair-resident");worker.relationship.member=true;worker.relationship.consent=true;worker.relationship.home_arrived=true;worker.householdId="home-residents";worker.hunger=90.0;worker.thirst=90.0;worker.fatigue=0.0
	var mounted:=mount(claimed,"claimed capacity fixture")
	if not mounted.ok:finish();return
	var rt:RefCounted=mounted.runtime;var services:Dictionary=mounted.services
	var created:=command(rt,"logistics.create","",{"source_id":source_id,"destination_id":destination_id,"items":{"timber":1}})
	check("real task accepts before workforce claim",created.ok)
	if not created.ok:finish();return
	var task:Dictionary=rt.world.extension(Factory.LOGISTICS).tasks[0]
	var prepared:Dictionary=services.actions.prepare_workforce({"actor_id":"repair-resident","candidate_id":task.id,"command_id":"B:create:claim"})
	var committed:Dictionary=rt._commit(prepared) if prepared.ok else prepared
	check("actual B executor claims one finite unit and destination promise",committed.ok and services.production.capacity_reserved(destination_id,"timber")==1,committed)
	if not committed.ok:finish();return
	var before:Dictionary=rt.capture_checkpoint()
	var refused:=command(rt,"logistics.create","",{"source_id":source_id,"destination_id":destination_id,"items":{"timber":2}})
	check("real create includes other actual task's destination reservation",not refused.ok and refused.get("code")=="BUFFER_FULL" and Data.json_equal(before,rt.capture_checkpoint()),refused)
	var exact:=command(rt,"logistics.create","",{"source_id":source_id,"destination_id":destination_id,"items":{"timber":1}})
	check("exact unpromised remainder queues without duplicating current goods",exact.ok and rt.world.extension(Factory.LOGISTICS).tasks.size()==2 and services.production.capacity_reserved(destination_id,"timber")==1 and rt.stock(source_id).items.timber==8 and rt.stock(destination_id).items.timber==limit-2 and rt.actor("repair-resident").pack.is_empty())
	var cold:=mount(rt.capture_checkpoint(),"claimed plus queued capacity cold checkpoint")
	check("restore preserves original reservation and all physical goods",cold.ok and cold.services.production.capacity_reserved(destination_id,"timber")==1 and cold.runtime.stock(source_id).items.timber==8 and cold.runtime.stock(destination_id).items.timber==limit-2)
	evidence.append({"destination_id":destination_id,"limit":limit,"logistics":rt.world.extension(Factory.LOGISTICS),"scope":"create checks actual plus claimed promises; queued tasks do not reserve until claimed"})
	finish()
