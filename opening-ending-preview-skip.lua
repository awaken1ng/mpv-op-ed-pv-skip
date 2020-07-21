local PREV_CHAPTER = nil
local ENABLED = true
local KEYBIND = "y"
local OPENING = {"op", "opening"}
local ENDING = {"ed", "ending", "ending credits", "preview", "next episode preview", "endcard"}

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
  if not ENABLED 
  or chapter == nil 
  or chapter < 0 -- can be -1 when going backwards on first chapter
  then return end

  -- figure out in which direction the chapter was changed
  if PREV_CHAPTER == nil or chapter > PREV_CHAPTER then
    forward = true
    to_chapter = chapter + 1
  else
    forward = false
    to_chapter = chapter - 1
  end

  title = mp.get_property("chapter-list/" .. chapter .. "/title"):lower()
  if has_value(OPENING, title) then
    -- to next or previous chapter
    mp.set_property("chapter", to_chapter)
  elseif has_value(ENDING, title) then
    chapters = tonumber(mp.get_property("chapter-list/count") - 1)

    if forward and chapter >= chapters then
      -- on last chapter, to next playlist item
      -- if we don't do this, we'll still go to the next item, but will get the following error
      -- The chapter option must be <= {last chapter}: {last chapter + 1}
      mp.command("playlist-next")
    else
      -- to next or previous chapter
      mp.set_property("chapter", to_chapter)
    end
  end
end)

mp.observe_property("chapter", "number", function(_, chapter)
  PREV_CHAPTER = chapter
end)
