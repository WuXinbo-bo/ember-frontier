extends "res://tests/world/factory_normal_path.gd"
## C-only paired before/current replays. Real normal commands are separate from
## explicit stale-plan/adapter fixtures. No app, renderer, gift or relocation.
const TerrainNow=preload("res://scripts/terrain/terrain_service.gd")
const TerrainBefore=preload("res://tests/world/fixtures/terrain_before_step.gd")
const RuntimeSource=preload("res://scripts/runtime/game_runtime.gd")
var pairs:Array=[]
var samples:Array=[]
var notices:Array=[]
var actual:Array=[]
var output:String

func mount(capture:Dictionary,before:bool)->Dictionary:
	var client:=Native.new();var b:Dictionary=client._assemble(capture);client.free()
	if b.get("ok",false) and before:
		var previous:=TerrainBefore.new()
		previous.configure({"world":b.world,"runtime":b.runtime,"spatial":b.services.buildings,"services":b.services,"definitions":b.services.terrain.context.get("definitions",{})})
		b.services.terrain=previous;b.runtime._services.terrain=previous
	return b

func signature(b:Dictionary)->PackedByteArray:return var_to_bytes(b.runtime.capture_checkpoint())
func equivalent(label:String)->void:
	check(label,signature(pairs[0])==signature(pairs[1]))

func observe_prepares(label:String)->void:
	var before:PackedByteArray=signature(pairs[0]);var equal:bool=true
	for i:int in 64:
		var results:Array=[{},{}];var row:Dictionary={"label":label,"step":i}
		for j:int in [0,1] if i%2==0 else [1,0]:
			var t:int=Time.get_ticks_usec();results[j]=pairs[j].services.terrain.advance(0.1)
			row["old" if j==0 else "new"]=Time.get_ticks_usec()-t
		equal=equal and results[0]==results[1];samples.append(row)
	check("identical prepare and isolated authority "+label,equal and signature(pairs[0])==before and signature(pairs[1])==before)

func order(kind:String,payload:Dictionary={})->Dictionary:
	sequence+=1
	var req:Dictionary={"command_id":"r34:c:terrain-step:%d"%sequence,"actor_id":"player","kind":kind,"target_id":"","payload":payload}
	var a:Dictionary=pairs[0].runtime.command(req);var b:Dictionary=pairs[1].runtime.command(req)
	check("same actual command receipt "+str(sequence),a==b,{"old":a,"new":b})
	actual.append({"request":req,"receipt":b})
	return b

func steps(count:int,label:String)->void:
	var equal:bool=true
	for i:int in count:
		var row:Dictionary={"label":label,"step":i}
		for j:int in [0,1] if i%2==0 else [1,0]:
			var t:int=Time.get_ticks_usec();pairs[j].runtime.tick(0.1)
			row["old" if j==0 else "new"]=Time.get_ticks_usec()-t
		samples.append(row);equal=equal and signature(pairs[0])==signature(pairs[1])
	check("same full actual checkpoint each STEP "+label,equal)

func cold(label:String)->void:
	equivalent("strict full live before canonical cold "+label)
	var encoded:Dictionary=Store.encode(pairs[0].runtime.capture_checkpoint())
	var decoded:Dictionary=Store.decode(encoded.text) if encoded.ok else encoded
	check("canonical cold decodes "+label,decoded.ok)
	if not decoded.ok:return
	for j:int in 2:
		pairs[j].runtime.retire();pairs[j]=mount(decoded.capture,j==0)
	check("both original and current Native cold mount "+label,pairs[0].ok and pairs[1].ok)
	equivalent("strict decoded canonical mount "+label)
	FileAccess.open(output+"/"+label+".native.json",FileAccess.WRITE).store_string(encoded.text)

