extends SceneTree
const Factory=preload("res://scripts/world/factory_generator.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const BeforeContract=preload("res://tests/world/fixtures/generation_before_story8.gd")
const BeforeFactory=preload("res://tests/world/fixtures/generator_before_story8.gd")
const Entrance=preload("res://scripts/world/factory_story_entrances.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
func _init()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:checks.append({"label":label,"ok":ok,"detail":detail})
func run()->void:
	var report:String=OS.get_cmdline_user_args()[0];var profiles:Array=Catalog.profiles()
	for version:int in range(1,8):
		var story:int=1 if version>=3 else 0
		var old:Dictionary=BeforeContract.fresh(profiles,version,story);var now:Dictionary=Contract.fresh(profiles,version,story)
		check("historical%d whole lock bytes unchanged"%version,old.ok and now.ok and JSON.stringify(old.contract,"",true,true)==JSON.stringify(now.contract,"",true,true) and Contract.resolve(old.contract,profiles).ok)
		for coord:Vector2i in [Vector2i.ZERO,Vector2i(0,-1)]:
			var before:Dictionary=BeforeFactory.plan_region(713,coord,profiles,old.contract);var after:Dictionary=Factory.plan_region(713,coord,profiles,old.contract)
			check("historical%d %s whole saved plan unchanged"%[version,coord],before.ok and after.ok and Data.json_equal(before.plan,after.plan) and not after.plan.has("story_entrances"))
	var lock:Dictionary=Contract.fresh(profiles,8,1)
	check("explicit8 retains original policies and adds entrance policy only",lock.ok and lock.contract.story_entrance_policy=="yard-stone-v1" and lock.contract.story_site_policy=="s01-s03-v1" and lock.contract.tool_recovery_policy=="mt01-v1" and lock.contract.water_recovery_policy=="wt01-v1" and Contract.fresh(profiles).contract.content_version==2)
	for mode:String in ["missing","tampered","old-injection"]:
		var bad:Dictionary=lock.contract.duplicate(true)
		if mode=="missing":bad.erase("story_entrance_policy")
		elif mode=="tampered":bad.story_entrance_policy="other"
		else:bad=Contract.fresh(profiles,7,1).contract;bad.story_entrance_policy="yard-stone-v1"
		check("strict saved entrance policy "+mode,Contract.resolve(bad,profiles).get("code")=="FACTORY_GENERATION_POLICY_MISMATCH")
	var rows:Array=[]
	for seed:int in [713,2026,17,999]:
		for coord:Vector2i in [Vector2i(-1,0),Vector2i(0,-1),Vector2i.ZERO]:
			var one:Dictionary=Factory.plan_region(seed,coord,profiles,lock.contract);var two:Dictionary=Factory.plan_region(seed,coord,profiles,lock.contract)
			var old:Dictionary=BeforeFactory.plan_region(seed,coord,profiles,BeforeContract.fresh(profiles,7,1).contract)
			check("seed%d %s content8 deterministic bounded placement"%[seed,coord],one.ok and two.ok and Data.json_equal(one.plan,two.plan),one.get("reason"))
			if not one.ok:continue
			check("seed%d %s retains old EV identity, original sites and sources"%[seed,coord],Data.json_equal(one.plan.regional_sites,old.plan.regional_sites) and Data.json_equal(one.plan.story_sites,old.plan.story_sites) and Data.json_equal(one.plan.content_anchors,old.plan.content_anchors) and one.plan.story_entrances.size()==(1 if coord==Vector2i.ZERO else 0))
			if coord==Vector2i.ZERO:rows.append({"seed":seed,"site":one.plan.story_entrances[0]})
	var draft:Dictionary=Factory.draft_region(713,Vector2i.ZERO,profiles,lock.contract)
	check("actual raster includes 24 exact physical stone cells and original 12 base cells",draft.get("ok",false) and draft.plan.story_entrances[0].obstacle_cells.size()==24 and draft.plan.story_entrances[0].base_cells.size()==12)
	if draft.get("ok",false):
		var original:Dictionary=draft.duplicate(true);var site:Dictionary=draft.plan.story_entrances[0]
		# One occupied cell is enough to reject, without partial writes to any
		# other detached air cell. This is an explicit isolated conflict fixture.
		for c:Dictionary in site.obstacle_cells:
			var cell:=Vector3i(c.x,c.y,c.z);draft.chunks[Data.key(Data.cell_chunk(cell,16))].cells[Data.local_index(cell,16)]=0
		var conflict:Dictionary=site.obstacle_cells[-1];var cv:=Vector3i(conflict.x,conflict.y,conflict.z)
		draft.chunks[Data.key(Data.cell_chunk(cv,16))].cells[Data.local_index(cv,16)]=2
		var before_conflict:Dictionary=draft.duplicate(true);var rejected:Dictionary=Entrance.apply(draft)
		check("one occupied cell rejects all detached placement atomically",rejected.get("code")=="S01_ENTRANCE_OCCUPIED_OR_UNSUPPORTED_CELL" and Data.json_equal(before_conflict,draft))
		check("normal placement never aliases an independently copied draft",original.plan.story_entrances[0].obstacle_cells.all(func(c:Dictionary)->bool:var v:=Vector3i(c.x,c.y,c.z);return original.chunks[Data.key(Data.cell_chunk(v,16))].cells[Data.local_index(v,16)]==3))
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(report,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"rows":rows,"scope":"post23 explicit content8 plan/contract/raster and isolated placement atomicity; no package/OS/normal route qualification"},"\t",true,true));quit(1 if failed else 0)
