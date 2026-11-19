extends SceneTree
## Isolated counterexamples for the scoped sampler, never normal-world facts.
const View=preload("res://scripts/world/world_view.gd")
const Data=preload("res://scripts/world/world_data.gd")
const Before=preload("res://tests/world/fixtures/environment_before_refresh_followup.gd")
const Sampler=preload("res://scripts/environment/support_sampler.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.is_empty():quit(2);return
	var cfg:Dictionary=Data.DEFAULT_CONFIG.duplicate(true)
	var state:Dictionary={"config":cfg,"chunks":{}}
	for z:int in range(-2,2):
		for x:int in range(-2,2):
			for y:int in range(floori(float(cfg.minCellY)/16),ceili(float(cfg.maxCellY)/16)):
				var cells:=PackedInt32Array();cells.resize(4096)
				for i:int in cells.size():cells[i]=1 if y*16+i/256<=0 else 0
				state.chunks[Data.key(Vector3i(x,y,z))]={"generated":true,"resident":true,"cells":cells}
	for mode:String in ["plain","unknown","unresident-lower","plateau-boundary","unresident-above","upper-page","lower-page","solid-above","changed-soil","upper-generation"]:
		var copy:Dictionary=state.duplicate(true)
		var low:String="0,0,0";var high:String="0,1,0"
		if mode in ["plateau-boundary","unresident-above","upper-page","upper-generation"]:copy.chunks[low].cells.fill(1)
		if mode=="unknown":copy.chunks.erase(low)
		elif mode=="unresident-lower":copy.chunks[low].resident=false
		elif mode=="unresident-above":copy.chunks[high].resident=false
		elif mode=="upper-page":copy.chunks[high]["cell_page"]={"fixture":true}
		elif mode=="lower-page":copy.chunks[low]["cell_page"]={"fixture":true}
		elif mode=="solid-above":copy.chunks[low].cells[Data.local_index(Vector3i(0,1,0),16)]=3
		elif mode=="changed-soil":copy.chunks[low].cells[0]=2
		elif mode=="upper-generation":copy.chunks[high].generated=false
		var world:=View.new(copy);var original:=Before.new();original.world=world
		var sampler:=Sampler.new(world);var exact:bool=true;var count:int=0
		for p:Vector3 in [Vector3(-8,0.5,-8),Vector3(-0.01,0.5,-0.01),Vector3(0,0.5,0),Vector3(0.25,0.5,0.25),Vector3(7.99,0.5,7.99),Vector3(8,0.5,8),Vector3(0.25,8,0.25),Vector3(0.25,0.3,0.25),Vector3(0.25,cfg.minCellY*cfg.cellSize,0.25),Vector3(0.25,cfg.maxCellY*cfg.cellSize,0.25)]:
			for width:float in [0.24,0.52,1.5]:
				for material:int in [-1,1,2]:
					exact=exact and original._grounded(p,Vector2.ONE*width,material)==sampler.grounded(p,Vector2.ONE*width,material);count+=1
		for p:Vector2 in [Vector2(-8,-8),Vector2(-0.01,-0.01),Vector2.ZERO,Vector2(0.25,0.25),Vector2(7.99,7.99),Vector2(8,8)]:
			exact=exact and world.surface_height(p.x,p.y)==sampler.surface_height(p.x,p.y)
		checks.append({"name":mode+" exact original footprint/material/known/resident/air/minmax/surface semantics","ok":exact,"detail":{"footprint_queries":count,"surface_queries":6,"retained_chunks":sampler.chunks.size(),"scope":"isolated fixture; cold page marker is not a codec/normal resource result"}})
		original.free()
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed},"\t",true,true));quit(1 if failed else 0)
