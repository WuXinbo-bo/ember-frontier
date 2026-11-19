extends SceneTree
const Before=preload("res://tests/world/fixtures/prepare_20261115_before.gd")
const Current=preload("res://scripts/world/world_state.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool)->void:
	checks.append({"label":label,"ok":ok})
	if not ok:push_error("FAIL "+label)
func source()->Dictionary:
	var cells:=PackedInt32Array();cells.resize(64);cells.fill(1)
	return {"schemaVersion":1,"worldId":"test:prepare-isolation","seed":713,"generatorVersion":"rural-1","revision":0,"config":{"cellSize":0.5,"chunkCells":4,"minCellY":-8,"maxCellY":40,"maxEditCells":256,"maxReach":2.5},"regions":{"r":{"id":"r","bounds":{"min":{"x":-4,"y":-4,"z":-4},"max":{"x":4,"y":8,"z":4}},"exits":[],"editAreas":[],"generated":true}},"entities":{"e":{"id":"e","position":{"x":0.5,"y":0,"z":0.5},"bounds":{"min":{"x":0,"y":0,"z":0},"max":{"x":1,"y":1,"z":1}},"regionId":"r","revision":0,"metadata":{"door":{"open":false}}}},"extensions":{"test:extension":{"nested":[{"v":1}]}},"receipts":{},"retiredEntityIds":[],"chunks":{"0,-1,0":{"key":"0,-1,0","coord":{"x":0,"y":-1,"z":0},"cells":cells,"revision":0,"resident":true,"generated":true,"generatorVersion":"rural-1"}}}
func entity_op(w:RefCounted,after:Dictionary)->Dictionary:
	return {"op":"entity.put","id":"e","before_exists":true,"before":w.entity("e"),"after":after}
func run()->void:
	var original:=source()
	var a:=Before.new();var b:=Current.new()
	check("same baseline/current schema load",a.load_snapshot(original).ok and b.load_snapshot(original).ok)
	var good:Dictionary=b.entity("e");good.metadata.door.open=true
	var cases:Array=[[],[entity_op(b,good)],[{"op":"extension.set","id":"test:extension","before_exists":true,"before":b.extension("test:extension"),"after":{"nested":[{"v":2}]}}],[{"op":"entity.remove","id":"e","before":b.entity("e")}],[{"op":"voxel.set","cell":{"x":0,"y":-1,"z":0},"before":1,"after":2}]]
	for pair:Array in [["id","spoof"],["position",{}],["position",{"x":5,"y":0,"z":0}],["bounds",{}],["bounds",{"min":{"x":1,"y":0,"z":0},"max":{"x":0,"y":1,"z":1}}],["regionId","missing"],["metadata",{"bad":NAN}],["metadata",{"bad":RefCounted.new()}]]:
		var bad:Dictionary=good.duplicate(true);bad[pair[0]]=pair[1];cases.append([entity_op(b,bad)])
	var wrong_before:=entity_op(b,good);wrong_before.before={};cases.append([wrong_before])
	var wrong_exists:=entity_op(b,good);wrong_exists.before_exists=false;cases.append([wrong_exists])
	var missing:=entity_op(b,good);missing.erase("before");cases.append([missing])
	cases.append([entity_op(b,good),entity_op(b,good)])
	var new_bad:=entity_op(b,good);new_bad.id="new";new_bad.before_exists=false;new_bad.before=null;cases.append([new_bad])
	var new_good:Dictionary=good.duplicate(true);new_good.id="new";new_bad=new_bad.duplicate(true);new_bad.after=new_good;cases.append([new_bad])
	cases.append([entity_op(b,good),{"op":"voxel.set","cell":{"x":0,"y":-1,"z":0},"before":1,"after":2}])
	for i in cases.size():
		var p:Dictionary=a.prepare_changes(cases[i],0);var q:Dictionary=b.prepare_changes(cases[i],0)
		check("full-schema/metadata/mixed differential result "+str(i),p.ok==q.ok and p.code==q.code and p.get("reason")==q.get("reason"))
		if p.ok:
			check("complete isolated projection/receipt equivalent "+str(i),Data.json_equal(p.view.snapshot(),q.view.snapshot()) and Data.json_equal(p.changes,q.changes))
			a.discard_prepared(p.capability);b.discard_prepared(q.capability)
	check("all candidate rejections/discards leave base facts exact",Data.json_equal(a.snapshot(),original) and Data.json_equal(b.snapshot(),original))
	var input:Array=[entity_op(b,good),{"op":"extension.set","id":"test:extension","before_exists":true,"before":b.extension("test:extension"),"after":{"nested":[{"v":2}]}},{"op":"voxel.set","cell":{"x":0,"y":-1,"z":0},"before":1,"after":2}]
	var tx:=b.prepare_changes(input,0);var expected:Dictionary=tx.view.snapshot();var receipt:Dictionary=tx.changes.duplicate(true)
	input[0].after.metadata.door.open=false;input[1].after.nested[0].v=999
	tx.view._state.entities.e.metadata.door.open=false;tx.view._state.extensions["test:extension"].nested[0].v=333
	tx.view._state.chunks["0,-1,0"].cells.fill(0)
	tx.changes.operations[0].after.metadata.door.open=false;tx.changes.operations[1].after.nested[0].v=777;tx.changes.operations.clear()
	check("public input/view/reflection/receipt cannot mutate live base",Data.json_equal(b.snapshot(),original))
	var committed:=b.commit_prepared(tx.capability)
	check("all reflection attacks leave exact private capability world",committed.ok and Data.json_equal(b.snapshot(),expected))
	check("private receipt unaffected by public result/input edits",Data.json_equal(committed.changes,receipt))
	committed.changes.operations[1].after.nested[0].v=444
	check("commit receipt remains detached from committed extension",b.extension("test:extension").nested[0].v==2)
	check("single-use capability rejected",b.commit_prepared(tx.capability).code=="PREPARED_CLOSED")
	var stale:=b.prepare_changes([],b.get_revision());b.load_snapshot(original)
	check("reload epoch invalidates previous capability",not b.commit_prepared(stale.capability).ok)
	check("revision CAS refuses stale request",b.prepare_changes([],1).code=="STALE_WORLD_REVISION")
	var tokens:Array=[]
	for i in 32:tokens.append(b.prepare_changes([],0).capability)
	check("bounded outstanding capabilities retained",b.prepare_changes([],0).code=="TOO_MANY_PREPARED")
	b.discard_prepared(tokens.pop_back())
	var reclaim:=b.prepare_changes([],0);check("discard reclaims exactly one capability slot",reclaim.ok)
	b.load_snapshot(original);tokens.clear()
	var remove:=b.prepare_changes([{"op":"entity.remove","id":"e","before":b.entity("e")}],0)
	check("structural remove still fully validated and commits",remove.ok and b.commit_prepared(remove.capability).ok)
	check("retired ID cannot be reintroduced",b.prepare_changes([{"op":"entity.put","id":"e","before_exists":false,"before":null,"after":good}],b.get_revision()).code=="RETIRED_ENTITY_ID")
	var failed:int=checks.filter(func(c:Dictionary):return not c.ok).size()
	var result:Dictionary={"failed":failed,"checks":checks,"scope":"Differential exact schema/rejection/output and private draft/receipt isolation; real old-source transaction timing in separate paired probe. No final B safety bypass."}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));quit(1 if failed else 0)
