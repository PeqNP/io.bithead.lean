## Copyright © 2026 Bithead LLC. All rights reserved.

## Shared formatting helpers used across all FactoryFloor scenes.
##
## All functions are static — call without instantiation:
##   Helpers.format_cycle_time(3600)  # → "1h"
##   Helpers.format_eta("2026-06-10T17:00:00Z")  # → "Wed, Jun 10 @ 05:00p"

class_name Helpers


## Format a cycle time given in seconds into a human-readable string.
## Returns empty string for null/zero input.
## Examples: 90 → "1m 30s", 3661 → "1h 1m", 172800 → "2d"
static func format_cycle_time(seconds) -> String:
	if seconds == null or seconds == 0:
		return ""
	var s: int = int(seconds)
	var days    := s / 86400
	var hours   := (s % 86400) / 3600
	var minutes := (s % 3600) / 60
	var secs    := s % 60

	var parts: Array[String] = []
	if days    > 0: parts.append("%dd" % days)
	if hours   > 0: parts.append("%dh" % hours)
	if minutes > 0: parts.append("%dm" % minutes)
	if secs    > 0 and days == 0: parts.append("%ds" % secs)

	if parts.is_empty():
		return ""
	return "Cycle: " + " ".join(parts)


## Format an ISO-8601 date string into a short display string.
## Returns empty string on parse failure.
## Example: "2026-05-01T17:00:00Z" → "Thu, May 1 @ 05:00p"
static func format_eta(iso_string) -> String:
	if iso_string == null or iso_string == "":
		return ""
	# Parse using Godot's Time singleton.
	var dict: Dictionary = Time.get_datetime_dict_from_datetime_string(str(iso_string), true)
	if dict.is_empty():
		return ""

	var month_names := ["Jan","Feb","Mar","Apr","May","Jun",
						"Jul","Aug","Sep","Oct","Nov","Dec"]
	var day_names   := ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]

	var month: int = dict.get("month", 1)
	var day: int = dict.get("day", 1)
	var hour: int = dict.get("hour", 0)
	var minute: int = dict.get("minute", 0)
	var weekday: int = dict.get("weekday", 0)

	var month_str: String = month_names[clamp(month - 1, 0, 11)]
	var weekday_str: String = day_names[clamp(weekday, 0, 6)]
	var ampm        := "a" if hour < 12 else "p"
	var display_hour := hour % 12
	if display_hour == 0:
		display_hour = 12

	return "%s, %s %d @ %02d:%02d%s" % [weekday_str, month_str, day, display_hour, minute, ampm]
