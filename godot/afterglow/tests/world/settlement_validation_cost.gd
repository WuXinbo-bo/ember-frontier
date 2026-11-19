extends SceneTree
const Before=preload("res://tests/world/fixtures/settlement_world_data_before.gd")
const Data=preload("res://scripts/world/world_data.gd")
const State=preload("res://scripts/world/world_state.gd")
const Generator=preload("res://scripts/world/settlement_generator.gd")
const Building=preload("res://scripts/buildings/building_service.gd")
var checks: Array=[]
func _initialize() -> void:call_deferred("run")
func check(label: String,ok: bool,detail: Variant=null) -> void:
	checks.append({"label":label,"ok":ok,"detail":detail})
	if not ok:push_error("FAIL "+label+" "+str(detail))
func run() -> void:
	var snapshot: Dictionary=Generator.generate(713,Building.generation_profiles())
	var keys: Array=snapshot.chunks.keys();keys.sort()
	var parity:=true
	for key in keys:parity=parity and Before.chunk_error(key,snapshot.chunks[key],snapshot)==Data.chunk_error(key,snapshot.chunks[key],snapshot)
	check("all actual 512 generated packed buffers have exact old/new validation parity",parity)
	var key: String=keys[0];var source: Dictionary=snapshot.chunks[key]
	for value in [-2147483648,-1,7,999,2147483647]:
		var chunk: Dictionary=source.duplicate(true);chunk.cells[4095]=value
		check("packed unknown material rejected exactly "+str(value),Before.chunk_error(key,chunk,snapshot)=="UNKNOWN_MATERIAL" and Data.chunk_error(key,chunk,snapshot)=="UNKNOWN_MATERIAL")
	for value in [true,"1",0.25,NAN,INF]:
		var chunk: Dictionary=source.duplicate(true);chunk.cells=Array(source.cells);chunk.cells[0]=value
		check("legacy JSON scalar remains strict "+str(value),Before.chunk_error(key,chunk,snapshot)=="UNKNOWN_MATERIAL" and Data.chunk_error(key,chunk,snapshot)=="UNKNOWN_MATERIAL")
	var valid: Dictionary=source.duplicate(true);valid.cells=Array(source.cells);valid.cells[0]=1.0
	check("legacy integral JSON numbers still accepted",Data.chunk_error(key,valid,snapshot)==Before.chunk_error(key,valid,snapshot) and Data.chunk_error(key,valid,snapshot)=="")
	var metadata: Dictionary=source.duplicate(true);metadata.extra=Vector3.ZERO
	check("native fast proof does not bypass metadata JSON validation",Data.chunk_error(key,metadata,snapshot)=="INVALID_JSON_FACT")
	var world:=State.new();world.load_snapshot(snapshot)
	var replacement: Dictionary=source.duplicate(true);replacement.cells[13]=999
	var bad: Dictionary=world.prepare_changes([{"op":"chunk.put","id":key,"before_exists":true,"before":world.chunk(key),"after":replacement}],world.get_revision())
	check("actual capability rejects corrupt replacement and leaves world unchanged",not bad.ok and bad.code=="UNKNOWN_MATERIAL" and world.get_revision()==0 and world.cell_at(0,0,0)==snapshot.chunks["0,0,0"].cells[0],bad)
	var times: Dictionary={"before":[],"native":[]}
	for warmup in 2:
		for k in keys.slice(0,256):Before.chunk_error(k,snapshot.chunks[k],snapshot);Data.chunk_error(k,snapshot.chunks[k],snapshot)
	for iteration in 6:
		for side in (["before","native"] if iteration%2==0 else ["native","before"]):
			var started:=Time.get_ticks_usec()
			for k in keys.slice(0,256):
				if side=="before":Before.chunk_error(k,snapshot.chunks[k],snapshot)
				else:Data.chunk_error(k,snapshot.chunks[k],snapshot)
			times[side].append((Time.get_ticks_usec()-started)/1000.0)
	var summaries: Dictionary={}
	for side in times:
		var ordered: Array=times[side].duplicate();ordered.sort()
		summaries[side]={"median_ms":(ordered[2]+ordered[3])/2,"max_ms":ordered[-1],"samples_ms":times[side]}
	var failed:=checks.filter(func(c: Dictionary)->bool:return not c.ok).size()
	var result: Dictionary={"scope":"exact old source versus native packed-cell material proof; 256 identical chunk records, CPU only, not whole prepare/frame/Metal/app qualification","checks":checks,"failed":failed,"costs":summaries}
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true)+"\n")
	print(JSON.stringify({"checks":checks.size(),"failed":failed,"costs":summaries}));quit(1 if failed else 0)
