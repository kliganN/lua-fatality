-- skeet_hud_core.lua
-- Fatality Lua HUD: watermark, keybind list, indicators and event log.

local SCRIPT_ID = 'skeet_hud_core'

local ui = {}
local state = {
    logs = {},
    fps = 0,
    last_frame = draw.GetTime(),
}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function lerp(a, b, t)
    return a + (b - a) * clamp(t, 0, 1)
end

local function safe(fn, fallback)
    local ok, value = pcall(fn)
    if ok then return value end
    return fallback
end

local function get_bool(control, fallback)
    if not control then return fallback end
    return safe(function() return control:GetValue():Get() end, fallback)
end

local function get_num(control, fallback)
    if not control then return fallback end
    return safe(function() return control:Get() end, fallback)
end

local function get_col(control, fallback)
    if not control then return fallback end
    return safe(function() return control:Get() end, fallback)
end

local function set_value(control, value)
    if control then
        pcall(function() control:GetValue():Set(value) end)
    end
end

local function text_w(text)
    return #tostring(text) * 7
end

local function color(r, g, b, a)
    return draw.Color(r, g, b, a or 255)
end

local function colors()
    local theme = safe(function() return gui.GetThemeColors() end, nil)
    local accent = get_col(ui.accent, theme and theme.accent or color(145, 210, 80))
    return {
        accent = accent,
        accent2 = theme and theme.accent2 or accent:Lighten(0.15),
        bg = theme and theme.bgBottom:ModA(0.92) or color(13, 13, 13, 235),
        panel = theme and theme.bgBlock:ModA(0.92) or color(22, 22, 22, 235),
        panel2 = theme and theme.bgBlock2:ModA(0.95) or color(32, 32, 32, 240),
        outline = theme and theme.outline or color(0, 0, 0, 220),
        text = theme and theme.text or color(235, 235, 235),
        muted = theme and theme.textMid or color(165, 165, 165),
        dark = color(0, 0, 0, 160),
        warn = theme and theme.warning or color(240, 195, 80),
        success = theme and theme.success or color(145, 210, 80),
    }
end

local function add_log(text, col)
    local limit = get_num(ui.log_limit, 6)
    table.insert(state.logs, 1, {
        text = text,
        col = col or colors().accent,
        born = draw.GetTime(),
        life = 4.2,
    })

    while #state.logs > limit do
        table.remove(state.logs)
    end
end

local function panel(layer, x, y, w, h, c)
    local cs = c or colors()
    local r = draw.Rect(x, y, x + w, y + h)
    layer:AddShadowRect(r, 10, true, 0.22)
    layer:AddRectFilled(r, cs.bg)
    layer:AddRect(r, cs.outline, 1.0)
    layer:AddLine(draw.Vec2(x + 1, y + 1), draw.Vec2(x + w - 1, y + 1), cs.accent, 1.0)
end

local function draw_row(layer, x, y, w, left, right, alpha, c)
    local cs = c or colors()
    local a = alpha or 1
    layer:AddRectFilled(draw.Rect(x, y, x + w, y + 18), cs.panel:ModA(a))
    layer:AddText(draw.Vec2(x + 6, y + 3), left, cs.text:ModA(a))
    if right and right ~= '' then
        layer:AddText(draw.Vec2(x + w - text_w(right) - 6, y + 3), right, cs.muted:ModA(a))
    end
end

local function screen_size()
    local display = safe(function() return draw.GetDisplay() end, nil)
    if display then return display.x, display.y end

    local ok, w, h = pcall(function()
        local w, h = game.engine:GetScreenSize()
        return w, h
    end)

    if ok and w and h then return w, h end
    return 1920, 1080
end

local function latency_ms()
    return safe(function()
        local chan = game.engine:GetNetChan()
        if chan and not chan:IsNull() then
            return math.floor(chan:GetLatency() * 1000.0 + 0.5)
        end
        return 0
    end, 0)
end

local function update_fps()
    local now = draw.GetTime()
    local ft = math.max(now - state.last_frame, 0.0001)
    state.last_frame = now
    state.fps = lerp(state.fps, 1 / ft, 0.08)
end

local function watermark(layer, c)
    if not get_bool(ui.watermark, true) then return end

    local w, _ = screen_size()
    local ping = latency_ms()
    local text = string.format('fatality.lua | skeet hud | %d fps | %d ms',
        math.floor(state.fps + 0.5), ping)
    local width = text_w(text) + 18
    local x = w - width - get_num(ui.margin, 12)
    local y = get_num(ui.margin, 12)

    panel(layer, x, y, width, 22, c)
    layer:AddText(draw.Vec2(x + 8, y + 5), text, c.text)
