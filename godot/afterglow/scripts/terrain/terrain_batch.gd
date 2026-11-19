extends RefCounted
## Read-only earthwork selection. Each job changes one real voxel through the
## original TerrainService; no balanced-volume teleport or atomic mega-sculpt.
const Data=preload("res://scripts/world/world_data.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
const MODES=["cut","fill","balance","ramp_x","ramp_z"]

static func target_y(zone:Dictionary,cell:Dictionary,size:float)->Variant:
 var policy:Dictionary=zone.get("policy",{});var height:Variant=policy.get("target_height");var mode:String=str(policy.get("mode","balance"))
 if not (height is float or height is int) or not is_finite(float(height)) or absf(float(height)/size-roundf(float(height)/size))>.000001 or mode not in MODES:return null
 var end:int=roundi(float(height)/size)
 if mode not in ["ramp_x","ramp_z"]:return end
 var axis:String="x" if mode=="ramp_x" else "z";var lo:int=int(zone.bounds.x0 if axis=="x" else zone.bounds.z0);var hi:int=int(zone.bounds.x1 if axis=="x" else zone.bounds.z1)
 if hi-lo<3:return null
 var starts:Array=zone.get("cells",[]).filter(func(c:Dictionary)->bool:return int(c[axis])==lo)
 if starts.is_empty():return null
 var start:int=int(starts[0].y)
 if not starts.all(func(c:Dictionary)->bool:return c.y==start) or absf(float(end-start))/float(hi-lo-1)>.5:return null
 return roundi(lerpf(float(start),float(end),float(int(cell[axis])-lo)/float(hi-lo-1)))

static func protected(world:RefCounted,cell:Dictionary,region:String)->String:
 var size:float=world.config().cellSize;var current:int=world.cell_at(cell.x,cell.y,cell.z)
 if current==4:return "PROTECTED_ROAD"
 var at:=Vector3((float(cell.x)+.5)*size,float(cell.y)*size,(float(cell.z)+.5)*size)
 var volume:=G.json_box(AABB(at-Vector3(size/2,size,size/2),Vector3(size,size*3,size)))
 for entity:Dictionary in world.entities_in_bounds(volume):
  if entity.get("blocksTerrain",true) or not entity.get("supportBounds",[]).is_empty():return "PROTECTED_OBJECT_OR_FOUNDATION"
 for exit:Dictionary in world.region(region).get("exits",[]):
  if G.point(exit.position).distance_to(at)<=float(exit.get("width",2))/2+size:return "PROTECTED_REGION_EXIT"
 # The outlet/foot may sit outside its solid well. Keep that physical mouth.
 for entity:Dictionary in world.entities_in_bounds(G.json_box(AABB(at-Vector3(3,2,3),Vector3(6,6,6)))):
  var source:Dictionary=entity.get("data",{}).get("raw_water_source",{})
  if not source.is_empty() and Vector2(float(source.use_point.x)-at.x,float(source.use_point.z)-at.z).length()<.85:return "PROTECTED_WATER_OUTLET"
 return ""

static func next_cell(world:RefCounted,zone:Dictionary,selected:Dictionary)->Dictionary:
 var size:float=world.config().cellSize;var top:Variant=world.surface_height((float(selected.x)+.5)*size,(float(selected.z)+.5)*size)
 var wanted:Variant=target_y(zone,selected,size)
 if top==null:return Data.reject("UNKNOWN_CELL")
 if wanted==null:return Data.reject("INVALID_BATCH_GRADE")
 var y:int=roundi(float(top)/size);var mode:String=str(zone.get("policy",{}).get("mode","balance"))
 if wanted==y or (mode=="cut" and y<wanted) or (mode=="fill" and y>wanted):return Data.reject("NO_CHANGE")
 var cell:Dictionary={"x":int(selected.x),"y":y-1 if y>wanted else y,"z":int(selected.z)}
 var cfg:Dictionary=world.config()
 if int(wanted)<=int(cfg.minCellY) or int(wanted)>=int(cfg.maxCellY):return Data.reject("HEIGHT_LIMIT")
 if cell.y<=cfg.minCellY or cell.y>=cfg.maxCellY:return Data.reject("HEIGHT_LIMIT")
 if not world.is_cell_known(cell.x,cell.y,cell.z) or not world.is_cell_resident(cell.x,cell.y,cell.z):return Data.reject("UNLOADED_CELL")
 var position:Dictionary={"x":(cell.x+.5)*size,"y":cell.y*size,"z":(cell.z+.5)*size}
 if world.region_at(position).get("id")!=zone.region_id:return Data.reject("WRONG_REGION")
 var reason:String=protected(world,cell,str(zone.region_id))
 # Filling over a road is protected even though the target itself is air.
 if world.cell_at(cell.x,y-1,cell.z)==4:reason="PROTECTED_ROAD"
 if not reason.is_empty():return Data.reject(reason)
 var before:int=world.cell_at(cell.x,cell.y,cell.z);var operation:String="dig" if y>wanted else "fill"
 var material:int=int(zone.get("policy",{}).get("fill_material",2))
 if material not in [2,3,6]:return Data.reject("UNKNOWN_MATERIAL")
 var after:int=0 if operation=="dig" else material
 if after==0 and not Data.MATERIALS.get(before,{}).get("diggable",false):return Data.reject("PROTECTED_TERRAIN")
 var item:String=str(Data.MATERIALS[before if operation=="dig" else material].get("item",""))
 var target:Dictionary=position.merged({"regionId":zone.region_id,"buildingId":null,"storeyId":null},true)
 target.y+=size # exposed/current or proposed top, never a buried voxel base
 return {"ok":true,"cell":cell,"before":before,"after":after,"operation":operation,"item":item,"quantity":size*size*size,"target":target,"current_y":y,"target_y":wanted,"remaining_voxels":absi(y-int(wanted))}

static func preview(world:RefCounted,zone:Dictionary)->Dictionary:
 var cells:Array=[];var excluded:Array=[];var reasons:Dictionary={};var cut:Dictionary={};var fill:Dictionary={};var voxels:int=0
 for cell:Dictionary in zone.get("cells",[]):
  var row:=next_cell(world,zone,cell)
  if not row.ok:
   if row.code=="NO_CHANGE":cells.append(cell.duplicate(true));continue
   reasons[row.code]=int(reasons.get(row.code,0))+1;excluded.append({"cell":cell.duplicate(true),"code":row.code});continue
  cells.append(cell.duplicate(true));voxels+=row.remaining_voxels
  # Exact layered excavation materials, not top-soil multiplied through rock.
  if row.operation=="dig":
   for y:int in range(int(row.target_y),int(row.current_y)):
    var material:int=world.cell_at(cell.x,y,cell.z)
    if material==4 or not Data.MATERIALS.get(material,{}).get("diggable",false):return Data.reject("PROTECTED_TERRAIN_LAYER")
    var item:String=Data.MATERIALS[material].item;cut[item]=float(cut.get(item,0))+.125
  else:fill[row.item]=float(fill.get(row.item,0))+.125*row.remaining_voxels
 var balance:Dictionary=cut.duplicate(true)
 for item:String in fill:balance[item]=float(balance.get(item,0))-float(fill[item])
 return {"ok":not cells.is_empty(),"code":"OK" if not cells.is_empty() else "NO_VALID_CELLS","cells":cells,"excluded":excluded,"reasons":reasons,"estimate":{"cut_m3":cut,"fill_m3":fill,"net_material":balance,"voxel_operations":voxels,"minimum_labor_seconds":voxels*1.5,"execution":"one voxel per real labor/pack transfer; partial completed work survives cancellation"},"world_revision":world.get_revision()}
