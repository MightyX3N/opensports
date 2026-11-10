## "Upscale textures" (Settings): the disc's own textures are enlarged once, on the GPU, with
## xBRZ, the edge-aware scaler emulators use (core/xbrz.gdshader). It makes edges and
## lettering cleaner; it can't add detail the way a texture pack can.
class_name Upscale

const MAX := 2048 # largest side we make

static var _done := {} # texture dictionary -> Image

static func factor() -> int:
	return {"2x": 2, "4x": 4}.get(Settings.get_value("upscale"), 1)

static func clear() -> void:
	_done.clear()

## the upscaled image made by prepare(), or null
static func image(img: Image, _f: int, _ws: int, _wt: int, tex = null) -> Image:
	return _done.get(tex) if tex != null else null

## upscale every texture of an archive on the GPU (needs a scene tree: a few frames)
static func prepare(tree: SceneTree, textures: Array) -> void:
	var f := factor()
	if f <= 1:
		return
	var shader: Shader = load("res://core/xbrz.gdshader")
	for t in textures:
		if _done.has(t) or t.w * t.h < 64:
			continue
		var k := f
		while k > 1 and maxi(t.w, t.h) * k > MAX:
			k /= 2
		if k <= 1:
			continue
		var src := Image.create_from_data(t.w, t.h, false, Image.FORMAT_RGBA8, Brres.decode_texture(t))
		var vp := SubViewport.new()
		vp.size = Vector2i(t.w * k, t.h * k)
		vp.transparent_bg = true
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var rect := TextureRect.new()
		rect.texture = ImageTexture.create_from_image(src)
		rect.size = Vector2(vp.size)
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("Source", rect.texture)
		m.set_shader_parameter("SourceSize", Vector2(t.w, t.h))
		m.set_shader_parameter("OutputSize", Vector2(vp.size))
		rect.material = m
		vp.add_child(rect)
		tree.root.add_child.call_deferred(vp)
		await tree.process_frame
		await RenderingServer.frame_post_draw
		var out := vp.get_texture().get_image()
		vp.queue_free()
		if out != null and not out.is_empty():
			out.convert(Image.FORMAT_RGBA8)
			_done[t] = out
