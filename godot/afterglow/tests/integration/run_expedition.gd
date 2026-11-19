extends "res://tests/integration/run_gameplay.gd"
## Explicit combat fixture (extra finite medicine), then actual movement,
## transfer/settlement/defense using the formal runtime. Not app input acceptance.
func configure_fixture(facts:Dictionary)->void:
	facts.actors[0].pack["medicine"]=6
func heal()->bool:
	if runtime.actor("player").hp>=72:return true
	var receipt:=request("medicine")
	if not receipt.ok:return false
	for tick:int in 13:runtime.tick(0.1)
	return float(runtime.actor("player").hp)>0
func travel(place:Dictionary)->Dictionary:
	seq+=1
	var result:Dictionary=runtime.command({"command_id":"travel:"+str(seq),"actor_id":"player","kind":"walk","destination":place,"payload":{},"expected_revision":runtime.get_revision()})
	if not result.ok:return result
	for tick:int in 1600:
		runtime.tick(0.1)
		if runtime.actor("player").get("intent")==null:
			var a:Dictionary=runtime.actor("player")
			var distance:float=Vector3(a.x,a.y,a.z).distance_to(Vector3(place.x,place.y,place.z))
			return {"ok":distance<0.4,"actor":a,"distance":distance}
	return {"ok":false,"reason":"walk did not finish"}
func combat_step(direction:Vector3)->void:
	var a:Dictionary=runtime.actor("player")
	if a.regionId=="RH-HOME":
		if float(a.z)<37 and direction.z<0:direction=Vector3.RIGHT
		elif float(a.x)>45 and direction.x>0:direction=Vector3.BACK
		elif float(a.z)>54 and direction.z>0:direction=Vector3.LEFT
		elif float(a.x)<31 and direction.x<0:direction=Vector3.FORWARD
	var destination:Dictionary={"x":float(a.x)+direction.x*0.28,"y":a.y,"z":float(a.z)+direction.z*0.28,"regionId":a.regionId,"buildingId":a.get("buildingId"),"storeyId":a.get("storeyId")}
	seq+=1
	runtime.command({"command_id":"combat-step:"+str(seq),"actor_id":"player","kind":"direct_move","destination":destination,"payload":{},"expected_revision":runtime.get_revision()})
func fight()->bool:
	for tick:int in 700:
		var living:Array=runtime.facts().actors.filter(func(a:Dictionary)->bool:return a.get("faction")=="infected" and a.get("regionId")==runtime.actor("player").regionId and float(a.hp)>0)
		if living.is_empty():return state().defense.status!="active" or state().defense.actors.all(func(id:String)->bool:return runtime.actor(id).hp<=0)
		if float(runtime.actor("player").hp)<=0:return false
		var a:Dictionary=runtime.actor("player")
		living.sort_custom(func(x:Dictionary,y:Dictionary)->bool:return Vector3(a.x,a.y,a.z).distance_squared_to(Vector3(x.x,x.y,x.z))<Vector3(a.x,a.y,a.z).distance_squared_to(Vector3(y.x,y.y,y.z)))
		if float(a.hp)<40 and a.intent==null and float(a.pack.get("medicine",0))>0:request("medicine")
		elif a.intent==null:
			var offset:Vector3=Vector3(a.x,a.y,a.z)-Vector3(living[0].x,living[0].y,living[0].z)
			var distance:float=offset.length()
			if float(a.cooldown)<=0 and float(a.stamina)>=14 and distance<=2.05:request("attack",living[0].id,{"tool_id":"fixture:axe"})
			elif distance<1.7:combat_step(offset.normalized())
			elif distance>1.9 and float(a.stamina)>=14:combat_step(-offset.normalized())
		runtime.tick(0.1)
	return false
func continue_route()->void:
	check("finite medicine fixture heals via real timed consumption",heal())
	var drops:Array=runtime.facts().stocks.filter(func(s:Dictionary)->bool:return str(s.id).begins_with("infected:"))
	if drops.is_empty():return
	var source:Dictionary=drops[0]
	var result:=travel(source.location)
	check("walk to actual ground loot",result.ok,result.get("reason",result.get("actor",{}).get("activity")))
	if not result.ok:return
	var before:float=runtime.actor("player").pack.get("scrap",0)
	var taken:=request("take",source.id,{"items":{"scrap":1}})
	check("real loot transfer consumes ground stock once",taken.ok and runtime.actor("player").pack.get("scrap",0)==before+1 and runtime.stock(source.id).items.get("scrap",0)==0,taken)
	runtime.tick(0.1)
	check("real transfer ledger counted for settlement",int(state().exploration.loot_collected)==1)
	result=travel({"x":32.0,"y":0.0,"z":-26.5,"regionId":"RH-VILLAGE","buildingId":null,"storeyId":null})
	check("actual road movement reaches second finite encounter",result.ok,result.get("actor",{}).get("activity"))
	if not result.ok:return
	check("second actual encounter can be fought",fight())
	for tick:int in 2:runtime.tick(0.1)
	check("both finite encounters actually cleared",state().encounters.all(func(e:Dictionary)->bool:return e.cleared))
	var choices:Array=state().exploration.candidates
	check("second encounter offers remaining different choices",choices.size()>=2 and not choices.has(state().exploration.upgrades[0]),choices)
	if not choices.is_empty():check("second choice actual command",request("explore_choose","",{"choice_id":choices[0]}).ok)
	heal()
	result=travel({"x":32.0,"y":0.0,"z":43.0,"regionId":"RH-HOME","buildingId":null,"storeyId":null})
	check("same world route returns across actual region exit",result.ok,result.get("actor",{}).get("activity"))
	if not result.ok:return
	var inventory:Dictionary=runtime.actor("player").pack
	var hp:float=runtime.actor("player").hp
	var end:=request("explore_end")
	check("explicit settlement clears temporary abilities only",end.ok and state().exploration.upgrades.is_empty() and runtime.actor("player").pack==inventory and runtime.actor("player").hp==hp,end)
	check("two choices and recovered real loot trigger warning",state().flags.get("exploration_completed",false) and state().defense.status=="warning")
	check("repeat settlement cannot duplicate rewards",not request("explore_end").ok)
	var encoded:Dictionary=Store.encode(runtime.capture_checkpoint());var decoded:Dictionary=Store.decode(encoded.get("text",""))
	var rebuilt:Dictionary=host._assemble(decoded.capture) if decoded.ok else decoded
	check("settled journey and warning pass full restore",rebuilt.ok,rebuilt.get("reason"))
	if not rebuilt.ok:return
	runtime=rebuilt.runtime
	check("player can actually recover stamina before readiness",request("rest").ok)
	for tick:int in 120:runtime.tick(0.1)
	check("actual readiness advances finite defense",request("defend").ok)
	runtime.tick(0.1)
	check("defense spawns exactly three real actors",state().defense.actors.size()==3)
	check("finite defense actually fought through shared combat",fight(),runtime.actor("player"))
	for tick:int in 2:runtime.tick(0.1)
	check("defense resolves actual deaths without infinite respawn",state().defense.status=="cleared",state().defense)
	var count:int=runtime.facts().actors.size()
	for tick:int in 100:runtime.tick(0.1)
	check("finite defense remains settled on later ticks",runtime.facts().actors.size()==count and state().defense.status=="cleared")
	check("radio remains unconnected until real repair",state().radio.status=="unrepaired" and not request("radio","",{"operation":"transmit"}).ok)
