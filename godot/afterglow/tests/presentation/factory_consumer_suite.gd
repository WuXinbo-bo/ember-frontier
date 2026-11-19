extends SceneTree
## Explicit owner-DTO counterexamples, not owner integration or visual approval.
const View=preload("res://scripts/presentation/factory_view.gd")
const Stock=preload("res://scripts/presentation/factory_stock_view.gd")
const Contracts=preload("res://scripts/runtime/factory_contracts.gd")
class Authority extends RefCounted:
	var world:=RefCounted.new()
	var dto:Dictionary={}
	var queries:=0
	func factory_snapshot()->Dictionary:
		queries+=1
		return dto.duplicate(true)
var checks:Array=[]
var failures:Array=[]

func expect(label:String,ok:bool,evidence:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"evidence":evidence})
	if not ok:failures.append(label);print("FAIL ",label," ",JSON.stringify(evidence))

func _initialize()->void:call_deferred("run")

static func instance(id:String)->Dictionary:
	return {"id":id,"location":{"x":12.0,"y":2.0,"z":-8.0},"quarter_turn":1,"state_code":"running","visuals":{
		"anchors":{"output":{"position":[15.0,2.0,-10.0],"forward":[1.0,0.0],"quarter_turn":3},"work":{"position":[14.0,2.9,-9.0],"forward":[0.0,1.0],"quarter_turn":2}},
		"buffers":[{"id":"wood","stock_ref":"stock:"+id,"item_id":"wood","unit":"m3","actual":5.0,"capacity":10.0,"reserved":3.0,"representation":"log","anchor_id":"output","extent":[1.2,0.9,1.8]}],
		"mechanism":{"kind":"reciprocating_saw","anchor_id":"work","active":true,"phase":"processing","progress_seconds":0.2,"duration_seconds":6.0,"effective_work":0.1,"paused_reason":""},"construction":{},"damage":{}}}

static func snapshot()->Dictionary:
	var dto:Dictionary=Contracts.empty_snapshot("fixture-world",1,1)
	dto.available=true;dto.modules={"available":true,"instances":[instance("a"),instance("b")],"projects":[],"definitions":[]}
	return dto

func has_error(view:Node3D,code:String)->bool:
	return view.statistics().required_errors.any(func(row:Dictionary)->bool:return row.code==code)

