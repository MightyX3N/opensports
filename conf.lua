function love.conf(t)
  t.identity = "opensports"
  -- LÖVE 12 is the target (gyro sensors); 11.5 also runs the game, just without gyro, so
  -- tell each version what it expects instead of showing a "made for another version" box
  t.version = (love._version_major or 0) >= 12 and "12.0" or "11.5"
  t.window.title = "Open Sports"
  t.window.width, t.window.height = 1280, 720
  t.window.resizable = true
  t.window.highdpi = true
  t.window.minwidth, t.window.minheight = 640, 360
  t.modules.physics = false
end
