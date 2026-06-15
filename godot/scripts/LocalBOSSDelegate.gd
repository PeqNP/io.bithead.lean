## Copyright © 2026 Bithead LLC. All rights reserved.

## LocalBOSSDelegate — BOSS client-side delegate for offline / no-browser testing.
##
## Fires the "configure" command immediately without requiring a browser or a
## running BOSS server. Backend HTTP is handled separately by LocalBOSSBridgeBackend,
## which must be assigned to BOSSBridge before this delegate's ready() is called.
##
## Pair with LocalBOSSBridgeBackend in FactoryFloor._ready():
##   _boss = LocalBOSSDelegate.new()
##   BOSSBridge.set_backend(LocalBOSSBridgeBackend.new())

class_name LocalBOSSDelegate extends BOSSDelegate

const DUMMY_FACTORY_ID := 1


func ready(on_command: Callable) -> void:
	print("LocalBOSSDelegate: firing configure")
	on_command.call("configure", {
		"factoryId": DUMMY_FACTORY_ID,
		"baseUrl":   "",
	})


func receive(event_name: String, data: Dictionary) -> void:
	print("LocalBOSSDelegate.receive: %s %s" % [event_name, str(data)])
