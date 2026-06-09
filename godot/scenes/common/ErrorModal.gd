## Copyright © 2026 Bithead LLC. All rights reserved.

## Error modal dialog. Shown by FactoryFloor when BOSSBridge emits error().
##
## Usage:
##   $ErrorModal.show_error("Request Failed", "Server returned 500.")

extends CanvasLayer

@onready var _title_label: Label       = $Panel/VBox/TitleLabel
@onready var _desc_label: Label        = $Panel/VBox/DescLabel
@onready var _ok_button: Button        = $Panel/VBox/OKButton
@onready var _panel: Panel             = $Panel


func _ready() -> void:
	_ok_button.pressed.connect(_on_ok_pressed)
	_panel.hide()


## Display the modal with a title and description.
func show_error(title: String, description: String) -> void:
	_title_label.text = title
	_desc_label.text  = description
	_panel.show()


func _on_ok_pressed() -> void:
	_panel.hide()
