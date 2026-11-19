extends RefCounted
## Read-only movement evidence. Never drives input, interpolation or simulation.
var frames:Array[float]=[]
var distance_m:=0.0
var discontinuities:=0
var _previous:Variant=null
var _moved_at:int=-1000000

func break_continuity()->void:
	_previous=null;_moved_at=-1000000

func observe(actor:Dictionary,now_usec:int,interval_ms:float,collect:bool)->void:
	if not actor.has_all(["x","y","z"]):break_continuity();return
	var at:=Vector3(float(actor.x),float(actor.y),float(actor.z))
	if not at.is_finite():break_continuity();return
	var distance:float=at.distance_to(_previous) if _previous is Vector3 else 0.0
	_previous=at
	if distance>3.0:
		# A load/teleport is not walking. Keep it visible, outside this subset;
		# the unfiltered whole-frame sample still contains the full interval.
		if collect:discontinuities+=1
		_moved_at=-1000000;return
	if distance>0.000001:
		_moved_at=now_usec
		if collect:distance_m+=distance
	# Render and physics frequencies differ. Include the 120ms after an
	# actual displacement, without inferring movement merely from held keys.
	if collect and now_usec-_moved_at<=120000:frames.append(interval_ms)
