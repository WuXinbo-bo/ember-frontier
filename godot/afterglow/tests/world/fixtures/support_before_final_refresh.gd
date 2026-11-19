extends RefCounted
## Disposable synchronous projection sampler. The public chunk API returns
## detached values; never store authority or retain this across notifications.
## Cold pages stay cold. Every exact footprint/material/air check is retained.
const Data=preload("res://scripts/world/world_data.gd")
var world:RefCounted
var config:Dictionary
var chunks:Dictionary={}
var n:int
var s:float
var min_y:int
var max_y:int
func _init(source:RefCounted)->void:
	world=source;config=source.config()
	n=int(config.chunkCells);s=float(config.cellSize)
	min_y=int(config.minCellY);max_y=int(config.maxCellY)
func _chunk(coord:Vector3i)->Dictionary:
	if not chunks.has(coord):chunks[coord]=world.chunk(Data.key(coord))
	return chunks[coord]
func _known(c:Dictionary)->bool:
	return c.get("generated",false) and not c.has("cell_page")
func resident_cell(cell:Vector3i)->bool:
	if cell.y<min_y or cell.y>=max_y:return false
	var c:Dictionary=_chunk(Data.cell_chunk(cell,n))
	return c.get("generated",false) and c.get("resident",false)
func grounded(p:Vector3,size:Vector2,required_material:int=-1)->bool:
	var y:int=floori((p.y-0.001)/s)
	if y<min_y or y+1>=max_y or absf((y+1)*s-p.y)>0.001:return false
	for z:int in range(floori((p.z-size.y/2+0.00001)/s),floori((p.z+size.y/2-0.00001)/s)+1):
		for x:int in range(floori((p.x-size.x/2+0.00001)/s),floori((p.x+size.x/2-0.00001)/s)+1):
			var cell:=Vector3i(x,y,z);var above:=Vector3i(x,y+1,z)
			var below_coord:Vector3i=Data.cell_chunk(cell,n);var above_coord:Vector3i=Data.cell_chunk(above,n)
			var below:Dictionary=_chunk(below_coord)
			var top:Dictionary=below if below_coord==above_coord else _chunk(above_coord)
			if not _known(below) or not _known(top) or not below.get("resident",false):return false
			var material:int=int(below.cells[Data.local_index(cell,n)])
			if material==0 or (required_material>=0 and material!=required_material) or int(top.cells[Data.local_index(above,n)])!=0:return false
	return true
func surface_height(x:float,z:float)->Variant:
	if not is_finite(x) or not is_finite(z):return null
	var i:int=floori(x/s);var k:int=floori(z/s)
	var cx:int=floori(float(i)/n);var cz:int=floori(float(k)/n)
	var column:int=posmod(i,n)+n*posmod(k,n);var j:int=max_y-1
	while j>=min_y:
		var cy:int=floori(float(j)/n);var c:Dictionary=_chunk(Vector3i(cx,cy,cz))
		if not _known(c):return null
		var bottom:int=maxi(min_y,cy*n);var cells:PackedInt32Array=c.cells
		while j>=bottom:
			if cells[column+n*n*posmod(j,n)]!=0:return (j+1)*s
			j-=1
	return null
