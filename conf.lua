function love.conf(t)
  t.identity = "opensports"
  t.version = "12.0"
  t.window.title = "Open Sports"
  t.window.width, t.window.height = 1280, 720
  t.window.resizable = true
  t.window.highdpi = true
  t.window.minwidth, t.window.minheight = 640, 360
  t.modules.physics = false
end
