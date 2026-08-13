extends SceneTree
## Rasterizes assets/art/icon.svg into the PNG sizes Godot's Web PWA export wants
## (144x144, 180x180, 512x512). Re-run this after editing icon.svg, then re-export
## the Web build so the new icons get bundled into builds/web/.
## Usage: godot --headless --script res://tools/gen_pwa_icons.gd

const SVG_PATH := "res://assets/art/icon.svg"
const OUT_DIR := "res://assets/art/pwa/"
const SIZES: Array[int] = [144, 180, 512]
const NATIVE_SIZE := 128.0

func _init() -> void:
	var svg_text := FileAccess.get_file_as_string(SVG_PATH)
	if svg_text.is_empty():
		printerr("Could not read ", SVG_PATH)
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	for size in SIZES:
		var scale: float = size / NATIVE_SIZE
		var img := Image.new()
		var err := img.load_svg_from_string(svg_text, scale)
		if err != OK:
			printerr("Failed to rasterize at ", size, "x", size, " (error ", err, ")")
			quit(1)
			return
		var out_path := OUT_DIR + "icon_%d.png" % size
		img.save_png(out_path)
		print("Wrote ", out_path, " (", img.get_width(), "x", img.get_height(), ")")

	quit(0)
