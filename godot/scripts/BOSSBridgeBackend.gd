## Copyright © 2026 Bithead LLC. All rights reserved.

## BOSSBridgeBackend — protocol (base class) for Godot ↔ server communication.
##
## Two implementations exist:
##   WebBOSSBridgeBackend  — production; makes real HTTP calls.
##   LocalBOSSBridgeBackend — offline testing; applies mutations in-memory.
##
## BOSSBridge holds a `_backend: BOSSBridgeBackend` and routes all HTTP through
## it. Neither BOSSBridge nor any entity script needs to know which backend is
## active.

class_name BOSSBridgeBackend extends Node


## Execute a request and return the parsed response Dictionary.
## Returns an empty Dictionary on error or when there is no response body.
## Must be awaitable — implementations that make HTTP calls will be async.
func request(method: String, path: String, body: Dictionary) -> Dictionary:
	return {}
