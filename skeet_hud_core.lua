-- skeet_hud_core.lua
-- Fatality Lua HUD: watermark, keybind list, indicators and event log.

local SCRIPT_ID = 'skeet_hud_core'

local ui = {}
local state = {
    logs = {},
    hit_logs = {},
    hit_markers = {},
    combo = 0,
    combo_until = 0,
    fps = 0,
    last_frame = draw.GetTime(),
    drag = nil,
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

local function point_in_rect(p, x, y, w, h)
    return p and p.x >= x and p.x <= x + w and p.y >= y and p.y <= y + h
end

local function text_w(text)
    return #tostring(text) * 7
end

local function ease_out(t)
    t = clamp(t, 0, 1)
    return 1 - (1 - t) * (1 - t)
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

local hitgroups = {
    [0] = 'generic',
    [1] = 'head',
    [2] = 'chest',
    [3] = 'stomach',
    [4] = 'left arm',
    [5] = 'right arm',
    [6] = 'left leg',
    [7] = 'right leg',
    [8] = 'neck',
}

local function player_name(controller)
    return safe(function()
        local name = controller:GetName()
        if name and name ~= '' then return name end
        return 'unknown'
    end, 'unknown')
end

local function is_local_controller(controller)
    local local_controller = safe(function() return entities.GetLocalController() end, nil)
    if not controller or not local_controller then return false end
    if controller == local_controller then return true end
    return player_name(controller) == player_name(local_controller)
end

local function add_hit_log(event, c)
    if not get_bool(ui.hitlogs, true) then return end

    local now = draw.GetTime()
    local attacker = safe(function() return event:GetController('attacker') end, nil)
    if not is_local_controller(attacker) then return end

    local victim = safe(function() return event:GetController('userid') end, nil)
    local victim_name = player_name(victim)
    local damage = safe(function() return event:GetInt('dmg_health') end, 0)
    local remaining = safe(function() return event:GetInt('health') end, 0)
    local hitgroup = safe(function() return event:GetInt('hitgroup') end, 0)
    local group = hitgroups[hitgroup] or 'body'
    local limit = get_num(ui.hitlog_limit, 6)

    local hit_col = c.accent
    if remaining <= 0 then
        hit_col = c.success
    elseif hitgroup == 1 or damage >= 90 then
        hit_col = c.warn
    end

    if now <= state.combo_until then
        state.combo = state.combo + 1
    else
        state.combo = 1
    end
    state.combo_until = now + 1.25

    table.insert(state.hit_logs, 1, {
        victim = victim_name,
        group = group,
        damage = damage,
        remaining = remaining,
        born = now,
        life = 5.0,
        col = hit_col,
        head = hitgroup == 1,
        kill = remaining <= 0,
        combo = state.combo,
    })

    table.insert(state.hit_markers, 1, {
        damage = damage,
        group = group,
        born = now,
        life = 1.15,
        col = hit_col,
        head = hitgroup == 1,
        kill = remaining <= 0,
        combo = state.combo,
    })

    while #state.hit_logs > limit do
        table.remove(state.hit_logs)
    end

    while #state.hit_markers > 8 do
        table.remove(state.hit_markers)
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

local function draw_tag(layer, x, y, text, col, alpha)
    local w = text_w(text) + 10
    layer:AddRectFilled(draw.Rect(x, y, x + w, y + 14), col:ModA(0.18 * alpha))
    layer:AddRect(draw.Rect(x, y, x + w, y + 14), col:ModA(0.55 * alpha), 1.0)
    layer:AddText(draw.Vec2(x + 5, y + 2), text, col:ModA(alpha))
    return w
end

local screen_size

local function drag_panel(id, x, y, w, h, x_control, y_control)
    if not gui.IsVisible() or not get_bool(ui.drag_panels, true) then
        if state.drag and state.drag.id == id then state.drag = nil end
        return x, y
    end

    local cur = safe(function() return gui.input:Cursor() end, nil)
    local down = safe(function() return gui.input:IsMouseDown(gui.MouseButton.LEFT) end, false)
    local clicked = safe(function() return gui.input:IsMouseClicked(gui.MouseButton.LEFT) end, false)
    local released = safe(function() return gui.input:IsMouseReleased(gui.MouseButton.LEFT) end, false)

    if released or not down then
        if state.drag and state.drag.id == id then state.drag = nil end
    end

    local header_h = math.min(24, h)
    if clicked and not state.drag and point_in_rect(cur, x, y, w, header_h) then
        state.drag = {
            id = id,
            dx = cur.x - x,
            dy = cur.y - y,
        }
    end

    if state.drag and state.drag.id == id and down and cur then
        local sw, sh = screen_size()
        local nx = clamp(cur.x - state.drag.dx, 0, math.max(0, sw - w))
        local ny = clamp(cur.y - state.drag.dy, 0, math.max(0, sh - h))
        set_value(x_control, math.floor(nx + 0.5))
        set_value(y_control, math.floor(ny + 0.5))
        return nx, ny
    end

    return x, y
end

local function drag_hint(layer, x, y, w, h, c)
    if gui.IsVisible() and get_bool(ui.drag_panels, true) then
        layer:AddRect(draw.Rect(x, y, x + w, y + h), c.accent:ModA(0.42), 1.0)
        layer:AddText(draw.Vec2(x + w - 37, y + 5), 'drag', c.muted:ModA(0.75))
    end
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

function screen_size()
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
    local now = draw.GetTime()
    local ping = latency_ms()
    local title = 'fatality.lua'
    local subtitle = 'skeet hud'
    local fps = tostring(math.floor(state.fps + 0.5)) .. ' fps'
    local ms = tostring(ping) .. ' ms'
    local width = text_w(title) + text_w(subtitle) + text_w(fps) + text_w(ms) + 78
    local height = 28
    local default_x = w - width - get_num(ui.margin, 12)
    local x = get_num(ui.watermark_x, default_x)
    local y = get_num(ui.watermark_y, get_num(ui.margin, 12))

    if x <= 0 then x = default_x end
    x, y = drag_panel('watermark', x, y, width, height, ui.watermark_x, ui.watermark_y)

    panel(layer, x, y, width, height, c)
    layer:AddRectFilled(draw.Rect(x + 5, y + 5, x + 21, y + 21), c.accent:ModA(0.22))
    layer:AddRect(draw.Rect(x + 5, y + 5, x + 21, y + 21), c.accent:ModA(0.68), 1.0)
    layer:AddLine(draw.Vec2(x + 9, y + 14), draw.Vec2(x + 17, y + 14), c.accent, 1.0)
    layer:AddLine(draw.Vec2(x + 13, y + 10), draw.Vec2(x + 13, y + 18), c.accent, 1.0)

    layer.font = draw.fonts['gui_bold']
    layer:AddText(draw.Vec2(x + 27, y + 5), title, c.text)
    layer.font = draw.fonts['gui_main']

    local sx = x + 31 + text_w(title)
    layer:AddText(draw.Vec2(sx, y + 5), subtitle, c.muted)
    sx = sx + text_w(subtitle) + 12
    draw_tag(layer, sx, y + 7, fps, c.success, 0.9)
    sx = sx + text_w(fps) + 20
    draw_tag(layer, sx, y + 7, ms, ping > 80 and c.warn or c.accent, 0.9)

    local scan = (now * 95) % math.max(width - 18, 1)
    layer:AddLineMulticolor(
        draw.Vec2(x + 8 + scan, y + height - 2),
        draw.Vec2(math.min(x + 8 + scan + 42, x + width - 8), y + height - 2),
        c.accent:ModA(0.1),
        c.accent:ModA(0.95),
        1.0
    )
    drag_hint(layer, x, y, width, height, c)
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
    local preview = gui.IsVisible() and get_bool(ui.preview, true)
    if #binds == 0 and not preview then return end

    local x = get_num(ui.bind_x, 18)
    local y = get_num(ui.bind_y, 180)
    local width = get_num(ui.bind_w, 178)
    local rows = math.max(#binds, preview and 2 or 0)
    local height = 22 + rows * 18 + 4
    x, y = drag_panel('keybinds', x, y, width, height, ui.bind_x, ui.bind_y)

    panel(layer, x, y, width, height, c)
    layer:AddText(draw.Vec2(x + 7, y + 5), 'keybinds', c.text)

    if #binds == 0 then
        draw_row(layer, x + 1, y + 23, width - 2, 'menu preview', 'hold', 0.72, c)
        draw_row(layer, x + 1, y + 41, width - 2, 'damage override', 'toggle', 0.58, c)
        drag_hint(layer, x, y, width, height, c)
        return
    end

    for i, bind in ipairs(binds) do
        draw_row(layer, x + 1, y + 23 + (i - 1) * 18, width - 2, bind.label, bind.value, 1, c)
    end
    drag_hint(layer, x, y, width, height, c)
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
    local preview = gui.IsVisible() and get_bool(ui.preview, true)
    local rows = state.logs

    for i = #state.logs, 1, -1 do
        local log = state.logs[i]
        if now - log.born > log.life then
            table.remove(state.logs, i)
        else
            max_w = math.max(max_w, text_w(log.text) + 24)
        end
    end

    if #state.logs == 0 and preview then
        rows = {
            { text = 'round started', col = c.success, born = now, life = 1 },
            { text = 'bomb planted', col = c.warn, born = now, life = 1 },
            { text = 'skeet hud preview', col = c.accent, born = now, life = 1 },
        }
        max_w = 210
    elseif #state.logs == 0 then
        return
    end

    local width = math.max(max_w, 210)
    local height = 24 + #rows * 18
    x, y = drag_panel('logs', x, y, width, height, ui.log_x, ui.log_y)
    panel(layer, x, y, width, height, c)
    layer:AddText(draw.Vec2(x + 7, y + 5), 'event log', c.text)

    for i, log in ipairs(rows) do
        local age = now - log.born
        local alpha = preview and 0.88 or clamp(math.min(age / 0.18, (log.life - age) / 0.45), 0, 1)
        local yy = y + 23 + (i - 1) * 18
        layer:AddRectFilled(draw.Rect(x + 1, yy, x + width - 1, yy + 18), c.panel:ModA(alpha))
        layer:AddText(draw.Vec2(x + 7, yy + 3), '[lua]', log.col:ModA(alpha))
        layer:AddText(draw.Vec2(x + 43, yy + 3), log.text, c.text:ModA(alpha))
    end
    drag_hint(layer, x, y, width, height, c)
end

local function hit_logs(layer, c)
    if not get_bool(ui.hitlogs, true) then return end

    local now = draw.GetTime()
    local x = get_num(ui.hitlog_x, 18)
    local y = get_num(ui.hitlog_y, 330)
    local max_w = 0
    local preview = gui.IsVisible() and get_bool(ui.preview, true)
    local rows = state.hit_logs

    for i = #state.hit_logs, 1, -1 do
        local log = state.hit_logs[i]
        if now - log.born > log.life then
            table.remove(state.hit_logs, i)
        else
            local line = string.format('hit %s in %s', log.victim, log.group)
            max_w = math.max(max_w, text_w(line) + 118)
        end
    end

    if #state.hit_logs == 0 and preview then
        rows = {
            { victim = 'enemy_01', group = 'head', damage = 92, remaining = 0, born = now - 0.12, life = 1, col = c.success, head = true, kill = true, combo = 3 },
            { victim = 'mirage enjoyer', group = 'stomach', damage = 48, remaining = 52, born = now - 0.28, life = 1, col = c.accent, head = false, kill = false, combo = 2 },
            { victim = 'player', group = 'chest', damage = 27, remaining = 73, born = now - 0.44, life = 1, col = c.accent, head = false, kill = false, combo = 1 },
        }
        max_w = 330
    elseif #state.hit_logs == 0 then
        return
    end

    local width = math.max(max_w, 260)
    local height = 24 + #rows * 20
    x, y = drag_panel('hitlogs', x, y, width, height, ui.hitlog_x, ui.hitlog_y)
    panel(layer, x, y, width, height, c)
    layer:AddText(draw.Vec2(x + 7, y + 5), 'hit logs', c.text)

    for i, log in ipairs(rows) do
        local age = now - log.born
        local alpha = preview and 0.92 or clamp(math.min(age / 0.16, (log.life - age) / 0.55), 0, 1)
        local slide = preview and 0 or (1 - alpha) * 18
        local yy = y + 23 + (i - 1) * 20
        local damage = tostring(log.damage) .. ' dmg'
        local remaining = tostring(math.max(log.remaining, 0)) .. ' hp'
        local left = string.format('hit %s in %s', log.victim, log.group)
        local right_w = text_w(damage) + text_w(remaining) + 22
        local rx = x - slide
        local tag_x = rx + 8

        layer:AddRectFilled(draw.Rect(rx + 1, yy, rx + width - 1, yy + 20), c.panel:ModA(alpha))
        layer:AddRectFilled(draw.Rect(rx + 1, yy, rx + 4, yy + 20), log.col:ModA(alpha))
        layer:AddLine(draw.Vec2(rx + 5, yy + 19), draw.Vec2(rx + 5 + (width - 10) * alpha, yy + 19), log.col:ModA(alpha * 0.65), 1.0)

        if log.kill then
            tag_x = tag_x + draw_tag(layer, tag_x, yy + 3, 'KILL', c.success, alpha) + 4
        elseif log.head then
            tag_x = tag_x + draw_tag(layer, tag_x, yy + 3, 'HEAD', c.warn, alpha) + 4
        end

        if log.combo and log.combo > 1 then
            tag_x = tag_x + draw_tag(layer, tag_x, yy + 3, 'x' .. tostring(log.combo), c.accent, alpha) + 4
        end

        layer:AddText(draw.Vec2(tag_x, yy + 4), left, c.text:ModA(alpha))
        layer:AddText(draw.Vec2(rx + width - right_w, yy + 4), damage, log.col:ModA(alpha))
        layer:AddText(draw.Vec2(rx + width - text_w(remaining) - 12, yy + 4), remaining, c.muted:ModA(alpha))
    end
    drag_hint(layer, x, y, width, height, c)
end

local function hit_markers(layer, c)
    if not get_bool(ui.hitmarkers, true) then return end

    local now = draw.GetTime()
    local sw, sh = screen_size()
    local cx = math.floor(sw * 0.5)
    local cy = math.floor(sh * 0.5) + get_num(ui.marker_y, -54)
    local preview = gui.IsVisible() and get_bool(ui.preview, true)
    local rows = state.hit_markers

    for i = #state.hit_markers, 1, -1 do
        local marker = state.hit_markers[i]
        if now - marker.born > marker.life then
            table.remove(state.hit_markers, i)
        end
    end

    if #state.hit_markers == 0 and preview then
        rows = {
            { damage = 92, group = 'head', born = now - 0.18, life = 1, col = c.success, head = true, kill = true, combo = 3 },
        }
    elseif #state.hit_markers == 0 then
        return
    end

    for i, marker in ipairs(rows) do
        local age = now - marker.born
        local t = preview and 0.35 or clamp(age / marker.life, 0, 1)
        local alpha = preview and 0.9 or clamp(math.min(age / 0.1, (marker.life - age) / 0.34), 0, 1)
        local rise = ease_out(t) * 34
        local label = tostring(marker.damage)

        if marker.kill then
            label = label .. ' KILL'
        elseif marker.head then
            label = label .. ' HEAD'
        end

        if marker.combo and marker.combo > 1 then
            label = label .. ' x' .. tostring(marker.combo)
        end

        local width = text_w(label) + 16
        local x = cx - width * 0.5
        local y = cy - rise - (i - 1) * 14

        layer:AddShadowRect(draw.Rect(x, y, x + width, y + 18), 8, true, 0.18 * alpha)
        layer:AddRectFilled(draw.Rect(x, y, x + width, y + 18), c.bg:ModA(0.68 * alpha))
        layer:AddRect(draw.Rect(x, y, x + width, y + 18), marker.col:ModA(0.55 * alpha), 1.0)
        layer:AddText(draw.Vec2(x + 8, y + 3), label, marker.col:ModA(alpha))
    end
end

local function on_event(event)
    local name = event:GetName()
    local c = colors()

    if name == 'player_hurt' then
        add_hit_log(event, c)
    elseif not get_bool(ui.logs, true) then
        return
    elseif name == 'round_start' then
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
    hit_markers(layer, c)
    hit_logs(layer, c)
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

    local main = gui.Group(SCRIPT_ID .. '_main', 'Main', 350, gui.GroupWidthMode.FULL)
    local layout = gui.Group(SCRIPT_ID .. '_layout', 'Layout', 470, gui.GroupWidthMode.FULL)

    parent:Add(main)
    parent:Add(layout)

    ui.watermark, ui.watermark_row = gui.MakeControlEasy(SCRIPT_ID .. '_watermark', 'Watermark', 'checkbox')
    ui.keybinds, ui.keybinds_row = gui.MakeControlEasy(SCRIPT_ID .. '_keybinds', 'Keybind list', 'checkbox')
    ui.indicators, ui.indicators_row = gui.MakeControlEasy(SCRIPT_ID .. '_indicators', 'Indicators', 'checkbox')
    ui.hitlogs, ui.hitlogs_row = gui.MakeControlEasy(SCRIPT_ID .. '_hitlogs', 'Hit logs', 'checkbox')
    ui.hitmarkers, ui.hitmarkers_row = gui.MakeControlEasy(SCRIPT_ID .. '_hitmarkers', 'Hit markers', 'checkbox')
    ui.logs, ui.logs_row = gui.MakeControlEasy(SCRIPT_ID .. '_logs', 'Event log', 'checkbox')
    ui.drag_panels, ui.drag_panels_row = gui.MakeControlEasy(SCRIPT_ID .. '_drag_panels', 'Draggable panels', 'checkbox')
    ui.preview, ui.preview_row = gui.MakeControlEasy(SCRIPT_ID .. '_preview', 'Menu preview', 'checkbox')
    ui.accent, ui.accent_row = gui.MakeControlEasy(SCRIPT_ID .. '_accent', 'Accent', 'color_picker', true)
    ui.hitlog_limit, ui.hitlog_limit_row = gui.MakeControlEasy(SCRIPT_ID .. '_hitlog_limit', 'Hit log limit', 'slider', 2, 10)
    ui.log_limit, ui.log_limit_row = gui.MakeControlEasy(SCRIPT_ID .. '_log_limit', 'Log limit', 'slider', 2, 10)

    ui.watermark:SetValue(true)
    ui.keybinds:SetValue(true)
    ui.indicators:SetValue(true)
    ui.hitlogs:SetValue(true)
    ui.hitmarkers:SetValue(true)
    ui.logs:SetValue(true)
    ui.drag_panels:SetValue(true)
    ui.preview:SetValue(true)
    set_value(ui.accent, color(145, 210, 80))
    set_value(ui.hitlog_limit, 6)
    set_value(ui.log_limit, 6)

    main:Add(ui.watermark_row)
    main:Add(ui.keybinds_row)
    main:Add(ui.indicators_row)
    main:Add(ui.hitlogs_row)
    main:Add(ui.hitmarkers_row)
    main:Add(ui.logs_row)
    main:Add(ui.drag_panels_row)
    main:Add(ui.preview_row)
    main:Add(ui.accent_row)
    main:Add(ui.hitlog_limit_row)
    main:Add(ui.log_limit_row)
    main:Reset()

    ui.margin, ui.margin_row = gui.MakeControlEasy(SCRIPT_ID .. '_margin', 'Screen margin', 'slider', 4, 40)
    ui.watermark_x, ui.watermark_x_row = gui.MakeControlEasy(SCRIPT_ID .. '_watermark_x', 'Watermark X', 'slider', 0, 2200)
    ui.watermark_y, ui.watermark_y_row = gui.MakeControlEasy(SCRIPT_ID .. '_watermark_y', 'Watermark Y', 'slider', 0, 1200)
    ui.bind_x, ui.bind_x_row = gui.MakeControlEasy(SCRIPT_ID .. '_bind_x', 'Binds X', 'slider', 0, 2200)
    ui.bind_y, ui.bind_y_row = gui.MakeControlEasy(SCRIPT_ID .. '_bind_y', 'Binds Y', 'slider', 0, 900)
    ui.bind_w, ui.bind_w_row = gui.MakeControlEasy(SCRIPT_ID .. '_bind_w', 'Binds width', 'slider', 130, 280)
    ui.ind_x, ui.ind_x_row = gui.MakeControlEasy(SCRIPT_ID .. '_ind_x', 'Indicators X', 'slider', -300, 300)
    ui.ind_y, ui.ind_y_row = gui.MakeControlEasy(SCRIPT_ID .. '_ind_y', 'Indicators Y', 'slider', -200, 300)
    ui.marker_y, ui.marker_y_row = gui.MakeControlEasy(SCRIPT_ID .. '_marker_y', 'Hit marker Y', 'slider', -180, 120)
    ui.hitlog_x, ui.hitlog_x_row = gui.MakeControlEasy(SCRIPT_ID .. '_hitlog_x', 'Hit logs X', 'slider', 0, 2200)
    ui.hitlog_y, ui.hitlog_y_row = gui.MakeControlEasy(SCRIPT_ID .. '_hitlog_y', 'Hit logs Y', 'slider', 0, 900)
    ui.log_x, ui.log_x_row = gui.MakeControlEasy(SCRIPT_ID .. '_log_x', 'Log X', 'slider', 0, 2200)
    ui.log_y, ui.log_y_row = gui.MakeControlEasy(SCRIPT_ID .. '_log_y', 'Log Y', 'slider', 0, 900)

    local sw, _ = screen_size()
    set_value(ui.watermark_x, math.max(sw - 360, 0))
    set_value(ui.watermark_y, 12)
    set_value(ui.margin, 12)
    set_value(ui.bind_x, 18)
    set_value(ui.bind_y, 180)
    set_value(ui.bind_w, 178)
    set_value(ui.ind_x, -42)
    set_value(ui.ind_y, 38)
    set_value(ui.marker_y, -54)
    set_value(ui.hitlog_x, 18)
    set_value(ui.hitlog_y, 330)
    set_value(ui.log_x, 18)
    set_value(ui.log_y, 430)

    layout:Add(ui.margin_row)
    layout:Add(ui.watermark_x_row)
    layout:Add(ui.watermark_y_row)
    layout:Add(ui.bind_x_row)
    layout:Add(ui.bind_y_row)
    layout:Add(ui.bind_w_row)
    layout:Add(ui.ind_x_row)
    layout:Add(ui.ind_y_row)
    layout:Add(ui.marker_y_row)
    layout:Add(ui.hitlog_x_row)
    layout:Add(ui.hitlog_y_row)
    layout:Add(ui.log_x_row)
    layout:Add(ui.log_y_row)
    layout:Reset()
end

add_controls()

pcall(function() mods.events:AddListener('player_hurt') end)

events.presentQueue:Add(on_present)
events.event:Add(on_event)

add_log('skeet hud core loaded', colors().accent)

function __shutdown()
    print('skeet hud core unloaded')
end