func run()->void:
	var parent:=Node3D.new();root.add_child(parent)
	parent.position=Vector3(40,5,90);parent.rotation.y=1.2;parent.scale=Vector3.ONE*1.3
	var view:=View.new();parent.add_child(view);view.set_process(false)
	view.configure(RefCounted.new())
	expect("missing API never creates fake instances",view.get_child_count()==0 and not view.statistics().available)
	var authority:=Authority.new();authority.dto=snapshot();view.configure(authority)
	expect("two module DTOs produce two isolated roots",view._roots.size()==2 and view.get_child_count()==2)
	var stock:Node3D=view._buffers.a.wood
	var machine:Node3D=view._machines.a
	expect("world anchor applied once under rotated module and transformed parent",stock.global_position.is_equal_approx(Vector3(15,2,-10)) and stock.global_basis.is_equal_approx(Basis(Vector3.UP,-3*PI/2)),str(stock.global_transform))
	expect("mechanism uses independent world contact anchor",machine.global_position.is_equal_approx(Vector3(14,2.9,-9)),str(machine.global_transform))
	var root_id:int=view._roots.a.get_instance_id();var part_id:int=stock.get_child(0).get_instance_id()
	var mesh_id:int=stock.get_child(0).mesh.get_instance_id()
	var unchanged:String=JSON.stringify(authority.dto);var count:int=view.statistics().updates
	view.sync()
	expect("unchanged sync retains nodes and avoids reapplying visuals",view.statistics().updates==count and view._roots.a.get_instance_id()==root_id)
	parent.position+=Vector3(5,2,1);view.sync()
	expect("host movement does not move cached world anchors",stock.global_position.is_equal_approx(Vector3(15,2,-10)))
	authority.dto.modules.instances[0].visuals.buffers[0].actual=6.0;view.sync()
	expect("same stock band changes actual without rebuilding proxy geometry",stock.get_child(0).get_instance_id()==part_id and stock.get_child(0).mesh.get_instance_id()==mesh_id and stock.statistics().actual==6.0)
	expect("reserved output capacity never subtracts from visible actual",stock.statistics().band==2 and stock.statistics().visible_parts==3,stock.statistics())
	for amount:float in [0.0,1.0,5.0,9.0,10.0]:
		authority.dto.modules.instances[0].visuals.buffers[0].actual=amount;view.sync()
		expect("five-band visibility follows true stock "+str(amount),stock.statistics().visible_parts==Stock.BAND_COUNTS[Stock.band(amount,10.0)],stock.statistics())
	var count_row:Dictionary=authority.dto.modules.instances[0].visuals.buffers[0].duplicate(true)
	count_row.id="bottles";count_row.item_id="water_bottle";count_row.unit="count";count_row.actual=4;count_row.representation="crate"
	authority.dto.modules.instances[0].visuals.buffers.append(count_row);view.sync()
	expect("count and cubic metres remain separate item rows",view._buffers.a.size()==2 and view._buffers.a.bottles.get_meta("unit")=="count" and stock.get_meta("unit")=="m3")
	authority.dto.modules.instances[0].visuals.buffers[1].representation="liquid";view.sync()
	expect("count bottles never become a fake liquid surface",has_error(view,"LIQUID_UNIT_REQUIRED") and not view._buffers.a.bottles.visible)
	view.sync();expect("invalid stable snapshots retain diagnostics",has_error(view,"LIQUID_UNIT_REQUIRED"))
	authority.dto.modules.instances[0].visuals.buffers[1].representation="mystery";view.sync()
	expect("unknown representation is explicit failure with no commodity shown",has_error(view,"UNSUPPORTED_REPRESENTATION") and not view._buffers.a.bottles.visible)
	authority.dto=snapshot();view.sync();machine=view._machines.a
	var blade:Vector3=machine._blade.position;var crank:Vector3=machine._crank.rotation
	view._process(20.0)
	expect("wall delta never advances machinery or owner DTO",machine._blade.position==blade and machine._crank.rotation==crank and JSON.stringify(authority.dto)==unchanged)
	for reason:String in ["missing_energy","paused","damaged","region_paused"]:
		authority.dto.modules.instances[0].state_code=reason;view.sync()
		expect("non-running module cannot display active cutting "+reason,not machine.statistics().active and machine._chips.all(func(p:Node3D)->bool:return not p.visible))
	authority.dto.modules.instances[0].state_code="running"
	authority.dto.modules.instances[0].visuals.mechanism.paused_reason="missing_energy";view.sync()
	expect("mechanism blocker overrides an inconsistent active flag",not machine.statistics().active)
	authority.dto.modules.instances[0].visuals.mechanism={};view.sync()
	expect("removed mechanism releases visible active status",not machine.visible and not machine.statistics().active)
	authority.dto=snapshot();view.sync()
	authority.dto.modules.instances[0].visuals.buffers[0].anchor_id="absent";view.sync()
	expect("lost anchor removes stale stock at old position",not view._buffers.a.has("wood") and has_error(view,"BUFFER_ID_OR_ANCHOR_REQUIRED"))
	authority.dto=snapshot();view.sync()
	authority.dto.modules.instances[0].definition_id="fixture:woodshop"
	authority.dto.modules.definitions=[{"id":"fixture:woodshop","state_assets":{"damaged":"b_wood_damaged"}}]
	authority.dto.modules.instances[0].visuals.construction={"active":true,"project_id":"real-project","phase":"building","progress_seconds":1.0,"duration_seconds":12.0,"anchor_id":"work","paused_reason":""}
	authority.dto.modules.instances[0].visuals.damage={"hp":70.0,"max_hp":100.0,"state_code":"damaged","ruin_id":"","anchor_id":"output"}
	view.sync()
	expect("public consumer wires owner construction and damage DTO",view._conditions.a.statistics().construction_active and view._conditions.a.statistics().damage_visible and view.statistics().required_errors.is_empty(),view.statistics())
	var condition:Node3D=view._conditions.a
	expect("construction uses world work contact without double transform",condition._work.global_position.is_equal_approx(Vector3(14,2.9,-9)))
	expect("damage plane follows outward world normal rather than module rotation",condition._damage.global_basis.z.is_equal_approx(Vector3.RIGHT) and condition._damage.global_position.is_equal_approx(Vector3(15.006,2,-10)))
	authority.dto.modules.instances[0].visuals.construction.paused_reason="missing_operator";view.sync()
	expect("real blocked construction suppresses local work",not condition.statistics().construction_active)
	authority.dto.modules.instances[0].visuals.damage.hp=100.0;view.sync()
	expect("repair clears damage through public consumer",not condition.statistics().damage_visible)
	authority.dto.modules.instances[0].visuals.damage.hp=50.0
	authority.dto.modules.instances[0].visuals.anchors.output.forward=[0,0];view.sync()
	expect("missing surface normal hides stale damage and reports failure",not condition.statistics().damage_visible and has_error(view,"DAMAGE_SURFACE_NORMAL_REQUIRED"))
	authority.dto.modules.instances[0].visuals.anchors.work.position=[INF,0,0];view.sync()
	expect("invalid construction contact hides prior chips",not condition.statistics().construction_active and has_error(view,"CONSTRUCTION_ANCHOR_REQUIRED"))
	authority.dto=snapshot();view.sync()
	expect("removed condition projections hide previous details",not condition.statistics().construction_active and not condition.statistics().damage_visible)
	var duplicate:Dictionary=authority.dto.modules.instances[0].duplicate(true)
	authority.dto.modules.instances.append(duplicate);authority.dto.modules.instances.append(duplicate.duplicate(true));view.sync()
	expect("even three duplicate IDs cannot recreate ambiguous instance",not view._roots.has("a") and view._roots.has("b") and has_error(view,"DUPLICATE_MODULE_ID"))
	authority.dto=snapshot();view.sync()
	authority.dto.modules.instances[0].visuals.buffers.append(authority.dto.modules.instances[0].visuals.buffers[0].duplicate(true));view.sync()
	expect("duplicate buffer IDs remove old commodity",not view._buffers.a.has("wood") and has_error(view,"BUFFER_ID_OR_ANCHOR_REQUIRED"))
	authority.dto=snapshot();view.sync();root_id=view._roots.a.get_instance_id()
	var before_cold:String=JSON.stringify(authority.dto)
	var old_stock:Node3D=view._buffers.a.wood
	authority.dto.modules.instances[0].detailed=false;view.sync()
	expect("non-detailed owner retires root buffers machines and condition references",not view._roots.has("a") and not view._buffers.has("a") and not view._machines.has("a") and not view._conditions.has("a") and view._roots.has("b") and view.get_child_count()==1)
	await process_frame
	expect("remote module old stock node is actually freed",not is_instance_valid(old_stock))
	authority.dto.modules.instances[0].detailed=true;view.sync()
	expect("returning detailed region rebuilds same-ID real stock without issuing goods",view._roots.a.get_instance_id()!=root_id and view._buffers.a.wood.statistics().actual==5.0 and authority.dto.modules.instances[0].visuals.buffers[0].actual==5.0)
	authority.dto.modules.instances[0].erase("detailed")
	expect("cold release and remount never mutate supplied facts",JSON.stringify(authority.dto)==before_cold)
	authority.dto.modules.instances[0].detailed="false";view.sync()
	expect("malformed detail state cannot keep stale remote display",not view._roots.has("a") and has_error(view,"MODULE_DETAIL_STATE_REQUIRED"))
	authority.dto=snapshot();view.sync();root_id=view._roots.a.get_instance_id()
	authority.dto.world_id="second-world";view.sync()
	expect("two modules release and recreate on changed world ID",view._roots.size()==2 and view.get_child_count()==2 and view._roots.a.get_instance_id()!=root_id)
	root_id=view._roots.a.get_instance_id();authority.world=RefCounted.new();view.sync()
	expect("restore replaces same-ID roots on same runtime new world object",view._roots.size()==2 and view._roots.a.get_instance_id()!=root_id)
	root_id=view._roots.a.get_instance_id();var next:=Authority.new();next.dto=authority.dto.duplicate(true);view.configure(next)
	expect("replacement authority retires both old roots",view._roots.size()==2 and view._roots.a.get_instance_id()!=root_id)
	next.dto.available=false;view.sync();view.sync();view._clear();view._clear()
	expect("unavailable and repeated clear release all per-module references",view.get_child_count()==0 and view._roots.is_empty() and view._buffers.is_empty() and view._machines.is_empty() and view._conditions.is_empty() and view._keys.is_empty())
	next.dto=snapshot();view.sync();next.dto.modules.available=false;view.sync()
	expect("unavailable owner clears both module roots",view.get_child_count()==0)
	next.dto=snapshot();view.sync();next.dto.modules.instances.remove_at(0);view.sync()
	expect("deleted instance retires only its own nodes",not view._roots.has("a") and view._roots.has("b"))
	next.dto.version=987;view.sync()
	expect("unsupported DTO schema fails closed",view.get_child_count()==0 and has_error(view,"FACTORY_SCHEMA_UNSUPPORTED"))
	parent.free()
	await process_frame
	var report:Dictionary={"scope":"explicit DTO consumer counterexamples, copied source/imports; not owner integration, OS, VA or performance qualification","checks":checks,"failures":failures}
	var file:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("DDD_FACTORY_CONSUMER ",JSON.stringify({"checks":checks.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
