extends "res://tests/modules/run_factory_lifecycle.gd"
const Identity=preload("res://scripts/modules/module_identity.gd")
var aggregate_checked:=false
func run()->void:
	var values:Array=[null,0,12.5,false,[],{},"","__proto__","constructor","prototype","good:id","中文😀:原件"," ",String.chr(127),"x".repeat(240),"x".repeat(241)]
	for code:int in 32:
		values.append(String.chr(code));values.append("valid:"+String.chr(code)+":tail")
	for value:Variant in values:
		check("native predicate exact before and after reuse "+str(values.find(value)),Identity.valid_id(value)==Data.valid_id(value) and Identity.valid_id(value)==Data.valid_id(value))
	for i:int in 2200:Identity.valid_id("B:bounded-pure-id:"+str(i))
	check("bounded eviction never changes original string policy",Identity.valid_id("中文😀:原件") and not Identity.valid_id("valid:"+String.chr(31)+":tail") and not Identity.valid_id("prototype"))
	super.run()
func advance(rt:RefCounted,services:Dictionary,steps:int,domain:String)->void:
	super.advance(rt,services,steps,domain)
	if not aggregate_checked and domain=="production":
		var state:Dictionary=rt.world.extension(Factory.KEY)
		if state is Dictionary and not state.batches.is_empty() and Factory.live_batch(state.batches[0]):
			aggregate_checked=true;aggregate(rt,services,state)
func aggregate(rt:RefCounted,services:Dictionary,p:Dictionary)->void:
	var before:Dictionary=rt.capture_checkpoint();var modules:RefCounted=services.modules;var production:RefCounted=services.production
	var facts:Dictionary=rt.facts();var m:Dictionary=modules.instance(str(p.batches[0].module_id));var out:String=m.stock_refs.output
	var definition:Dictionary=Modules.definition(m.definition_id);var limit:float=Draft.find(definition.buffer_specs,"output").limits.timber
	# Explicit staged owner-validator fixtures combine all three EXISTING hold
	# kinds. They are not submitted as synthetic gameplay or a normal journey.
	var l:Dictionary=Factory.logistics_initial();l.tasks.append({"id":"B:validator:haul","source_id":m.stock_refs.input,"destination_id":out,"items":{"timber":2.0},"actor_id":"player","phase":"collect","status":"collecting","repeat":false,"priority":0.0,"created_at":0.0,"trips":0,"reason":""});Factory.sync_logistics(l)
	var legacy:Dictionary=production.state();var recipe_id:String=""
	for key:String in production.recipes:
		if production.recipes[key].get("outputs",{}).has("timber"):recipe_id=key;break
	check("real existing manual recipe supplies original output hold",not recipe_id.is_empty())
	if recipe_id.is_empty():return
	legacy.orders.append({"id":"B:validator:manual","status":"active","kind":"craft","outputId":out,"targetId":recipe_id})
	var overrides:Dictionary={Factory.KEY:p,Factory.LOGISTICS:l,production.KEY:legacy}
	var tx:=Draft.new(production.context);tx.staged=facts.duplicate(true);tx.extensions=overrides.duplicate(true)
	var promised:float=production.capacity_reserved(out,"timber","",tx)
	var expected:float=4.0+2.0+float(production.recipes[recipe_id].outputs.timber)
	check("original public reservation observer counts WIP logistics manual",promised==expected and promised>6.0)
	var full:Dictionary=facts.duplicate(true);Draft.find(full.stocks,out).items.timber=limit-promised
	check("exact aggregate boundary accepts all original holds",production.validate_extensions(full,overrides).ok)
	Draft.find(full.stocks,out).items.timber+=1
	check("one excess across combined holds rejects",production.validate_extensions(full,overrides).get("code")=="BUFFER_OVERCOMMITTED")
	var none:Dictionary=overrides.duplicate(true);none[Factory.KEY]=Factory.initial();none[Factory.LOGISTICS]=Factory.logistics_initial();none[production.KEY]=production.empty_state()
	Draft.find(full.stocks,out).items.timber=limit
	check("explicit empty overrides do not borrow live WIP or holds",production.validate_extensions(full,none).ok)
	Draft.find(full.stocks,out).items.timber=limit+1
	check("no promises still validates every buffer capacity",production.validate_extensions(full,none).get("code")=="BUFFER_OVERCOMMITTED")
	var bad:Dictionary=overrides.duplicate(true);bad[Factory.LOGISTICS].reservations[0].items.timber+=1
	check("forged reservation still rejects before capacity aggregation",production.validate_extensions(facts,bad).get("code")=="INVALID_LOGISTICS_RESERVATIONS")
	bad=overrides.duplicate(true);bad[Factory.KEY].batches[0].wip.log=2
	check("forged WIP still rejects its complete schema",production.validate_extensions(facts,bad).get("code")=="INVALID_FACTORY_WIP")
	var ms:Dictionary=modules.state();var member:Dictionary=ms.instances[0].members[0];Identity.valid_id(member.id)
	var malformed:Dictionary=ms.duplicate(true);malformed.instances[0].members[0].id+=String.chr(31)
	check("warm valid prefix cannot authorize a modified control ID",modules.validate_extensions(facts,{Modules.KEY:malformed}).get("code")=="INVALID_MODULE_MEMBERS")
	malformed=ms.duplicate(true);malformed.instances[0].members.append(member.duplicate(true))
	check("pure string reuse never skips duplicate member checks",modules.validate_extensions(facts,{Modules.KEY:malformed}).get("code")=="INVALID_MODULE_MEMBERS")
	malformed=ms.duplicate(true);malformed.instances[0].geometry_version="future"
	check("warm identities never skip version pin checks",modules.validate_extensions(facts,{Modules.KEY:malformed}).get("code")=="MODULE_GEOMETRY_VERSION_MISMATCH")
	check("all probes preserve world facts holds and time",Data.json_equal(before,rt.capture_checkpoint()))
func finish()->void:
	check("combined hold boundary sampled actual running batch",aggregate_checked)
	super.finish()
