E_MODEL_REPLAY_BOO = smlua_model_util_get_id("replay_boo_geo")

local REPLAY_BOO_ACT_RACE = 0
local REPLAY_BOO_ACT_WON = 1
local REPLAY_BOO_ACT_FOLLOW = 0

replayBoos = {}

-- Smooth spline interpolation between p1 and p2 using p0, p1, p2, p3 context
local function catmullRom(p0, p1, p2, p3, t)
    return 0.5 * (
        (2 * p1) +
        (-p0 + p2) * t +
        (2*p0 - 5*p1 + 4*p2 - p3) * t^2 +
        (-p0 + 3*p1 - 3*p2 + p3) * t^3
    )
end

---@param obj Object
local function bhv_replay_boo_init(obj)
    obj.oFlags = OBJ_FLAG_UPDATE_GFX_POS_AND_ANGLE
    obj.oAction = REPLAY_BOO_ACT_RACE
    obj_set_model_extended(obj, E_MODEL_REPLAY_BOO)

    replayBoos[obj.oAnimState] = {
        replay = replayBoos[obj.oAnimState].replay or {},
        pos = {x = 0, y = 0, z = 0},
        lastPos = {x = 0, y = 0, z = 0},
        opacity = 1,
        obj = obj,
        light = le_add_light(obj.oPosX, obj.oPosY, obj.oPosZ, 220, 255, 220, 300, 255)
    }
end

---@param obj Object
local function bhv_replay_boo_loop(obj)
    local booAct = obj.oAnimState
    local booData = replayBoos[booAct]
    local f = math.floor(areaTimer/REPLAY_RATE)
    local t = (areaTimer % REPLAY_RATE) / REPLAY_RATE
    if obj.oAction == REPLAY_BOO_ACT_RACE then
        -- Make Ghost follow saved path
        if booData.replay ~= nil then
            if booData.replay[f] ~= nil then
                -- Get four neighboring samples (make sure they exist)
                local p1 = booData.replay[f]           -- current
                local p0 = booData.replay[f - 1] or p1 -- previous
                local p2 = booData.replay[f + 1] or p1 -- next
                local p3 = booData.replay[f + 2] or p2 -- next next

                -- Smooth position interpolation
                booData.pos = {
                    x = catmullRom(p0.x, p1.x, p2.x, p3.x, t),
                    y = catmullRom(p0.y, p1.y, p2.y, p3.y, t) + 160,
                    z = catmullRom(p0.z, p1.z, p2.z, p3.z, t),
                }
            else
                obj.oAction = REPLAY_BOO_ACT_WON
            end
        end
    elseif obj.oAction == REPLAY_BOO_ACT_WON then
        -- Circle in Victory
        local starPos = booData.replay[#booData.replay]
        booData.pos = {
            x = starPos.x + sins(get_global_timer()*0x300)*120,
            y = starPos.y + math.sin(get_global_timer()/20)*60,
            z = starPos.z + coss(get_global_timer()*0x300)*120,
        }
    end

    local pos = booData.pos
    local lastPos = booData.lastPos
    obj.oPosX = pos.x
    obj.oPosY = pos.y
    obj.oPosZ = pos.z

    obj.header.gfx.pos.x = obj.oPosX
    obj.header.gfx.pos.y = obj.oPosY
    obj.header.gfx.pos.z = obj.oPosZ
    
    obj.oFaceAngleYaw = atan2s(lastPos.z - pos.z, lastPos.x - pos.x)
    obj.oFaceAnglePitch = (pos.y - lastPos.y)*0x100

    spawn_non_sync_object(id_bhvSparkle, E_MODEL_SPARKLES_ANIMATION, lastPos.x, lastPos.y + math.sin(get_global_timer()/30)*50, lastPos.z, nil)
    if vec3f_dist(booData.lastPos, booData.pos) > 1 then
        vec3f_copy(booData.lastPos, booData.pos)
    end

    le_set_light_pos(booData.light, obj.oPosX, obj.oPosY, obj.oPosZ)
end

id_bhvReplayBoo = hook_behavior(nil, OBJ_LIST_DEFAULT, true, bhv_replay_boo_init, bhv_replay_boo_loop, "bhvReplayBoo")