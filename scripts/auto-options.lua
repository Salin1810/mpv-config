-- Set options dynamically.
-- Upon start, `determine_level()` will select a level (hq/mq/lq)
-- whose options will then be applied.
--
-- General mpv options can be defined in the `options` table while VO
-- sub-options are to be defined in `vo_opts`.
--
-- One probably has to reimplement `determine_level()` since it's pretty OS and
-- user specific.
--
-- Note: this requires `force-window=no`, otherwise it's already too late for
-- some (VO) options to be set/changed.

if mp.get_property_bool("option-info/vo/set-from-commandline") then
    return
end

local options = require 'mp.options'
local utils = require 'mp.utils'

local o = {
    hq = "high",
    mq = "mid",
    lq = "low",
    verbose = false,
}
options.read_options(o)

local vo = {}
local vo_opts = {}
local options = {}


function determine_level()
    -- default level
    local level = o.mq

    -- call an external bash function determining if this is a desktop or mobile computer
    loc = {}
    loc.args = {"bash", "-c", 'source "$HOME"/local/shell/location-detection && is-desktop'}
    loc_ret = utils.subprocess(loc)

    -- something went wrong
    if loc_ret.error then
        return level
    end

    -- desktop -> hq
    if loc_ret.status == 0 then
        level = o.hq
    -- mobile  -> mq/lq
    elseif loc_ret.status == 1 then
        level = o.mq
        -- go down to lq when we are on battery
        bat = {}
        bat.args = {"/usr/bin/pmset", "-g", "ac"}
        bat_ret = utils.subprocess(bat)
        if bat_ret.stdout == "No adapter attached.\n" then
            level = o.lq
        end
    elseif o.verbose then
        print("unable to determine location, using default level: " .. level)
    end

    return level
end


function vo_property_string(level)
    -- use `vo` and `vo_opts` to build a `vo=key1=val1:key2=val2:key3=val3` string
    local result = {}
    for k, v in pairs(vo_opts[level]) do
        if v and v ~= "" then
            table.insert(result, k .. "=" ..v)
        else
            table.insert(result, k)
        end
    end
    return vo[level] .. (next(result) == nil and "" or (":" .. table.concat(result, ":")))
end


-- Define VO sub-options for different levels.

vo = {
    [o.hq] = "opengl-hq",
    [o.mq] = "opengl-hq",
    [o.lq] = "opengl",
}

vo_opts[o.hq] = {
    ["scale"]  = "ewa_lanczossharp",
    ["cscale"] = "ewa_lanczossoft",
    ["dscale"] = "mitchell",
    ["tscale"] = "oversample",
    ["scale-antiring"]  = "0.8",
    ["cscale-antiring"] = "0.9",

    ["dither-depth"]        = "auto",
    ["target-prim"]         = "bt.709",
    ["gamma"]               = "0.9338",
    ["scaler-resizes-only"] = "",
    ["sigmoid-upscaling"]   = "",

    ["fancy-downscaling"] = "",
    ["source-shader"]     = "~~/shaders/deband.glsl",
    ["icc-cache-dir"]     = "~~/icc-cache",
    ["3dlut-size"]        = "256x256x256",
    ["temporal-dither"]   = "",
    ["pbo"] = "",
}

vo_opts[o.mq] = {
    ["scale"]  = "spline36",
    ["cscale"] = "spline36",
    ["dscale"] = "mitchell",
    ["tscale"] = "oversample",
    ["scale-antiring"]  = "0.8",
    ["cscale-antiring"] = "0.9",

    ["dither-depth"]        = "auto",
    ["target-prim"]         = "bt.709",
    ["gamma"]               = "0.9338",
    ["scaler-resizes-only"] = "",
    ["sigmoid-upscaling"]   = "",

    ["fancy-downscaling"] = "",
    ["source-shader"]     = "~~/shaders/deband.glsl",
}

vo_opts[o.lq] = {
    ["scale"]  = "lanczos",
    ["dscale"] = "mitchell",
    ["tscale"] = "oversample",
    ["scale-radius"] = "2",

    ["dither-depth"]        = "auto",
    ["target-prim"]         = "bt.709",
    ["gamma"]               = "0.9338",
    ["scaler-resizes-only"] = "",
    ["sigmoid-upscaling"]   = "",
}


-- Define mpv options for different levels.
-- Option names are given as strings, values as functions without parameters.

options[o.hq] = {
    ["options/vo"] = function () return vo_property_string(o.hq) end,
}

options[o.mq] = {
    ["options/vo"] = function () return vo_property_string(o.mq) end,
}

options[o.lq] = {
    ["options/vo"] = function () return vo_property_string(o.lq) end,
    ["options/hwdec"] = function () return "auto" end,
}


-- Set all defined options for the determined level.

local level = determine_level()
local err_occ = false
for k, v in pairs(options[level]) do
    local val = v()
    success, err = mp.set_property(k, val)
    err_occ = err_occ or not (err_occ or success)
    if success and o.verbose then
        print("Set '" .. k .. "' to '" .. val .. "'")
    elseif o.verbose then
        print("Failed to set '" .. k .. "' to '" .. val .. "'")
        print(err)
    end
end


function print_status(name, value)
    if not value then
        return
    end

    local duration = 4
    if err_occ then
        print("Error setting level: " .. level)
        mp.osd_message("Error setting level: " .. level, duration)
    else
        print("Active level: " .. level)
        mp.osd_message("Level: " .. level, duration)
    end
    mp.unobserve_property(print_status)
end

mp.observe_property("vo-configured", "bool", print_status)