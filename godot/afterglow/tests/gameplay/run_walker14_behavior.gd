extends SceneTree
## Isolated deterministic AI contract: fake sight/motion boundaries are
## deliberate fixtures. Actual generation/cold persistence has its own test.
const Gameplay=preload("res://scripts/runtime/rural_gameplay.gd")
const Initial=preload("res://scripts/runtime/initial_state.gd")
const Draft=preload("res://scripts/actions/domain_draft.gd")
var checks:Array=[]
class World extends RefCounted:
	var values:Dictionary={"r3:production":{"tools":[]}}
	func extension(id:String)->Variant:return values.get(id)
class Space extends RefCounted:
	var visible:bool=true
	func current_space()->RefCounted:return self
	func line_clear(_a:Dictionary,_b:Dictionary,_id:String)->bool:return visible
class Actions extends RefCounted:
	var blocked:bool=false
	var paths:int=0
	func move_step(_id:String,_from:Dictionary,to:Dictionary)->Dictionary:return {"ok":not blocked,"location":to}
	func route(_id:String,from:Dictionary,to:Dictionary)->Dictionary:
		paths+=1
		var side:Dictionary=from.duplicate();side.z+=1
		return {"ok":true,"steps":[{"kind":"move","to":side},{"kind":"move","to":to}]}
class Modules extends RefCounted:
	var hits:int=0
	func strike_hostile(_tx:RefCounted,_id:String)->Dictionary:hits+=1;return {"ok":true}
func _initialize()->void:call_deferred("run")
func check(label:String,ok:bool)->void:
	checks.append({"name":label,"ok":ok})
	if not ok:push_error(label)
func at(x:float,z:float)->Dictionary:return {"x":x,"y":0.0,"z":z,"regionId":"EXTERIOR","buildingId":null,"storeyId":null}
func run()->void:
	var world:=World.new();var space:=Space.new();var actions:=Actions.new();var modules:=Modules.new()
	var enemy:Dictionary=Initial.actor("enemy","感染者",at(0,0),at(0,0),{"scrap":1})
	enemy.faction="infected";enemy.walker_version=14;enemy.walker_brain={"phase":"patrol","origin":at(0,0),"next_sense":0.0,"next_path":0.0,"route":[]}
	var player:Dictionary=Initial.actor("player","测试角色",at(6,0),at(6,0),{})
	var facts:Dictionary={"scenario":"factory-settlement-r34","time":0.0,"actors":[enemy,player],"stocks":[],"ledger":[]}
	var context:Dictionary={"world":world,"spatial":space,"facts":func()->Dictionary:return facts,"clock":func()->float:return 0.0,"region_is_detailed":func(_id:String)->bool:return true}
	var service:=Gameplay.new();service.context=context;service._actions=weakref(actions);service._modules=weakref(modules)
	var tx:=Draft.new(context);enemy=tx.actor("enemy");player=tx.actor("player")
	space.visible=false;service._walker_step(tx,enemy,{},.1,0.0)
	check("unseen wall-separated human is not acquired",enemy.walker_brain.phase=="patrol" and not enemy.walker_brain.has("target_id"))
	var patrol_start:float=float(enemy.x)
	service._walker_step(tx,enemy,{},.1,.1)
	check("idle walker actually patrols",float(enemy.x)!=patrol_start)
	space.visible=true;service._walker_step(tx,enemy,{},.1,.4)
	check("first visual contact acquires living target",enemy.walker_brain.phase=="chase" and enemy.walker_brain.target_id=="player")
	var remembered:Dictionary=enemy.walker_brain.last_seen.duplicate()
	space.visible=false;player.x=30.0;service._walker_step(tx,enemy,{},.1,.8)
	check("occlusion loses live tracking and searches last seen position",enemy.walker_brain.phase=="search" and enemy.walker_brain.last_seen==remembered)
	service._walker_step(tx,enemy,{},.1,7.0)
	check("expired search returns without permanent wall tracking",enemy.walker_brain.phase in ["return","patrol"] and not enemy.walker_brain.has("target_id"))
	enemy.walker_brain.phase="patrol";enemy.walker_brain.next_sense=0;player.merge(at(8,0),true);player.intent={"kind":"craft"}
	service._walker_step(tx,enemy,{},.1,8.0)
	check("real ongoing production intent produces an investigable sound",enemy.walker_brain.phase=="investigate" and enemy.walker_brain.last_seen.x==8.0)
	player.intent=null;enemy.walker_brain.next_sense=0;enemy.walker_brain.phase="chase";space.visible=true;player.merge(at(float(enemy.x)+.5,float(enemy.z)),true)
	var hp:float=float(player.hp);service._walker_step(tx,enemy,{},.1,9.0)
	check("visible contact causes real damage cooldown and wound",player.hp==hp-8 and enemy.cooldown==1.3 and player.wounds.size()==1)
	enemy.cooldown=0.0;actions.blocked=true;service._walker_path_budget=1;enemy.walker_brain.next_path=0;enemy.walker_brain.route=[]
	service._walker_move(tx,enemy,at(10,0),.1,10.0);service._walker_move(tx,enemy,at(10,0),.1,10.1)
	check("obstacle requests real route once within bounded replan interval",actions.paths==1 and enemy.walker_brain.route.size()==2)
	check("blocked walker delegates contact damage to authority",modules.hits==2)
	enemy.hp=0;service._drop(tx,enemy);service._drop(tx,enemy)
	check("death emits exactly one actual loot container",tx.staged.stocks.size()==1 and tx.extra.size()==1 and enemy.pack.is_empty() and enemy.death_settled)
	var result:Dictionary={"ok":checks.all(func(row:Dictionary)->bool:return row.ok),"scope":"Isolated deterministic sight/motion/actor fixtures; validates production walker logic, not natural combat or GPU.","checks":checks}
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if not args.is_empty():DirAccess.make_dir_recursive_absolute(args[0]);var file:=FileAccess.open(args[0].path_join("results.json"),FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));quit(0 if result.ok else 1)
