extends "res://tests/world/village_contours.gd"
## Freeze the actual old-model inputs before the opt-in v5 implementation.
const Store=preload("res://scripts/storage/native_store.gd")
func run()->void:
	var args:=OS.get_cmdline_user_args()
	var folder:String=args[0].get_base_dir()
	var rows:Array=[]
	for seed:int in [12,713]:
		var start:=Time.get_ticks_usec()
		var source:Dictionary=Landscape.generate(seed,Building.generation_profiles())
		var generated_ms:float=(Time.get_ticks_usec()-start)/1000.0
		check("baseline is unchanged explicit v4 "+str(seed),source.get("extensions",{}).get("generation:rural2",{}).get("landscape_model")=="village-contours-v4")
		if not source.has("chunks"):continue
		FileAccess.open(folder+"/seed%d-source.var"%seed,FileAccess.WRITE).store_var(source)
		start=Time.get_ticks_usec()
		var assembled:Dictionary=Assembly.prepare(source)
		check("baseline actual A/B assembly "+str(seed),assembled.ok,assembled.get("reason"))
		var row:Dictionary={"seed":seed,"raster_sha256":raster_digest(source),"generate_ms":generated_ms,"assembly_ms":(Time.get_ticks_usec()-start)/1000.0}
		if assembled.ok:
			var world:=State.new();world.load_snapshot(assembled.capture.world)
			var runtime:=Runtime.new()
			var configured:Dictionary=runtime.configure({"world":world,"facts":assembled.capture.facts,"source":assembled.capture.source,"services":{"buildings":Building.new(),"actions":Actions.new(),"production":Production.new()}})
			check("baseline formal runtime capture "+str(seed),configured.ok,configured)
			if configured.ok:
				var encoded:Dictionary=Store.encode(runtime.capture_checkpoint())
				check("baseline native encoding "+str(seed),encoded.ok,encoded.get("reason"))
				if encoded.ok:FileAccess.open(folder+"/seed%d-v4.native.json"%seed,FileAccess.WRITE).store_string(encoded.text)
		rows.append(row)
	costs.rows=rows
	costs.scope="Two old v4 raw source snapshots and full A/B native captures, no active slot or formal application. Single CPU samples are diagnostic only."
	finish()
