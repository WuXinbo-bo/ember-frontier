extends SceneTree
## 6.35 consumer boundary tests. Original25 checkpoint stays untouched.
## All added home records/stocks/status/permission/residency variants are
## transaction-only isolation fixtures, NOT construction or a natural journey.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Modules=preload("res://scripts/modules/module_service.gd")
const Shape=preload("res://scripts/modules/module_geometry.gd")
const Life=preload("res://scripts/runtime/resident_life.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Data=preload("res://scripts/world/world_data.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const EXPECTED:Dictionary={"small_porch":2,"small_annex":4,"small_court":5,"medium_long":5,"medium_corner":6,"medium_twin":8,"large_u":9,"large_double":12,"large_lodge":15}
class ActionProbe extends RefCounted:
	var transfers:Array=[]
	var routes:Array=[]
	func transfer_in(_tx:RefCounted,actor_id:String,source:String,target:String,payload:Dictionary)->Dictionary:
		transfers.append({"actor_id":actor_id,"source":source,"target":target,"payload":payload.duplicate(true)})
		return {"ok":false,"code":"PROBE_NO_TRANSFER","reason":"隔离探针不转货"}
	func route(_actor_id:String,_from:Dictionary,to:Dictionary)->Dictionary:
		routes.append(to.duplicate(true))
		return {"ok":false,"code":"PROBE_NO_ROUTE","reason":"隔离探针不执行步行"}
var checks:Array=[]
var output:String
var runtime:RefCounted
var evidence:Array=[]
func check(name:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+name)
func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0]
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]));var host:=Native.new()
	var built:Dictionary=host._assemble(decoded.capture) if decoded.get("ok",false) else decoded;host.free()
	check("unchanged actual25 finite cooperative checkpoint mounts",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	runtime=built.runtime
	var before:Dictionary=runtime.capture_checkpoint();var modules:RefCounted=built.services.modules
	var life:RefCounted=built.services.residents
	var provider_before:Dictionary=modules.housing_projection("player")
	check("old homes do not acquire design capacity or occupants",provider_before.available and provider_before.homes.is_empty())
	var actor_id:String="village-resident";var actor:Dictionary=runtime.actor(actor_id)
	check("original consenting resident is used without changing body or needs",actor.get("relationship",{}).get("member",false) and actor.relationship.get("consent",false))
	var probe:=ActionProbe.new();var isolated:=Life.new()
	isolated.configure({"runtime":runtime,"world":runtime.world,"spatial":built.services.actions.building,"services":{"actions":probe,"production":built.services.production,"modules":modules}})
	# Single explicit new-home stock + damaged record in an ephemeral Draft.
	# No fixture writes enter Runtime, no virtual route/transfer can succeed.
	var home:Dictionary=Modules.record_for({"id":"E:housing:fixture","definition_id":"r34.module.home_small_porch_v1","region":actor.regionId,"position":G.json_point(G.point(actor)),"quarter_turn":0})
	var tx:=Draft.new({"facts":func()->Dictionary:return runtime.facts(),"world":runtime.world})
	var state:Dictionary=Modules.initial();state.instances=[home]
	tx.extensions[Modules.KEY]=state
	var stock:Dictionary=Modules.stock_rows(home,Modules.definition(home.definition_id))[0]
	stock.items={"water":1};tx.staged.stocks=[stock]
	home.status="damaged";home.hp=1
	var attempted:bool=isolated._seek_supplies(tx.actor(actor_id),{},tx,"drink",runtime.clock(),true)
	check("damaged new home is excluded before any transfer or route",not attempted and probe.transfers.is_empty() and probe.routes.is_empty(),{"attempted":attempted,"transfers":probe.transfers,"routes":probe.routes})
	check("E exposes housing provider without manufacturing a second capacity",life.has_method("housing_projection"))
	if not life.has_method("housing_projection"):return finish()
	check("public workforce snapshot consumes current housing provider",runtime.factory_snapshot("player").workforce.housing==provider_before)
	check("missing provider reports unavailable without inventing capacity",Life.new().housing_projection()=={"available":false,"homes":[]})
	for key:String in EXPECTED:
		var d:Dictionary=Modules.definition("r34.module.home_"+key+"_v1")
		check("unique nested design capacity "+key,d.get("architecture",{}).get("design_capacity")==EXPECTED[key] and not d.has("capacity") and d.shape=="home")
		for turn:int in 4:
			var row:Dictionary=Modules.record_for({"id":"E:housing:"+key,"definition_id":d.id,"region":actor.regionId,"position":G.json_point(G.point(actor)),"quarter_turn":turn})
			var s:Dictionary=Modules.initial();s.instances=[row]
			var overrides:Dictionary={Modules.KEY:s}
			var result:Dictionary=life.housing_projection(actor_id,tx.staged,overrides)
			var points:Array=[]
			for port:Dictionary in Shape.ports(row,d):
				if port.purpose=="service":points.append_array(port.use_points)
			check("capacity and exact rotated service points "+key+":"+str(turn),result.available and result.homes.size()==1 and result.homes[0].capacity==EXPECTED[key] and result.homes[0].usable and result.homes[0].service_points==points and not result.homes[0].has("occupied") and not result.homes[0].has("beds"))
			if turn==0:evidence.append(result)
	# All these transitions remain explicitly isolated provider inputs.
	home.status="operational";home.hp=Modules.definition(home.definition_id).hp
	var normal:Dictionary=life.housing_projection(actor_id,tx.staged,tx.extensions)
	check("current override restores usable design service",normal.homes.size()==1 and normal.homes[0].usable)
	var original:Dictionary=normal.duplicate(true);normal.homes[0].capacity=999;normal.homes[0].service_points.clear();normal.homes.clear()
	check("returned public DTO is detached from authority",life.housing_projection(actor_id,tx.staged,tx.extensions)==original)
	var expected_points:Array=original.homes[0].service_points
	probe.transfers.clear();probe.routes.clear()
	check("operational selection asks B transfer and only exact public service feet",isolated._seek_supplies(tx.actor(actor_id),{},tx,"drink",runtime.clock(),true) and probe.transfers.size()==1 and probe.routes==expected_points,{"transfers":probe.transfers,"routes":probe.routes})
	for bad:String in ["damaged","destroyed"]:
		home.status=bad;home.hp=0 if bad=="destroyed" else 1
		var v:Dictionary=life.housing_projection(actor_id,tx.staged,tx.extensions)
		var transfer_count:int=probe.transfers.size()
		var denied:Dictionary=isolated._take_supply(tx,actor_id,stock.id,"water")
		check("arrival rechecks "+bad+" without touching stock",v.homes.size()==1 and not v.homes[0].usable and not denied.ok and denied.code=="HOUSING_SERVICE_UNAVAILABLE" and probe.transfers.size()==transfer_count)
	home.status="operational";home.hp=0
	check("operational label with zero HP cannot serve",not life.housing_projection(actor_id,tx.staged,tx.extensions).homes[0].usable)
	home.hp=Modules.definition(home.definition_id).hp
	tx.actor(actor_id).relationship.consent=false
	check("revoked consent preserves B household projection but blocks E shared supply",life.housing_projection(actor_id,tx.staged,tx.extensions)==modules.housing_projection(actor_id,tx.staged,tx.extensions) and not isolated._seek_supplies(tx.actor(actor_id),{},tx,"drink",runtime.clock(),true) and not isolated._take_supply(tx,actor_id,stock.id,"water").ok)
	tx.actor(actor_id).relationship.consent=true
	home.discovered=false
	check("unknown house does not leak capacity or points",life.housing_projection(actor_id,tx.staged,tx.extensions).homes.is_empty())
	home.discovered=true;home.owner="not-this-household"
	check("unrelated owner grants no housing service",life.housing_projection(actor_id,tx.staged,tx.extensions).homes.is_empty())
	home.owner="home-residents";home.region="E:nonresident"
	check("nonresident home never grants live service",not life.housing_projection(actor_id,tx.staged,tx.extensions).homes[0].usable)
	home.region=actor.regionId
	tx.actor(actor_id).hp=0
	check("dead actor cannot query a live service",not life.housing_projection(actor_id,tx.staged,tx.extensions).available)
	check("unknown and wildcard do not impersonate player",not life.housing_projection("unknown",tx.staged,tx.extensions).available and not life.housing_projection("*",tx.staged,tx.extensions).available)
	# Provider override absent must read the actual world, never a prior result.
	check("transaction data does not leak into committed projection",life.housing_projection("player").homes.is_empty() and runtime.factory_snapshot("player").workforce.housing.homes.is_empty())
	check("all original facts world stocks tools beds and clock remain byte-equivalent",Data.json_equal(before,runtime.capture_checkpoint()))
	finish()
func finish()->void:
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var result:Dictionary={"checks":checks,"failed":failed,"homes":evidence,"scope":"Actual25 unchanged checkpoint mounting plus explicit ephemeral record/stock/status/owner/consent/residency fixtures. ActionProbe records calls and refuses every transfer/route; no construction, natural life journey, lifecycle, visual, package or performance qualification."}
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true));print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
