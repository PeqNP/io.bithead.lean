## Copyright © 2026 Bithead LLC. All rights reserved.

## LocalBOSSBridgeBackend — offline backend for editor / no-server testing.
##
## Loads res://fixtures/factory-floor.json on _ready() and holds it as an
## in-memory Dictionary. All BOSSBridge.post() / .patch() calls are handled
## here and applied to that snapshot immediately, simulating successful server
## responses. poll_snapshot() re-emits the updated snapshot so FactoryFloor
## re-renders exactly as it would with a real server.

class_name LocalBOSSBridgeBackend extends BOSSBridgeBackend

const FIXTURE_PATH := "res://fixtures/factory-floor.json"

var _snapshot: Dictionary = {}


func _ready() -> void:
	_load_fixture()


func request(method: String, path: String, body: Dictionary) -> Dictionary:
	# GET /lean/factory-floor/{id} — used by BOSSBridge.poll_snapshot()
	if method == "GET" and path.begins_with("/lean/factory-floor/"):
		return _snapshot

	if method == "PATCH":
		return _handle_patch(path, body)

	if method == "POST":
		return _handle_post(path, body)
	if method == "DELETE":
		return _handle_delete(path)

	print("LocalBOSSBridgeBackend: unhandled %s %s" % [method, path])
	return {}


# ---------------------------------------------------------------------------
# Fixture loading
# ---------------------------------------------------------------------------

func _load_fixture() -> void:
	if not FileAccess.file_exists(FIXTURE_PATH):
		push_error("LocalBOSSBridgeBackend: fixture not found at %s" % FIXTURE_PATH)
		return
	var text: String = FileAccess.get_file_as_string(FIXTURE_PATH)
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("LocalBOSSBridgeBackend: failed to parse fixture: %s" % json.get_error_message())
		return
	var parsed = json.get_data()
	if parsed is Dictionary:
		_snapshot = parsed
		print("LocalBOSSBridgeBackend: loaded fixture (%d lines, %d inventories)" % [
			(_snapshot.get("lines", []) as Array).size(),
			(_snapshot.get("inventories", []) as Array).size(),
		])
	else:
		push_error("LocalBOSSBridgeBackend: fixture root must be a Dictionary")


# ---------------------------------------------------------------------------
# Route handlers
# ---------------------------------------------------------------------------

func _handle_patch(path: String, body: Dictionary) -> Dictionary:
	var re := RegEx.new()

	# PATCH /lean/station/{id}/position  {posX, posY}
	re.compile("^/lean/station/(\\d+)/position$")
	var m := re.search(path)
	if m:
		_update_station(int(m.get_string(1)), {"posX": body.get("posX", 0), "posY": body.get("posY", 0)})
		return {}

	# PATCH /lean/station/view-state/{id}  {overlay}
	re.compile("^/lean/station/view-state/(\\d+)$")
	m = re.search(path)
	if m:
		_update_station(int(m.get_string(1)), {"overlay": body.get("overlay", "none")})
		return {}

	# PATCH /lean/line/{id}/position  {x, y}
	re.compile("^/lean/line/(\\d+)/position$")
	m = re.search(path)
	if m:
		_update_entity("lines", int(m.get_string(1)), {"gridX": body.get("x", 0), "gridY": body.get("y", 0)})
		return {}

	# PATCH /lean/inventory/{id}/position  {x, y}
	re.compile("^/lean/inventory/(\\d+)/position$")
	m = re.search(path)
	if m:
		_update_entity("inventories", int(m.get_string(1)), {"gridX": body.get("x", 0), "gridY": body.get("y", 0)})
		return {}

	# PATCH /lean/line/{id}/focused  {focused}
	re.compile("^/lean/line/(\\d+)/focused$")
	m = re.search(path)
	if m:
		_update_entity("lines", int(m.get_string(1)), {"focused": body.get("focused", false)})
		return {}

	# PATCH /lean/inventory/{id}/focused  {focused}
	re.compile("^/lean/inventory/(\\d+)/focused$")
	m = re.search(path)
	if m:
		_update_entity("inventories", int(m.get_string(1)), {"focused": body.get("focused", false)})
		return {}

	# PATCH /lean/line/{id}/locked  {locked}
	re.compile("^/lean/line/(\\d+)/locked$")
	m = re.search(path)
	if m:
		_update_entity("lines", int(m.get_string(1)), {"locked": body.get("locked", false)})
		return {}

	# PATCH /lean/inventory/{id}/locked  {locked}
	re.compile("^/lean/inventory/(\\d+)/locked$")
	m = re.search(path)
	if m:
		_update_entity("inventories", int(m.get_string(1)), {"locked": body.get("locked", false)})
		return {}

	print("LocalBOSSBridgeBackend: unhandled PATCH %s" % path)
	return {}


