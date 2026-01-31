--[[
    mpv360.lua - Interactive 360° Video Viewer for mpv

    This script enables interactive viewing of 360° videos in mpv media player.
    It supports multiple projection formats (equirectangular, dual fisheye,
    dual half-equirectangular, half-equirectangular, cylindrical, Equi-Angular Cubemap)
    with full camera control through mouse and keyboard inputs.

    Installation:
    1. Place the files in the mpv config directory:
       - Linux/macOS: ~/.config/mpv/
       - Windows: %APPDATA%/mpv/
    2. Configure keybindings in mpv360.conf (optional)

    Configuration:
    By default, the script doesn't bind any keys. Only script messages are bound.
    To enable keybindings, use default configuration or customize it.
    You can use input.conf to bind keys, look at commands table in script for
    available commands.
    Example:
    ```
    Ctrl+r script-binding mpv360/reset-view
    ```

    Usage:
    - Press configured toggle key to enable/disable 360° mode
    - Ctrl+Click to enable mouse look, ESC or Ctrl+Click to exit
    - Use configured keys for camera control and projection switching
    - For SBS output, select `Both` eye (Ctrl+E to switch eye).

    Author: Kacper Michajłow <kasper93@gmail.com>
    Version: 1.3
    License: MIT
--]]

local mp = require "mp"
local options = require "mp.options"

local config = {
    -- Initial camera orientation (in radians)
    yaw = 0.0,                          -- Horizontal rotation (-π to π]
    pitch = 0.0,                        -- Vertical rotation (-π/2 to π/2)
    roll = 0.0,                         -- Camera tilt (-π to π)
    fov = math.rad(120),                -- Field of view (0 to π)

    input_projection = 0,               -- 0=equirectangular, 1=dual_fisheye,
                                        -- 2=dual_hequirectangular, 3=hequirectangular
    eye = 0,                            -- 0=left, 1=right (for dual formats)
    fisheye_fov = math.rad(180),        -- fisheye fov (0 to 2π]
    sampling = 0,                       -- 0=linear, 1=mitchell, 2=lanczos

    shader_path = mp.command_native({"expand-path", "~~/shaders/mpv360.glsl"}),

    invert_mouse = false,               -- Invert mouse movement
    mouse_sensitivity = math.rad(0.2),  -- Mouse look sensitivity

    invert_keyboard = false,            -- Invert keyboard controls
    step = math.rad(0.75),              -- Step for keyboard controls
    fisheye_fov_step = math.rad(10),    -- Step for fisheye FOV adjustment

    enabled = false,                    -- Start with 360° mode enabled
    show_values = true,                 -- Show camera orientation on change
}

local commands
local initial_pos
local mouse_look_active
local last_mouse_pos
local cursor_autohide
local osc_visibility
local keepaspect

local projection_names = {
    [0] = "Equirectangular",
    [1] = "Dual Fisheye",
    [2] = "Dual Half-Equirectangular",
    [3] = "Half-Equirectangular",
    [4] = "Dual Equirectangular (Vert)",
    [5] = "Cylindrical",
    [6] = "Equi-Angular Cubemap",
    [7] = "Dual Equi-Angular Cubemap",
}

local eye_names = {
    [0] = "Left",
    [1] = "Right",
    [2] = "Both",
}

local sampling_names = {
    [0] = "Linear",
    [1] = "Mitchell",
    [2] = "Lanczos",
}

local eps = 1e-6
local animation_interval = 1/60
local animations = {
    fov = {
        timer = nil,
        step = math.rad(0.25)
    },
    fisheye_fov = {
        timer = nil,
        step = math.rad(3.33)
    }
}

local is_dual_eye = function()
    return config.input_projection == 1 or
           config.input_projection == 2 or
           config.input_projection == 4 or
           config.input_projection == 7
end

local is_fisheye = function()
    return config.input_projection == 1
end

local function show_values()
    if not config.show_values then
        return
    end
    local eye = is_dual_eye() and " | Eye: " .. eye_names[config.eye] or ""
    local fisheye_fov = is_fisheye()
                        and string.format(" | Fisheye FOV: %.0f°", math.deg(config.fisheye_fov))
                        or ""
    local info = string.format(
        "Proj: %s" ..  fisheye_fov .. eye .. " | Sampling: %s\n" ..
        "Yaw: %.1f° | Pitch: %.1f° | Roll: %.1f° | FOV: %.1f°",
        projection_names[config.input_projection] or "N/A",
        sampling_names[config.sampling] or "N/A",
        math.deg(config.yaw), math.deg(config.pitch), math.deg(config.roll),
        math.deg(config.fov)
    )
    mp.osd_message(info)
end

local function clamp(value, min, max)
    return math.min(math.max(value, min), max)
end

