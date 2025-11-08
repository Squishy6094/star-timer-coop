-- name: Star Timer

-- Get/Create ModFs
local modFs = mod_fs_get() or mod_fs_create()

-- Constants
REPLAY_FPS = 3
REPLAY_RATE = math.ceil(30/REPLAY_FPS)
ACT_MAX = 7
MARIO_HEIGHT = 160

SAVE_VAR_NAME = "name"
SAVE_VAR_COOPID = "coopid"
SAVE_VAR_FRAMES = "frames"
SAVE_VAR_REPLAY = "replay"

---@param str string
--- Splits a string into a table by spaces
function string_split(str, splitAt)
    if str == nil then return end
    if splitAt == nil then
        splitAt = " "
    end
    local result = {}
    for match in str:gmatch(string.format("[^%s]+", splitAt)) do
        table.insert(result, match)
    end
    return result
end

-- Server/Level Settings
local originalStayInLevel = gServerSettings.stayInLevelAfterStar
gServerSettings.stayInLevelAfterStar = 0
gLevelValues.showStarNumber = 1

-- Check Mods
serverMoveset = false
for i in pairs(gActiveMods) do
    if gActiveMods[i].name:find("Cheats") or gActiveMods[i].name:find("Object Spawner") or gActiveMods[i].name:find("Noclip") then
        cheats = true
    end
    if (gActiveMods[i].incompatible ~= nil and gActiveMods[i].incompatible:find("moveset")) then
        serverMoveset = true
    end
end

-- Check Romhack
romhack = "sm64"
for mod in pairs(gActiveMods) do
    if gActiveMods[mod].incompatible ~= nil and gActiveMods[mod].incompatible:find("romhack") then
        romhack = gActiveMods[mod].relativePath
        break
    end
end

local function get_modifiers_string()
    local moveset = false
    if _G.OmmEnabled and _G.OmmApi.omm_get_setting(m, _G.OmmApi["OMM_SETTING_MOVESET"]) == _G.OmmApi["OMM_SETTING_MOVESET_ODYSSEY"] then
        moveset = true
    end
    if _G.charSelectExists then
        local charMovesetTable = _G.charSelect.character_get_moveset(_G.charSelect.character_get_current_number(0))
        local charMoveset = charMovesetTable ~= nil and #charMovesetTable > 0
        local charToggle = _G.charSelect.get_options_status(_G.charSelect.optionTableRef.localMoveset) ~= 0 
        if charMoveset and charToggle then
            moveset = true
        end
    end

    local modifiers = ""
    if serverMoveset or moveset then
        modifiers = modifiers .. "Moveset"
    end
    if cheats then
        modifiers = modifiers .. ", Cheats"
    end
    if modifiers ~= "" then
        modifiers = " (" .. modifiers .. ")"
    end
    return modifiers
end

