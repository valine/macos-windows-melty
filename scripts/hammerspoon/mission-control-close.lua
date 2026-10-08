-- Close only the actual Mission Control thumbnail under the pointer.
-- macOS 27 hosts the overview in WindowManager; older releases use Dock.
local M = {}
local types = hs.eventtap.event.types
local properties = hs.eventtap.event.properties

local function contains(frame, point)
  return frame and frame.w > 0 and frame.h > 0
    and point.x >= frame.x and point.x < frame.x + frame.w
    and point.y >= frame.y and point.y < frame.y + frame.h
end

function M.targetAt(point)
  local matches, active = {}, false
  for _, bundle in ipairs({ "com.apple.WindowManager", "com.apple.dock" }) do
    local app = hs.application.get(bundle)
    if app then
      local root = hs.axuielement.applicationElement(app)
      local function visit(element, inOverview, depth)
        if depth > 8 then return end
        local identifier = element:attributeValue("AXIdentifier")
        inOverview = inOverview or identifier == "mc" or identifier == "mc.display"
        if inOverview then active = true end
        -- Spaces and their close buttons are not application windows.
        if identifier and identifier:match("^mc%.spaces") then return end
        if inOverview and element:attributeValue("AXRole") == "AXButton"
            and contains(element:attributeValue("AXFrame"), point) then
          local id = tonumber(element:attributeValue("wid"))
          if id and id > 0 then matches[id] = true end
        end
        for _, child in ipairs(element:attributeValue("AXChildren") or {}) do
          visit(child, inOverview, depth + 1)
        end
      end
      visit(root, false, 0)
    end
  end
  -- Ambiguous or missing identity must never become a focused-window close.
  local id
  for candidate in pairs(matches) do
    if id then return nil, active end
    id = candidate
  end
  if not id then return nil, active end
  local window = hs.window.get(id)
  if window and window:id() == id then return window, active end
  return nil, active
end

function M.start()
  if M.tap then M.tap:stop() end
  local swallowedKeys, swallowedMiddle = {}, false
  M.handle = function(event)
    local kind = event:getType()
    local key = event:getKeyCode()
    if kind == types.keyUp then
      local swallowed = swallowedKeys[key]
      swallowedKeys[key] = nil
      return swallowed == true
    end
    if kind == types.otherMouseUp or kind == types.otherMouseDragged then
      if event:getProperty(properties.mouseEventButtonNumber) ~= 2 then return false end
      local swallowed = swallowedMiddle
      if kind == types.otherMouseUp then swallowedMiddle = false end
      return swallowed
    end
    local keyboard = kind == types.keyDown
    if keyboard then
      if key ~= hs.keycodes.map.forwarddelete and key ~= hs.keycodes.map.delete then return false end
      if swallowedKeys[key] then return true end
    elseif kind ~= types.otherMouseDown
        or event:getProperty(properties.mouseEventButtonNumber) ~= 2 then
      return false
    end
    local flags = event:getFlags()
    if flags.cmd or flags.alt or flags.ctrl or flags.shift then return false end
    local point = keyboard and hs.mouse.absolutePosition() or event:location()
    local window, active = M.targetAt(point)
    if not active then return false end
    if keyboard then swallowedKeys[key] = true else swallowedMiddle = true end
    -- One physical press closes at most one window, even as the layout changes.
    if window and (not keyboard or event:getProperty(properties.keyboardEventAutorepeat) == 0) then
      window:close()
    end
    return true
  end
  M.tap = hs.eventtap.new({ types.keyDown, types.keyUp, types.otherMouseDown,
                           types.otherMouseUp, types.otherMouseDragged }, M.handle):start()
  return M
end

return M
