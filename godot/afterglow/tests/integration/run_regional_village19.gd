extends SceneTree

const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Generator=preload("res://scripts/world/factory_generator.gd")
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Regional=preload("res://scripts/modules/village_regional_catalog.gd")
const Layout=preload("res://scripts/world/village_opening_layout.gd")
var checks:Array=[]

func _initialize()->void:call_deferred("run")

func run()->void:
	var args:=OS.get_cmdline_user_args()
	var profiles:=Assembly.generation_profiles(19)
	var lock:=Contract.fresh(profiles.profiles,19,1)
	var old_lock:=Contract.fresh(Assembly.generation_profiles(18).profiles,18,1)
	var old_from_current:=Contract.fresh(profiles.profiles,18,1)
	_verify("new profiles do not change the old generation lock",old_lock.ok and old_from_current.ok and Contract.digest(old_lock.contract)==Contract.digest(old_from_current.contract))
	var east:=Vector2i(1,0)
	var found:int=0
	for seed:int in 32:
		if Layout.variant(seed,east)!=3:continue
		var current:=Generator.draft_region(seed,east,profiles.profiles,lock.contract)
		var previous:=Generator.draft_region(seed,east,profiles.profiles,old_lock.contract)
		_verify("field depot is generated and historical plan retains the old model at seed %d"%seed,current.ok and previous.ok and _depot(current.plan)==Regional.SHED and _depot(previous.plan)=="r34.module.warehouse_long_v3")
		found+=1
		if found==3:break
	_verify("three independently generated peripheral depots checked",found==3)
	var old:=Store.decode(FileAccess.get_file_as_string(args[1]))
	var client:=Native.new();var mounted:=client._assemble(old.capture) if old.ok else old;client.free()
	_verify("previous playable checkpoint cold-mounts without replacing its old store",mounted.ok and mounted.runtime._services.modules.instance("r34:generated:RH-VILLAGE:store").definition_id=="r34.module.supply_rear_v3")
	if mounted.ok:mounted.runtime.retire()
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed},"\t"))
	print(JSON.stringify({"regional_checks":checks.size(),"failed":failed}))
	quit(1 if failed else 0)

func _depot(plan:Dictionary)->String:
	for row:Dictionary in plan.module_seeds:
		if row.purpose=="field-stockyard":return row.definition_id
	return ""

func _verify(label:String,ok:bool)->void:
	checks.append({"label":label,"ok":ok})
	if not ok:print("FAIL "+label)
