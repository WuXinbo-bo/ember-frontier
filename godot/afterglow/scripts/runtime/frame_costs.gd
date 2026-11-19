extends RefCounted
## Opt-in process cost counters. Derived diagnostics, never simulation state.
static var enabled:=false
static var phases:Dictionary={}
static var trace_enabled:=false
static var trace:Dictionary={}
static func begin()->int:return Time.get_ticks_usec() if enabled else 0
static func end(name:String,started:int)->void:
 if started==0:return
 var elapsed:int=Time.get_ticks_usec()-started
 var row:Dictionary=phases.get(name,{"count":0,"total_usec":0,"max_usec":0,"over16ms":0})
 row.count+=1;row.total_usec+=elapsed;row.max_usec=maxi(row.max_usec,elapsed);row.over16ms+=int(elapsed>16000);phases[name]=row
 if trace_enabled:trace[name]=int(trace.get(name,0))+elapsed
static func snapshot()->Dictionary:return phases.duplicate(true)