func idle(path:String)->void:
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(path))
	check("actual input decodes "+path,decoded.ok)
	if not decoded.ok:return
	pairs=[mount(decoded.capture,true),mount(decoded.capture,false)]
	check("both source services use real Native input "+path,pairs[0].ok and pairs[1].ok)
	if not pairs[0].ok or not pairs[1].ok:return
	var initial:PackedByteArray=signature(pairs[0]);var equal:bool=true;var no_writes:bool=true
	for i:int in 128:
		var row:Dictionary={"label":"idle-prepare:"+path.get_file(),"step":i}
		var plans:Array=[{},{}]
		for j:int in [0,1] if i%2==0 else [1,0]:
			var at:int=Time.get_ticks_usec();plans[j]=pairs[j].services.terrain.advance(0.1)
			row["old" if j==0 else "new"]=Time.get_ticks_usec()-at
		equal=equal and plans[0]==plans[1];no_writes=no_writes and plans[1].world_changes.is_empty() and plans[1].fact_changes.is_empty();samples.append(row)
	check("128 idle preparations keep exact public plan "+path,equal and no_writes)
	check("idle preparations leave sole checkpoint untouched "+path,signature(pairs[0])==initial and signature(pairs[1])==initial)
	steps(64,"actual-idle-before-cold:"+path.get_file());cold("idle-"+str(notices.size()))
	steps(64,"actual-idle-after-cold:"+path.get_file())
	notices.append({"input":path,"sha256":FileAccess.get_sha256(path),"simulation_old":pairs[0].runtime.simulation_costs(),"simulation_new":pairs[1].runtime.simulation_costs(),"scope":"128 exact real STEP replay, including canonical cold; background CPU only"})
	for b:Dictionary in pairs:b.runtime.retire()

func actual_work(path:String)->void:
	var decoded:Dictionary=Store.decode(FileAccess.get_file_as_string(path))
	pairs=[mount(decoded.capture,true),mount(decoded.capture,false)]
	var rt:RefCounted=pairs[1].runtime;var world:RefCounted=pairs[1].world
	var tool:String=""
	for t:Dictionary in world.extension("r3:production").tools:
		if t.kind=="shovel" and t.holderId=="pack:player" and float(t.durability)>0:tool=t.id;break
	check("original normally collected shovel remains available",not tool.is_empty())
	if tool.is_empty():return
	var actor:Dictionary=rt.actor("player");var selected:Dictionary={}
	for dz:int in range(-4,5):
		for dx:int in range(-4,5):
			var x:int=floori(actor.x*2)+dx;var z:int=floori(actor.z*2)+dz
			var height:Variant=world.surface_height((x+0.5)*0.5,(z+0.5)*0.5)
			if height==null:continue
			var cell:Dictionary={"x":x,"y":roundi(float(height)*2)-1,"z":z}
			if world.cell_at(cell.x,cell.y,cell.z) not in [1,2]:continue
			var payload:Dictionary=brush(cell,"dig",tool,1,0.0,2)
			var ready:Dictionary=rt.availability({"command_id":"r34:c:probe","actor_id":"player","kind":"terrain","payload":payload})
			if ready.ok:selected={"cell":cell,"payload":payload};break
		if not selected.is_empty():break
	check("untouched actual feet find legal visible soil",not selected.is_empty())
	if selected.is_empty():return
	var cell:Dictionary=selected.cell;var before:int=world.cell_at(cell.x,cell.y,cell.z)
	var quantity:float=rt.actor("player").pack.get("soil_m3",0);var wear:float=rt.tool(tool).durability
	check("real terrain command starts",order("terrain",selected.payload).ok)
	observe_prepares("real-active-prepare")
	steps(3,"real-active-before-release")
	var progress_before:float=pairs[1].runtime.actor("player").intent.elapsed
	check("real held release is accepted",order("held",{"held":false}).ok)
	observe_prepares("real-held-prepare")
	steps(5,"real-held-no-write")
	check("held work preserves elapsed material wear and cell",pairs[1].runtime.actor("player").intent.elapsed==progress_before and world.cell_at(cell.x,cell.y,cell.z)==before and rt.tool(tool).durability==wear and rt.actor("player").pack.get("soil_m3",0)==quantity)
	cold("real-held")
	for b:Dictionary in pairs:b.runtime.set_paused(true)
	var clock:float=pairs[1].runtime.clock();steps(4,"real-global-pause")
	check("global pause keeps clock",pairs[1].runtime.clock()==clock)
	for b:Dictionary in pairs:b.runtime.set_paused(false)
	check("real resume accepted",order("held",{"held":true}).ok)
	steps(2,"real-resumed")
	check("normal cancellation accepted",order("cancel").ok)
	check("cancel does not award or change terrain",pairs[1].world.cell_at(cell.x,cell.y,cell.z)==before and pairs[1].runtime.actor("player").pack.get("soil_m3",0)==quantity and pairs[1].runtime.tool(tool).durability==wear)
	check("real dig restarts",order("terrain",selected.payload).ok)
	steps(16,"real-dig-completes")
	check("real completion pays exact volume and tool once",pairs[1].world.cell_at(cell.x,cell.y,cell.z)==0 and pairs[1].runtime.actor("player").pack.get("soil_m3",0)==quantity+0.125 and is_equal_approx(pairs[1].runtime.tool(tool).durability,wear-0.1))
	steps(3,"real-idle-after-completion")
	cold("real-completed")
	var foot:Dictionary=Geometry.location(pairs[1].runtime.actor("player"))
	check("no actor teleport or gift was used",foot==Geometry.location(actor))
	# Restore only the volume just dug using the original physical command.
	var fill:Dictionary={"tool_id":tool,"held":true,"edit":{"operation":"fill","material":2,"cells":[cell]}}
	check("real fill starts using paid recovered volume",order("terrain",fill).ok)
	steps(16,"real-fill-completes")
	check("fill consumes original physical volume once",pairs[1].world.cell_at(cell.x,cell.y,cell.z)==2 and pairs[1].runtime.actor("player").pack.get("soil_m3",0)==quantity and is_equal_approx(pairs[1].runtime.tool(tool).durability,wear-0.2))
	check("real dig starts for exact atomic counterexamples",order("terrain",selected.payload).ok)
	steps(5,"real-atomic-base")
	cold("real-active")
	atomic_cases(cell,tool)
	fixture_cases(selected.payload)
	for b:Dictionary in pairs:b.runtime.retire()

