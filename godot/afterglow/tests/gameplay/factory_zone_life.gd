extends SceneTree
## 6.36 E food selection only. Explicit ephemeral stock/pack/reservation
## fixtures, all transfers/routes refused. No meal/seed/material is granted
## to the live Runtime, no actual farming/cooking/consumption is claimed.
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Life=preload("res://scripts/runtime/resident_life.gd")
const Content=preload("res://scripts/runtime/content_definitions.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
const Data=preload("res://scripts/world/world_data.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
class ProductionProbe extends RefCounted:
	var holds:Dictionary={}
	var calls:Array=[]
	func reserved(source:String,item:String,_excluded:String,tx:RefCounted)->float:
		calls.append({"source":source,"item":item,"same_draft":tx!=null})
		return float(holds.get(source+"|"+item,0))
	func available_for(source:String,item:String,purpose:String,_excluded:String,tx:RefCounted)->float:
		calls.append({"source":source,"item":item,"same_draft":tx!=null,"purpose":purpose})
		return float(tx.stock(source).get("items",{}).get(item,0))-float(holds.get(source+"|"+item,0))
class ActionProbe extends RefCounted:
	var transfers:Array=[]
	var routes:Array=[]
	func transfer_in(_tx:RefCounted,actor:String,source:String,target:String,payload:Dictionary)->Dictionary:
		transfers.append({"actor_id":actor,"source":source,"target":target,"payload":payload.duplicate(true)})
		return {"ok":false,"code":"PROBE_STOP","reason":"隔离消费者不转移物资"}
	func route(_actor:String,_from:Dictionary,to:Dictionary)->Dictionary:
		routes.append(to.duplicate(true));return {"ok":false,"code":"PROBE_STOP","reason":"隔离消费者不行走"}
var checks:Array=[]
var output:String
var runtime:RefCounted
func check(name:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+name)
func run()->void:
	var args:=OS.get_cmdline_user_args();output=args[0]
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(args[1]));var native:=Native.new()
	var built:Dictionary=native._assemble(decoded.capture) if decoded.get("ok",false) else decoded;native.free()
	check("original unchanged finite checkpoint mounts with additive item definitions",built.get("ok",false),built.get("reason"))
	if not built.get("ok",false):return finish()
	runtime=built.runtime;var before:Dictionary=runtime.capture_checkpoint()
	var actions:=ActionProbe.new();var production:=ProductionProbe.new();var life:=Life.new()
	life.configure({"runtime":runtime,"world":runtime.world,"spatial":built.services.actions.building,"services":{"actions":actions,"production":production,"modules":built.services.modules}})
	var tx:=Draft.new(life.context);var actor:Dictionary=tx.actor("village-resident")
	var stock:Dictionary={"id":"E:explicit-food-selection-fixture","owner":"home-residents","searched":true,"location":G.location(actor),"items":{}}
	tx.staged.stocks=[stock]
	for item:String in ["r34:potato_seed","r34:bean_seed","r34:rice_seed","r34:broadleaf_seed","r34:conifer_seed","r34:raw_water","r34:filtered_water","r34:potato","r34:beans","r34:paddy","r34:rice"]:
		check("registered non-consumable excluded "+item,not Content.item_definition(item).is_empty() and life._supply_item({item:1},"eat").is_empty() and life._supply_item({item:1},"drink").is_empty())
		stock.items={item:1};var tries:int=actions.transfers.size()
		check("arrival refuses unsafe supply "+item,not life._take_supply(tx,str(actor.id),str(stock.id),item).ok and actions.transfers.size()==tries)
	for item:String in ["r34:meal_simple","r34:meal_hearty","r34:dry_ration"]:
		stock.items={item:1};production.holds.clear()
		check("new cooked item selected by unique Content definition "+item,life._supply_item(stock.items,"eat",str(stock.id),tx)==item and life._supply_item(stock.items,"drink",str(stock.id),tx).is_empty())
		var tries:int=actions.transfers.size();life._seek_supplies(actor,{},tx,"eat",runtime.clock(),true)
		check("B receives exact cooked item ID and one-unit life purpose "+item,actions.transfers.size()==tries+1 and actions.transfers[-1].payload=={"items":{item:1},"purpose":"life"})
		production.holds[str(stock.id)+"|"+item]=1;tries=actions.transfers.size()
		check("reserved cooked unit cannot be selected or taken "+item,not life._seek_supplies(actor,{},tx,"eat",runtime.clock(),true) and not life._take_supply(tx,str(actor.id),str(stock.id),item).ok and actions.transfers.size()==tries)
	production.holds.clear();stock.items={"food":1,"r34:meal_simple":1}
	check("legacy food remains first when both are actually available",life._supply_item(stock.items,"eat",str(stock.id),tx)=="food")
	production.holds[str(stock.id)+"|food"]=1
	check("reserved legacy food does not hide available cooked meal",life._supply_item(stock.items,"eat",str(stock.id),tx)=="r34:meal_simple")
	stock.items={"water":1,"r34:raw_water":8,"r34:filtered_water":8}
	check("only actual safe legacy water can satisfy thirst",life._supply_item(stock.items,"drink",str(stock.id),tx)=="water")
	production.holds[str(stock.id)+"|water"]=1
	check("last safe water hold cannot be bypassed with raw or filtered water",life._supply_item(stock.items,"drink",str(stock.id),tx).is_empty())
	production.holds.clear();stock.items={"r34:meal_simple":1};stock.searched=false
	check("unknown stock is never inspected as an available meal",not life._seek_supplies(actor,{},tx,"eat",runtime.clock(),true))
	stock.searched=true;stock.owner="other-household"
	check("unrelated stock permission is retained",not life._seek_supplies(actor,{},tx,"eat",runtime.clock(),true))
	stock.owner="home-residents";actor.relationship.consent=false
	check("withdrawn work consent grants no team food permission",not life._seek_supplies(actor,{},tx,"eat",runtime.clock(),true))
	check("reservation query always receives current Draft",not production.calls.is_empty() and production.calls.all(func(row:Dictionary)->bool:return row.same_draft))
	check("all B policy availability queries explicitly use the life exception",production.calls.all(func(row:Dictionary)->bool:return row.get("purpose")=="life"))
	check("all actual original stocks tools people needs events and clock remain unchanged",Data.json_equal(before,runtime.capture_checkpoint()))
	finish()
func finish()->void:
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"scope":"6.36 E stock/consumable selection with additive A exact Content snapshot only. Explicit isolated Draft stock/permission/consent/hold fixtures; every transfer/route refused. No meal injected into actual Runtime, no farming/cooking/consumption/natural journey/new-PCK/OS/VA/FPS claim."},"\t",true,true))
	print(JSON.stringify({"checks":checks.size(),"failed":failed}));quit(1 if failed else 0)