func _handle_post(path: String, body: Dictionary) -> Dictionary:
	var re := RegEx.new()

	# POST /lean/line/{id}/station  body: {index: int (1-based) | absent for append}
	re.compile("^/lean/line/(\\d+)/station$")
	var m := re.search(path)
	if m:
		_insert_station(int(m.get_string(1)), body)
		return {}

	# POST /lean/line/{id}/intake-queue  body: {index: int (0-based) | absent for append}
	re.compile("^/lean/line/(\\d+)/intake-queue$")
	m = re.search(path)
	if m:
		_insert_intake_queue(int(m.get_string(1)), body)
		return {}

	print("LocalBOSSBridgeBackend: stub POST %s %s" % [path, str(body)])
	return {}


func _handle_delete(path: String) -> Dictionary:
	var re := RegEx.new()

	# DELETE /lean/line/{line_id}/station/{station_id}
	re.compile("^/lean/line/(\\d+)/station/(\\d+)$")
	var m := re.search(path)
	if m:
		_delete_station(int(m.get_string(1)), int(m.get_string(2)))
		return {}

	# DELETE /lean/line/{line_id}/intake-queue/{queue_id}
	re.compile("^/lean/line/(\\d+)/intake-queue/(\\d+)$")
	m = re.search(path)
	if m:
		_delete_intake_queue(int(m.get_string(1)), int(m.get_string(2)))
		return {}

	print("LocalBOSSBridgeBackend: unhandled DELETE %s" % path)
	return {}


## Insert a new station into a line.
## body["index"] (1-based) shifts existing stations from that index onward;
## absent or null means append after the last station.
##
## Cascade rules (mirrors FactoryFloor._is_station_insert_blocked):
##   Exit direction: right (posX+1) unless prev.posX > last.posX → left (posX-1).
##   For null/append: new station placed at last station's exit position; last stays.
##   For index k: new station takes station[k-1]'s position; each station from
##   k-1 onward inherits the next station's position; last station moves in exit dir.
##   If exit direction would go negative (posX < 0): try posY+1 (down), then posY-1 (up).
func _insert_station(line_id: int, body: Dictionary) -> void:
	var lines: Array = (_snapshot.get("lines", []) as Array)
	var line_dict: Dictionary = {}
	for l: Dictionary in lines:
		if l.get("id", -1) == line_id:
			line_dict = l
			break
	if line_dict.is_empty():
		push_warning("LocalBOSSBridgeBackend: line %d not found" % line_id)
		return

	var stations: Array = (line_dict.get("stations", []) as Array)

	# Compute exit direction from last two stations.
	var exit_dx: int = 1
	if stations.size() >= 2:
		var last_s := stations.back() as Dictionary
		var prev_s := stations[stations.size() - 2] as Dictionary
		if int(prev_s.get("posX", 0)) > int(last_s.get("posX", 0)):
			exit_dx = -1

	# Generate a new station id (max existing + 1, minimum 1).
	var new_id: int = 1
	for s: Dictionary in stations:
		var sid: int = int(s.get("id", 0))
		if sid >= new_id:
			new_id = sid + 1

	# Compute where the last station will move to (needed for both paths).
	var last_dict: Dictionary = stations.back() as Dictionary if not stations.is_empty() else {}
	var lpx: int = int(last_dict.get("posX", 0))
	var lpy: int = int(last_dict.get("posY", 0))
	var new_last_x: int = lpx + exit_dx
	var new_last_y: int = lpy
	if new_last_x < 0:
		var moved := false
		for try_y in [lpy + 1, lpy - 1]:
			if try_y < 0:
				continue
			var taken := false
			for s: Dictionary in stations:
				if int(s.get("posX", 0)) == lpx and int(s.get("posY", 0)) == try_y:
					taken = true
					break
			if not taken:
				new_last_x = lpx
				new_last_y = try_y
				moved = true
				break
		if not moved:
			push_warning("LocalBOSSBridgeBackend: no space on line %d for new station" % line_id)
			return

	var raw_index = body.get("index", null)

	if raw_index == null:
		# Append: new station placed at exit position; no cascading.
		var new_station := {
			"id": new_id, "posX": new_last_x, "posY": new_last_y,
			"name": "New Station", "overlay": "none"
		}
		stations.append(new_station)
	else:
		# Indexed insert (1-based → 0-based).
		var insert_idx: int = int(raw_index) - 1
		insert_idx = clamp(insert_idx, 0, stations.size())

		# If inserting between two existing stations, check whether the cell
		# one step in the first-leg direction from the preceding station is
		# free. If so, place the new station there without cascading.
		# First-leg direction: y-axis first when there is a y-delta (belt exits
		# downward/upward before turning), otherwise x-axis.
		var placed_without_cascade := false
		if insert_idx > 0 and insert_idx < stations.size():
			var prev_s := stations[insert_idx - 1] as Dictionary
			var next_s := stations[insert_idx]     as Dictionary
			var ppx: int = int(prev_s.get("posX", 0))
			var ppy: int = int(prev_s.get("posY", 0))
			var nnx: int = int(next_s.get("posX", 0))
			var nny: int = int(next_s.get("posY", 0))
			var step_x: int
			var step_y: int
			if nny != ppy:
				step_x = 0
				step_y = sign(nny - ppy)
			else:
				step_x = sign(nnx - ppx)
				step_y = 0
			var cx: int = ppx + step_x
			var cy: int = ppy + step_y
			if cx >= 0 and cy >= 0:
				var occupied := false
				for s: Dictionary in stations:
					if int(s.get("posX", 0)) == cx and int(s.get("posY", 0)) == cy:
						occupied = true
						break
				if not occupied:
					stations.insert(insert_idx, {
						"id": new_id, "posX": cx, "posY": cy,
						"name": "New Station", "overlay": "none"
					})
					placed_without_cascade = true

		if not placed_without_cascade:
			# Save positions from insert_idx to end before any mutation.
			var saved: Array = []
			for k in range(insert_idx, stations.size()):
				var s := stations[k] as Dictionary
				saved.append({"posX": int(s.get("posX", k)), "posY": int(s.get("posY", 0))})

			# Cascade: each station[insert_idx..last] inherits successor's saved pos; last gets exit pos.
			for k in range(insert_idx, stations.size()):
				var s := stations[k] as Dictionary
				var offset: int = k - insert_idx
				if k == stations.size() - 1:
					s["posX"] = new_last_x
					s["posY"] = new_last_y
				else:
					s["posX"] = saved[offset + 1]["posX"]
					s["posY"] = saved[offset + 1]["posY"]

			# Insert new station with the first saved position.
			stations.insert(insert_idx, {
				"id": new_id, "posX": saved[0]["posX"], "posY": saved[0]["posY"],
				"name": "New Station", "overlay": "none"
			})

	line_dict["stations"] = stations