func atomic_cases(cell:Dictionary,tool:String)->void:
	# Explicit interference fixtures branch only from the legally started work.
	# These changes are NOT described as normal tool loss or natural cold events.
	var canonical:Dictionary=Store.decode(Store.encode(pairs[0].runtime.capture_checkpoint()).text)
	for label:String in ["held intervenes","world cell conflict","tool exhausted","target turns cold"]:
		for j:int in 2:
			pairs[j].runtime.retire();pairs[j]=mount(canonical.capture,j==0)
		var prepared:Array=[pairs[0].services.terrain.advance(1.0),pairs[1].services.terrain.advance(1.0)]
		check("same complete isolated plan "+label,prepared[0]==prepared[1] and not prepared[1].world_changes.is_empty())
		if label=="held intervenes":
			check("normal release changes old and new fact basis",order("held",{"held":false}).ok)
			var before:PackedByteArray=signature(pairs[0]);var rejected:Array=[]
			for j:int in 2:rejected.append(pairs[j].runtime._commit(prepared[j]))
			check("stale fact plans reject atomically without payment",rejected[0]==rejected[1] and not rejected[1].ok and rejected[1].code=="CAS_MISMATCH" and signature(pairs[0])==before and signature(pairs[1])==before,rejected)
		else:
			for j:int in 2:
				var b:Dictionary=pairs[j];var ops:Array=[]
				if label=="world cell conflict":ops=[{"op":"voxel.set","cell":cell,"before":b.world.cell_at(cell.x,cell.y,cell.z),"after":0}]
				elif label=="tool exhausted":
					var state:Dictionary=b.world.extension("r3:production");var changed:Dictionary=state.duplicate(true)
					for t:Dictionary in changed.tools:
						if t.id==tool:t.durability=0.0
					ops=[{"op":"extension.set","id":"r3:production","before_exists":true,"before":state,"after":changed}]
				else:
					var key:String=Data.key(Data.cell_chunk(Vector3i(cell.x,cell.y,cell.z),16))
					ops=[{"op":"chunk.residency","id":key,"before":true,"after":false}]
				var p:Dictionary=b.world.prepare_changes(ops,b.world.get_revision())
				check("explicit C interference prepares "+label+str(j),p.ok,p)
				if p.ok:b.world.commit_prepared(p.capability)
			if label=="world cell conflict":
				var before:PackedByteArray=signature(pairs[0]);var rejected:Array=[]
				for j:int in 2:rejected.append(pairs[j].runtime._commit(prepared[j]))
				check("stale voxel plans reject atomically without material or wear",rejected[0]==rejected[1] and not rejected[1].ok and signature(pairs[0])==before and signature(pairs[1])==before,rejected)
			else:
				var next:Array=[pairs[0].services.terrain.advance(1.0),pairs[1].services.terrain.advance(1.0)]
				check("same current tool and cold revalidation "+label,next[0]==next[1] and next[1].world_changes.is_empty() and not next[1].fact_changes.is_empty())
				var results:Array=[]
				for j:int in 2:results.append(pairs[j].runtime._commit(next[j]))
				check("same interruption commits atomically "+label,results[0]==results[1] and results[1].ok and pairs[1].runtime.actor("player").intent==null,results)
			equivalent("full interrupted state identical "+label)