local function update_params()
    local function normalize(angle)
        while angle > math.pi do
            angle = angle - 2 * math.pi
        end
        while angle < -math.pi do
            angle = angle + 2 * math.pi
        end
        return angle
    end

    config.roll = clamp(normalize(config.roll), -math.pi + eps, math.pi - eps)
    config.pitch = clamp(config.pitch, -math.pi / 2, math.pi / 2)
    config.yaw = clamp(normalize(config.yaw), -math.pi, math.pi)
    config.fov = clamp(config.fov, eps, math.pi - eps)

    config.input_projection = clamp(config.input_projection, 0, #projection_names)
    config.eye = clamp(config.eye, 0, #eye_names)
    config.fisheye_fov = clamp(config.fisheye_fov, eps, 2 * math.pi)
    config.sampling = clamp(config.sampling, 0, #sampling_names)

    if not config.enabled then
        return
    end

    local params = string.format(
        "mpv360/fov=%f,mpv360/yaw=%f,mpv360/pitch=%f,mpv360/roll=%f," ..
        "mpv360/input_projection=%d,mpv360/fisheye_fov=%f,mpv360/eye=%d,mpv360/sampling=%d",
        config.fov, config.yaw, config.pitch, config.roll,
        config.input_projection, config.fisheye_fov, config.eye, config.sampling
    )
    mp.commandv("no-osd", "change-list", "glsl-shader-opts", "add", params)
    show_values()
end

local function add_key_bindings()
    for cmd, func in pairs(commands) do
        if cmd ~= "toggle" then
            mp.add_forced_key_binding(config[cmd] ~= "" and config[cmd], cmd,
            function ()
                func()
                if cmd ~= "show-help" then
                    update_params()
                end
            end, {repeatable = true})
        end
    end
end

local function remove_key_bindings()
    for cmd in pairs(commands) do
        if cmd ~= "toggle" then
            mp.remove_key_binding(cmd)
        end
    end
end

local function on_mouse_move()
    local mouse_pos = mp.get_property_native("mouse-pos")
    local dx = mouse_pos.x - last_mouse_pos.x
    local dy = mouse_pos.y - last_mouse_pos.y
    last_mouse_pos = mouse_pos

    if config.invert_mouse then
        dx = dx * -1
        dy = dy * -1
    end

    config.yaw = config.yaw + dx * config.mouse_sensitivity
    config.pitch = config.pitch - dy * config.mouse_sensitivity

    update_params()
end

local function stop_mouse_look()
    mouse_look_active = false
    mp.unobserve_property(on_mouse_move)

    if cursor_autohide ~= nil then
        mp.set_property_native("cursor-autohide", cursor_autohide)
        cursor_autohide = nil
    end

    if osc_visibility ~= nil then
        mp.command(string.format("script-message osc-visibility %s no-osd", osc_visibility))
        osc_visibility = nil
    end

    mp.remove_key_binding("_mpv360_esc")
    mp.remove_key_binding("_mpv360_wheel_up")
    mp.remove_key_binding("_mpv360_wheel_down")
end

local function start_mouse_look()
    if not config.enabled or mouse_look_active then
        return
    end

    mouse_look_active = true
    last_mouse_pos = mp.get_property_native("mouse-pos")
    cursor_autohide = mp.get_property_native("cursor-autohide")
    mp.set_property_native("cursor-autohide", "always")
    osc_visibility = mp.get_property_native("user-data/osc/visibility")
    mp.command("script-message osc-visibility never no-osd")
    mp.osd_message("Mouse look enabled. Press ESC or Ctrl+click to exit.")
    mp.observe_property("mouse-pos", "native", on_mouse_move)
    mp.add_forced_key_binding("WHEEL_UP", "_mpv360_wheel_up", function ()
        commands["fov-decrease"]()
        update_params()
    end)
    mp.add_forced_key_binding("WHEEL_DOWN", "_mpv360_wheel_down", function ()
        commands["fov-increase"]()
        update_params()
    end)
    mp.add_forced_key_binding("ESC", "_mpv360_esc", stop_mouse_look)
end

local function animate_fov(fov_type, target)
    local animation = animations[fov_type]
    if animation.timer then
        animation.timer:kill()
    end

    animation.timer = mp.add_periodic_timer(animation_interval, function()
        local diff = target - config[fov_type]

        if math.abs(diff) < animation.step then
            config[fov_type] = target
            update_params()
            animation.timer:kill()
            return
        end

        config[fov_type] = config[fov_type] + (diff > 0 and animation.step or -animation.step)
        update_params()
    end)
end

local function enable()
    stop_mouse_look()

    config.enabled = true
    update_params()
    mp.command("no-osd change-list glsl-shaders append " .. config.shader_path)

    add_key_bindings()

    keepaspect = mp.get_property_native("keepaspect")
    mp.set_property_bool("keepaspect", false)

    local msg = "360° mode enabled - " .. projection_names[config.input_projection]
    if config["show-help"] then
        msg = msg .. " - Press " .. config["show-help"] .. " for help"
    end
    mp.osd_message(msg)
end

local function disable()
    stop_mouse_look()
    remove_key_bindings()

    if keepaspect ~= nil then
        mp.set_property_native("keepaspect", keepaspect)
        keepaspect = nil
    end

    mp.command("no-osd change-list glsl-shaders remove " .. config.shader_path)

    config.enabled = false
end

local function show_help()
    local function get_key(cmd)
        return config[cmd] and config[cmd] ~= "" and config[cmd] or "not set"
    end

    local help = {
        "360° Video Controls",
        "",
        "• Enable mouse look: " .. get_key("toggle-mouse-look"),
        "• Exit mouse look: ESC or " .. get_key("toggle-mouse-look"),
        "• Adjust FOV (in mouse look): Scroll wheel",
        "",
        "• Toggle 360° mode: " .. get_key("toggle"),
        "• Reset view: " .. get_key("reset-view"),
        "• Look up: " .. get_key("look-up"),
        "• Look down: " .. get_key("look-down"),
        "• Look left: " .. get_key("look-left"),
        "• Look right: " .. get_key("look-right"),
        "• Roll left: " .. get_key("roll-left"),
        "• Roll right: " .. get_key("roll-right"),
        "• Increase FOV: " .. get_key("fov-increase"),
        "• Decrease FOV: " .. get_key("fov-decrease"),
        "",
        "• Cycle projection: " .. get_key("cycle-projection"),
        "• Increase Fisheye FOV: " .. get_key("fisheye-fov-increase"),
        "• Decrease Fisheye FOV: " .. get_key("fisheye-fov-decrease"),
        "• Switch eye: " .. get_key("switch-eye"),
        "• Cycle sampling: " .. get_key("cycle-sampling"),
        "",
        "• Toggle mouse look: " .. get_key("toggle-mouse-look"),
        "• Show this help: " .. get_key("show-help"),
    }
    mp.osd_message(table.concat(help, "\n"), 10)
end

commands = {
    ["toggle"] = function () if config.enabled then disable() else enable() end end,
    ["look-up"] = function () config.pitch = config.pitch + config.step end,
    ["look-down"] = function () config.pitch = config.pitch - config.step end,
    ["look-left"] = function () config.yaw = config.yaw - config.step end,
    ["look-right"] = function () config.yaw = config.yaw + config.step end,
    ["roll-left"] = function () config.roll = config.roll - config.step end,
    ["roll-right"] = function () config.roll = config.roll + config.step end,
    ["fov-increase"] = function ()
        target_fov = clamp(config.fov + config.step, eps, math.pi - eps)
        animate_fov("fov", target_fov)
    end,
    ["fov-decrease"] = function ()
        target_fov = clamp(config.fov - config.step, eps, math.pi - eps)
        animate_fov("fov", target_fov)
    end,
    ["toggle-mouse-look"] = function ()
        if mouse_look_active then
            stop_mouse_look()
        else
            start_mouse_look()
        end
    end,
    ["reset-view"] = function ()
        config.yaw = initial_pos.yaw
        config.pitch = initial_pos.pitch
        config.roll = initial_pos.roll
        config.fov = initial_pos.fov
    end,
    ["cycle-projection"] = function ()
        config.input_projection = (config.input_projection + 1) % (#projection_names + 1)
    end,
    ["fisheye-fov-increase"] = function ()
        target_fisheye_fov = clamp(config.fisheye_fov + config.fisheye_fov_step, eps, 2 * math.pi)
        animate_fov("fisheye_fov", target_fisheye_fov)
    end,
    ["fisheye-fov-decrease"] = function ()
        target_fisheye_fov = clamp(config.fisheye_fov - config.fisheye_fov_step, eps, 2 * math.pi)
        animate_fov("fisheye_fov", target_fisheye_fov)
    end,
    ["switch-eye"] = function ()
        if is_dual_eye() then
            config.eye = (config.eye + 1) % (#eye_names + 1)
        else
            mp.msg.warn("Eye selection only available for dual eye formats.")
        end
    end,
    ["cycle-sampling"] = function ()
        config.sampling = (config.sampling + 1) % (#sampling_names + 1)
    end,
    ["show-help"] = show_help,
}

for cmd in pairs(commands) do
    config[cmd] = ""
end

options.read_options(config, "mpv360", update_params)

initial_pos = {
    yaw = config.yaw,
    pitch = config.pitch,
    roll = config.roll,
    fov = config.fov,
}

mp.add_key_binding(config["toggle"], "toggle", commands["toggle"], {repeatable = true})

if config.enabled then
    enable()
end
