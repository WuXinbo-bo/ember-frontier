extends SceneTree
## Controlled mask/segment fixtures using C's real generated voxel/chunk data.
## A synthetic rural-2 identity here only enables the partition policy; this
## does not claim the legacy layout became a production rural-2 world.
const Generator=preload("res://scripts/world/rural_generator.gd")
const View=preload("res://scripts/world/world_view.gd")
const Space=preload("res://scripts/buildings/building_space.gd")
const Geometry=preload("res://scripts/buildings/building_geometry.gd")
var checks:Array=[]
var failed:=false
var source:Dictionary
var geometry:=Geometry.new()

func expect(label:String,ok:bool,evidence:Variant=null)->void:
	checks.append({"label":label,"ok":ok,"evidence":evidence})
	if not ok:failed=true;print("FAIL ",label," ",JSON.stringify(evidence))

func at(x:float,z:float)->Dictionary:
	return {"x":x,"y":0.0,"z":z,"regionId":"RH-HOME" if z>=0 else "RH-VILLAGE","buildingId":null,"storeyId":null}

func query(entities:Array=[])->RefCounted:
	var state:=source.duplicate(true);state.entities={}
	for e:Dictionary in entities:state.entities[e.id]=e
	var view:=View.new(state);var q:=Space.new()
	q.configure(view,{"instances":[],"storeys":[]},geometry,func(_a:String,_t:String,_k:String,_p:Dictionary)->Variant:return null)
	return q

func prop(solid:bool,opaque:bool)->Dictionary:
	return {"id":"fixture:thin","kind":"prop","regionId":"RH-VILLAGE","position":{"x":48.0,"y":0.0,"z":-0.55},"bounds":{"min":{"x":47.7,"y":0.0,"z":-0.555},"max":{"x":48.3,"y":1.8,"z":-0.545}},"data":{"solid":solid,"opaque":opaque},"revision":0}

func _initialize()->void:call_deferred("run")
func run()->void:
	source=Generator.generate(713);source.generatorVersion="rural-2"
	geometry.configure(JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/catalog.json")))
	var a:=at(48,3);var b:=at(48,-3)
	var q:=query()
	expect("fixture real ground supports both sides",not q.standing_point(a).is_empty() and not q.standing_point(b).is_empty())
	expect("six metre sight crosses real bounds without hand range",q.line_clear(a,b))
	expect("C contact range remains short",not q.world.continuous_outdoor_contact(a,b).ok)
	expect("same six metre scene translated into one region agrees",q.line_clear(at(48,13),at(48,7)))
	q=query([prop(true,false)])
	expect("transparent solid does not occlude sight",q.line_clear(a,b))
	expect("transparent solid still blocks tool contact",not q.contact_clear(a,b))
	expect("transparent solid still blocks body",not q.walk("player",a,b).ok)
	q=query([prop(false,true)])
	expect("opaque non-solid thin sheet occludes exact sight",not q.line_clear(a,b))
	expect("opaque non-solid sheet does not invent contact collider",q.contact_clear(a,b))
	expect("opaque non-solid sheet does not invent body collider",q.walk("player",a,b).ok)
	q=query([prop(true,true)])
	expect("excluded endpoint identity is purpose independent",q.line_clear(a,b,"fixture:thin") and q.contact_clear(a,b,"fixture:thin"))
	var box:=AABB(Vector3.ZERO,Vector3.ONE)
	for row:Dictionary in [
		{"name":"start inside","a":Vector3(0.5,0.5,0.5),"b":Vector3(2,0.5,0.5),"hit":true},
		{"name":"endpoint min included","a":Vector3(-1,0.5,0.5),"b":Vector3(0,0.5,0.5),"hit":true},
		{"name":"endpoint max excluded","a":Vector3(2,0.5,0.5),"b":Vector3(1,0.5,0.5),"hit":false},
		{"name":"max-face coplanar","a":Vector3(-1,1,0.5),"b":Vector3(2,1,0.5),"hit":false},
		{"name":"min-face owner","a":Vector3(-1,0,0.5),"b":Vector3(2,0,0.5),"hit":true},
		{"name":"zero-volume corner graze","a":Vector3(-1,1,0.5),"b":Vector3(1,-1,0.5),"hit":false},
		{"name":"corner tie enters interior","a":Vector3(-1,-1,-1),"b":Vector3(2,2,2),"hit":true}]:
		expect("B box segment "+row.name,Space.segment_hits_box(box,row.a,row.b)==row.hit)
	var nav:Dictionary=q.route("player",a,b)
	expect("NPC navigator crosses away from authored exit",nav.ok,nav)
	var old:String=source.generatorVersion;source.generatorVersion="r3-town-5"
	q=query();expect("old city does not gain implicit continuous portal",not q.route("player",a,b).ok and not q.line_clear(a,b))
	source.generatorVersion=old
	print(JSON.stringify({"ok":not failed,"checks":checks,"scope":"B pure query fixtures; generated C chunks; independent masks and partition policy, not formal app or rural model acceptance"}))
	quit(1 if failed else 0)
