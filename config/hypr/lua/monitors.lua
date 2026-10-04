-- Re-apply the last layout on every lua parse/reload.
-- A reload clears eval'd hl.monitor rules and would otherwise autoplace
-- every output.

local function config_hypr()
    local xdg = os.getenv("XDG_CONFIG_HOME")
    if xdg and xdg ~= "" then
        return xdg .. "/hypr"
    end
    return (os.getenv("HOME") or "") .. "/.config/hypr"
end

local function state_hypr()
    local xdg = os.getenv("XDG_STATE_HOME")
    if xdg and xdg ~= "" then
        return xdg .. "/hypr"
    end
    return (os.getenv("HOME") or "") .. "/.local/state/hypr"
end

local function read_file(path)
    local fh = io.open(path, "r")
    if not fh then
        return nil
    end
    local text = fh:read("*a")
    fh:close()
    return text
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalize_spec(spec)
    return (spec:gsub("@([%d%.]+)Hz,", "@%1,"))
end

local function split_csv(spec)
    local parts = {}
    for part in (spec .. ","):gmatch("([^,]*),") do
        parts[#parts + 1] = trim(part)
    end
    return parts
end

local function apply_spec(spec)
    spec = normalize_spec(trim(spec))
    if spec == "" then
        return
    end
    local parts = split_csv(spec)
    local name = parts[1] or ""
    local rest = parts[2] or ""
    if rest == "disable" or rest == "disabled" then
        hl.monitor({ output = name, disabled = true })
        return
    end
    local mode = parts[2] or "preferred"
    local position = parts[3] or "auto"
    local scale = parts[4] or "auto"
    local nscale = tonumber(scale)
    hl.monitor({
        output = name,
        disabled = false,
        mode = mode,
        position = position,
        scale = nscale or scale,
    })
end

local function position_x(spec)
    local parts = split_csv(normalize_spec(trim(spec)))
    local pos = parts[3] or "0x0"
    local x = tonumber(pos:match("^(%-?%d+)"))
    return x or 0
end

local function collect_specs(text)
    local enabled = {}
    local disabled = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        line = trim(line:gsub("#.*", ""))
        local spec = line:match("^[Mm]onitor%s*=%s*(.*)$")
        if spec and spec ~= "" then
            spec = normalize_spec(trim(spec))
            local parts = split_csv(spec)
            if (parts[2] or "") == "disable" or (parts[2] or "") == "disabled" then
                disabled[#disabled + 1] = spec
            else
                enabled[#enabled + 1] = spec
            end
        end
    end
    table.sort(enabled, function(a, b)
        return position_x(a) > position_x(b)
    end)
    local ordered = {}
    for _, spec in ipairs(enabled) do
        ordered[#ordered + 1] = spec
    end
    for _, spec in ipairs(disabled) do
        ordered[#ordered + 1] = spec
    end
    return ordered
end

local function apply_runtime_monitors()
    local runtime = state_hypr() .. "/monitors.runtime.conf"
    local fallback = config_hypr() .. "/conf.d/monitors.d/default.conf"
    local text = read_file(runtime) or read_file(fallback)
    if not text then
        return
    end
    for _, spec in ipairs(collect_specs(text)) do
        apply_spec(spec)
    end
end

apply_runtime_monitors()
hl.on("config.reloaded", apply_runtime_monitors)
