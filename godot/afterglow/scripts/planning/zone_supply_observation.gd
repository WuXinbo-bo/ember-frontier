extends RefCounted
## One synchronous, immutable candidate observation. Never retained by a
## service, used by admission, or reused after a fact/extension mutation.
## Derive holds once instead of deeply comparing the entire Draft per tool.
const G=preload("res://scripts/buildings/building_geometry.gd")
var _production:RefCounted
var _tx:RefCounted
var _holds:Array=[]
var _stocks:Dictionary={}
var _floors:Dictionary={}
var _exclusions:Dictionary={}

func _init(production:RefCounted,tx:RefCounted)->void:
	_production=production;_tx=tx
	_holds=production.all_holds(tx)
	for hold:Dictionary in _holds:_exclusions[str(hold.intent_id)]=true
	# These are the complete additional exclusion identities used by the
	# original capacity checker (including water's reusable output promises).
	for spec:Array in [["r3:production","orders","id"],["r34:production","batches","id"],["r34:logistics","reservations","task_id"]]:
		var source:Variant=tx.extensions[spec[0]] if tx.extensions.has(spec[0]) else production.context.world.extension(spec[0])
		for row:Dictionary in source.get(spec[1],[]) if source is Dictionary else []:_exclusions[str(row.get(spec[2],""))]=true
	var modules:Variant=tx.extensions["r34:modules"] if tx.extensions.has("r34:modules") else production.context.world.extension("r34:modules")
	for project:Dictionary in modules.get("water",{}).get("projects",[]) if modules is Dictionary else []:_exclusions[str(project.id)]=true
	for stock:Dictionary in tx.staged.get("stocks",[]):_stocks[str(stock.id)]=stock
	for actor:Dictionary in tx.staged.get("actors",[]):
		_stocks["pack:"+str(actor.id)]={"id":"pack:"+str(actor.id),"items":actor.pack,"location":G.location(actor),"owner":actor.id,"searched":true}

func exclusion_key(id:String)->String:return id if _exclusions.has(id) else ""

func available_for(source:String,item:String,purpose:String="work",excluding:String="",_observation:RefCounted=null)->float:
	var held:float=0
	for hold:Dictionary in _holds:
		if hold.intent_id!=excluding and hold.source_id==source:held+=float(hold.cost.get(item,0))
	if purpose!="life":
		var key:Array=[source,item]
		if not _floors.has(key):_floors[key]=_production.reserve_floor(source,item,_tx)
		held+=float(_floors[key])
	return maxf(0,float(_stocks.get(source,{}).get("items",{}).get(item,0))-held)

func tool_unavailable(id:String,excluding:String="",_observation:RefCounted=null)->bool:
	for hold:Dictionary in _holds:
		if hold.intent_id!=excluding and hold.tool_ids.has(id):return true
	return false

func work_reserved(source:String,item:String,excluding:String="",_observation:RefCounted=null)->float:
	var held:float=0
	for hold:Dictionary in _holds:
		if hold.intent_id!=excluding and hold.source_id==source:held+=float(hold.cost.get(item,0))
	var key:Array=[source,item]
	if not _floors.has(key):_floors[key]=_production.reserve_floor(source,item,_tx)
	return held+float(_floors[key])

func use_reserved(target:String,excluding:String="",_observation:RefCounted=null)->bool:
	if target.is_empty():return false
	for hold:Dictionary in _holds:
		if hold.intent_id!=excluding and hold.use_target_id==target:return true
	return false

func reach(actor_id:String,target_id:String,target:Dictionary,purpose:String="stock",_observation:RefCounted=null)->Variant:
	return _production.reach(actor_id,target_id,target,purpose,_tx)

func tool_qualities(tool:Dictionary)->Dictionary:return _production.tool_qualities(tool)
func tool_definition(tool:Dictionary)->Dictionary:return _production.tool_definition(tool)
func qualities(state:Dictionary,ids:Array,required:Dictionary)->bool:return _production.qualities(state,ids,required)
func capacity_check(stock_id:String,items:Dictionary,excluding:String="",_observation:RefCounted=null)->Dictionary:
	return _production.capacity_check(stock_id,items,excluding,_tx)
