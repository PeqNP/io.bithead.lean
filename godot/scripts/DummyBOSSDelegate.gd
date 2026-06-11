## Copyright © 2026 Bithead LLC. All rights reserved.

## DummyBOSSDelegate — local/editor testing without a browser or BOSS instance.
##
## ready() immediately fires the "configure" command with hardcoded values so
## BOSSBridge starts polling a local server.
##
## receive() prints the event to the console and does nothing else.

class_name DummyBOSSDelegate extends BOSSDelegate

const DUMMY_FACTORY_ID := 1
const DUMMY_BASE_URL   := "http://127.0.0.1:8081"


func ready(on_command: Callable) -> void:
	print("DummyBOSSDelegate: simulating BOSS configure command")
	on_command.call("configure", {
		"factoryId": DUMMY_FACTORY_ID,
		"baseUrl":   DUMMY_BASE_URL,
	})


func receive(event_name: String, data: Dictionary) -> void:
	print("DummyBOSSDelegate.receive: %s %s" % [event_name, str(data)])