-- Timer format
local function timestamp(frames)
    seconds = frames / 30
    local hours = math.floor(seconds / 60 / 60)
    local minutes = math.floor(seconds / 60) % 60
    local milliseconds = math.floor((seconds - math.floor(seconds)) * 1000)
    seconds = math.floor(seconds) % 60
    return hours > 0 and string.format("%d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds) or (minutes > 0 and string.format("%d:%02d.%03d", minutes, seconds, milliseconds) or string.format("%01d.%03d", seconds, milliseconds))
end

local function load_star_replay(level, star)
    local replayData = {
        name = "Replay",
        id = "-1",
        frames = 0,
        replayString = "",
        replay = {},
    }
    local filename = "replay-"..tostring(romhack).."-"..tostring(level).."-"..tostring(star)
    local file = modFs:get_file(filename)
    if file == nil then
        return replayData
    end
    file:rewind() -- Reset offset to the beginning of the file

    repeat
        local currLine = file:read_line()
        local lineSplit = string_split(currLine, "|")
        if lineSplit ~= nil then
            local linePrefix = lineSplit[1]
            local lineContent = ""
            for i = 2, #lineSplit do
                if lineSplit[i] ~= nil then
                    lineContent = lineContent..lineSplit[i]
                end
            end

            if linePrefix == SAVE_VAR_NAME then
                replayData.name = lineContent
            end
            if linePrefix == SAVE_VAR_COOPID then
                replayData.id = lineContent
            end
            if linePrefix == SAVE_VAR_FRAMES then
                replayData.frames = tonumber(lineContent)
            end
            if linePrefix == SAVE_VAR_REPLAY then
                replayData.dataString = lineContent
            end
            log_to_console(currLine)
        end
        -- Read next line
    until file:is_eof()
    
    local replayString = string_split(replayData.dataString, ",")
    if replayString == nil then return {} end
    local replayTable = {}
    local prevPos = {x = 0, y = 0, z = 0}
    for i = 1, #replayString do
        local pos = string_split(replayString[i], " ")
        if pos ~= nil then
            replayTable[i - 1] = {x = pos[1] + prevPos.x, y = pos[2] + prevPos.y, z = pos[3] + prevPos.z}
            vec3f_copy(prevPos, replayTable[i - 1])
        end
    end
    replayData.data = replayTable

    file:set_text_mode(true) -- Set mode to text
    file:rewind() -- Reset offset to the beginning of the file
    return replayData
end

local function save_star_replay(level, star, frames, table)
    local best = load_star_replay(level, star).frames
    local isPB = best == 0 or best > frames
    local np = gNetworkPlayers[0]

    -- Save Replay
    if isPB then
        local filename = "replay-"..tostring(romhack).."-"..tostring(level).."-"..tostring(star)
        local savePathMsg = "\\#00ffff\\star-timer.modfs/"..filename
        local file = modFs:get_file(filename) or modFs:create_file(filename, false)
        file:erase(file.size)
        file:set_text_mode(true) -- Set mode to text
        file:rewind() -- Reset offset to the beginning of the file

        file:write_line(SAVE_VAR_NAME.."|"..np.name)
        
        file:write_line(SAVE_VAR_COOPID.."|"..get_coopnet_id(0))

        file:write_line(SAVE_VAR_FRAMES.."|"..tostring(frames))
        
        local replayString = ""
        local prevPos = {x = 0, y = 0, z = 0}
        for i = 0, #table do
            replayString = replayString..tostring(math.floor(table[i].x - prevPos.x)).." "..tostring(math.floor(table[i].y - prevPos.y)).." "..tostring(math.floor(table[i].z - prevPos.z)) .. ","
            vec3f_copy(prevPos, table[i])
        end
        file:write_line(SAVE_VAR_REPLAY.."|"..replayString)
        
        modFs:save()
        if best > frames then
            djui_chat_message_create("New Personal Best!"
            .. "\n\\#ff0000\\" .. timestamp(best) .. "\\#ffffff\\ -> \\#00ff00\\" .. timestamp(frames) .. "\\#ffffff\\ | \\#00ffff\\-" .. timestamp(best - frames)
            .." \n\\#ffffff\\Saved to ".. savePathMsg)
        else
            djui_chat_message_create("\\#ffffff\\New Time Saved to " .. savePathMsg)
        end
    end
    return isPB
end

local function load_star_time(level, star)
    return mod_storage_load_number(romhack.."-"..level.."-"..star)
end

local function load_level_star_time(level)
    local stars = {}
    for i = 1, 8 do
        stars[i] = mod_storage_load_number(romhack.."-"..level.."-"..i)
    end
    return stars
end

local function save_star_time(level, star, frames)
    local best = load_star_time(level, star)
    if best == 0 or best > frames then
        mod_storage_save_number(romhack.."-"..level.."-"..star, frames)
        if best > frames then
            djui_chat_message_create("New Personal Best!\n \\#ff0000\\" .. timestamp(best) .. "\\#ffffff\\ -> \\#00ff00\\" .. timestamp(frames) .. "\n\\#00ffff\\(-" .. timestamp(best - frames) .. ")")
        else
            djui_chat_message_create("New Time Saved!")
        end
        return true
    end
    return false
end

local forceTimerActs = {
    [ACT_LEDGE_GRAB] = true,
    [ACT_LEDGE_CLIMB_DOWN] = true,
    [ACT_LEDGE_CLIMB_FAST] = true,
    [ACT_LEDGE_CLIMB_SLOW_1] = true,
    [ACT_LEDGE_CLIMB_SLOW_2] = true,
}

local savedPos = {}

areaTimer = 0
local areaTimerStop = true
local areaTimerBest = 0
local function update()
    local m = gMarioStates[0]
    local np = gNetworkPlayers[0]
    if not areaTimerStop and np.currLevelNum ~= 0
    and (m.action & ACT_GROUP_CUTSCENE == 0 or m.action & ACT_FLAG_ON_POLE ~= 0 or forceTimerActs[m.action])
    and (m.area.camera == nil or m.area.camera.cutscene == 0) then
        if areaTimer%REPLAY_RATE == 0 then
            savedPos[areaTimer/REPLAY_RATE] = {x = m.pos.x, y = m.pos.y, z = m.pos.z}
        end
        areaTimer = areaTimer + 1
    end
end

local function lerp(a, b, t)
    return a * (1 - t) + b * t
end

local timerColor = {r = 255, g = 255, b = 255}
local timerColorTarget = {r = 0, g = 255, b = 0}
local function hud_render()
    djui_hud_set_resolution(RESOLUTION_N64)
    local screenWidth = djui_hud_get_screen_width()
    local screenHeight = 240
    djui_hud_set_font(FONT_SPECIAL)
    if areaTimerBest == 0 then
        timerColorTarget = {r = 255, g = 255, b = 255}
    else
        if areaTimerBest >= areaTimer then
            timerColorTarget = {r = 0, g = 255, b = 0}
        else
            timerColorTarget = {r = 255, g = 0, b = 0}
        end
    end
    timerColor.r = lerp(timerColor.r, timerColorTarget.r, 0.1)
    timerColor.g = lerp(timerColor.g, timerColorTarget.g, 0.1)
    timerColor.b = lerp(timerColor.b, timerColorTarget.b, 0.1)
    djui_hud_set_color(timerColor.r, timerColor.g, timerColor.b, 255)
    local timerString = timestamp(areaTimer)
    djui_hud_print_text(timerString, screenWidth*0.5 - djui_hud_measure_text(timerString)*0.25, screenHeight - 18, 0.5)
    djui_hud_set_color(255, 255, 255, 255)
    local timerBestString = " / "..timestamp(areaTimerBest)
    djui_hud_print_text(timerBestString, screenWidth*0.5 + djui_hud_measure_text(timerString)*0.25, screenHeight - 11, 0.25)
end

---@param m MarioState
---@param o Object
local function on_interact(m, o, type, value)
    local np = gNetworkPlayers[0]
    if m.playerIndex ~= 0 and np.currCourseNum ~= 0 then return end
    if type == INTERACT_STAR_OR_KEY then
        local starNum = ((o.oBehParams >> 24) & 0xFF) + 1
        table.insert(savedPos, {x = o.oPosX, y = o.oPosY, z = o.oPosZ})
        if save_star_replay(np.currLevelNum, starNum, areaTimer, savedPos) then
            areaTimerBest = areaTimer
        end
        timerColorTarget = {r = 255, g = 255, b = 255}
        areaTimerStop = true
    end
end

local function level_init()
    local np = gNetworkPlayers[0]
    if np.currCourseNum == 0 then return end
    areaTimer = 0
    areaTimerStop = false
    areaTimerBest = load_star_replay(np.currLevelNum, np.currActNum ~= 0 and np.currActNum or 1).frames
    savedPos = {}
    for i = 1, ACT_MAX do
        if replayBoos[i] == nil then replayBoos[i] = {} end
        replayBoos[i].replay = {}
        if np.currActNum == 0 or np.currActNum == i then
            replayBoos[i].replay = load_star_replay(np.currLevelNum, i)
            if replayBoos[i].replay ~= nil then
                spawn_non_sync_object(id_bhvReplayBoo, E_MODEL_REPLAY_BOO, 0, 0, 0, function (obj)
                    obj.oAnimState = i
                end)
            end
        end
    end
end

hook_event(HOOK_UPDATE, update)
hook_event(HOOK_ON_HUD_RENDER_BEHIND, hud_render)
hook_event(HOOK_ON_INTERACT, on_interact)
hook_event(HOOK_ON_LEVEL_INIT, level_init)