end

local function active_binds()
    local out = {}
    local controls = safe(function() return gui.GetHotkeyList() end, {})

    for _, control in ipairs(controls or {}) do
        local ok, label, value = pcall(function()
            local element = control:Cast()
            local active = safe(function() return element:GetHotkeyState() end, false)
            if not active then
                active = safe(function() return element:GetValue():GetHotkeyState() end, false)
            end

            if active then
                local name = element:GetLabel().text
                local raw = element:GetValue():Get()
                local val = type(raw) == 'boolean' and 'on' or tostring(raw)
                return name, val
            end
        end)

        if ok and label and label ~= '' then
            table.insert(out, { label = label, value = value or 'on' })
        end
    end

    return out
end

local function keybinds(layer, c)
    if not get_bool(ui.keybinds, true) then return end

    local binds = active_binds()
    if #binds == 0 and not gui.IsVisible() then return end

    local x = get_num(ui.bind_x, 18)
    local y = get_num(ui.bind_y, 180)
    local width = get_num(ui.bind_w, 178)
    local rows = math.max(#binds, gui.IsVisible() and 1 or 0)
    local height = 22 + rows * 18 + 4

    panel(layer, x, y, width, height, c)
    layer:AddText(draw.Vec2(x + 7, y + 5), 'keybinds', c.text)

    if #binds == 0 then
        draw_row(layer, x + 1, y + 23, width - 2, 'menu preview', 'hold', 0.72, c)
        return
    end

    for i, bind in ipairs(binds) do
        draw_row(layer, x + 1, y + 23 + (i - 1) * 18, width - 2, bind.label, bind.value, 1, c)
    end
end

local function indicators(layer, c)
    if not get_bool(ui.indicators, true) then return end

    local w, h = screen_size()
    local ping = latency_ms()
    local x = math.floor(w * 0.5) + get_num(ui.ind_x, -42)
    local y = math.floor(h * 0.5) + get_num(ui.ind_y, 38)
    local items = {
        { 'LUA', c.accent },
        { string.format('%d FPS', math.floor(state.fps + 0.5)), c.success },
    }

    if ping > 0 then
        table.insert(items, { string.format('%d MS', ping), ping > 80 and c.warn or c.muted })
    end

    for i, item in ipairs(items) do
        local yy = y + (i - 1) * 15
        layer:AddText(draw.Vec2(x + 1, yy + 1), item[1], c.dark)
        layer:AddText(draw.Vec2(x, yy), item[1], item[2])
    end
end

local function logs(layer, c)
    if not get_bool(ui.logs, true) then return end

    local now = draw.GetTime()
    local x = get_num(ui.log_x, 18)
    local y = get_num(ui.log_y, 430)
    local max_w = 0

    for i = #state.logs, 1, -1 do
        local log = state.logs[i]
        if now - log.born > log.life then
            table.remove(state.logs, i)
        else
            max_w = math.max(max_w, text_w(log.text) + 24)
        end
    end

    if #state.logs == 0 then return end

    local width = math.max(max_w, 210)
    panel(layer, x, y, width, 24 + #state.logs * 18, c)
    layer:AddText(draw.Vec2(x + 7, y + 5), 'event log', c.text)

    for i, log in ipairs(state.logs) do
        local age = now - log.born
        local alpha = clamp(math.min(age / 0.18, (log.life - age) / 0.45), 0, 1)
        local yy = y + 23 + (i - 1) * 18
        layer:AddRectFilled(draw.Rect(x + 1, yy, x + width - 1, yy + 18), c.panel:ModA(alpha))
        layer:AddText(draw.Vec2(x + 7, yy + 3), '[lua]', log.col:ModA(alpha))
        layer:AddText(draw.Vec2(x + 43, yy + 3), log.text, c.text:ModA(alpha))
    end
end

local function on_event(event)
    if not get_bool(ui.logs, true) then return end

    local name = event:GetName()
    local c = colors()

    if name == 'round_start' then
        add_log('round started', c.success)
    elseif name == 'bomb_beginplant' then
        add_log('bomb plant started', c.warn)
    elseif name == 'bomb_abortplant' then
        add_log('bomb plant aborted', c.warn)
    elseif name == 'bomb_planted' then
        add_log('bomb planted', c.warn)
        pcall(function() game.PlaySound('sounds/ui/beepclear', 0.18) end)
    elseif name == 'bomb_defused' then
        add_log('bomb defused', c.success)
    elseif name == 'bomb_exploded' then
        add_log('bomb exploded', c.warn)
    elseif name == 'game_newmap' then
        add_log('new map loaded', c.accent)
    end
end

local function on_present()
    update_fps()

    local layer = draw.surface
    layer.font = draw.fonts['gui_main']

    local c = colors()
    watermark(layer, c)
    keybinds(layer, c)
    indicators(layer, c)
    logs(layer, c)
end

local function add_controls()
    local parent = safe(function()
        local wnd = gui.GetMainWindow()
        return wnd:AddTab(SCRIPT_ID .. '_tab', draw.textures['icon_scripts'], 'Skeet HUD', gui.TabLayoutMode.DEFAULT)
    end, nil)

    if not parent then
        parent = gui.ctx:Find('lua>groups')
    end

    local main = gui.Group(SCRIPT_ID .. '_main', 'Main', 220, gui.GroupWidthMode.FULL)
    local layout = gui.Group(SCRIPT_ID .. '_layout', 'Layout', 260, gui.GroupWidthMode.FULL)

    parent:Add(main)
    parent:Add(layout)

    ui.watermark, ui.watermark_row = gui.MakeControlEasy(SCRIPT_ID .. '_watermark', 'Watermark', 'checkbox')
    ui.keybinds, ui.keybinds_row = gui.MakeControlEasy(SCRIPT_ID .. '_keybinds', 'Keybind list', 'checkbox')
    ui.indicators, ui.indicators_row = gui.MakeControlEasy(SCRIPT_ID .. '_indicators', 'Indicators', 'checkbox')
    ui.logs, ui.logs_row = gui.MakeControlEasy(SCRIPT_ID .. '_logs', 'Event log', 'checkbox')
    ui.accent, ui.accent_row = gui.MakeControlEasy(SCRIPT_ID .. '_accent', 'Accent', 'color_picker', true)
    ui.log_limit, ui.log_limit_row = gui.MakeControlEasy(SCRIPT_ID .. '_log_limit', 'Log limit', 'slider', 2, 10)

    ui.watermark:SetValue(true)
    ui.keybinds:SetValue(true)
    ui.indicators:SetValue(true)
    ui.logs:SetValue(true)
    set_value(ui.accent, color(145, 210, 80))
    set_value(ui.log_limit, 6)

    main:Add(ui.watermark_row)
    main:Add(ui.keybinds_row)
    main:Add(ui.indicators_row)
    main:Add(ui.logs_row)
    main:Add(ui.accent_row)
    main:Add(ui.log_limit_row)
    main:Reset()

    ui.margin, ui.margin_row = gui.MakeControlEasy(SCRIPT_ID .. '_margin', 'Screen margin', 'slider', 4, 40)
    ui.bind_x, ui.bind_x_row = gui.MakeControlEasy(SCRIPT_ID .. '_bind_x', 'Binds X', 'slider', 0, 900)
    ui.bind_y, ui.bind_y_row = gui.MakeControlEasy(SCRIPT_ID .. '_bind_y', 'Binds Y', 'slider', 0, 900)
    ui.bind_w, ui.bind_w_row = gui.MakeControlEasy(SCRIPT_ID .. '_bind_w', 'Binds width', 'slider', 130, 280)
    ui.ind_x, ui.ind_x_row = gui.MakeControlEasy(SCRIPT_ID .. '_ind_x', 'Indicators X', 'slider', -300, 300)
    ui.ind_y, ui.ind_y_row = gui.MakeControlEasy(SCRIPT_ID .. '_ind_y', 'Indicators Y', 'slider', -200, 300)
    ui.log_x, ui.log_x_row = gui.MakeControlEasy(SCRIPT_ID .. '_log_x', 'Log X', 'slider', 0, 900)
    ui.log_y, ui.log_y_row = gui.MakeControlEasy(SCRIPT_ID .. '_log_y', 'Log Y', 'slider', 0, 900)

    set_value(ui.margin, 12)
    set_value(ui.bind_x, 18)
    set_value(ui.bind_y, 180)
    set_value(ui.bind_w, 178)
    set_value(ui.ind_x, -42)
    set_value(ui.ind_y, 38)
    set_value(ui.log_x, 18)
    set_value(ui.log_y, 430)

    layout:Add(ui.margin_row)
    layout:Add(ui.bind_x_row)
    layout:Add(ui.bind_y_row)
    layout:Add(ui.bind_w_row)
    layout:Add(ui.ind_x_row)
    layout:Add(ui.ind_y_row)
    layout:Add(ui.log_x_row)
    layout:Add(ui.log_y_row)
    layout:Reset()
end

add_controls()

events.presentQueue:Add(on_present)
events.event:Add(on_event)

add_log('skeet hud core loaded', colors().accent)

function __shutdown()
    print('skeet hud core unloaded')
end
