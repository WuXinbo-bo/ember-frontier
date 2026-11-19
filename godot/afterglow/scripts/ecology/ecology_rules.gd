extends RefCounted
## Pure game-time values; never a clock, inventory or content registry.
const VERSION:=1
const MAX_PLANTS:=4096
const MAX_DUE_PER_STEP:=32
const MAX_ZONE_CELLS:=1024
const CROPS={
 "potato":{"seed":"r34:potato_seed","item":"r34:potato","seconds":600.0,"water":1,"yield":3,"height":0.45},
 "bean":{"seed":"r34:bean_seed","item":"r34:beans","seconds":900.0,"water":1,"yield":4,"height":0.8},
 "rice":{"seed":"r34:rice_seed","item":"r34:paddy","seconds":1200.0,"water":2,"yield":4,"height":1.0}}
const TREES={
 "broadleaf":{"seed":"r34:broadleaf_seed","seedling":"r34:broadleaf_seedling","model":"broadleaf_tree","young_seconds":1200.0,"mature_seconds":3600.0},
 "conifer":{"seed":"r34:conifer_seed","seedling":"r34:conifer_seedling","model":"conifer_tree","young_seconds":1500.0,"mature_seconds":4200.0}}
const ITEMS={
 "r34:raw_water":"原水；不能直接饮用","r34:filtered_water":"仅过滤的原水；仍须消毒，不是饮水",
 "r34:potato_seed":"马铃薯种薯；不进入生活食物池","r34:bean_seed":"菜豆种子；不进入生活食物池","r34:rice_seed":"稻种；不进入生活食物池",
 "r34:potato":"生马铃薯；供食堂加工","r34:beans":"生菜豆；供食堂加工","r34:paddy":"带壳稻谷；须脱壳加工","r34:rice":"脱壳米；须熟制",
 "r34:broadleaf_seed":"阔叶树种","r34:conifer_seed":"针叶树种","r34:broadleaf_seedling":"阔叶苗","r34:conifer_seedling":"针叶苗","r34:crop_residue":"真实每次收获一份残余；不可食/播种，用于原生产堆肥","r34:compost":"堆肥；用于田畦肥力"}

static func initial()->Dictionary:
 return {"version":VERSION,"revision":0,"plants":{},"plant_count":0,"buckets":{},"due":[],"next_due":-1.0,"seed_receipts":{},"sources":{},"completed":{}}
static func plant_id(region:String,cell:Dictionary)->String:return "r34:ecology:"+region+":%d:%d:%d"%[int(cell.x),int(cell.y),int(cell.z)]
static func job_id(zone:String,kind:String,target:String,revision:int)->String:return zone+":"+kind+":"+target+":"+str(revision)
# A persistent binary min-heap retains due identity across save/cold restoration.
static func before(a:Dictionary,b:Dictionary)->bool:return a.at<b.at or (a.at==b.at and str(a.id)<str(b.id))
static func push(heap:Array,item:Dictionary)->void:
 heap.append(item);var i:int=heap.size()-1
 while i>0:
  var parent:int=(i-1)/2
  if not before(heap[i],heap[parent]):break
  var old:Variant=heap[parent];heap[parent]=heap[i];heap[i]=old;i=parent
static func pop(heap:Array)->Dictionary:
 var result:Dictionary=heap[0];var last:Variant=heap.pop_back()
 if heap.is_empty():return result
 heap[0]=last;var i:int=0
 while true:
  var left:int=i*2+1
  if left>=heap.size():break
  var right:int=left+1;var child:int=right if right<heap.size() and before(heap[right],heap[left]) else left
  if not before(heap[child],heap[i]):break
  var old:Variant=heap[i];heap[i]=heap[child];heap[child]=old;i=child
 return result
