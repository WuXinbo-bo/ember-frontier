extends SceneTree
const Factory=preload("res://scripts/world/factory_generator.gd")
const Catalog=preload("res://scripts/modules/module_catalog.gd")
const Contract=preload("res://scripts/world/factory_generation_contract.gd")
const Raster=preload("res://scripts/world/settlement_generator.gd")
const Water=preload("res://scripts/world/factory_water_sources.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
func _initialize()->void:
 var profiles:Array=Catalog.profiles_for_content(10);var rows:Array=[]
 for number:int in [713,2026]:
  var result:Dictionary=Factory.plan_region(number,Vector2i(0,-1),profiles,Contract.fresh(profiles,10,1).contract)
  var plan:Dictionary=result.plan;var seed:Dictionary=plan.module_seeds.filter(func(s:Dictionary)->bool:return s.purpose=="store")[0]
  var profile:Dictionary=profiles.filter(func(p:Dictionary)->bool:return p.id==seed.definition_id)[0]
  var root:Array=profile.ports[0].use_points[0];var noise:=Raster._noise(number);var roads:=Raster._road_index(plan);var candidates:Array=[]
  for x:float in [-3.0,-2.2,-1.8,-1.4,1.4,1.8,2.2,3.0]:
   for z:float in [.4,.9,1.4,2.0]:
    var p:Vector3=G.point(seed.position)+G.rotate(Vector3(root[0]+x,root[1],root[2]+z),seed.quarter_turn)
    var u:Vector3=p+G.rotate(Vector3(signf(x)*.9,0,0),seed.quarter_turn)
    var distances:Array=[]
    for segment:Dictionary in roads.get(Vector2i(floori(p.x/8),floori(p.z/8)),[]):distances.append({"d":Raster._distance(p.x,p.z,segment.a,segment.b).x,"half":segment.half})
    candidates.append({"offset":[x,z],"p":G.json_point(p),"h":Water._surface(plan,noise,roads,p.x,p.z,.5),"uh":Water._surface(plan,noise,roads,u.x,u.z,.8),"roads":distances})
  rows.append({"seed":number,"module":seed,"profile":profile,"parcels":plan.parcels,"candidates":candidates})
 FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify({"checks":[],"failed":0,"rows":rows},"\t",true,true));quit()