func fixture_cases(payload:Dictionary)->void:
	# Isolated schema/availability adapters, explicitly not normal gameplay.
	var original:Dictionary=pairs[1].runtime.facts();var row:Dictionary=original.actors[0]
	for a:Dictionary in original.actors:
		if a.id=="player":row=a;break
	var intent:Dictionary={"schema_version":1,"id":"fixture:terrain-step","owner":"terrain","kind":"terrain","request":{"command_id":"fixture:terrain-step","actor_id":"player","kind":"terrain","payload":payload},"held":false,"tool_id":payload.tool_id,"source_id":"pack:player","cost":{},"elapsed":0.0,"duration":1.5}
	var old:=TerrainBefore.new();var now:=TerrainNow.new();var read:Dictionary=original.duplicate(true);var calls:Dictionary={"facts":0}
	var context:Dictionary={"world":pairs[1].world,"facts":func()->Dictionary:calls.facts+=1;return read.duplicate(true),"actor":func(id:String)->Dictionary:return RuntimeSource.fact_from(read,"actors",id),"available":func()->bool:return true}
	old.context=context;now.context=context
	var person:Dictionary=RuntimeSource.fact_from(read,"actors","player")
	for label:String in ["held valid","held malformed","live work","dead active","no consent","unrelated owner","empty"]:
		person.intent=intent.duplicate(true);person.hp=100.0;person.relationship.consent=true
		if label=="held malformed":person.intent.duration=0.0
		if label in ["live work","dead active","no consent"]:person.intent.held=true
		if label=="dead active":person.hp=0.0
		if label=="no consent":person.id="fixture:npc";person.intent.request.actor_id=person.id;person.intent.source_id="pack:"+person.id;person.relationship.consent=false
		if label=="unrelated owner":person.intent.owner="actions"
		if label=="empty":person.intent=null
		read.actors=[person.duplicate(true)]
		var a:Dictionary=old.advance(0.1);var b:Dictionary=now.advance(0.1)
		check("isolated adapter current facts same plan "+label,a==b,{"old":a,"new":b})
		person.id="player"
	for dt:float in [0.0,-0.1,1.1,INF,NAN]:check("same invalid STEP rejection "+str(dt),old.advance(dt)==now.advance(dt))
	context.available=func()->bool:return false
	check("same unavailable adapter empty rejection",old.advance(0.1)==now.advance(0.1))
	check("fallback never modifies observed adapter facts",read.actors[0].intent==null)

func run()->void:
	var args:=OS.get_cmdline_user_args();output=str(args[0]).get_base_dir()
	idle(args[1]);idle(args[2]);actual_work(args[1])
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	var summary:Dictionary={}
	for row:Dictionary in samples:
		if not summary.has(row.label):summary[row.label]={"old":[],"new":[]}
		for k:String in ["old","new"]:summary[row.label][k].append(row[k])
	for label:String in summary:
		for k:String in ["old","new"]:
			var v:Array=summary[label][k];v.sort();var total:int=0
			for t:int in v:total+=t
			summary[label][k]={"count":v.size(),"total_usec":total,"median_usec":(v[(v.size()-1)/2]+v[v.size()/2])/2.0,"max_usec":v[-1]}
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"samples":samples,"summary":summary,"inputs":notices,"actual_commands":actual,"scope":"paired before/current C domain, real normal20 and late21 inputs; actual harvest terrain commands separate from adapter fixtures; canonical cold not raw binary losslessness; no renderer/OS/FPS"},"\t",true,true))
	print("terrain STEP ",checks.size(),"/",failed);quit(1 if failed else 0)
