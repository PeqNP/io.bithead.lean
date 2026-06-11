## DummyBOSSDelegate — local/editor testing without a browser or BOSS instance.
##
## ready() sets the base_url on BOSSBridge, signs in via the debug route to
## acquire a session token, then fires the "configure" command with hardcoded
## values so BOSSBridge starts polling a local server.
##
## receive() prints the event to the console and does nothing else.

class_name DummyBOSSDelegate extends BOSSDelegate

const DUMMY_FACTORY_ID := 1
const DUMMY_BASE_URL   := "http://127.0.0.1:8081"


func ready(on_command: Callable) -> void:
	print("DummyBOSSDelegate: signing in via debug route")
	# Set base_url so BOSSBridge.sign_in() knows where to connect.
	BOSSBridge._base_url = DUMMY_BASE_URL
	await BOSSBridge.sign_in()
	print("DummyBOSSDelegate: simulating BOSS configure command")
	on_command.call("configure", {
		"factoryId": DUMMY_FACTORY_ID,
		"baseUrl":   DUMMY_BASE_URL,
	})


func receive(event_name: String, data: Dictionary) -> void:
	print("DummyBOSSDelegate.receive: %s %s" % [event_name, str(data)])
