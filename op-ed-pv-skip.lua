-- configuration
local KEYBIND = string.lower("y") -- must be lowercase, uppercase will be used for mode cycle
local PATTERNS_EXACT = {
    -- "intro" -- unfortunately ambiguous, some use it as a prologue, some as opening
    "op", "opening", " - op",
    "ed", "ending", " - ed",
    "ending credits", "credits",
    "pv", "preview", "next episode preview", "next ep. preview", "nextp ep. preview", "next", "next time",
    "endcard", " - ed card",
}
local PATTERNS_START = {
    "op by ",
    "ed song - ",
}
local PATTERNS_END = {
    " (opening)", " - opening", " - op",
    " (ending)", " - ed",
    " preview",
}
-- internal configuration
local MODE_CHAPTER_NAME   = "chapter name"
local MODE_CHAPTER_LENGTH = "chapter length"
-- state
local ENABLED = true
local PREV_CHAPTER = nil
local CURRENT_MODE = MODE_CHAPTER_NAME

local function starts_with(str, start)
    return str:sub(1, #start) == start
end

local function is_op_ed_pv(chapter_index)
    title = mp.get_property("chapter-list/" .. chapter_index .. "/title"):lower()

    for _, pattern in ipairs(PATTERNS_EXACT) do
        if pattern == title then
            return true
        end
    end

    for _, pattern in ipairs(PATTERNS_START) do
        if starts_with(title, pattern) then
            return true
        end
    end

    local function ends_with(str, ending)
        return ending == "" or str:sub(-#ending) == ending
    end

    for _, pattern in ipairs(PATTERNS_END) do
        if ends_with(title, pattern) then
            return true
        end
    end

    return false
end

local function seek_to_next_or_prev_chapter(chapter_index)
    -- figure out in which direction the chapter was changed
    if PREV_CHAPTER == nil or chapter_index > PREV_CHAPTER then
        forward = true
        to_chapter = chapter_index + 1
    else
        forward = false
        to_chapter = chapter_index - 1

        -- check previous title, if it's an opening, skip over it
        -- but don't if we're already on first chapter,
        -- previous chapter will go out of bounds, and result in a crash trying to get a chapter title
        if to_chapter > 0 and is_op_ed_pv(to_chapter) then
            to_chapter = to_chapter - 1
        end
    end

    chapters = mp.get_property_number("chapter-list/count")
    is_seeking = mp.get_property_bool("seeking")

    if not forward and is_seeking then
        -- avoid getting stuck when seeking backwards into chapter thats then immediately skipped
        -- instead, step over the skipped chapter, and seek into previous chapter

        if chapter_index >= chapters - 1 then
            -- current chapter is last, use total file duration instead
            -- e.g. ../Part B/ED/Part C|, when seeking from part C over ED
            chapter_end = mp.get_property_number("duration")
        else
            -- start of the next chapter is also the end of current chapter
            chapter_end = mp.get_property_number("chapter-list/" .. chapter_index + 1 .. "/time")
        end

        chapter_start = mp.get_property_number("chapter-list/" .. chapter_index .. "/time")
        current_position = mp.get_property_number("playback-time")

        -- how many seconds we've seeked into the skipped chapter
        seeked_skipped = chapter_end - current_position

        -- check if we skipped exactly an entire chapter
        -- floor the floats before comparing
        chapter_length = chapter_end - chapter_start
        if math.floor(chapter_length) == math.floor(seeked_skipped) then
            -- entire chapter was skipped, seek to the start of the previous one
            mp.set_property_number("chapter", to_chapter)
        elseif chapter_index == 0 then
            -- if first chapter is an opening, seek into it instead
            -- don't have to do anything for that, this is the default behaviour
        else
            -- seek into the previous chapter
            seeked_previous = chapter_start - seeked_skipped
            mp.set_property_number("playback-time", seeked_previous)
        end
    elseif chapter_index >= chapters - 1 then
        -- on last chapter, to next playlist item
        -- if we don't do this, we'll still go to the next item, but will get the following error
        -- The chapter option must be <= {last chapter}: {last chapter + 1}
        mp.command("playlist-next")
    else
        next_chapter_start = mp.get_property_number("chapter-list/" .. to_chapter + 1 .. "/time")
        chapter_start = mp.get_property_number("chapter-list/" .. to_chapter .. "/time")
        file_duration = mp.get_property_number("duration")

        if next_chapter_start == nil and chapter_start > file_duration then
            -- if last chapter starts beyond the end of the file, playback will get stuck when switched to the next file
            mp.command("playlist-next")
        else
            -- to next or previous chapter
            mp.set_property_number("chapter", to_chapter)
        end
    end
end

local function mode_cycle()
    if CURRENT_MODE == MODE_CHAPTER_NAME then
        CURRENT_MODE = MODE_CHAPTER_LENGTH
    elseif CURRENT_MODE == MODE_CHAPTER_LENGTH then
        CURRENT_MODE = MODE_CHAPTER_NAME
    end

    mp.osd_message("OP/ED/PV skip: " .. CURRENT_MODE)
end

mp.add_key_binding(KEYBIND, "op-ed-pv-skip-toggle", function()
    msg = "OP/ED/PV skip: "
    if ENABLED then
        ENABLED = false
        msg = msg .. "disabled"
    else
        ENABLED = true
        msg = msg .. "enabled"
    end

    mp.osd_message(msg)
end)

mp.add_key_binding(string.upper(KEYBIND), "op-ed-pv-skip-mode-cycle", function ()
    if not ENABLED then
        return
    end

    mode_cycle()
end)

mp.observe_property("chapters", "number", function(_, chapter_count)
    if chapter_count == nil
    or chapter_count == 0 then
        return
    end

    -- must run before `chapter` handler
    -- otherwise, chapter skip might not happen when opening the file (and first chapter is an OP)

    named_chapters = false
    for chapter_index = 0, chapter_count - 1 do -- range is inclusive, but chapters are 0-indexed
        title = mp.get_property("chapter-list/" .. chapter_index .. "/title")
        if not starts_with(title, "Chapter ") then
            named_chapters = true
            break
        end
    end

    if (named_chapters and CURRENT_MODE ~= MODE_CHAPTER_NAME)
    or (not named_chapters and CURRENT_MODE ~= MODE_CHAPTER_LENGTH)
    then
        -- `mp.commandv("keypress", string.upper(KEYBIND))` could have been used here,
        -- but the mode cycle seem to happen after `chapter` handler, so skip doesn't happen when opening the file
        mode_cycle()
    end
end)

mp.observe_property("chapter", "number", function(_, chapter_index)
    if not ENABLED
    or chapter_index == nil -- nil on startup before opening the file
    or chapter_index < 0    -- -1 when seeking backwards on first chapter
    then
        -- 0 is emitted next, so ignore this event
        return
    end

    if CURRENT_MODE == MODE_CHAPTER_NAME then
        if is_op_ed_pv(chapter_index) then
            seek_to_next_or_prev_chapter(chapter_index)
        end
    elseif CURRENT_MODE == MODE_CHAPTER_LENGTH then
        -- figure out chapter length
        current_chapter_start = mp.get_property_number("chapter-list/" .. chapter_index .. "/time")
        chapter_count = mp.get_property_number("chapter-list/count")
        last_chapter_index = chapter_count - 1
        if chapter_index == last_chapter_index then
            -- last chapter, since there's no next chapter, substract from total duration instead
            file_duration = mp.get_property_number("duration")
            chapter_length = file_duration - current_chapter_start
        else
            next_chapter_start = mp.get_property_number("chapter-list/" .. chapter_index + 1 .. "/time")
            chapter_length = next_chapter_start - current_chapter_start
        end

        -- chapter_length is a float, so use ranges when comparing
        if (chapter_index == 0                      -- |OP/..
        or chapter_index == 1                       -- |Intro/OP/..
        or chapter_index == 2                       -- |???/Intro/OP/..
        or chapter_index == last_chapter_index      -- ../ED|
        or chapter_index == last_chapter_index - 1  -- ../ED/PV|
        or chapter_index == last_chapter_index - 2) -- ../ED/PV/Endcard|
        and chapter_length >= 89 and chapter_length <= 91
        then
            seek_to_next_or_prev_chapter(chapter_index)
        end

        if chapter_index == last_chapter_index -- ../Preview|
        and chapter_length >= 14 and chapter_length <= 26
        then
            seek_to_next_or_prev_chapter(chapter_index)
        end
    end

    PREV_CHAPTER = chapter_index
end)

mp.observe_property("path", "none", function()
    -- reset previous chapter when changing files,
    -- `seek_to_next_or_prev_chapter` checks in which direction the chapter was changed
    -- by comparing current and previous chapter indices, if it was backwards,
    -- then it checks the previous title by substracting 1 and calling `is_op_ed_pv`,
    -- the problem is that if we change the file, and the first chapter is an opening,
    -- then current chapter index is 0, but previous was not reset and probably >0,
    -- so -1 gets passed into `is_op_ed_pv`, which then crashes when trying to fetch the title
    PREV_CHAPTER = nil
end)
