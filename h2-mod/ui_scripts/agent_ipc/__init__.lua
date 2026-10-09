-- Agent IPC Bridge for Overlord / MW2CR
-- Enables bidirectional communication between host environment (shell/agent/CLI) and in-game Lua/engine.
-- Listens for requests on "h2-mod/ipc_in.txt" and writes results to "h2-mod/ipc_out.txt".

if _G.AgentIPC_Active then
    print("[Agent IPC] Module already active, skipping re-init")
    return
end
_G.AgentIPC_Active = true

print("[Agent IPC] Initializing Agent IPC Bridge v1.0.0...")

local IN_PATH  = "h2-mod/ipc_in.txt"
local OUT_PATH = "h2-mod/ipc_out.txt"

-- Table serialization helper for Lua evaluations
local function serialize(v, depth)
    depth = depth or 0
    if depth > 3 then return "..." end
    local t = type(v)
    if t == "table" then
        local items = {}
        local count = 0
        for k, val in pairs(v) do
            count = count + 1
            if count > 20 then
                table.insert(items, "... (truncated at 20 entries)")
                break
            end
            table.insert(items, tostring(k) .. " = " .. serialize(val, depth + 1))
        end
        return "{ " .. table.concat(items, ", ") .. " }"
    elseif t == "string" then
        return string.format("%q", v)
    else
        return tostring(v)
    end
end

-- Execute a Lua script/expression safely and capture stdout
local function execute_lua(code)
    local output = {}
    local old_print = print
    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            table.insert(parts, tostring(select(i, ...)))
        end
        table.insert(output, table.concat(parts, "\t"))
        old_print(...)
    end

    -- First try as expression "return <code>"
    local fn, err = loadstring("return " .. code, "agent_ipc_eval")
    if not fn then
        -- Fall back to statement
        fn, err = loadstring(code, "agent_ipc_eval")
    end

    if not fn then
        print = old_print
        return false, "Compilation error: " .. tostring(err)
    end

    local ok, res1, res2, res3 = pcall(fn)
    print = old_print

    if not ok then
        return false, "Runtime error: " .. tostring(res1)
    end

    local results = {}
    if #output > 0 then
        table.insert(results, table.concat(output, "\n"))
    end
    if res1 ~= nil then
        table.insert(results, "=> " .. serialize(res1))
    end
    if res2 ~= nil then
        table.insert(results, serialize(res2))
    end
    if res3 ~= nil then
        table.insert(results, serialize(res3))
    end

    if #results == 0 then
        return true, "Success (no return value)"
    else
        return true, table.concat(results, "\n")
    end
end

-- Process incoming payload
local function handle_payload(raw)
    local lines = {}
    for line in string.gmatch(raw, "[^\r\n]+") do
        local trimmed = string.match(line, "^%s*(.-)%s*$")
        if trimmed and #trimmed > 0 then
            table.insert(lines, trimmed)
        end
    end

    if #lines == 0 then
        return "status: ok\noutput: empty payload\n"
    end

    local req_id = nil
    local commands = {}
    for _, line in ipairs(lines) do
        local id_match = string.match(line, "^id:%s*(.+)$")
        if id_match then
            req_id = id_match
        else
            table.insert(commands, line)
        end
    end

    local out_parts = {}
    local all_ok = true

    for _, cmd_line in ipairs(commands) do
        -- Check command types
        if string.sub(cmd_line, 1, 5) == "eval:" then
            local code = string.match(cmd_line, "^eval:%s*(.+)$") or ""
            local ok, res = execute_lua(code)
            if not ok then all_ok = false end
            table.insert(out_parts, "[LUA] " .. res)

        elseif string.sub(cmd_line, 1, 4) == "lua:" then
            local code = string.match(cmd_line, "^lua:%s*(.+)$") or ""
            local ok, res = execute_lua(code)
            if not ok then all_ok = false end
            table.insert(out_parts, "[LUA] " .. res)

        elseif string.sub(cmd_line, 1, 7) == "cmdnow:" then
            local c = string.match(cmd_line, "^cmdnow:%s*(.+)$") or ""
            if Engine and Engine.ExecNow then
                Engine.ExecNow(c)
                table.insert(out_parts, "[CMDNOW] Executed: " .. c)
            else
                table.insert(out_parts, "[CMDNOW ERROR] Engine.ExecNow not available")
                all_ok = false
            end

        elseif string.sub(cmd_line, 1, 4) == "cmd:" then
            local c = string.match(cmd_line, "^cmd:%s*(.+)$") or ""
            if Engine and Engine.Exec then
                Engine.Exec(c)
                table.insert(out_parts, "[CMD] Queued: " .. c)
            else
                table.insert(out_parts, "[CMD ERROR] Engine.Exec not available")
                all_ok = false
            end

        elseif string.sub(cmd_line, 1, 5) == "dvar:" then
            local dvar_part = string.match(cmd_line, "^dvar:%s*(.+)$") or ""
            local var, val = string.match(dvar_part, "^([^=]+)=(.*)$")
            if var and val then
                -- Set dvar
                if Engine and type(Engine.SetDvarString) == "function" then
                    Engine.SetDvarString(var, val)
                    table.insert(out_parts, "[DVAR SET] " .. var .. " = " .. val)
                else
                    table.insert(out_parts, "[DVAR ERROR] Engine.SetDvarString not available")
                    all_ok = false
                end
            else
                -- Get dvar
                var = dvar_part
                local val_str = Engine and Engine.GetDvarString and Engine.GetDvarString(var)
                table.insert(out_parts, "[DVAR GET] " .. var .. " = " .. tostring(val_str))
            end

        elseif cmd_line == "help" then
            table.insert(out_parts, [[
Available commands:
  cmd: <console command>     - Queues an engine console command (e.g. cmd: god)
  cmdnow: <console command>  - Executes console command immediately
  lua: <code>                - Evaluates arbitrary Lua code / expressions
  eval: <code>               - Evaluates arbitrary Lua code / expressions
  dvar: <name>               - Gets dvar value
  dvar: <name>=<value>       - Sets dvar value
  <console command>          - Any un-prefixed line is executed as a console command
]])

        else
            -- Default: treat as engine console command
            if Engine and Engine.Exec then
                Engine.Exec(cmd_line)
                table.insert(out_parts, "[CMD] Queued: " .. cmd_line)
            else
                table.insert(out_parts, "[CMD ERROR] Engine.Exec not available")
                all_ok = false
            end
        end
    end

    local resp = ""
    if req_id then
        resp = resp .. "id: " .. req_id .. "\n"
    end
    resp = resp .. "status: " .. (all_ok and "ok" or "error") .. "\n"
    resp = resp .. "output:\n" .. table.concat(out_parts, "\n") .. "\n"
    return resp
