extends SceneTree
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Reference=preload("res://tests/modules/advance_reference/domain_draft.gd")
const Runtime=preload("res://scripts/runtime/game_runtime.gd")
var held:Array=[]
var checks:Array=[]
class ExtensionView extends RefCounted:
	var values:Dictionary={"probe":{"version":1,"rows":[{"id":"one","n":1}]}}
	func extension(id:String)->Variant:
		var v:Variant=values.get(id)
		return v.duplicate(true) if v is Dictionary or v is Array else v
	func has_extension(id:String)->bool:return values.has(id)
func _initialize()->void:call_deferred("run")
func digest(value:Variant)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(var_to_bytes(value));return h.finish().hex_encode()
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail});if not ok:print("FAIL "+label)
func probe(script:Script,mode:String,fallback:bool)->Dictionary:
	var source:Dictionary={"scenario":"factory-settlement-r34","actors":[{"id":"player","pack":{"timber":4},"hp":100,"x":1.0,"y":0.5,"z":2.0,"regionId":"region"}],"stocks":[{"id":"stock","items":{"timber":2},"owner":null}],"actions":[],"quests":[],"ledger":[{"id":"event","items":{"n":1}}]}
	var source_before:Dictionary=source.duplicate(true);var view:=ExtensionView.new();var available:Dictionary={"value":true}
	var context:Dictionary={"world":view,"facts":func()->Dictionary:return source.duplicate(true),"available":func()->bool:return available.value}
	if not fallback:context.facts_diff=Runtime.facts_diff
	var tx:RefCounted=script.new() if mode=="default" else script.new(context)
	var details:Array=[]
	match mode:
		"initial-read":details.append(tx.initial.duplicate(true))
		"initial-reassign":tx.initial={"actors":[{"id":"replacement","pack":{}}],"stocks":[]}
		"initial-nested-write":tx.initial.actors[0].pack.timber=99
		"initial-reference-write":
			var initial_ref:Dictionary=tx.initial;initial_ref.ledger[0].items.n=55
		"staged-nested-write":tx.staged.actors[0].pack.timber=3
		"staged-reassign":tx.staged={"actors":[],"stocks":[]}
		"actor-stock":tx.actor("player").hp=90;details.append(tx.stock_delta("pack:player",{"timber":1},-1));details.append(tx.stock_delta("stock",{"timber":1}))
		"extensions":tx.extension("probe").rows[0].n=2;tx.extension("new",{"version":1,"rows":[]}).rows.append({"id":"new"})
		"fact-extension-combined":tx.actor("player").pack.timber=2;tx.extension("probe").rows[0].n=3
		"explicit-overlay":tx.initial=source.duplicate(true);tx.staged=source.duplicate(true);tx.extensions={"probe":{"version":1,"rows":[]}}
		"available-false":available.value=false
		"retired-switch":tx.actor("player").hp=90;tx.extra.append({"op":"probe"});tx.events.append({"kind":"probe"});available.value=false
		"snapshot-before-source-edit":source.actors[0].hp=5;source.ledger[0].items.n=7
		"initial-stage-reassign":tx.initial={"actors":[]};tx.staged=source.duplicate(true);tx.initial={"actors":[{"id":"other"}]}
		"extra-event":tx.extra.append({"op":"probe","data":{"n":1}});tx.events.append({"kind":"probe","data":{"n":1}})
		"stock-failure":details.append(tx.stock_delta("pack:player",{"timber":1,"unknown-item":2},-1))
		"stock-overdraw":details.append(tx.stock_delta("stock",{"timber":3},-1))
		"result-pollution":
			tx.actor("player").hp=90;tx.extension("probe").rows[0].n=2;var first:Dictionary=tx.result()
			first.fact_changes[0].after.hp=1;first.world_changes[0].after.rows[0].n=88
	var plan:Dictionary=tx.result()
	return {"initial":tx.initial.duplicate(true),"staged":tx.staged.duplicate(true),"extensions":tx.extensions.duplicate(true),"plan":plan,"details":details,"live_source":source,"source_before":source_before,"world":view.values}
func run()->void:
	var args:=OS.get_cmdline_user_args();var old:Script=Reference
	var modes:Array=["default","noop","initial-read","initial-reassign","initial-nested-write","initial-reference-write","staged-nested-write","staged-reassign","actor-stock","extensions","fact-extension-combined","explicit-overlay","available-false","retired-switch","snapshot-before-source-edit","initial-stage-reassign","extra-event","stock-failure","stock-overdraw","result-pollution"]
	for fallback:bool in [false,true]:
		for mode:String in modes:
			var before:Dictionary=probe(old,mode,fallback);var after:Dictionary=probe(Draft,mode,fallback)
			check(mode+" complete original/new contract; fallback="+str(fallback),digest(before)==digest(after),{"old":digest(before),"new":digest(after)})
	# The new observation API exposes only this Draft's detached snapshot; all
	# consumers are audited read-only. Mutating source after construction cannot
	# change that observation, and actual writes still deep-fork staged first.
	var live:Dictionary={"actors":[{"id":"player","hp":100}],"stocks":[]}
	var tx:=Draft.new({"facts":func()->Dictionary:return live.duplicate(true),"world":ExtensionView.new()})
	var observed:Dictionary=tx.observe_facts();live.actors[0].hp=50
	check("observation is constructor-time detached facts",observed.actors[0].hp==100)
	tx.staged=observed.duplicate(true);tx.actor("player").hp=80
	check("fork before actual write isolates source and observed facts",live.actors[0].hp==50 and observed.actors[0].hp==100 and tx.staged.actors[0].hp==80)
	var report:Dictionary={"checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size(),"scope":"Exact old/new Draft contract and detached adapter isolation fixtures; not normal gameplay"}
	FileAccess.open(args[0]+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));quit(0 if report.failed==0 else 1)
