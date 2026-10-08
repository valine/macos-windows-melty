-- Run with: hs -c 'dofile("/absolute/path/Diagnostics/mission-control-close-tests.lua")'
local source = debug.getinfo(1, "S").source:sub(2)
local modulePath = source:match("^(.*)/Diagnostics/") .. "/scripts/hammerspoon/mission-control-close.lua"
local function element(attributes)
  return { attributeValue = function(_, name) return attributes[name] end }
end
local frame = { x = 100, y = 100, w = 200, h = 200 }
local function thumbnail(id, bounds)
  return element({ AXRole = "AXButton", AXFrame = bounds or frame, wid = id })
end
local roots, closed = {}, {}
local t = { keyDown=1, keyUp=2, otherMouseDown=3, otherMouseUp=4, otherMouseDragged=5 }
local p = { mouseEventButtonNumber=1, keyboardEventAutorepeat=2 }
local fake = {
  eventtap = { event = { types=t, properties=p }, new=function()
    return { start=function(self) return self end, stop=function() end }
  end },
  keycodes = { map = { delete=51, forwarddelete=117 } },
  mouse = { absolutePosition=function() return {x=150,y=150} end },
  application = { get=function(bundle) return roots[bundle] end },
  axuielement = { applicationElement=function(app) return app end },
  window = { get=function(id)
    if id == 999 then return nil end
    return { id=function() return id end, close=function() closed[#closed+1]=id end }
  end, focusedWindow=function() error("Must never use focused window") end },
}
local env = setmetatable({hs=fake}, {__index=_G})
local m = assert(loadfile(modulePath, "t", env))()
local function overview(children)
  roots = { ["com.apple.WindowManager"] = element({AXChildren={
    element({AXIdentifier="mc.display", AXChildren=children})
  }}) }
end
local function event(kind, key, button, repeatValue, flags)
  return { getType=function() return kind end, getKeyCode=function() return key end,
    getFlags=function() return flags or {} end,
    location=function() return {x=150,y=150} end,
    getProperty=function(_, prop) if prop==p.mouseEventButtonNumber then return button or 2 end; return repeatValue or 0 end }
end
local function target() return m.targetAt({x=150,y=150}) end
overview({thumbnail(42)})
assert(target():id()==42)
overview({thumbnail(42),thumbnail(43)})
assert(target()==nil, "Overlapping identities must not close anything")
overview({thumbnail(999)})
assert(target()==nil, "Stale IDs must not fall back")
overview({element({AXIdentifier="mc.spaces",AXChildren={thumbnail(42)}})})
assert(target()==nil, "Space thumbnails must be ignored")
overview({thumbnail(42,{x=500,y=500,w=200,h=200})})
assert(target()==nil, "Do not use unscaled desktop bounds")
overview({thumbnail(42)})
m.start()
assert(m.handle(event(t.keyDown,117)))
assert(#closed==1 and closed[1]==42)
overview({thumbnail(43)})
assert(m.handle(event(t.keyDown,117,2,1)))
assert(#closed==1, "Repeat must not close newly reflowed target")
assert(m.handle(event(t.keyUp,117)))
assert(m.handle(event(t.otherMouseDown)))
assert(#closed==2 and closed[2]==43)
roots={}
assert(m.handle(event(t.otherMouseUp)), "Swallow release even after overview disappears")
assert(not m.handle(event(t.keyDown,117)), "Delete outside overview must pass through")
assert(not m.handle(event(t.otherMouseDown)), "Middle click outside overview must pass through")
overview({thumbnail(42)})
assert(not m.handle(event(t.otherMouseDown,nil,3)), "Side buttons must pass through")
assert(not m.handle(event(t.keyDown,117,2,0,{cmd=true})))
assert(m.handle(event(t.keyDown,51)))
assert(#closed==3 and closed[3]==42)
print("Mission Control close: all regression checks passed")
