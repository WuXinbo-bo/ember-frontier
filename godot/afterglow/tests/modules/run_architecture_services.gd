extends "res://tests/modules/normal_module_lifecycle.gd"
const Draft=preload("res://scripts/actions/domain_draft.gd")
## Consume the explicitly finite lifecycle laboratory saves, never a natural
## economy claim. Manual-only branches declare an original physical book and
## hand saw in the player's possession, then use real study/craft settlement.
var cases:Array=[]

func run()->void:
	var args:=OS.get_cmdline_user_args();outdir=args[0];var input:String=args[1];sequence=200000
	var filter:String=args[2] if args.size()>2 else "all"
	var exclude:String=args[3] if args.size()>3 else ""
	for definition:Dictionary in Modules.module_definitions():
		if definition.get("architecture",{}).get("set")!="r34-architecture-30-v1":continue
		if filter=="manual-only" and definition.shape!="manual":continue
		if filter.begins_with("r34.module.") and definition.id!=filter:continue
		if definition.id==exclude:continue
		var label:String=definition.id
		var path:String=input+"/"+label.replace(".","_")+".native.json"
		var decoded:=Store.decode(FileAccess.get_file_as_string(path))
		check("exact lifecycle repaired save decodes "+label,decoded.get("ok",false))
		if not decoded.get("ok",false):continue
		var setup:Dictionary={}
		if definition.shape=="manual":
			var legacy:Dictionary=decoded.capture.world.extensions["r3:production"]
			var player:Dictionary=Draft.find(decoded.capture.facts.actors,"player")
			for record:Dictionary in legacy.records:
				if record.itemId=="book_woodwork":
					setup.record=record.id;setup.original_book_holder=record.holderId
					record.holderId="pack:player";player.pack["book_woodwork"]=1;break
			for tool:Dictionary in legacy.tools:
				if tool.kind=="hand_saw":
					setup.saw=tool.id;setup.original_tool_holder=tool.holderId
					tool.holderId="pack:player";break
		var pack_keys:Array=[]
		for key:Variant in Draft.find(decoded.capture.facts.actors,"player").pack:
			pack_keys.append({"key":key,"type":type_string(typeof(key)),"value":Draft.find(decoded.capture.facts.actors,"player").pack[key]})
		setup.pack_keys=pack_keys
		var native:=Native.new();live=native._assemble(decoded.capture);native.free()
		check("real Native restores service fixture "+label,live.get("ok",false),{"reason":live.get("reason"),"declared_setup":setup})
		if not live.get("ok",false):continue
		var rt:RefCounted=live.runtime;var id:String="B:life:"+label
		var module:Dictionary=rt._services.modules.instance(id)
		check("paid repaired module remains original geometry and empty caches "+label,module.status=="operational" and module.geometry_version==definition.geometry_version and module.stock_refs.values().all(func(stock_id:String)->bool:return rt.stock(stock_id).items.is_empty()))
		var ports:Array=ModuleShape.ports(module,definition)
		for port:Dictionary in ports:
			var arrived:=walk(rt,port.location)
			check("actual real body route to "+label+":"+str(port.id),arrived.get("ok",false),arrived.get("reason"))
		for buffer:Dictionary in definition.buffer_specs:
			var stock_id:String=module.stock_refs[buffer.id];var item:String=buffer.limits.keys()[0]
			var port:Dictionary=Draft.find(ports,str(buffer.port_id));var arrived:=walk(rt,port.location)
			var before:Dictionary=rt.actor("player").pack.duplicate(true)
			var put:Dictionary=send(rt,"deposit",stock_id,{"items":{item:1}}) if arrived.get("ok",false) else {"ok":false,"reason":"actual service route failed"}
			var take:Dictionary=send(rt,"take",stock_id,{"items":{item:1}}) if put.ok else {"ok":false}
			check("real finite stock roundtrip "+label+":"+str(buffer.id),put.ok and take.ok and rt.stock(stock_id).items.get(item,0)==0 and Data.json_equal(rt.actor("player").pack,before),{"deposit":put.get("code"),"take":take.get("code"),"reason":put.get("reason")})
		if definition.shape=="manual":
			var studied:Dictionary=send(rt,"study",str(setup.get("record","")),{"direct":false})
			var learned:Dictionary=progress(rt,200) if studied.ok else {}
			check("declared physical book actual twelve-second study "+label,studied.ok and learned.get("finished",false) and rt._services.production.state().knowledge.get("player",[]).has("basic_woodwork"),studied.get("reason"))
			if care(rt,50):
				var before:Dictionary=rt.actor("player").pack.duplicate(true);var durability:float=rt.tool(str(setup.get("saw",""))).get("durability",0)
				var made:=send(rt,"craft",str(module.config.workbench_id),{"direct":false,"recipe_id":"saw_timber","source_id":"pack:player","output_id":"pack:player","tool_ids":[str(setup.get("saw",""))]})
				var finished:Dictionary=progress(rt,1000) if made.ok else {}
				check("original unique bench actual contact labor materials and wear "+label,made.ok and finished.get("finished",false) and rt.actor("player").pack.get("log",0)==float(before.get("log",0))-1 and rt.actor("player").pack.get("timber",0)==float(before.get("timber",0))+4 and is_equal_approx(rt.tool(str(setup.get("saw",""))).durability,durability-2),{"code":made.get("code"),"reason":made.get("reason"),"intent":rt.actor("player").get("intent")})
		elif definition.shape=="woodshop":
			var fed:bool=true
			for spec:Array in [["input",2],["fuel",1]]:
				var stock_id:String=module.stock_refs[spec[0]];var reached:bool=near_stock(rt,stock_id)
				var put:Dictionary=send(rt,"deposit",stock_id,{"items":{"log":spec[1]}}) if reached else {"ok":false}
				check("physical original log feed "+label+":"+str(spec[0]),put.ok,put.get("reason"));fed=fed and put.ok
			var order:=send(rt,"factory.configure",id,{"recipe_id":"saw_timber","batches":2}) if fed else {"ok":false}
			for step:int in 450:
				if not order.ok or rt.stock(module.stock_refs.output).items.get("timber",0)==8:break
				rt.tick(.1)
			var production:Dictionary=rt.factory_snapshot().production
			check("original machine two finite batches settle once "+label,order.ok and rt.stock(module.stock_refs.output).items.get("timber",0)==8 and production.batches.filter(func(b:Dictionary)->bool:return b.module_id==id and b.status=="completed").size()==2 and rt.stock(module.stock_refs.input).items.get("log",0)==0 and rt.stock(module.stock_refs.fuel).items.get("log",0)==0,production.orders)
			var projected:Dictionary=rt._services.modules.projection("player",id).instances[0]
			var anchor:Array=projected.visuals.anchors.saw.position;var point:Array=definition.machine_work_point
			var expected:Dictionary=ModuleShape.at(module,Vector3(point[0],point[1],point[2]))
			check("real mechanism follows actual versioned saw geometry "+label,Vector3(anchor[0],anchor[1],anchor[2]).distance_to(Geometry.point(expected))<.001)
		cases.append({"id":label,"shape":definition.shape,"declared_manual_setup":setup,"actual_pack":rt.actor("player").pack,"stocks":module.stock_refs})
		cold("actual-services-"+label.replace(".","_"))
		live.runtime.retire();live={}
	finish()

func finish()->void:
	var result:Dictionary={"checks":checks,"cases":cases,"commands":commands,"live_roundtrip":live_roundtrip,"scope":"All thirty explicitly finite flat lifecycle laboratory saves; actual Native/Runtime walk and stock transfer, original manual book study/craft or two original fuel-machine batches and strict cold persistence. Manual branches explicitly relocate the original book/tool and declare one book item before mount; not a natural economic/source journey, NPC residence allocation, enemy attack, PCK/GPU/VA/FPS."}
	FileAccess.open(outdir+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	var ok:bool=not checks.is_empty() and checks.all(func(c:Dictionary)->bool:return c.ok)
	quit(0 if ok else 1)
