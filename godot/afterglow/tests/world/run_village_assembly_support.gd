extends SceneTree
## Same production assembly gate used by new-game entry; no funded fixture.
const Assembly=preload("res://scripts/runtime/factory_assembly.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func run()->void:
	var profiles:Dictionary=Assembly.generation_profiles(13)
	for seed:int in [713,2026,17]:
		var source:Dictionary=Assembly.generate(seed,profiles.get("profiles",[]),13) if profiles.ok else profiles
		var result:Dictionary=Assembly.prepare(source) if source.get("ok",true) else source
		var ok:bool=result.get("ok",false)
		var row:Dictionary={"seed":seed,"ok":ok,"code":result.get("code"),"reason":result.get("reason")}
		if ok:
			var actors:Array=result.capture.facts.actors
			row.three_in_home=actors.size()==3 and actors.all(func(a:Dictionary)->bool:return a.regionId=="RH-HOME")
			row.opening_version=result.layout.get("opening_version")
			ok=bool(row.three_in_home) and row.opening_version==3
			row.ok=ok
		checks.append(row);print(JSON.stringify(row))
		if not ok:push_error("actual opening assembly "+str(seed)+": "+str(row))
	var failed:int=checks.filter(func(c:Dictionary)->bool:return not c.ok).size()
	print(JSON.stringify({"suite":"village-actual-assembly-support","checks":checks,"failed":failed}))
	quit(0 if failed==0 else 1)
