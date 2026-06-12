## Copyright © 2026 Bithead LLC. All rights reserved.

## Solarized Light color palette for the FactoryFloor.
##
## Usage: Palette.BG_0, Palette.FG_1, Palette.BLUE, Palette.GREEN_FILL, etc.
## All constants are accessible without instantiation via the class name.

class_name Palette
extends RefCounted

# ---------------------------------------------------------------------------
# Background tones
# ---------------------------------------------------------------------------

## Lightest background — primary floor / card hover fill.
const BG_0 := Color(0.992, 0.965, 0.890)   # Base3  #fdf6e3
## Secondary background — default card fill / panel background.
const BG_1 := Color(0.933, 0.910, 0.835)   # Base2  #eee8d5

# ---------------------------------------------------------------------------
# Foreground tones (light → dark)
# ---------------------------------------------------------------------------

## Muted / secondary text.
const FG_0 := Color(0.576, 0.631, 0.631)   # Base1  #93a1a1
## Primary text, borders.
const FG_1 := Color(0.345, 0.431, 0.459)   # Base01 #586e75

# ---------------------------------------------------------------------------
# Accent colors
# ---------------------------------------------------------------------------

const YELLOW  := Color(0.710, 0.537, 0.000)   # #b58900
const ORANGE  := Color(0.796, 0.294, 0.086)   # #cb4b16
const RED     := Color(0.863, 0.196, 0.184)   # #dc322f
const MAGENTA := Color(0.827, 0.212, 0.510)   # #d33682
const VIOLET  := Color(0.424, 0.443, 0.769)   # #6c71c4
const BLUE    := Color(0.149, 0.545, 0.824)   # #268bd2
const CYAN    := Color(0.165, 0.631, 0.596)   # #2aa198
const GREEN   := Color(0.522, 0.600, 0.000)   # #859900

# ---------------------------------------------------------------------------
# Light fill tones (very pale tint matching each accent)
# ---------------------------------------------------------------------------

## Very pale warm cream.
const YELLOW_FILL  := Color(0.969, 0.949, 0.890)   # #f7f2e3
## Soft peach.
const ORANGE_FILL  := Color(0.961, 0.918, 0.898)   # #f5eae5
## Pale rose-pink.
const RED_FILL     := Color(0.957, 0.902, 0.902)   # #f4e6e6
## Light dusty rose.
const MAGENTA_FILL := Color(0.953, 0.906, 0.929)   # #f3e7ed
## Pale periwinkle.
const VIOLET_FILL  := Color(0.914, 0.914, 0.945)   # #e9e9f1
## Soft sky blue.
const BLUE_FILL    := Color(0.902, 0.933, 0.957)   # #e6eef4
## Pale mint.
const CYAN_FILL    := Color(0.906, 0.953, 0.949)   # #e7f3f2
## Light sage/lime.
const GREEN_FILL   := Color(0.957, 0.969, 0.890)   # #f4f7e3

# ---------------------------------------------------------------------------
# Alpha variants used by specific UI elements
# ---------------------------------------------------------------------------

## Semi-opaque BG_1 — used for overlay panel backgrounds.
const BG_1_PANEL   := Color(0.933, 0.910, 0.835, 0.97)
## Ghost outline for drag overlay.
const FG_1_GHOST   := Color(0.345, 0.431, 0.459, 0.15)
## Drag placement available highlight.
const GREEN_AVAIL  := Color(0.522, 0.600, 0.000, 0.35)
## Drag placement occupied highlight.
const RED_OCCUPIED := Color(0.863, 0.196, 0.184, 0.35)

## Belt colors (slightly transparent for visual layering).
const YELLOW_BELT  := Color(0.710, 0.537, 0.000, 0.90)   # Inventory → Station
const VIOLET_BELT  := Color(0.424, 0.443, 0.769, 0.90)   # Station ↔ Line
const CYAN_BELT    := Color(0.165, 0.631, 0.596, 0.90)   # Station → IntakeQueue
const BLUE_BELT    := Color(0.149, 0.545, 0.824, 0.80)   # Chevron belt default
