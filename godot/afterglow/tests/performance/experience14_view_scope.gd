extends SceneTree
## Notification dependency isolation only; no scene/FPS qualification.
class Probe extends "res://scripts/buildings/building_view.gd":
	var updates:Dictionary={"visibility":0,"contents":0,"state":0}
	func update_visibility()->void:updates.visibility+=1
	func update_contents()->void:updates.contents+=1
	func update_state_details()->void:updates.state+=1
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool,detail:Variant=null)->void:checks.append({"label":label,"ok":ok,"detail":detail})
func movement(id:String)->Dictionary:
	var before:Dictionary={"id":id,"x":1.0,"y":0.5,"z":2.0,"regionId":"RH-HOME","buildingId":null,"storeyId":null}
	var after:Dictionary=before.duplicate(true);after.x+=0.1
	return {"world":[],"facts":[{"collection":"actors","id":id,"before":before,"after":after}],"events":[{"kind":"actor-moved","actor_id":id,"mode":"walk","elapsed":0.05}],"revision":1,"actor_transitions":[]}
func run()->void:
	var view:=Probe.new()
	for i:int in 20:view._profiled_changed(movement("walker:"+str(i%2)))
	check("two other walkers never query or refresh building view",view.updates=={"visibility":0,"contents":0,"state":0},view.updates.duplicate())
	view._profiled_changed(movement("player"))
	check("player viewpoint still refreshes immediately",view.updates=={"visibility":1,"contents":0,"state":0},view.updates.duplicate())
	view._profiled_changed({"clock":1.0,"revision":2,"simulation":{}})
	check("original clock sampling still settles pending room transitions",view.updates.visibility==2)
	var edit:Dictionary=movement("walker:0")
	edit.world=[{"op":"extension.set","id":"fixture:permission","before_exists":false,"before":null,"after":{"allowed":false}}]
	view._profiled_changed(edit)
	check("world permission/metadata mutation never uses other-actor shortcut",view.updates.visibility==3)
	var transition:Dictionary=movement("walker:0");transition.actor_transitions=[{"actor_id":"player","reason":"released"}]
	view._profiled_changed(transition)
	check("player exit/release transition remains immediate",view.updates.visibility==4)
	var stock:Dictionary=movement("walker:0");stock.facts.append({"collection":"stocks","id":"actual:drop","before":null,"after":{"id":"actual:drop"}})
	view._profiled_changed(stock)
	check("mixed actor/stock notification refreshes contents and visibility",view.updates.visibility==5 and view.updates.contents==1)
	var unknown:Dictionary=movement("walker:0");unknown.fixture_unknown=true
	view._profiled_changed(unknown)
	check("unknown notification shape cannot claim fast path",view.updates.visibility==6)
	var changed:Dictionary=movement("walker:0");changed.facts[0].collection="quests"
	view._profiled_changed(changed)
	check("non-actor fact does not claim actor-only proof",view.updates.visibility==7)
	view.free()
	var failed:int=checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	var result:Dictionary={"checks":checks,"failed":failed,"scope":"isolated exact notification-dependency interception; actor rendering/authority unchanged; not actual scene/FPS"}
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true))
	print("VIEW_SCOPE "+JSON.stringify(result));quit(1 if failed else 0)
