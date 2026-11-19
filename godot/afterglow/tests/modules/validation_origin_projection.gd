extends SceneTree
const Native=preload("res://scripts/runtime/native_client.gd")
const Store=preload("res://scripts/storage/native_store.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Service=preload("res://scripts/modules/module_service.gd")
var checks:Array=[]
class FullView extends RefCounted:
	var values:Dictionary={}
	var copies:int=0
	func extension(id:String)->Variant:
		copies+=1;var v:Variant=values.get(id);return v.duplicate(true) if v is Dictionary or v is Array else v
class FieldsView extends FullView:
	var reads:int=0
	func extension_fields(id:String,fields:Array[String])->Dictionary:
		reads+=1;var v:Variant=values.get(id);var out:Dictionary={}
		if not v is Dictionary:return out
		for field:String in fields:
			if v.has(field):out[field]=v[field].duplicate(true) if v[field] is Dictionary or v[field] is Array else v[field]
		return out
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail});if not ok:print("FAIL ",label," ",detail)
func compare(a:RefCounted,b:RefCounted,facts:Dictionary,state:Dictionary,label:String)->void:
	var before:Dictionary={"facts":facts.duplicate(true),"state":state.duplicate(true)}
	var x:Dictionary=a.validate_extensions(facts,{Service.KEY:state});var y:Dictionary=b.validate_extensions(facts,{Service.KEY:state})
	check(label,Data.json_equal(x,y),{"actual":x,"before":y})
	check(label+" query pure",Data.json_equal(before,{"facts":facts,"state":state}))
func run()->void:
	var args:=OS.get_cmdline_user_args();var cfg:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[3]));var original:Script=load(cfg.reference_modules)
	for input:String in [args[1],args[4]]:
		var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(input));var h:=Native.new();var built:Dictionary=h._assemble(decoded.capture);h.free()
		check("actual input restored "+input,built.get("ok",false))
		if not built.get("ok",false):continue
		var rt:RefCounted=built.runtime;var current:RefCounted=built.services.modules;var old:RefCounted=original.new();old.context=current.context
		var facts:Dictionary=rt.facts();var source:Dictionary=current.state();var authority:Dictionary=rt.capture_checkpoint()
		compare(current,old,facts,source,"actual full validator")
		for mode:String in ["stock owner","stock missing","capacity","hp","member duplicate","project cost","source receipt"]:
			var f:=facts.duplicate(true);var s:=source.duplicate(true);var v:Dictionary=s.instances[0];var stock_id:String=v.stock_refs.values()[0]
			match mode:
				"stock owner":
					for stock:Dictionary in f.stocks:
						if stock.id==stock_id:stock.owner="explicit:denied"
				"stock missing":f.stocks=f.stocks.filter(func(stock:Dictionary)->bool:return stock.id!=stock_id)
				"capacity":
					for stock:Dictionary in f.stocks:
						if stock.id==stock_id:stock.items={"timber":10000}
				"hp":v.hp=-1
				"member duplicate":v.members.append(v.members[0].duplicate(true))
				"project cost":s.projects[0].cost={"timber":0}
				"source receipt":s.source_receipts["explicit:bad"]={"source_key":"wrong"}
			compare(current,old,f,s,"explicit current mutation "+mode)
		if source.has("water"):
			var values:Dictionary={}
			for region:Dictionary in built.world.regions():values["generation:"+str(region.id)]=built.world.extension("generation:"+str(region.id))
			for projected:bool in [false,true]:
				var view:RefCounted=FieldsView.new() if projected else FullView.new();view.values=values.duplicate(true)
				var a:=Service.new();var b:RefCounted=original.new();a.context={"world":view};b.context={"world":view}
				compare(a,b,facts,source,"actual origin with projection/fallback "+str(projected))
				if projected:check("production source proof really uses field projection",view.reads>0 and view.copies>0)
				for kind:String in ["version","water source","restoration source","missing"]:
					view.values=values.duplicate(true)
					for key:String in view.values:
						var plan:Variant=view.values[key]
						if not plan is Dictionary:continue
						if kind=="version":plan.generation_content_version=0
						elif kind=="water source":plan.water_sources=[]
						elif kind=="restoration source":plan.story_sites=[]
						else:view.values[key]=null
					compare(a,b,facts,source,"origin invalidation "+str(projected)+kind)
		check("actual authority untouched",Data.json_equal(authority,rt.capture_checkpoint()));rt.retire()
	var report:Dictionary={"checks":checks,"scope":"Actual normal20/23 S01 facts and full source. Explicit dynamic corruption/origin edits and legacy no-fields view; original full validators executed, no permission/result cache."}
	FileAccess.open(args[0]+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));quit(0 if checks.all(func(c:Dictionary)->bool:return c.ok) else 1)