## Remove a station by id from its line.
func _delete_station(line_id: int, station_id: int) -> void:
	var lines: Array = (_snapshot.get("lines", []) as Array)
	for l: Dictionary in lines:
		if l.get("id", -1) == line_id:
			var stations: Array = (l.get("stations", []) as Array)
			for i in range(stations.size()):
				if int((stations[i] as Dictionary).get("id", -1)) == station_id:
					stations.remove_at(i)
					l["stations"] = stations
					return
			push_warning("LocalBOSSBridgeBackend: station %d not found in line %d" % [station_id, line_id])
			return
	push_warning("LocalBOSSBridgeBackend: line %d not found" % line_id)


## Insert a new intake queue into a line.
## body["index"] (0-based) inserts at that position; absent or null means append.
func _insert_intake_queue(line_id: int, body: Dictionary) -> void:
	var lines: Array = (_snapshot.get("lines", []) as Array)
	var line_dict: Dictionary = {}
	for l: Dictionary in lines:
		if l.get("id", -1) == line_id:
			line_dict = l
			break
	if line_dict.is_empty():
		push_warning("LocalBOSSBridgeBackend: line %d not found" % line_id)
		return
	var queues: Array = (line_dict.get("intakeQueues", []) as Array)
	# Generate new id (max existing + 1, minimum 1).
	var new_id: int = 1
	for q: Dictionary in queues:
		var qid: int = int(q.get("id", 0))
		if qid >= new_id:
			new_id = qid + 1
	var new_queue := {
		"id": new_id,
		"name": "New Intake Queue",
		"mixRatio": null,
		"cycleTime": 3600,
		"numWorkUnits": 0,
		"color": null,
	}
	var raw_index = body.get("index", null)
	if raw_index == null:
		queues.append(new_queue)
	else:
		var idx: int = clamp(int(raw_index), 0, queues.size())
		queues.insert(idx, new_queue)
	line_dict["intakeQueues"] = queues


## Remove an intake queue by id from its line.
func _delete_intake_queue(line_id: int, queue_id: int) -> void:
	var lines: Array = (_snapshot.get("lines", []) as Array)
	for l: Dictionary in lines:
		if l.get("id", -1) == line_id:
			var queues: Array = (l.get("intakeQueues", []) as Array)
			for i in range(queues.size()):
				if int((queues[i] as Dictionary).get("id", -1)) == queue_id:
					queues.remove_at(i)
					l["intakeQueues"] = queues
					return
			push_warning("LocalBOSSBridgeBackend: intake queue %d not found in line %d" % [queue_id, line_id])
			return
	push_warning("LocalBOSSBridgeBackend: line %d not found" % line_id)


# ---------------------------------------------------------------------------
# In-memory mutation helpers
# ---------------------------------------------------------------------------

func _update_station(station_id: int, fields: Dictionary) -> void:
	for line: Dictionary in (_snapshot.get("lines", []) as Array):
		for station: Dictionary in (line.get("stations", []) as Array):
			if station.get("id", -1) == station_id:
				for key in fields:
					station[key] = fields[key]
				return
	push_warning("LocalBOSSBridgeBackend: station %d not found" % station_id)


func _update_entity(collection: String, entity_id: int, fields: Dictionary) -> void:
	for entity: Dictionary in (_snapshot.get(collection, []) as Array):
		if entity.get("id", -1) == entity_id:
			for key in fields:
				entity[key] = fields[key]
			return
	push_warning("LocalBOSSBridgeBackend: %s id=%d not found" % [collection, entity_id])
