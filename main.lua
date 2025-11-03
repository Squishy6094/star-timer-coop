-- name: Star Timer

-- Get/Create ModFs
local modFs = mod_fs_get() or mod_fs_create()

-- Constants
local REPLAY_FPS = 5
local REPLAY_RATE = math.ceil(30/REPLAY_FPS)


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

local function save_replay_table(level, star, table)
    log_to_console("Start Save")
    local replayString = ""
    local prevPos = {x = 0, y = 0, z = 0}
    for i = 0, #table do
        replayString = replayString..tostring(math.floor(table[i].x - prevPos.x)).." "..tostring(math.floor(table[i].y - prevPos.y)).." "..tostring(math.floor(table[i].z - prevPos.z)) .. ","
        log_to_console(replayString)
    end

    -- Save Replay
    local filename = "replay-"..tostring(romhack).."-"..tostring(level).."-"..tostring(star)
    local file = modFs:get_file(filename) or modFs:create_file(filename, true)
    file:erase(file.size)
    file:set_text_mode(true) -- Set mode to text
    file:rewind() -- Reset offset to the beginning of the file
    file:write_string(replayString)
    modFs:save()
    djui_chat_message_create("Saved to \\#00ffff\\star-timer.modfs/"..filename)
    return replayString
end

local function load_replay_table(level, star)
    log_to_console("Start Load")
    local filename = "replay-"..tostring(romhack).."-"..tostring(level).."-"..tostring(star)
    local file = modFs:get_file(filename) or modFs:create_file(filename, true)
    file:rewind() -- Reset offset to the beginning of the file
    
    local replayString = string_split(file:read_string(), ",")
    if replayString == nil then return {} end
    local replayTable = {}
    local prevPos = {x = 0, y = 0, z = 0}
    for i = 1, #replayString do
        local pos = string_split(replayString[i], " ")
        if pos ~= nil then
            replayTable[i - 1] = {x = pos[1] + prevPos.x, y = pos[2] + prevPos.y, z = pos[3] + prevPos.z}
        end
        log_to_console(tostring(replayTable[i-1].x) .. ", " .. tostring(replayTable[i-1].y) .. ", " .. tostring(replayTable[i-1].z))
    end
    file:erase(file.size)
    file:set_text_mode(true) -- Set mode to text
    file:rewind() -- Reset offset to the beginning of the file

    modFs:save()
    return replayTable
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

local replay = {}
local savedPos = {}

local areaTimer = 0
local areaTimerStop = false
local areaTimerBest = 0
local function update()
    local m = gMarioStates[0]
    local np = gNetworkPlayers[0]
    if not areaTimerStop and np.currLevelNum ~= 0
    and (m.action & ACT_GROUP_CUTSCENE == 0 or m.action & ACT_FLAG_ON_POLE ~= 0 or forceTimerActs[m.action])
    and (m.area.camera == nil or m.area.camera.cutscene == 0) then
        if areaTimer%REPLAY_RATE == 0 then
            djui_chat_message_create("noted"..areaTimer/REPLAY_RATE)
            savedPos[areaTimer/REPLAY_RATE] = {x = m.pos.x, y = m.pos.y, z = m.pos.z}
        end
        local replayCurrPos = replay[math.floor(areaTimer/REPLAY_RATE)]
        local replayNextPos = replay[math.floor(areaTimer/REPLAY_RATE) + 1]
        if replayCurrPos ~= nil then
            local replayX = math.lerp(replayCurrPos.x, replayNextPos and replayNextPos.x or replayCurrPos.x, (areaTimer%REPLAY_RATE)/REPLAY_RATE)
            local replayY = math.lerp(replayCurrPos.y, replayNextPos and replayNextPos.y or replayCurrPos.y, (areaTimer%REPLAY_RATE)/REPLAY_RATE)
            local replayZ = math.lerp(replayCurrPos.z, replayNextPos and replayNextPos.z or replayCurrPos.z, (areaTimer%REPLAY_RATE)/REPLAY_RATE)
            spawn_non_sync_object(id_bhvSparkleSpawn, E_MODEL_NONE, replayX, replayY, replayZ, nil)
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
        if save_star_time(np.currLevelNum, starNum, areaTimer) then
            areaTimerBest = areaTimer
        end
        save_replay_table(np.currLevelNum, starNum, savedPos)
        timerColorTarget = {r = 255, g = 255, b = 255}
        areaTimerStop = true
    end
end

local function level_init()
    local np = gNetworkPlayers[0]
    if np.currCourseNum == 0 then return end 
    areaTimer = 0
    areaTimerStop = false
    areaTimerBest = load_star_time(np.currLevelNum, np.currActNum ~= 0 and np.currActNum or 1)
    replay = load_replay_table(np.currLevelNum, np.currActNum ~= 0 and np.currActNum or 1)
end

hook_event(HOOK_UPDATE, update)
hook_event(HOOK_ON_HUD_RENDER_BEHIND, hud_render)
hook_event(HOOK_ON_INTERACT, on_interact)
hook_event(HOOK_ON_LEVEL_INIT, level_init)