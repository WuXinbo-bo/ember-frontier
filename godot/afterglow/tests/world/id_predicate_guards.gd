extends SceneTree
## Exact historical predicate oracle; cache state is test-inspected, never saved.
const Data=preload("res://scripts/world/world_data.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok:print("FAIL "+label+" "+str(detail))
static func original(v:Variant)->bool:
	if not v is String or v.is_empty() or v.length()>240 or v in ["__proto__","constructor","prototype"]:return false
	for c in v:
		if c.unicode_at(0)<32:return false
	return true
static func cache_size()->int:
	Data._valid_id_mutex.lock();var n:int=Data._valid_id_cache.size();Data._valid_id_mutex.unlock();return n
func run()->void:
	var args:=OS.get_cmdline_user_args()
	var samples:Array=[null,false,true,0,1,-1,0.0,NAN,INF,[],{},Vector2.ZERO,Vector3.ZERO,RefCounted.new(),StringName("legal"),StringName("constructor"),PackedStringArray(["legal"])]
	for v:Variant in samples:check("exact original type behavior "+type_string(typeof(v))+" "+str(v),Data.valid_id(v)==original(v))
	for v:String in ["","__proto__","constructor","prototype","Constructor","prototype ","terrain:-1:0:-2","世界:山坡:🌿","\u007f","\u0085","\u200b","\ufeff","\u2028","a".repeat(239),"a".repeat(240),"a".repeat(241),"界".repeat(240),"界".repeat(241),"🌿".repeat(240),"🌿".repeat(241),"e\u0301".repeat(120),"e\u0301".repeat(121)]:
		check("exact original string bytes/length "+str(v.length())+" "+v.substr(0,16),Data.valid_id(v)==original(v))
	var bad:int=0
	for code:int in range(1,256):
		for v:String in [String.chr(code),"valid:"+String.chr(code),String.chr(code)+"valid"]:
			if Data.valid_id(v)!=original(v):bad+=1
	check("all representable 1..255 codepoints in three positions match",bad==0,bad)
	var nul:String=String.chr(0)
	check("engine NUL representation follows original",Data.valid_id("x"+nul+"y")==original("x"+nul+"y"),{"chr0_length":nul.length()})
	var value:String="warm:世界"
	check("successful value warms",Data.valid_id(value))
	var valid_copy:String=value;value+="\n"
	check("mutated value cannot borrow warm prefix",not Data.valid_id(value) and Data.valid_id(valid_copy))
	var prior:int=cache_size()
	for i:int in 100:Data.valid_id("bad:"+str(i)+"\n")
	check("negative results never occupy cache",cache_size()==prior,{"before":prior,"after":cache_size()})
	var peak:int=0
	for i:int in 6200:
		var id:String="evict:"+str(i)
		if not Data.valid_id(id):bad+=1
		peak=maxi(peak,cache_size())
	check("6200 unique positive identities preserve strict bounded storage",bad==0 and peak<=2048 and Data._VALID_ID_LIMIT==2048,{"peak":peak,"after":cache_size()})
	check("eviction revalidates original valid and reserved/control values",Data.valid_id(valid_copy) and not Data.valid_id("constructor") and not Data.valid_id(valid_copy+"\u001f"))
	var threads:Array[Thread]=[]
	for worker:int in 4:
		var thread:=Thread.new();var code:Error=thread.start(_worker.bind(worker))
		check("worker starts "+str(worker),code==OK,code)
		if code==OK:threads.append(thread)
	var results:Array=[]
	for thread:Thread in threads:results.append(thread.wait_to_finish())
	check("concurrent scans/evictions remain pure and bounded",results.size()==4 and results.all(func(r:Dictionary)->bool:return r.bad==0 and r.peak<=2048),results)
	check("all cache entries are true full-string oracle successes",cache_entries_valid())
	var report:Dictionary={"scope":"pure predicate equivalence, bounded positive-only memory metadata and four actual threads; no world/permission/schema validation is memoized","checks":checks,"failed":checks.filter(func(c:Dictionary)->bool:return not c.ok).size()}
	var f:=FileAccess.open(args[0],FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t",true,true));f.close()
	print(JSON.stringify({"checks":checks.size(),"failed":report.failed}));quit(1 if report.failed else 0)
static func _worker(index:int)->Dictionary:
	var bad:int=0;var peak:int=0
	for i:int in 3000:
		for v:Variant in ["thread:"+str(index)+":"+str(i)+":世界","shared:terrain:-1:0:2","invalid:"+str(i)+"\n","constructor",i]:
			if Data.valid_id(v)!=original(v):bad+=1
		if i%31==0:peak=maxi(peak,cache_size())
	return {"bad":bad,"peak":peak,"queries":15000}
static func cache_entries_valid()->bool:
	Data._valid_id_mutex.lock();var values:Dictionary=Data._valid_id_cache.duplicate();Data._valid_id_mutex.unlock()
	if values.size()>2048:return false
	for k:Variant in values:
		if not k is String or values[k]!=true or not original(k):return false
	return true