end

-- Main tick handler
local function poll_tick()
    if not (io and io.fileexists and io.readfile and io.removefile and io.writefile) then
        return
    end

    if not io.fileexists(IN_PATH) then
        return
    end

    local raw = io.readfile(IN_PATH)
    io.removefile(IN_PATH)

    if raw and #raw > 0 then
        -- The request file is already gone by this point, so an error in
        -- handle_payload would leave the caller waiting out its timeout and
        -- reporting a connection problem. Answer with the error instead.
        local ok, response = pcall(handle_payload, raw)
        if not ok then
            local req_id = string.match(raw, "id:%s*([^\r\n]+)")
            response = (req_id and ("id: " .. req_id .. "\n") or "")
                .. "status: error\noutput:\n[BRIDGE ERROR] "
                .. tostring(response) .. "\n"
        end
        io.writefile(OUT_PATH, response, false)
    end
end

-- Attachment and watchdog
local poller_elem = nil

local function get_active_root()
    if Engine and type(Engine.GetLuiRoot) == "function" then
        local ok, r = pcall(Engine.GetLuiRoot)
        if ok and r then return r end
    end
    if LUI and LUI.roots then
        return LUI.roots.UIRoot0 or LUI.roots.UIRootFull
    end
    return nil
end

local function attach_poller()
    local root = get_active_root()
    if not root then return false end

    if poller_elem and poller_elem:getParent() then
        return true
    end

    poller_elem = LUI.UIElement.new({
        topAnchor = true, leftAnchor = true,
        top = 0, left = 0, width = 0, height = 0,
        alpha = 0
    })
    poller_elem.id = "AgentIPCPollerElement"

    -- 200ms polling timer
    local POLL_INTERVAL_MS = 200
    local timer = LUI.UITimer.new(POLL_INTERVAL_MS, "agent_ipc_pulse")
    poller_elem:addElement(timer)
    poller_elem:registerEventHandler("agent_ipc_pulse", function()
        pcall(poll_tick)
    end)

    local ok, err = pcall(function() root:addElement(poller_elem) end)
    if ok then
        print(string.format("[Agent IPC] Poller attached to root (%dms interval)", POLL_INTERVAL_MS))
        -- Write initial readiness indicator
        io.writefile(OUT_PATH, "status: ready\noutput: Agent IPC Bridge active\n", false)
        return true
    else
        print("[Agent IPC] Failed to attach poller to root: " .. tostring(err))
        return false
    end
end

-- Initial attachment attempt
if not attach_poller() then
    print("[Agent IPC] Root not immediately ready; hooking menu open callbacks...")
end

-- Hook common menu opens to re-ensure poller attachment
if LUI and type(LUI.onmenuopen) == "function" then
    local menus = { "main_lockout", "main_campaign", "sp_pause_menu", "hud" }
    for _, menu_name in ipairs(menus) do
        LUI.onmenuopen(menu_name, function()
            attach_poller()
        end)
    end
end
