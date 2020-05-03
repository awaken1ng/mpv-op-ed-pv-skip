local ENABLED = true
local KEYBIND = "y"
local OPENING = {"op", "opening"}
local ENDING = {"ed", "ending", "preview"}

local function has_value(tab, val)
  for index, value in ipairs(tab) do
    if value == val then
      return true
    end
  end

  return false
end

mp.add_key_binding(KEYBIND, "op-ed-preview-skipper-toggle", function()
  msg = "OP/ED/Preview skipper "
  if ENABLED then
    ENABLED = false
    msg = msg .. "disabled"
  else
    ENABLED = true
    msg = msg .. "enabled"
  end
  mp.osd_message(msg)
end)

mp.observe_property("chapter", "number", function(_, chapter)
  if ENABLED == false
  or chapter == nil
  or chapter < 0
  then return end

  title = mp.get_property("chapter-list/" .. chapter .. "/title"):lower()

  if has_value(OPENING, title) then
    -- to next chapter
    mp.set_property("chapter", chapter + 1)
  elseif has_value(ENDING, title) then
    chapters = tonumber(mp.get_property("chapter-list/count") - 1)
    if chapter >= chapters then
      -- on last chapter, to next playlist item
      mp.command("playlist-next")
    else
      -- to next chapter
      mp.set_property("chapter", chapter + 1)
    end
  end
end)
