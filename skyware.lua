-- skyware.lua
-- Self-contained auto-execute (no workspace file, no hosting). Fresh joins still need a copy
-- in your executor's "autoexec" folder; queue_on_teleport only fires on teleports.
local AUTO_EXECUTE        = true   -- re-run after every teleport
local LOAD_DELAY          = 10     -- seconds to wait before loading (gives the game time to settle)
local LOADER_ON_FIRST_RUN = false  -- show the countdown on your manual execute too

local SRC = [==[
local function notify(msg)
    warn("[Skyware] " .. msg)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", { Title = "Skyware", Text = msg, Duration = 8 })
    end)
end

-- one copy per server; a different server (new JobId) always loads fresh
if getgenv().SkywareLoaded and getgenv().SkywareLoaded == game.JobId and game.JobId ~= "" then
    notify("Already loaded in this server. Set getgenv().SkywareLoaded = nil and re-execute to reload.")
    return
end
getgenv().SkywareLoaded = game.JobId ~= "" and game.JobId or true

if not game:IsLoaded() then game.Loaded:Wait() end

-- leaving this server: clear the flag so the queued run is never blocked
pcall(function()
    game:GetService("Players").LocalPlayer.OnTeleport:Connect(function()
        getgenv().SkywareLoaded = nil
    end)
end)
local ok, err = xpcall(function()

local LOGO = "rbxassetid://121472117628036" -- your logo (circular header/sidebar + toasts + reopen orb)
local ICON = LOGO

getgenv().Config = {
    Enabled = false,
    Holding = false,
    FOVPreview = false,
    HitPart = "Head",
    FOVRadius = 300,
    ShowFOV = false,
    Aimbot = { -- aimbot (separate from silent aim: own FOV circle, own keys, own range)
        Enabled = false,
        Holding = false,
        ShowFOV = false,
        FOVPreview = false,
        FOVRadius = 80,
        Smooth = 1, -- 1 = instant lock, higher = softer
        MaxDist = 300, -- studs; players farther than this are ignored
        HitPart = "Head",
    },
    Visuals = {
        ESP = false,
        ESPColor = Color3.fromRGB(255, 255, 255),
        MaxDistance = 500, -- fixed ESP range, no UI option
        Chams = false,
        ChamsColor = Color3.fromRGB(255, 60, 60),
        ChamsFillAlpha = 0,
        LockedColorOn = false,
        LockedColor = Color3.fromRGB(0, 220, 255),
        TargetLine = false,
        FOVColor = Color3.fromRGB(255, 255, 255),
        FOVThickness = 1,
        FOVFilled = false,
        FOVRainbow = false,
        Crosshair = false,
        CamFOVEnabled = false,
        CameraFOV = 90,
        Fullbright = false,
        Radar = false,
    },
}


local reps = game:GetService("ReplicatedStorage")
local plrs = game:GetService("Players")
local runs = game:GetService("RunService")
local cs = game:GetService("CollectionService")
local lplr = plrs.LocalPlayer
local cam = workspace.CurrentCamera

-- bail quietly in places that don't have the game's modules (lobby, menus)
if not reps:WaitForChild("Modules", 15) then
    getgenv().SkywareLoaded = nil
    notify("Rivals modules not found - join a match/the game place, then execute again.")
    return
end
if not lplr.Character then lplr.CharacterAdded:Wait() end

local U = require(reps.Modules.Utility)
local EL = require(reps.Modules.EnumLibrary)
local GU = require(reps.Modules.GameplayUtility)

local e, gun = pcall(require, lplr.PlayerScripts.Modules.ItemTypes.Gun)
if e and gun and gun.IsFullyAiming then
    gun.IsFullyAiming = function() return true end
end

local C = getgenv().Config
local V = C.Visuals
local console
local lockedEntity -- set every frame while aim is active

local function log(line)
    if console then console:Append(string.format("[%s] %s", os.date("%H:%M:%S"), line)) end
end

local function aimActive() return C.Enabled or C.Holding end

-- World helpers
local Lighting = game:GetService("Lighting")
local originalFOV = cam.FieldOfView
local lightingOriginal = {
    Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime, FogEnd = Lighting.FogEnd,
    GlobalShadows = Lighting.GlobalShadows, Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
}
local fullbrightProps = {
    Brightness = 2, ClockTime = 14, FogEnd = 100000, GlobalShadows = false,
    Ambient = Color3.fromRGB(178, 178, 178), OutdoorAmbient = Color3.fromRGB(178, 178, 178),
}
local function applyFullbright(on)
    for k, v in (on and fullbrightProps or lightingOriginal) do Lighting[k] = v end
end

--==========================================================================
--  SKYWARE GLASS UI
--  Liquid-glass window, all-circular icons/toggles/buttons, TweenService
--  animations everywhere. Replaces Rayfield; exposes the calls the script uses.
--==========================================================================
local UI = (function()
    local TS = game:GetService("TweenService")
    local UIS = game:GetService("UserInputService")
    local HttpService = game:GetService("HttpService")
    local LightingService = game:GetService("Lighting")

    local LOGO_IMAGE = "rbxassetid://121472117628036" -- your logo

    local WHITE = Color3.new(1, 1, 1)
    local TEXT = Color3.fromRGB(255, 255, 255)
    local MUTED = Color3.fromRGB(255, 255, 255)
    local DANGER = Color3.fromRGB(255, 92, 104)

    local THEMES = {
        default = Color3.fromRGB(160, 170, 255),
        cobalt = Color3.fromRGB(70, 140, 255),
        ember = Color3.fromRGB(255, 122, 60),
        amethyst = Color3.fromRGB(176, 112, 255),
        frost = Color3.fromRGB(130, 226, 255),
        rose = Color3.fromRGB(255, 110, 160),
    }
    local accent = THEMES.cobalt

    ----------------------------------------------------------------------
    -- Small helpers
    ----------------------------------------------------------------------
    local function tween(obj, t, props, style, dir)
        local tw = TS:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
        tw:Play()
        return tw
    end

    local function new(class, props, parent)
        local o = Instance.new(class)
        for k, v in pairs(props) do o[k] = v end
        o.Parent = parent
        return o
    end

    local function corner(o, r)
        return new("UICorner", { CornerRadius = r and UDim.new(0, r) or UDim.new(1, 0) }, o)
    end

    local function stroke(o, color, transparency, thickness)
        return new("UIStroke", {
            Color = color, Transparency = transparency, Thickness = thickness or 1,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }, o)
    end

    local function text(parent, props)
        local d = {
            BackgroundTransparency = 1, BorderSizePixel = 0, Font = Enum.Font.GothamMedium,
            TextColor3 = TEXT, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Text = "",
            TextStrokeColor3 = Color3.new(0, 0, 0), TextStrokeTransparency = 0.7,
        }
        for k, v in pairs(props) do d[k] = v end
        return new("TextLabel", d, parent)
    end

    -- Theme: anything bound to the accent re-tints live when the theme changes
    local accentSubs = {}
    local function onAccent(fn)
        accentSubs[#accentSubs + 1] = fn
        fn(accent, true)
    end
    local function bindAccent(obj, prop)
        onAccent(function(c, instant)
            if instant then obj[prop] = c else tween(obj, 0.35, { [prop] = c }) end
        end)
    end

    -- Localization: labels register their key, SetLocale re-texts all of them
    local LOCALES = {
        de = {
            ["Silent Aim"] = "Stille Zielhilfe", ["Enabled"] = "Aktiviert", ["Show FOV"] = "FOV anzeigen",
            ["FOV Radius"] = "FOV-Radius", ["Theme"] = "Design", ["Language"] = "Sprache",
            ["Target"] = "Ziel", ["Tools"] = "Werkzeuge", ["Log"] = "Protokoll",
        },
        fr = {
            ["Silent Aim"] = "Visée silencieuse", ["Enabled"] = "Activé", ["Show FOV"] = "Afficher le FOV",
            ["FOV Radius"] = "Rayon du FOV", ["Hit Part"] = "Zone visée",
            ["Fill Alpha"] = "Opacité du remplissage", ["Theme"] = "Thème", ["Language"] = "Langue",
            ["Toggle UI"] = "Afficher/masquer l'interface", ["Target"] = "Cible", ["Tools"] = "Outils",
            ["Log"] = "Journal", ["Interface"] = "Interface",
        },
        es = {
            ["Silent Aim"] = "Puntería silenciosa", ["Enabled"] = "Activado", ["Show FOV"] = "Mostrar FOV",
            ["FOV Radius"] = "Radio del FOV", ["Hit Part"] = "Zona de impacto",
            ["Fill Alpha"] = "Opacidad del relleno", ["Theme"] = "Tema", ["Language"] = "Idioma",
            ["Toggle UI"] = "Mostrar/ocultar interfaz", ["Target"] = "Objetivo", ["Tools"] = "Herramientas",
            ["Log"] = "Registro", ["Interface"] = "Interfaz",
        },
    }
    local locale = "en"
    local labelRegistry = {}
    local function tr(key)
        local t = LOCALES[locale]
        return (t and t[key]) or key
    end
    local function localized(obj, key)
        obj.Text = tr(key)
        labelRegistry[#labelRegistry + 1] = { obj, key }
    end

    -- Flags (saved/loaded by configs) + autosave hook
    local flags = {}
    local loadingConfig = false
    local autosaveHook = nil
    local function markDirty()
        if autosaveHook and not loadingConfig then autosaveHook() end
    end
    local function registerFlag(name, get, set)
        if name then flags[name] = { get = get, set = set } end
    end

    ----------------------------------------------------------------------
    -- Dragging
    ----------------------------------------------------------------------
    local function makeDraggable(handle, target)
        local dragging, startMouse, startPos = false, nil, nil
        handle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                startMouse = input.Position
                startPos = target.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then dragging = false end
                end)
            end
        end)
        UIS.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
                local d = input.Position - startMouse
                tween(target, 0.08, {
                    Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                        startPos.Y.Scale, startPos.Y.Offset + d.Y),
                }, Enum.EasingStyle.Sine)
            end
        end)
    end


    ----------------------------------------------------------------------
    -- Vector icon set (built from frames, no assets, no emoji)
    -- Every icon is drawn in a 0..1 box, strokes scale with the button.
    ----------------------------------------------------------------------
    local ICON_ALIAS = {
        ["◎"] = "aim", ["◉"] = "eye", ["⚙"] = "sliders", ["✕"] = "close", ["✓"] = "check",
        ["↺"] = "reset", ["↻"] = "refresh", ["≡"] = "list", ["↓"] = "download", ["↑"] = "upload",
        ["‹"] = "prev", ["›"] = "next", ["•"] = "dot",
        aim = "aim", eye = "eye", sliders = "sliders", gear = "sliders", close = "close", check = "check",
        reset = "reset", refresh = "refresh", list = "list", download = "download", upload = "upload",
        prev = "prev", next = "next", dot = "dot",
    }
    local ICON_COLOR = Color3.fromRGB(236, 241, 255)

    -- fires once, the first time the window is shown (entrance animations wait for it)
    local opened = false
    local openSignal = Instance.new("BindableEvent")

    local function buildIcon(parent, kind, size)
        local S = math.floor(size * 0.52)
        local T = math.max(2, math.floor(S * 0.11 + 0.5)) -- stroke thickness in px
        local holder = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(S, S), BackgroundTransparency = 1, BorderSizePixel = 0,
        }, parent)
        local fills, strokes = {}, {}
        local api = { holder = holder }

        local function ring(cx, cy, d, thick, filled)
            local f = new("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(cx, cy), Size = UDim2.fromScale(d, d),
                BackgroundColor3 = ICON_COLOR, BackgroundTransparency = filled and 0 or 1, BorderSizePixel = 0,
            }, holder)
            corner(f)
            if filled then
                fills[#fills + 1] = f
            else
                local s = new("UIStroke", {
                    Color = ICON_COLOR, Thickness = thick or T, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                }, f)
                strokes[#strokes + 1] = s
            end
            return f
        end
        local function pill(cx, cy, w, h)
            local f = new("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(cx, cy), Size = UDim2.fromScale(w, h),
                BackgroundTransparency = 1, BorderSizePixel = 0,
            }, holder)
            corner(f)
            strokes[#strokes + 1] = new("UIStroke", {
                Color = ICON_COLOR, Thickness = T, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            }, f)
            return f
        end
        -- rounded line between two points (units 0..1)
        local function line(x1, y1, x2, y2)
            local dx, dy = (x2 - x1) * S, (y2 - y1) * S
            local len = math.sqrt(dx * dx + dy * dy)
            local f = new("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale((x1 + x2) / 2, (y1 + y2) / 2),
                Size = UDim2.fromOffset(len + T, T), Rotation = math.deg(math.atan2(dy, dx)),
                BackgroundColor3 = ICON_COLOR, BorderSizePixel = 0,
            }, holder)
            corner(f)
            fills[#fills + 1] = f
            return f
        end
        local function arrowHead(tx, ty, ang, len, spread)
            for _, s in ipairs({ -1, 1 }) do
                local a = ang + math.pi + s * spread
                line(tx, ty, tx + math.cos(a) * len, ty + math.sin(a) * len)
            end
        end

        if kind == "aim" then
            ring(0.5, 0.5, 0.64, T)
            line(0.5, 0.02, 0.5, 0.26); line(0.5, 0.74, 0.5, 0.98)
            line(0.02, 0.5, 0.26, 0.5); line(0.74, 0.5, 0.98, 0.5)
            ring(0.5, 0.5, 0.15, nil, true)
            api.hover = function(on) tween(holder, 0.45, { Rotation = on and 90 or 0 }, Enum.EasingStyle.Back) end
        elseif kind == "eye" then
            pill(0.5, 0.5, 1, 0.62)
            ring(0.5, 0.5, 0.34, T)
            local pupil = ring(0.5, 0.5, 0.14, nil, true)
            api.hover = function(on)
                tween(pupil, 0.3, { Position = UDim2.fromScale(on and 0.56 or 0.5, 0.5), Size = UDim2.fromScale(on and 0.2 or 0.14, on and 0.2 or 0.14) }, Enum.EasingStyle.Back)
            end
        elseif kind == "sliders" then
            local rows = { { 0.2, 0.32 }, { 0.5, 0.68 }, { 0.8, 0.42 } }
            local knobs = {}
            for i, r in ipairs(rows) do
                local y, kx = r[1], r[2]
                line(0.04, y, kx - 0.16, y)
                line(kx + 0.16, y, 0.96, y)
                knobs[i] = ring(kx, y, 0.26, T)
            end
            api.hover = function(on)
                local target = on and { 0.68, 0.32, 0.6 } or { 0.32, 0.68, 0.42 }
                for i, k in ipairs(knobs) do
                    tween(k, 0.35, { Position = UDim2.fromScale(target[i], rows[i][1]) }, Enum.EasingStyle.Back)
                end
            end
        elseif kind == "close" then
            line(0.14, 0.14, 0.86, 0.86); line(0.86, 0.14, 0.14, 0.86)
            api.hover = function(on) tween(holder, 0.3, { Rotation = on and 90 or 0 }, Enum.EasingStyle.Back) end
        elseif kind == "check" then
            line(0.12, 0.54, 0.40, 0.82); line(0.40, 0.82, 0.90, 0.22)
        elseif kind == "reset" or kind == "refresh" then
            local r = ring(0.5, 0.5, 0.72, T)
            local g = new("UIGradient", {
                Rotation = -45,
                Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0),
                    NumberSequenceKeypoint.new(0.801, 1), NumberSequenceKeypoint.new(1, 1),
                }),
            }, r:FindFirstChildOfClass("UIStroke"))
            local a = math.rad(-77)
            local ax, ay = 0.5 + 0.36 * math.cos(a), 0.5 + 0.36 * math.sin(a)
            local tx, ty = ax + 0.07, ay + 0.02
            arrowHead(tx, ty, math.atan2(0.02, 0.07), 0.2, math.rad(42))
            if kind == "reset" then holder.Size = UDim2.fromOffset(S, S) end
            api.hover = function(on) tween(holder, 0.5, { Rotation = on and 180 or 0 }, Enum.EasingStyle.Back) end
            if kind == "reset" then
                -- mirror horizontally so the arrow runs the other way
                for _, c in ipairs(holder:GetChildren()) do
                    if c:IsA("Frame") then
                        c.Position = UDim2.new(1 - c.Position.X.Scale, 0, c.Position.Y.Scale, 0)
                        if c.Rotation ~= 0 then c.Rotation = -c.Rotation end
                    end
                end
                g.Rotation = -135
                api.hover = function(on) tween(holder, 0.5, { Rotation = on and -180 or 0 }, Enum.EasingStyle.Back) end
            end
        elseif kind == "list" then
            line(0.34, 0.2, 0.96, 0.2); line(0.34, 0.5, 0.82, 0.5); line(0.34, 0.8, 0.9, 0.8)
            ring(0.08, 0.2, 0.14, nil, true); ring(0.08, 0.5, 0.14, nil, true); ring(0.08, 0.8, 0.14, nil, true)
        elseif kind == "download" then
            line(0.5, 0.08, 0.5, 0.64); arrowHead(0.5, 0.68, math.pi / 2, 0.3, math.rad(45))
            line(0.1, 0.92, 0.9, 0.92)
            api.hover = function(on) tween(holder, 0.25, { Position = UDim2.fromScale(0.5, on and 0.54 or 0.5) }, Enum.EasingStyle.Back) end
        elseif kind == "upload" then
            line(0.5, 0.36, 0.5, 0.92); arrowHead(0.5, 0.32, -math.pi / 2, 0.3, math.rad(45))
            line(0.1, 0.08, 0.9, 0.08)
            api.hover = function(on) tween(holder, 0.25, { Position = UDim2.fromScale(0.5, on and 0.46 or 0.5) }, Enum.EasingStyle.Back) end
        elseif kind == "prev" then
            line(0.64, 0.14, 0.28, 0.5); line(0.28, 0.5, 0.64, 0.86)
        elseif kind == "next" then
            line(0.36, 0.14, 0.72, 0.5); line(0.72, 0.5, 0.36, 0.86)
        else -- dot
            ring(0.5, 0.5, 0.3, nil, true)
        end

        function api.setColor(c, t)
            for _, f in ipairs(fills) do
                if t then tween(f, t, { BackgroundColor3 = c }) else f.BackgroundColor3 = c end
            end
            for _, s in ipairs(strokes) do
                if t then tween(s, t, { Color = c }) else s.Color = c end
            end
        end
        return api
    end

    ----------------------------------------------------------------------
    -- Circular button (used for every button / icon in the UI)
    -- hover: scale + brighten + accent ring, press: squish, release: pop back
    ----------------------------------------------------------------------
    local function circleButton(parent, size, glyph, callback, danger, activeFn, popDelay)
        local b = new("TextButton", {
            Size = UDim2.fromOffset(size, size), BackgroundColor3 = WHITE, BackgroundTransparency = 0.86,
            Text = "", AutoButtonColor = false, BorderSizePixel = 0,
        }, parent)
        corner(b)
        local st = stroke(b, WHITE, 0.72, 1.2)
        local kind = ICON_ALIAS[glyph]
        local g = text(b, {
            Size = UDim2.fromScale(1, 1), Text = kind and "" or glyph, Font = Enum.Font.GothamBold,
            TextSize = math.floor(size * 0.42), TextXAlignment = Enum.TextXAlignment.Center,
        })
        local ic = kind and buildIcon(b, kind, size)
        local sc = new("UIScale", { Scale = 1 }, b)
        local hovering = false

        local function tint() return danger and DANGER or accent end
        local booting = popDelay ~= nil
        local function refresh()
            if booting then return end
            if ic then
                local lit = hovering or (activeFn and activeFn())
                ic.setColor(lit and WHITE or ICON_COLOR, 0.2)
                if ic.hover then ic.hover(hovering) end
            end
            if hovering then
                tween(sc, 0.18, { Scale = 1.1 })
                tween(b, 0.18, { BackgroundColor3 = tint(), BackgroundTransparency = 0.5 })
                tween(st, 0.18, { Color = tint(), Transparency = 0.1 })
            elseif activeFn and activeFn() then
                tween(sc, 0.22, { Scale = 1 })
                tween(b, 0.22, { BackgroundColor3 = tint(), BackgroundTransparency = 0.62 })
                tween(st, 0.22, { Color = tint(), Transparency = 0.2 })
            else
                tween(sc, 0.22, { Scale = 1 })
                tween(b, 0.22, { BackgroundColor3 = WHITE, BackgroundTransparency = 0.86 })
                tween(st, 0.22, { Color = WHITE, Transparency = 0.72 })
            end
        end
        b.MouseEnter:Connect(function() hovering = true refresh() end)
        b.MouseLeave:Connect(function() hovering = false refresh() end)
        b.MouseButton1Down:Connect(function() tween(sc, 0.08, { Scale = 0.9 }) end)
        b.MouseButton1Up:Connect(function() tween(sc, 0.16, { Scale = hovering and 1.1 or 1 }, Enum.EasingStyle.Back) end)
        if callback then b.Activated:Connect(callback) end
        -- click ripple
        b.Activated:Connect(function()
            local rp = new("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromOffset(size * 0.5, size * 0.5), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5,
            }, b)
            corner(rp)
            local rs = stroke(rp, danger and DANGER or accent, 0.1, 2)
            tween(rp, 0.55, { Size = UDim2.fromOffset(size * 1.9, size * 1.9) })
            tween(rs, 0.55, { Transparency = 1 })
            task.delay(0.6, function() rp:Destroy() end)
        end)
        -- staggered entrance (waits for the window to open the first time)
        if popDelay then
            sc.Scale = 0
            task.spawn(function()
                if not opened then openSignal.Event:Wait() end
                task.wait(popDelay)
                tween(sc, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
                task.wait(0.5)
                booting = false
                refresh()
            end)
        end
        onAccent(function() refresh() end)
        return b, g, refresh
    end

    ----------------------------------------------------------------------
    -- Slider track (shared by sliders and the colour picker)
    ----------------------------------------------------------------------
    local function track(parent, o)
        local min, max, inc = o.range[1], o.range[2], o.increment or 0
        local value = o.value or min
        local hit = new("TextButton", {
            BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
            Position = o.position, Size = o.size,
        }, parent)
        local bar = new("Frame", {
            AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(1, 0, 0, 6),
            BackgroundColor3 = WHITE, BackgroundTransparency = 0.82, BorderSizePixel = 0,
        }, hit)
        corner(bar)
        local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = accent, BorderSizePixel = 0 }, bar)
        corner(fill)
        bindAccent(fill, "BackgroundColor3")
        local knob = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(16, 16),
            BackgroundColor3 = WHITE, BorderSizePixel = 0,
        }, bar)
        corner(knob)
        local ks = stroke(knob, accent, 0.2, 2)
        bindAccent(ks, "Color")
        local kScale = new("UIScale", { Scale = 1 }, knob)

        local api = {}
        local function snap(v)
            v = math.clamp(v, min, max)
            if inc > 0 then v = math.floor((v - min) / inc + 0.5) * inc + min end
            return tonumber(string.format("%.4f", math.clamp(v, min, max)))
        end
        local function show(v, t)
            local a = (v - min) / (max - min)
            tween(fill, t, { Size = UDim2.fromScale(a, 1) }, Enum.EasingStyle.Quad)
            tween(knob, t, { Position = UDim2.fromScale(a, 0.5) }, Enum.EasingStyle.Quad)
        end
        show(value, 0)

        function api.Set(v, silent)
            value = snap(v)
            show(value, 0.2)
            if not silent and o.onChange then o.onChange(value, false) end
        end
        function api.Get() return value end

        local dragging = false
        local function fromInput(pos)
            local a = math.clamp((pos.X - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
            value = snap(min + a * (max - min))
            show(value, 0.06)
            if o.onChange then o.onChange(value, true) end
        end
        hit.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                tween(kScale, 0.18, { Scale = 1.3 }, Enum.EasingStyle.Back)
                fromInput(i.Position)
            end
        end)
        UIS.InputChanged:Connect(function(i)
            if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
                or i.UserInputType == Enum.UserInputType.Touch) then
                fromInput(i.Position)
            end
        end)
        UIS.InputEnded:Connect(function(i)
            if dragging and (i.UserInputType == Enum.UserInputType.MouseButton1
                or i.UserInputType == Enum.UserInputType.Touch) then
                dragging = false
                tween(kScale, 0.2, { Scale = 1 })
                if o.onChange then o.onChange(value, false) end
                markDirty()
            end
        end)
        return api
    end

    ----------------------------------------------------------------------
    -- Keybinds (one global listener for all of them)
    ----------------------------------------------------------------------
    local keybinds, listening = {}, nil

    local function shortKey(k)
        if not k then return "-" end
        local n = k.Name
        if #n <= 2 then return n end
        local caps = (n:gsub("%l", ""))
        if #caps >= 2 then return caps:sub(1, 3) end
        return n:sub(1, 3)
    end

    UIS.InputBegan:Connect(function(input, processed)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        if listening then
            local kb = listening
            listening = nil
            if input.KeyCode == Enum.KeyCode.Backspace then
                kb:SetKey(nil)
            elseif input.KeyCode == Enum.KeyCode.Escape then
                kb:Render()
            else
                kb:SetKey(input.KeyCode)
            end
            return
        end
        if processed then return end
        for _, kb in ipairs(keybinds) do
            if kb.key and input.KeyCode == kb.key then kb:Press(true) end
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        for _, kb in ipairs(keybinds) do
            if kb.hold and kb.key and input.KeyCode == kb.key then kb:Press(false) end
        end
    end)

    ----------------------------------------------------------------------
    -- Container: every tab (and Grid) shares these control builders
    ----------------------------------------------------------------------
    local Container = {}
    Container.__index = Container

    function Container:_next()
        self._order = (self._order or 0) + 1
        return self._order
    end

    -- Glass row card. Returns row, nameLabel.
    function Container:_row(h, name, desc, rightPad, nameTop, parent)
        rightPad = rightPad or 90
        local f = new("Frame", {
            Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = WHITE, BackgroundTransparency = 0.9,
            BorderSizePixel = 0, LayoutOrder = self:_next(),
        }, parent or self.Frame)
        corner(f, 18)
        stroke(f, WHITE, 0.9)
        f.MouseEnter:Connect(function() tween(f, 0.2, { BackgroundTransparency = 0.84 }) end)
        f.MouseLeave:Connect(function() tween(f, 0.25, { BackgroundTransparency = 0.9 }) end)
        local nameL
        if name then
            local top = desc ~= nil or nameTop
            nameL = text(f, {
                Size = UDim2.new(1, -rightPad, 0, 18),
                Position = top and UDim2.fromOffset(14, 9) or UDim2.new(0, 14, 0.5, 0),
                AnchorPoint = top and Vector2.zero or Vector2.new(0, 0.5),
                TextTruncate = Enum.TextTruncate.AtEnd,
            })
            localized(nameL, name)
            if desc then
                text(f, {
                    Size = UDim2.new(1, -rightPad, 0, 14), Position = UDim2.fromOffset(14, 29),
                    TextSize = 12, TextColor3 = MUTED, Text = desc, TextTruncate = Enum.TextTruncate.AtEnd,
                })
            end
        end
        return f, nameL
    end

    function Container:Grid(cols)
        cols = cols or 2
        local f = new("Frame", {
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1, LayoutOrder = self:_next(),
        }, self.Frame)
        new("UIGridLayout", {
            CellSize = UDim2.new(1 / cols, -(8 * (cols - 1)) / cols, 0, 54),
            CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder,
        }, f)
        return setmetatable({ Frame = f }, Container)
    end

    function Container:Section(name, muted)
        local f = new("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = self:_next() }, self.Frame)
        local x = 4
        if not muted then
            local dot = new("Frame", {
                AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 2), Size = UDim2.fromOffset(9, 9),
                BackgroundColor3 = accent, BorderSizePixel = 0,
            }, f)
            corner(dot)
            bindAccent(dot, "BackgroundColor3")
            x = 24
        end
        local l = text(f, {
            Position = UDim2.new(0, x, 0, 4), Size = UDim2.new(1, -30, 1, -4),
            Font = Enum.Font.GothamBold, TextSize = muted and 11 or 13, TextColor3 = muted and MUTED or TEXT,
        })
        localized(l, name)
        return f
    end

    function Container:Divider(name) return self:Section(name, true) end

    -- Circular toggle: a round orb whose inner core pops in/out
    function Container:Toggle(o)
        local row = self:_row(54, o.name, o.description)
        local orb = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(32, 32),
            BackgroundColor3 = WHITE, BackgroundTransparency = 0.86, Text = "", AutoButtonColor = false, BorderSizePixel = 0,
        }, row)
        corner(orb)
        local ost = stroke(orb, WHITE, 0.65, 1.5)
        local core = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 0),
            BackgroundColor3 = accent, BackgroundTransparency = 1, BorderSizePixel = 0,
        }, orb)
        corner(core)
        local osc = new("UIScale", { Scale = 1 }, orb)

        local api = { value = o.value == true }
        local function render(instant)
            local t = instant and 0 or 0.28
            local on = api.value
            tween(core, t, {
                Size = on and UDim2.fromOffset(18, 18) or UDim2.fromOffset(0, 0),
                BackgroundColor3 = accent, BackgroundTransparency = on and 0 or 1,
            }, on and Enum.EasingStyle.Back or Enum.EasingStyle.Quint)
            tween(ost, t, { Color = on and accent or WHITE, Transparency = on and 0.05 or 0.65 })
            tween(orb, t, { BackgroundColor3 = on and accent or WHITE, BackgroundTransparency = on and 0.7 or 0.86 })
        end
        render(true)
        onAccent(function() render(false) end)

        function api:Set(v, silent)
            self.value = v == true
            render(false)
            if o.callback and not silent then task.spawn(o.callback, self.value) end
            markDirty()
        end
        orb.MouseEnter:Connect(function() tween(osc, 0.15, { Scale = 1.12 }) end)
        orb.MouseLeave:Connect(function() tween(osc, 0.2, { Scale = 1 }) end)
        orb.MouseButton1Down:Connect(function() tween(osc, 0.08, { Scale = 0.88 }) end)
        orb.Activated:Connect(function()
            tween(osc, 0.2, { Scale = 1.12 }, Enum.EasingStyle.Back)
            api:Set(not api.value)
        end)
        registerFlag(o.flag, function() return api.value end, function(v) api:Set(v) end)
        return api
    end

    function Container:Slider(o)
        local row = self:_row(62, o.name, nil, o.step and 150 or 110, true)
        local valueL = text(row, {
            AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 9),
            Size = UDim2.fromOffset(o.step and 56 or 90, 18),
            TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.GothamBold, TextColor3 = WHITE,
        })
        local inc = o.increment or 1
        local function fmt(v)
            local s = inc < 1 and string.format("%.2f", v) or string.format("%d", math.floor(v + 0.5))
            return s .. (o.suffix or "")
        end
        local api = { value = o.value or o.range[1] }
        local t
        t = track(row, {
            range = o.range, increment = inc, value = api.value,
            position = UDim2.fromOffset(14, 34), size = UDim2.new(1, -28, 0, 22),
            onChange = function(v, dragging)
                api.value = v
                valueL.Text = fmt(v)
                if o.callback then o.callback(v, dragging) end
            end,
        })
        valueL.Text = fmt(api.value)
        function api:Set(v, silent) t.Set(v, silent) api.value = t.Get() valueL.Text = fmt(api.value) end

        -- small arrows beside the value: o.step = amount per click
        if o.step then
            local token = 0
            local function nudge(d)
                api:Set(math.clamp(api.value + d, o.range[1], o.range[2]))
                if o.callback then
                    o.callback(api.value, true) -- flashes the FOV preview circle
                    token += 1
                    local mine = token
                    task.delay(0.9, function()
                        if token == mine then o.callback(api.value, false) end
                    end)
                end
            end
            local minus = circleButton(row, 22, "prev", function() nudge(-o.step) end)
            minus.AnchorPoint, minus.Position = Vector2.new(1, 0.5), UDim2.new(1, -100, 0, 18)
            local plus = circleButton(row, 22, "next", function() nudge(o.step) end)
            plus.AnchorPoint, plus.Position = Vector2.new(1, 0.5), UDim2.new(1, -74, 0, 18)
        end

        registerFlag(o.flag, function() return api.value end, function(v) api:Set(v) end)
        return api
    end

    -- Dropdown replacement: two circular arrows cycle through the options
    function Container:Cycle(o)
        local row = self:_row(54, o.name, nil, 250)
        local options = o.options or {}
        local index = 1
        for i, v in ipairs(options) do if v == o.value then index = i end end
        local api = { options = options }
        local valueL = text(row, {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -90, 0.5, 0), Size = UDim2.fromOffset(160, 18),
            TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = WHITE,
            TextTruncate = Enum.TextTruncate.AtEnd,
        })
        local function render()
            api.value = options[index]
            valueL.Text = options[index] or (o.placeholder or "-")
        end
        local function commit()
            render()
            if o.callback and options[index] ~= nil then task.spawn(o.callback, options[index]) end
            markDirty()
        end
        local function step(d)
            if #options == 0 then return end
            index = (index - 1 + d) % #options + 1
            commit()
        end
        local prevB = circleButton(row, 30, "‹", function() step(-1) end)
        prevB.AnchorPoint, prevB.Position = Vector2.new(1, 0.5), UDim2.new(1, -48, 0.5, 0)
        local nextB = circleButton(row, 30, "›", function() step(1) end)
        nextB.AnchorPoint, nextB.Position = Vector2.new(1, 0.5), UDim2.new(1, -12, 0.5, 0)
        render()

        function api:Set(v, silent)
            for i, opt in ipairs(options) do
                if opt == v then
                    index = i
                    render()
                    if o.callback and not silent then task.spawn(o.callback, opt) end
                    markDirty()
                    return
                end
            end
        end
        function api:Refresh(newOptions)
            options = newOptions
            api.options = newOptions
            if index > #options then index = 1 end
            render()
        end
        if not o.forgetState then
            registerFlag(o.flag, function() return api.value end, function(v) api:Set(v) end)
        end
        return api
    end

    function Container:Input(o)
        local row = self:_row(54, o.name, o.description, 200)
        local box = new("TextBox", {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(150, 32),
            BackgroundColor3 = WHITE, BackgroundTransparency = 0.88, BorderSizePixel = 0,
            Text = o.value or "", PlaceholderText = o.placeholder or "", PlaceholderColor3 = MUTED,
            TextColor3 = TEXT, Font = Enum.Font.GothamMedium, TextSize = 13, ClearTextOnFocus = false,
        }, row)
        corner(box)
        local bs = stroke(box, WHITE, 0.78)
        box.Focused:Connect(function() tween(bs, 0.2, { Color = accent, Transparency = 0.1 }) end)
        box.FocusLost:Connect(function()
            tween(bs, 0.25, { Color = WHITE, Transparency = 0.78 })
            if o.callback then o.callback(box.Text) end
            markDirty()
        end)
        if o.numeric then
            box:GetPropertyChangedSignal("Text"):Connect(function()
                local clean = box.Text:gsub("[^%d%.]", "")
                if clean ~= box.Text then box.Text = clean end
            end)
        end
        local api = {}
        function api:Set(v, silent)
            box.Text = tostring(v)
            if o.callback and not silent then o.callback(box.Text) end
        end
        function api:Get() return box.Text end
        if not o.forgetState then
            registerFlag(o.flag, function() return box.Text end, function(v) api:Set(v) end)
        end
        return api
    end

    function Container:Keybind(o)
        local row = self:_row(54, o.name, o.description, 170)
        local kb = {
            key = o.value, hold = o.hold, threshold = o.holdThreshold or 0,
            callback = o.callback, onChanged = o.onChanged, held = false, fired = false,
        }
        local btn, glyph = circleButton(row, 38, shortKey(kb.key), function()
            local prev = listening
            listening = kb
            if prev and prev ~= kb then prev:Render() end
            kb:Render()
        end)
        btn.AnchorPoint, btn.Position = Vector2.new(1, 0.5), UDim2.new(1, -12, 0.5, 0)
        local caption = text(row, {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -58, 0.5, 0), Size = UDim2.fromOffset(110, 14),
            TextXAlignment = Enum.TextXAlignment.Right, TextSize = 11, TextColor3 = MUTED,
        })
        function kb:Render()
            if listening == self then
                glyph.Text = "..."
                caption.Text = "press a key"
                caption.TextColor3 = WHITE
            else
                glyph.Text = shortKey(self.key)
                caption.Text = self.key and self.key.Name or "unbound"
                caption.TextColor3 = MUTED
            end
        end
        function kb:SetKey(k, silent)
            self.key = k
            self:Render()
            if not silent and self.onChanged then task.spawn(self.onChanged, k) end
            markDirty()
        end
        function kb:Press(down)
            if not self.callback then return end
            if not self.hold then
                if down then task.spawn(self.callback) end
                return
            end
            if down then
                self.held = true
                task.delay(self.threshold, function()
                    if self.held and not self.fired then
                        self.fired = true
                        self.callback(true)
                    end
                end)
            else
                self.held = false
                if self.fired then
                    self.fired = false
                    self.callback(false)
                end
            end
        end
        kb:Render()
        keybinds[#keybinds + 1] = kb
        registerFlag(o.flag, function() return kb.key or false end,
            function(v) kb:SetKey(typeof(v) == "EnumItem" and v or nil, true) end)
        return kb
    end

    -- Colour picker: circular swatch, click to expand H / S / V sliders
    function Container:Color(o)
        local wrap = new("Frame", {
            Size = UDim2.new(1, 0, 0, 54), BackgroundTransparency = 1, ClipsDescendants = true, LayoutOrder = self:_next(),
        }, self.Frame)
        local row = self:_row(54, o.name, o.description, 70, false, wrap)
        local color = o.color or WHITE
        local h, s, v = Color3.toHSV(color)
        local api = { value = color }

        local swatch = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(30, 30),
            BackgroundColor3 = color, Text = "", AutoButtonColor = false, BorderSizePixel = 0,
        }, row)
        corner(swatch)
        stroke(swatch, WHITE, 0.3, 2)
        local sc = new("UIScale", { Scale = 1 }, swatch)
        swatch.MouseEnter:Connect(function() tween(sc, 0.15, { Scale = 1.12 }) end)
        swatch.MouseLeave:Connect(function() tween(sc, 0.2, { Scale = 1 }) end)

        local panel = new("Frame", {
            Position = UDim2.fromOffset(0, 60), Size = UDim2.new(1, 0, 0, 90), BackgroundColor3 = WHITE,
            BackgroundTransparency = 0.95, BorderSizePixel = 0, Visible = false,
        }, wrap)
        corner(panel, 18)
        stroke(panel, WHITE, 0.9)

        local function apply(fire)
            color = Color3.fromHSV(h, s, v)
            api.value = color
            swatch.BackgroundColor3 = color
            if fire and o.callback then o.callback(color) end
        end
        local tracks = {}
        local names = { "H", "S", "V" }
        for i = 1, 3 do
            local y = 8 + (i - 1) * 26
            text(panel, {
                Position = UDim2.fromOffset(16, y), Size = UDim2.fromOffset(16, 22),
                Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = MUTED, Text = names[i],
            })
            tracks[i] = track(panel, {
                range = { 0, 1 }, increment = 0.01, value = (i == 1 and h) or (i == 2 and s) or v,
                position = UDim2.fromOffset(40, y), size = UDim2.new(1, -58, 0, 22),
                onChange = function(val)
                    if i == 1 then h = val elseif i == 2 then s = val else v = val end
                    apply(true)
                end,
            })
        end

        local open = false
        swatch.Activated:Connect(function()
            open = not open
            if open then
                panel.Visible = true
                tween(wrap, 0.35, { Size = UDim2.new(1, 0, 0, 156) })
            else
                tween(wrap, 0.3, { Size = UDim2.new(1, 0, 0, 54) })
                task.delay(0.3, function() if not open then panel.Visible = false end end)
            end
        end)

        function api:Set(c, silent)
            h, s, v = Color3.toHSV(c)
            tracks[1].Set(h, true) tracks[2].Set(s, true) tracks[3].Set(v, true)
            apply(not silent)
            markDirty()
        end
        registerFlag(o.flag, function() return api.value end, function(c) api:Set(c) end)
        return api
    end

    function Container:Text(o)
        local h = o.height or 58
        local row = self:_row(h, nil)
        text(row, {
            Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 14),
            TextSize = 11, TextColor3 = MUTED, Font = Enum.Font.GothamBold,
        })
        -- caption (localized) is the first label we just made
        local caption = row:FindFirstChildOfClass("TextLabel")
        localized(caption, o.name)
        local body = text(row, {
            Position = UDim2.fromOffset(14, 26), Size = UDim2.new(1, -28, 0, h - 32),
            TextSize = o.small and 12 or 15, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
            Text = o.text or "",
        })
        local api = {}
        function api:Set(t) body.Text = tostring(t) end
        return api
    end

    function Container:Progress(o)
        local range = o.range or { 0, o.steps or 1 } -- step bars (Aim Stage) have no range
        local min, max = range[1], range[2]
        local fmt = o.format or function(v) return string.format("%d", math.floor(v + 0.5)) end
        local api = { value = o.value or min }
        if o.steps then
            local row = self:_row(54, o.name, nil, 200)
            local dots = {}
            local cap = text(row, {
                AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -(14 + o.steps * 24 + 8), 0.5, 0),
                Size = UDim2.fromOffset(80, 16), TextXAlignment = Enum.TextXAlignment.Right,
                TextSize = 12, TextColor3 = MUTED,
            })
            for i = 1, o.steps do
                local d = new("Frame", {
                    AnchorPoint = Vector2.new(1, 0.5), Size = UDim2.fromOffset(16, 16), BorderSizePixel = 0,
                    Position = UDim2.new(1, -(14 + (o.steps - i) * 24), 0.5, 0),
                    BackgroundColor3 = WHITE, BackgroundTransparency = 0.8,
                }, row)
                corner(d)
                dots[i] = d
            end
            function api:Set(v)
                self.value = v
                for i, d in ipairs(dots) do
                    local on = i <= v
                    tween(d, 0.3, { BackgroundColor3 = on and accent or WHITE, BackgroundTransparency = on and 0 or 0.8 })
                end
                cap.Text = o.stageNames and o.stageNames[v + 1] or (v .. "/" .. o.steps)
            end
            onAccent(function() api:Set(api.value) end)
            return api
        end
        local row = self:_row(54, o.name, nil, 110, true)
        local valueL = text(row, {
            AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 9), Size = UDim2.fromOffset(90, 18),
            TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.GothamBold, TextColor3 = WHITE,
        })
        local bar = new("Frame", {
            Position = UDim2.fromOffset(14, 38), Size = UDim2.new(1, -28, 0, 6),
            BackgroundColor3 = WHITE, BackgroundTransparency = 0.82, BorderSizePixel = 0,
        }, row)
        corner(bar)
        local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = accent, BorderSizePixel = 0 }, bar)
        corner(fill)
        bindAccent(fill, "BackgroundColor3")
        function api:Set(v)
            self.value = v
            tween(fill, 0.35, { Size = UDim2.fromScale(math.clamp((v - min) / (max - min), 0, 1), 1) })
            valueL.Text = fmt(v)
        end
        api:Set(api.value)
        return api
    end

    -- Row of circular stat badges. defs: { {name=, suffix=, delta=, relative=}, ... }
    function Container:Stats(defs)
        local row = new("Frame", {
            Size = UDim2.new(1, 0, 0, 108), BackgroundColor3 = WHITE, BackgroundTransparency = 0.93,
            BorderSizePixel = 0, LayoutOrder = self:_next(),
        }, self.Frame)
        corner(row, 18)
        stroke(row, WHITE, 0.9)
        new("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
            VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 22), SortOrder = Enum.SortOrder.LayoutOrder,
        }, row)
        local out = {}
        for i, d in ipairs(defs) do
            local cell = new("Frame", { Size = UDim2.fromOffset(78, 92), BackgroundTransparency = 1, LayoutOrder = i }, row)
            local c = new("Frame", {
                AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(64, 64),
                BackgroundColor3 = WHITE, BackgroundTransparency = 0.86, BorderSizePixel = 0,
            }, cell)
            corner(c)
            local cs = stroke(c, accent, 0.45, 1.5)
            bindAccent(cs, "Color")
            local sc = new("UIScale", { Scale = 1 }, c)
            local num = text(c, {
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.78, 0.5),
                TextScaled = true, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Center, Text = "0",
            })
            new("UITextSizeConstraint", { MaxTextSize = 20, MinTextSize = 8 }, num)
            local cap = text(cell, {
                Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, 0, 0, 16), TextSize = 12,
                TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center,
            })
            localized(cap, d.name)

            local stat = {}
            local base, prev, last = 0, nil, 0
            local function show(v)
                local shown
                if d.delta then
                    shown = string.format("%+d", math.floor((v - (prev or v)) + 0.5))
                elseif d.relative then
                    shown = string.format("%d", math.floor(v - base + 0.5))
                else
                    shown = string.format("%d", math.floor(v + 0.5))
                end
                if num.Text ~= shown then
                    num.Text = shown
                    sc.Scale = 1.14
                    tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
                end
            end
            function stat:Set(v)
                last = v
                show(v)
                prev = v
            end
            function stat:ResetBaseline()
                base, prev = last, last
                show(last)
            end
            out[i] = stat
        end
        return out
    end

    -- Grid of labelled circular buttons
    function Container:Buttons(defs)
        local f = new("Frame", {
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1, LayoutOrder = self:_next(),
        }, self.Frame)
        new("UIGridLayout", {
            CellSize = UDim2.fromOffset(86, 80), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder,
        }, f)
        for i, d in ipairs(defs) do
            local cell = new("Frame", { BackgroundTransparency = 1, LayoutOrder = i }, f)
            local b = circleButton(cell, 46, d.glyph or "•", d.callback, d.danger)
            b.AnchorPoint, b.Position = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 4)
            local l = text(cell, {
                Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 0, 16), TextSize = 12,
                TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center,
            })
            localized(l, d.name)
        end
    end

    function Container:Console(o)
        local f = new("ScrollingFrame", {
            Size = UDim2.new(1, 0, 0, o.height or 130), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.55,
            BorderSizePixel = 0, ScrollBarThickness = 3, CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y, LayoutOrder = self:_next(),
        }, self.Frame)
        corner(f, 16)
        new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, f)
        new("UIPadding", {
            PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
        }, f)
        local api, raw, labels, n = {}, {}, {}, 0
        local maxLines = o.maxLines or 200
        function api:Append(line)
            n = n + 1
            raw[#raw + 1] = line
            labels[#labels + 1] = text(f, {
                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = n,
                Font = Enum.Font.Code, TextSize = 12, TextColor3 = MUTED, TextWrapped = true, Text = line,
            })
            if #labels > maxLines then
                table.remove(raw, 1)
                table.remove(labels, 1):Destroy()
            end
            if o.follow then
                task.defer(function() f.CanvasPosition = Vector2.new(0, 100000) end)
            end
        end
        function api:Clear()
            for _, l in ipairs(labels) do l:Destroy() end
            labels, raw = {}, {}
        end
        function api:Copy()
            return (pcall(function() setclipboard(table.concat(raw, "\n")) end))
        end
        return api
    end

    ----------------------------------------------------------------------
    -- Window
    ----------------------------------------------------------------------
    local DIR = "Skyware"
    local CFG_DIR = DIR .. "/configs"

    local function NewWindow(cfg)
        local window = { Tabs = {}, Flags = flags }
        local W, H = 640, 430
        if cfg.theme and THEMES[cfg.theme] then accent = THEMES[cfg.theme] end

        local gui = new("ScreenGui", {
            Name = HttpService:GenerateGUID(false), ResetOnSpawn = false, IgnoreGuiInset = true,
            DisplayOrder = 9999, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        })
        pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
        gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")

        -- Root holds the pop-up scale, the glow layers and the glass window
        local root = new("Frame", {
            Name = "Root", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(W, H), BackgroundTransparency = 1,
        }, gui)
        local rootScale = new("UIScale", { Scale = 0.86 }, root)
        -- auto-fit to the screen (bigger on large screens, smaller on phones); adjustable in Misc
        local uiScale = 1
        pcall(function()
            local vs = workspace.CurrentCamera.ViewportSize
            -- only shrink if the window wouldn't fit; never enlarge
            uiScale = math.min(1, math.floor(math.min(vs.X / (W + 40), vs.Y / (H + 40)) / 0.05) * 0.05)
        end)

        local glowOuter = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 36, 1, 36),
            BackgroundColor3 = accent, BackgroundTransparency = 1, BorderSizePixel = 0,
        }, root)
        corner(glowOuter, 44)
        bindAccent(glowOuter, "BackgroundColor3")
        local glowInner = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 14, 1, 14),
            BackgroundColor3 = accent, BackgroundTransparency = 1, BorderSizePixel = 0,
        }, root)
        corner(glowInner, 36)
        bindAccent(glowInner, "BackgroundColor3")

        -- The glass body (CanvasGroup so the whole window fades as one)
        local main = new("CanvasGroup", {
            Name = "Main", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1,
            BorderSizePixel = 0, GroupTransparency = 1,
        }, root)
        corner(main, 28)
        -- NOTE: the gradient lives on a child frame, not on the CanvasGroup itself
        -- (a UIGradient on a CanvasGroup tints everything inside it, text included).
        local bg = new("Frame", {
            Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.12, BorderSizePixel = 0,
        }, main)
        corner(bg, 28)
        new("UIGradient", {
            Color = ColorSequence.new(Color3.fromRGB(58, 72, 122), Color3.fromRGB(26, 32, 60)), Rotation = 135,
        }, bg)

        -- top sheen (the "liquid" highlight)
        local sheen = new("Frame", { Size = UDim2.new(1, 0, 0.45, 0), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, main)
        corner(sheen, 28)
        new("UIGradient", {
            Rotation = 90,
            Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.88), NumberSequenceKeypoint.new(1, 1) }),
        }, sheen)

        -- ambient accent glows that drift slowly behind the content
        local function glowOrb(px, startPos, endPos, dur, delay0)
            local g = new("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5), Position = startPos, Size = UDim2.fromOffset(px, px),
                BackgroundTransparency = 1, BorderSizePixel = 0,
            }, main)
            for i = 0, 7 do
                local d = px * (1 - i * 0.1)
                local f = new("Frame", {
                    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(d, d),
                    BackgroundColor3 = accent, BackgroundTransparency = 0.965, BorderSizePixel = 0,
                }, g)
                corner(f)
                bindAccent(f, "BackgroundColor3")
            end
            TS:Create(g, TweenInfo.new(dur, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, delay0 or 0), { Position = endPos }):Play()
        end
        glowOrb(300, UDim2.fromScale(0.82, 0.18), UDim2.fromScale(0.58, 0.46), 9)
        glowOrb(260, UDim2.fromScale(0.28, 0.9), UDim2.fromScale(0.62, 0.68), 11, 1.5)

        -- glass shimmer sweeping across the window every few seconds
        local shine = new("Frame", {
            Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0, BorderSizePixel = 0,
        }, main)
        corner(shine, 28)
        local shineGrad = new("UIGradient", {
            Rotation = 25, Offset = Vector2.new(-1, 0),
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1), NumberSequenceKeypoint.new(0.5, 0.93),
                NumberSequenceKeypoint.new(0.58, 1), NumberSequenceKeypoint.new(1, 1),
            }),
        }, shine)
        task.spawn(function()
            while main.Parent do
                task.wait(7)
                if root.Visible then
                    shineGrad.Offset = Vector2.new(-1, 0)
                    tween(shineGrad, 1.6, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
                end
            end
        end)

        -- slowly rotating gradient rim
        local edge = new("Frame", {
            Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2), BackgroundTransparency = 1, BorderSizePixel = 0,
        }, main)
        corner(edge, 27)
        local edgeStroke = stroke(edge, WHITE, 0, 1.5)
        local rim = new("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.5, 0.75), NumberSequenceKeypoint.new(1, 0.15),
            }),
        }, edgeStroke)
        onAccent(function(c)
            rim.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, WHITE), ColorSequenceKeypoint.new(0.5, c), ColorSequenceKeypoint.new(1, WHITE),
            })
        end)
        TS:Create(rim, TweenInfo.new(10, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), { Rotation = 360 }):Play()

        -- Sidebar: circular logo + circular tab buttons + close
        local side = new("Frame", {
            Position = UDim2.fromOffset(10, 10), Size = UDim2.new(0, 82, 1, -20), BackgroundColor3 = WHITE,
            BackgroundTransparency = 0.88, BorderSizePixel = 0, Active = true,
        }, main)
        corner(side, 22)
        stroke(side, WHITE, 0.88)

        -- Logo: big circle so the whole logo fits. Tweak LOGO_CIRCLE / LOGO_FIT to taste.
        local LOGO_CY = 52      -- vertical centre of the logo inside the sidebar
        local LOGO_CIRCLE = 66  -- diameter of the dark circle behind the logo
        local LOGO_FIT = 56     -- diameter of the logo image inside that circle
        local centre = UDim2.new(0.5, 0, 0, LOGO_CY)
        local ANCHOR_C = Vector2.new(0.5, 0.5)

        local logoRing = new("Frame", {
            AnchorPoint = ANCHOR_C, Position = centre, Size = UDim2.fromOffset(78, 78),
            BackgroundColor3 = accent, BackgroundTransparency = 0.8, BorderSizePixel = 0,
        }, side)
        corner(logoRing)
        bindAccent(logoRing, "BackgroundColor3")
        local breathe = new("UIScale", { Scale = 1 }, logoRing)
        TS:Create(breathe, TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.05 }):Play()

        -- orbiting light around the logo
        local orbit = new("Frame", {
            AnchorPoint = ANCHOR_C, Position = centre, Size = UDim2.fromOffset(LOGO_CIRCLE + 8, LOGO_CIRCLE + 8),
            BackgroundTransparency = 1, BorderSizePixel = 0,
        }, side)
        corner(orbit)
        local orbitStroke = stroke(orbit, WHITE, 0, 2.5)
        local orbitGrad = new("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 1),
                NumberSequenceKeypoint.new(0.7, 0), NumberSequenceKeypoint.new(1, 1),
            }),
        }, orbitStroke)
        onAccent(function(c)
            orbitGrad.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, c), ColorSequenceKeypoint.new(1, WHITE) })
        end)
        TS:Create(orbitGrad, TweenInfo.new(3.2, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), { Rotation = 360 }):Play()

        local logoHit = new("TextButton", {
            AnchorPoint = ANCHOR_C, Position = centre, Size = UDim2.fromOffset(LOGO_CIRCLE, LOGO_CIRCLE),
            BackgroundColor3 = Color3.fromRGB(18, 22, 40), BackgroundTransparency = 0.1, Text = "",
            AutoButtonColor = false, BorderSizePixel = 0,
        }, side)
        corner(logoHit)
        local logoStroke = stroke(logoHit, accent, 0.1, 2)
        bindAccent(logoStroke, "Color")
        local logoScale = new("UIScale", { Scale = 1 }, logoHit)
        local logo = new("ImageLabel", {
            AnchorPoint = ANCHOR_C, Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(LOGO_FIT, LOGO_FIT),
            BackgroundTransparency = 1, Image = cfg.logo or LOGO_IMAGE, ScaleType = Enum.ScaleType.Fit,
        }, logoHit)
        corner(logo)

        -- entrance pop, hover grow, click spin + ripple
        logoScale.Scale = 0
        task.spawn(function()
            if not opened then openSignal.Event:Wait() end
            task.wait(0.12)
            tween(logoScale, 0.7, { Scale = 1 }, Enum.EasingStyle.Back)
        end)
        local spinning = false
        logoHit.MouseEnter:Connect(function()
            if not spinning then tween(logoScale, 0.25, { Scale = 1.08 }, Enum.EasingStyle.Back) end
        end)
        logoHit.MouseLeave:Connect(function()
            if not spinning then tween(logoScale, 0.25, { Scale = 1 }) end
        end)
        logoHit.Activated:Connect(function()
            if spinning then return end
            spinning = true
            logo.Rotation = 0
            tween(logoScale, 0.12, { Scale = 0.9 })
            task.delay(0.12, function() tween(logoScale, 0.5, { Scale = 1.1 }, Enum.EasingStyle.Back) end)
            tween(logo, 0.8, { Rotation = 360 }, Enum.EasingStyle.Quint)
            local rp = new("Frame", {
                AnchorPoint = ANCHOR_C, Position = centre, Size = UDim2.fromOffset(LOGO_CIRCLE, LOGO_CIRCLE),
                BackgroundTransparency = 1, BorderSizePixel = 0,
            }, side)
            corner(rp)
            local rs = stroke(rp, accent, 0.1, 2.5)
            tween(rp, 0.8, { Size = UDim2.fromOffset(LOGO_CIRCLE + 40, LOGO_CIRCLE + 40) })
            tween(rs, 0.8, { Transparency = 1 })
            task.delay(0.85, function()
                rp:Destroy()
                logo.Rotation = 0
                spinning = false
                tween(logoScale, 0.25, { Scale = 1 })
            end)
        end)

        local tabList = new("Frame", {
            Position = UDim2.fromOffset(0, 104), Size = UDim2.new(1, 0, 1, -158), BackgroundTransparency = 1,
        }, side)
        new("UIListLayout", {
            Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
        }, tabList)

        -- sliding indicator that follows the active tab (tab buttons are 46px, 10px apart, list starts at y=104)
        local indicator = new("Frame", {
            AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromOffset(3, 104 + 23), Size = UDim2.fromOffset(4, 0),
            BackgroundColor3 = accent, BorderSizePixel = 0,
        }, side)
        corner(indicator)
        bindAccent(indicator, "BackgroundColor3")

        -- Header: brand + current tab title + tag chips
        local header = new("Frame", {
            Position = UDim2.fromOffset(102, 10), Size = UDim2.new(1, -112, 0, 48), BackgroundTransparency = 1, Active = true,
        }, main)
        local brandL = text(header, {
            Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -90, 0, 14), Font = Enum.Font.GothamBold,
            TextSize = 11, TextColor3 = WHITE, Text = string.upper(cfg.name or "SKYWARE"),
        })
        local titleL = text(header, {
            Position = UDim2.fromOffset(2, 16), Size = UDim2.new(1, -90, 0, 28), Font = Enum.Font.GothamBold, TextSize = 21,
        })
        local tagHolder = new("Frame", {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, 0.5, 0), Size = UDim2.fromOffset(120, 44),
            BackgroundTransparency = 1,
        }, header)
        new("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
            VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
        }, tagHolder)

        local pages = new("Frame", {
            Position = UDim2.fromOffset(102, 64), Size = UDim2.new(1, -112, 1, -76), BackgroundTransparency = 1, ClipsDescendants = true,
        }, main)

        makeDraggable(header, root)
        makeDraggable(side, root)

        -- Floating circular logo to bring the window back
        local orb = new("TextButton", {
            AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 26, 1, -26), Size = UDim2.fromOffset(54, 54),
            BackgroundColor3 = Color3.fromRGB(18, 22, 38), BackgroundTransparency = 0.15, Text = "",
            AutoButtonColor = false, BorderSizePixel = 0, Visible = false,
        }, gui)
        corner(orb)
        local orbStroke = stroke(orb, accent, 0.1, 2)
        bindAccent(orbStroke, "Color")
        local orbLogo = new("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -8, 1, -8),
            BackgroundTransparency = 1, Image = cfg.logo or LOGO_IMAGE, ScaleType = Enum.ScaleType.Crop,
        }, orb)
        corner(orbLogo)
        local orbScale = new("UIScale", { Scale = 0 }, orb)
        local pulse = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(54, 54),
            BackgroundTransparency = 1, BorderSizePixel = 0,
        }, orb)
        corner(pulse)
        local pulseStroke = stroke(pulse, accent, 0.3, 2)
        bindAccent(pulseStroke, "Color")
        local pulseInfo = TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1)
        TS:Create(pulse, pulseInfo, { Size = UDim2.fromOffset(90, 90) }):Play()
        TS:Create(pulseStroke, pulseInfo, { Transparency = 1 }):Play()
        orb.MouseEnter:Connect(function() tween(orbScale, 0.15, { Scale = 1.12 }) end)
        orb.MouseLeave:Connect(function() tween(orbScale, 0.2, { Scale = 1 }) end)

        -- Quick toggle button that sits beside the reopen orb (handy on mobile)
        local quickWrap = new("Frame", {
            AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 92, 1, -30), Size = UDim2.fromOffset(46, 46),
            BackgroundTransparency = 1, Visible = false,
        }, gui)
        local quickScale = new("UIScale", { Scale = 0 }, quickWrap)
        local quickMade = false

        function window:QuickToggle(o)
            local state = false
            local _, _, refresh = circleButton(quickWrap, 46, o.glyph or "aim", function()
                if o.callback then o.callback(not state) end
            end, false, function() return state end)
            quickMade = true
            return {
                Set = function(v) state = v == true refresh() end,
            }
        end

        -- Background blur (real glass look: blurs the world behind the window)
        local blur = new("BlurEffect", { Name = HttpService:GenerateGUID(false), Size = 0 }, LightingService)
        local blurOn = true

        -- Open / close: fade + scale pop
        local visible = false
        local function setVisible(v)
            visible = v
            if v then
                if not opened then opened = true openSignal:Fire() end
                root.Visible = true
                tween(rootScale, 0.5, { Scale = uiScale }, Enum.EasingStyle.Back)
                tween(main, 0.35, { GroupTransparency = 0 })
                tween(glowOuter, 0.5, { BackgroundTransparency = 0.94 })
                tween(glowInner, 0.5, { BackgroundTransparency = 0.88 })
                tween(blur, 0.4, { Size = blurOn and 16 or 0 })
                tween(orbScale, 0.2, { Scale = 0 })
                tween(quickScale, 0.2, { Scale = 0 })
                task.delay(0.2, function()
                    if visible then orb.Visible = false quickWrap.Visible = false end
                end)
            else
                tween(rootScale, 0.3, { Scale = uiScale * 0.88 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
                tween(main, 0.28, { GroupTransparency = 1 })
                tween(glowOuter, 0.28, { BackgroundTransparency = 1 })
                tween(glowInner, 0.28, { BackgroundTransparency = 1 })
                tween(blur, 0.3, { Size = 0 })
                task.delay(0.3, function() if not visible then root.Visible = false end end)
                orb.Visible = true
                orbScale.Scale = 0
                tween(orbScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
                if quickMade then
                    quickWrap.Visible = true
                    quickScale.Scale = 0
                    task.delay(0.08, function() tween(quickScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back) end)
                end
            end
        end
        orb.Activated:Connect(function() setVisible(true) end)

        local closeB = circleButton(side, 36, "✕", function() setVisible(false) end, true)
        closeB.AnchorPoint, closeB.Position = Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -14)

        function window:Show() setVisible(true) end
        function window:Hide() setVisible(false) end
        function window:ToggleHide() setVisible(not visible) end
        function window:GetScale() return uiScale end
        function window:SetScale(n)
            uiScale = n
            if visible then tween(rootScale, 0.25, { Scale = n }) end
        end
        function window:SetBlur(b)
            blurOn = b
            if visible then tween(blur, 0.35, { Size = b and 16 or 0 }) end
        end

        ------------------------------------------------------------------
        -- Tabs (slide + fade transitions)
        ------------------------------------------------------------------
        local current
        local function selectTab(tab)
            if current == tab then return end
            local old = current
            current = tab
            local dir = (old and old.index < tab.index) and 1 or -1
            if old then
                tween(old.group, 0.2, { GroupTransparency = 1, Position = UDim2.fromOffset(-34 * dir, 0) })
                task.delay(0.2, function() if current ~= old then old.group.Visible = false end end)
                old.refresh()
            end
            tab.group.Position = UDim2.fromOffset(34 * dir, 0)
            tab.group.GroupTransparency = 1
            tab.group.Visible = true
            tween(tab.group, 0.34, { GroupTransparency = 0, Position = UDim2.new() })
            tab.refresh()
            titleL.TextTransparency = 1
            titleL.Position = UDim2.fromOffset(18, 16)
            titleL.Text = tr(tab.Name)
            tween(titleL, 0.3, { TextTransparency = 0 })
            tween(titleL, 0.45, { Position = UDim2.fromOffset(2, 16) }, Enum.EasingStyle.Back)
            -- indicator: stretch toward the new tab, then settle
            local iy = 104 + (tab.index - 1) * 56 + 23
            tween(indicator, 0.16, { Position = UDim2.fromOffset(3, iy), Size = UDim2.fromOffset(4, 44) })
            task.delay(0.16, function()
                if current == tab then tween(indicator, 0.3, { Size = UDim2.fromOffset(4, 26) }, Enum.EasingStyle.Back) end
            end)
        end

        function window:CreateTab(o)
            local tab = setmetatable({}, Container)
            tab.Name = o.name
            tab.index = #window.Tabs + 1
            local group = new("CanvasGroup", {
                Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, GroupTransparency = 1, Visible = false,
            }, pages)
            local scroll = new("ScrollingFrame", {
                Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
                ScrollBarImageColor3 = accent, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
            }, group)
            bindAccent(scroll, "ScrollBarImageColor3")
            new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
            new("UIPadding", {
                PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 14),
            }, scroll)
            tab.Frame, tab.group = scroll, group

            local icon = o.icon or "•"
            local isImage = type(icon) == "string" and icon:sub(1, 11) == "rbxassetid:"
            local btn, glyph, refresh = circleButton(tabList, 46, isImage and "" or tostring(icon), function() selectTab(tab) end,
                false, function() return current == tab end, 0.25 + tab.index * 0.1)
            btn.LayoutOrder = tab.index
            if isImage then
                new("ImageLabel", {
                    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.58, 0.58),
                    BackgroundTransparency = 1, Image = icon,
                }, btn)
            end
            tab.refresh = refresh
            function tab:Select() selectTab(tab) end

            window.Tabs[#window.Tabs + 1] = tab
            if not current then selectTab(tab) end
            return tab
        end

        function window:Navigate(name)
            for _, t in ipairs(window.Tabs) do
                if t.Name == name then selectTab(t) return end
            end
        end

        function window:CreateTag(o)
            local chip = new("Frame", {
                Size = UDim2.fromOffset(40, 40), BackgroundColor3 = o.color or accent, BackgroundTransparency = 0.78,
                BorderSizePixel = 0, LayoutOrder = o.order or 0,
            }, tagHolder)
            corner(chip)
            local cs = stroke(chip, o.color or accent, 0.3, 1.2)
            TS:Create(cs, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.8 }):Play()
            text(chip, {
                Size = UDim2.fromScale(1, 1), Text = o.text, TextSize = 11, Font = Enum.Font.GothamBold,
                TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = o.color or TEXT,
            })
            if not o.color then bindAccent(chip, "BackgroundColor3") bindAccent(cs, "Color") end
        end

        function window:ChangeTheme(name)
            if not THEMES[name] then return end
            accent = THEMES[name]
            for _, fn in ipairs(accentSubs) do fn(accent, false) end
        end

        function window:SetLocale(l)
            locale = l
            for _, e in ipairs(labelRegistry) do
                if e[1].Parent then e[1].Text = tr(e[2]) end
            end
            if current then titleL.Text = tr(current.Name) end
        end

        ------------------------------------------------------------------
        -- Toasts (slide in from the right, fade out)
        ------------------------------------------------------------------
        local toastHolder = new("Frame", {
            AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -20), Size = UDim2.fromOffset(290, 420),
            BackgroundTransparency = 1,
        }, gui)
        new("UIListLayout", {
            VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Right,
            Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
        }, toastHolder)

        function window:Toast(o)
            local wrap = new("Frame", { Size = UDim2.fromOffset(280, 58), BackgroundTransparency = 1 }, toastHolder)
            local card = new("CanvasGroup", {
                Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(320, 0), BackgroundColor3 = Color3.fromRGB(18, 22, 38),
                BackgroundTransparency = 0.12, GroupTransparency = 1, BorderSizePixel = 0,
            }, wrap)
            corner(card, 29)
            local cs = stroke(card, accent, 0.4, 1.5)
            local ic = new("ImageLabel", {
                Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(38, 38), BackgroundTransparency = 1,
                Image = cfg.logo or LOGO_IMAGE, ScaleType = Enum.ScaleType.Crop,
            }, card)
            corner(ic)
            local sub = o.subtitle or o.content
            text(card, {
                Position = UDim2.fromOffset(58, sub and 9 or 0), Size = UDim2.new(1, -68, sub and 20 or 1, 0),
                Font = Enum.Font.GothamBold, TextSize = 14, Text = o.title or "", TextTruncate = Enum.TextTruncate.AtEnd,
            })
            if sub then
                text(card, {
                    Position = UDim2.fromOffset(58, 29), Size = UDim2.new(1, -68, 0, 18), TextSize = 12, TextColor3 = MUTED,
                    Text = sub, TextTruncate = Enum.TextTruncate.AtEnd,
                })
            end
            tween(card, 0.4, { Position = UDim2.new(), GroupTransparency = 0 })
            task.delay(o.duration or 3, function()
                tween(card, 0.3, { Position = UDim2.fromOffset(320, 0), GroupTransparency = 1 })
                task.delay(0.35, function() wrap:Destroy() end)
            end)
        end
        function window:Notify(o) window:Toast(o) end

        ------------------------------------------------------------------
        -- Popups (dimmed overlay + scale-in card + circular option buttons)
        ------------------------------------------------------------------
        function window:Popup(o)
            local overlay = new("Frame", {
                Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
                BorderSizePixel = 0, ZIndex = 50,
            }, gui)
            local backdrop = new("TextButton", {
                Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
            }, overlay)
            local boxes = o.boxes or {}
            local height = 150 + (o.content and 44 or 0) + #boxes * 60 + (o.subtitle and 16 or 0)
            local card = new("CanvasGroup", {
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(390, height),
                BackgroundColor3 = Color3.fromRGB(16, 20, 34), BackgroundTransparency = 0.1, BorderSizePixel = 0,
                GroupTransparency = 1, Active = true,
            }, overlay)
            corner(card, 28)
            local cs = stroke(card, accent, 0.35, 1.5)
            local cardScale = new("UIScale", { Scale = 0.88 }, card)

            local y = 18
            text(card, {
                Position = UDim2.fromOffset(22, y), Size = UDim2.new(1, -44, 0, 24),
                Font = Enum.Font.GothamBold, TextSize = 19, Text = o.title or "",
            })
            y = y + 26
            if o.subtitle then
                local s = text(card, {
                    Position = UDim2.fromOffset(22, y), Size = UDim2.new(1, -44, 0, 14), TextSize = 12,
                    TextColor3 = WHITE, Text = o.subtitle,
                })
                y = y + 20
            end
            if o.content then
                text(card, {
                    Position = UDim2.fromOffset(22, y), Size = UDim2.new(1, -44, 0, 40), TextSize = 13,
                    TextColor3 = MUTED, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = o.content,
                })
                y = y + 46
            end
            for _, bx in ipairs(boxes) do
                local f = new("Frame", {
                    Position = UDim2.fromOffset(22, y), Size = UDim2.new(1, -44, 0, 52), BackgroundColor3 = WHITE,
                    BackgroundTransparency = 0.93, BorderSizePixel = 0,
                }, card)
                corner(f, 14)
                text(f, {
                    Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 18), Font = Enum.Font.GothamBold,
                    TextSize = 13, Text = bx.title or "",
                })
                text(f, {
                    Position = UDim2.fromOffset(12, 25), Size = UDim2.new(1, -24, 0, 22), TextSize = 11, TextColor3 = MUTED,
                    TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = bx.description or "",
                })
                y = y + 60
            end

            local closed = false
            local function close(after)
                if closed then return end
                closed = true
                tween(card, 0.22, { GroupTransparency = 1 })
                tween(cardScale, 0.22, { Scale = 0.92 })
                tween(overlay, 0.22, { BackgroundTransparency = 1 })
                task.delay(0.25, function()
                    overlay:Destroy()
                    if after then after() end
                end)
            end

            local optRow = new("Frame", {
                AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(1, -40, 0, 74),
                BackgroundTransparency = 1,
            }, card)
            new("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
                VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 26), SortOrder = Enum.SortOrder.LayoutOrder,
            }, optRow)
            for i, opt in ipairs(o.options or { { text = "OK", style = "primary" } }) do
                local cell = new("Frame", { Size = UDim2.fromOffset(70, 70), BackgroundTransparency = 1, LayoutOrder = i }, optRow)
                local glyph = opt.glyph or ((opt.style == "danger" or opt.style == "primary") and "✓" or "✕")
                local b = circleButton(cell, 44, glyph, function()
                    close(opt.callback)
                end, opt.style == "danger")
                b.AnchorPoint, b.Position = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 0)
                text(cell, {
                    Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 16), TextSize = 11, TextColor3 = MUTED,
                    TextXAlignment = Enum.TextXAlignment.Center, Text = opt.text or "",
                })
            end
            if o.dismissable ~= false then
                backdrop.Activated:Connect(function() close() end)
            end

            tween(overlay, 0.25, { BackgroundTransparency = 0.5 })
            tween(card, 0.3, { GroupTransparency = 0 })
            tween(cardScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
            return { Close = function() close() end }
        end

        ------------------------------------------------------------------
        -- Configs + flags
        ------------------------------------------------------------------
        local function ensureDirs()
            pcall(function()
                if makefolder then
                    if not isfolder(DIR) then makefolder(DIR) end
                    if not isfolder(CFG_DIR) then makefolder(CFG_DIR) end
                end
            end)
        end
        local function encode(v)
            local t = typeof(v)
            if t == "Color3" then return { c = { v.R, v.G, v.B } } end
            if t == "EnumItem" then return { k = v.Name } end
            return v
        end
        local function decode(v)
            if type(v) == "table" then
                if v.c then return Color3.new(v.c[1], v.c[2], v.c[3]) end
                if v.k then return Enum.KeyCode[v.k] end
            end
            return v
        end
        local function clean(name) return (tostring(name):gsub("[^%w%-_ ]", "")) end

        function window:Set(flag, value)
            local f = flags[flag]
            if f then f.set(value) end
        end
        function window:Save(name)
            ensureDirs()
            local data = {}
            for flag, f in pairs(flags) do data[flag] = encode(f.get()) end
            pcall(function() writefile(CFG_DIR .. "/" .. clean(name) .. ".json", HttpService:JSONEncode(data)) end)
        end
        function window:Load(name)
            local ok, raw = pcall(function() return readfile(CFG_DIR .. "/" .. clean(name) .. ".json") end)
            if not ok then return false end
            local ok2, data = pcall(function() return HttpService:JSONDecode(raw) end)
            if not ok2 then return false end
            loadingConfig = true
            for flag, val in pairs(data) do
                local f = flags[flag]
                if f then pcall(function() f.set(decode(val)) end) end
            end
            loadingConfig = false
            return true
        end
        function window:ListConfigs()
            local out = {}
            pcall(function()
                for _, path in ipairs(listfiles(CFG_DIR)) do
                    local n = path:match("([^/\\]+)%.json$")
                    if n and n:sub(1, 1) ~= "_" then out[#out + 1] = n end
                end
            end)
            return out
        end
        function window:DeleteConfig(name)
            pcall(function() delfile(CFG_DIR .. "/" .. clean(name) .. ".json") end)
        end
        function window:ConfigExists(name)
            local ok, exists = pcall(isfile, CFG_DIR .. "/" .. clean(name) .. ".json")
            return ok and exists == true
        end

        -- auto load: one config name remembered in Skyware/configs/_autoload.json
        -- (leading "_" keeps it out of the saved-configs list)
        local AUTOLOAD_FILE = CFG_DIR .. "/_autoload.json"
        function window:GetAutoLoad()
            local ok, raw = pcall(readfile, AUTOLOAD_FILE)
            if not ok then return nil end
            local ok2, data = pcall(function() return HttpService:JSONDecode(raw) end)
            if ok2 and type(data) == "table" and type(data.name) == "string" and data.name ~= "" then
                return data.name
            end
            return nil
        end
        function window:SetAutoLoad(name)
            ensureDirs()
            pcall(writefile, AUTOLOAD_FILE, HttpService:JSONEncode({ name = clean(name) }))
        end
        function window:ClearAutoLoad()
            pcall(function()
                if isfile(AUTOLOAD_FILE) then delfile(AUTOLOAD_FILE) end
            end)
        end

        -- autosave (debounced), mirrors the original autoSave = true / autoLoad = false
        local pending = false
        autosaveHook = function()
            if pending then return end
            pending = true
            task.delay(1.5, function()
                pending = false
                window:Save("_autosave")
            end)
        end

        return window
    end

    return { NewWindow = NewWindow }
end)()

-- Window --------------------------------------------------------------
-- Tab icons: a symbol, or an "rbxassetid://..." string for an image icon.
local TAB_ICONS = { Aim = "aim", Visuals = "eye", Misc = "sliders" }

local window = UI.NewWindow({ name = "Skyware", theme = "cobalt", logo = LOGO })
window:CreateTag({ text = "v1.0", order = 0 })

local aimTab = window:CreateTab({ name = "Aim", icon = TAB_ICONS.Aim })
local visTab = window:CreateTab({ name = "Visuals", icon = TAB_ICONS.Visuals })
local miscTab = window:CreateTab({ name = "Misc", icon = TAB_ICONS.Misc })

local DEFAULTS = {
    AimEnabled = false, AimShowFOV = false, AimFOVRadius = 300, AimHitPart = "Head",
    AimbotEnabled = false, AimbotShowFOV = false, AimbotFOVRadius = 80, AimbotSmooth = 1, AimbotHitPart = "Head", AimbotMaxDist = 300,
    VisESP = false, VisChams = false, VisChamsFillAlpha = 0, VisLockedColorOn = false, VisTargetLine = false,
    VisFullbright = false, VisRadar = false, VisCamFOVOn = false, VisCrosshair = false,
}

local function resetAll()
    for flag, value in pairs(DEFAULTS) do window:Set(flag, value) end
    log("settings reset")
end

local function showChangelog()
    local pop = window:Popup({
        title = "What's new",
        subtitle = "Skyware v1.0",
        boxes = {
            { title = "Silent aim", description = "Locks the closest player in your FOV circle. Hold-to-aim key." },
            { title = "Aimbot", description = "Turns the camera onto the closest player in its own FOV circle and range. Smoothing, toggle/hold keys and a mobile quick toggle." },
            { title = "ESP", description = "Skeleton, name, health and studs in one toggle." },
            { title = "Chams", description = "Outline chams, fill alpha follows the color picker." },
            { title = "Interface", description = "Themes, languages, saved configs and a live log." },
        },
        options = { { text = "Got it", style = "primary" } },
    })
    task.delay(30, function() pcall(function() pop:Close() end) end)
end

local function keyToast(label)
    return function(key)
        window:Toast({
            title = label .. " key set",
            subtitle = typeof(key) == "EnumItem" and key.Name or tostring(key or "none"),
        })
    end
end

-- Aim tab ---------------------------------------------------------------
aimTab:Section("Silent Aim")

local aimRow = aimTab:Grid(2)
local aimToggle = aimRow:Toggle({
    name = "Enabled",
    flag = "AimEnabled",
    value = C.Enabled,
    callback = function(value)
        C.Enabled = value
        log(value and "silent aim on" or "silent aim off")
        window:Toast({ title = value and "Silent Aim on" or "Silent Aim off" })
    end,
})
aimRow:Toggle({
    name = "Show FOV",
    flag = "AimShowFOV",
    value = C.ShowFOV,
    callback = function(value) C.ShowFOV = value end,
})

aimTab:Cycle({
    name = "Hit Part",
    flag = "AimHitPart",
    options = { "Head", "UpperTorso", "HumanoidRootPart", "LowerTorso" },
    value = C.HitPart,
    callback = function(selected) C.HitPart = selected end,
})

local fovSlider = aimTab:Slider({
    name = "FOV Radius",
    flag = "AimFOVRadius",
    range = { 50, 800 },
    increment = 5,
    step = 10,
    value = C.FOVRadius,
    suffix = "px",
    callback = function(value, dragging)
        C.FOVRadius = value
        C.FOVPreview = dragging == true -- circle shows while the handle is held
    end,
})

aimTab:Input({
    name = "Exact FOV Radius",
    flag = "AimFOVInput",
    numeric = true,
    value = tostring(C.FOVRadius),
    placeholder = "50 - 800",
    forgetState = true,
    callback = function(text)
        local n = tonumber(text)
        if n then fovSlider:Set(math.clamp(n, 50, 800)) end
    end,
})

aimTab:Keybind({
    name = "Toggle Silent Aim",
    description = "Click the circle, press a key. Backspace clears.",
    flag = "AimKey",
    value = Enum.KeyCode.Z,
    callback = function() aimToggle:Set(not aimToggle.value) end,
    onChanged = keyToast("Aim"),
})

aimTab:Keybind({
    name = "Hold To Aim",
    description = "Silent aim is live only while this is held",
    flag = "AimHoldKey",
    value = Enum.KeyCode.V,
    hold = true,
    holdThreshold = 0.2,
    callback = function(held) C.Holding = held == true end,
    onChanged = keyToast("Hold"),
})

-- Aimbot -----------------------------------------------------------------
aimTab:Section("Aimbot")

local aimbotQuick -- mobile quick toggle, created after the toggle below
local aimbotRow = aimTab:Grid(2)
local aimbotToggle = aimbotRow:Toggle({
    name = "Aimbot",
    flag = "AimbotEnabled",
    value = C.Aimbot.Enabled,
    callback = function(value)
        C.Aimbot.Enabled = value
        if aimbotQuick then aimbotQuick.Set(value) end
        log(value and "aimbot on" or "aimbot off")
        window:Toast({ title = value and "Aimbot on" or "Aimbot off" })
    end,
})
aimbotQuick = window:QuickToggle({
    glyph = "aim",
    callback = function(v) aimbotToggle:Set(v) end,
})
aimbotQuick.Set(C.Aimbot.Enabled)

aimbotRow:Toggle({
    name = "Aimbot FOV",
    flag = "AimbotShowFOV",
    value = C.Aimbot.ShowFOV,
    callback = function(value) C.Aimbot.ShowFOV = value end,
})

aimTab:Cycle({
    name = "Lock Part",
    flag = "AimbotHitPart",
    options = { "Head", "UpperTorso", "HumanoidRootPart", "LowerTorso" },
    value = C.Aimbot.HitPart,
    callback = function(selected) C.Aimbot.HitPart = selected end,
})

local aimbotFovSlider = aimTab:Slider({
    name = "Aimbot FOV Radius",
    flag = "AimbotFOVRadius",
    range = { 20, 800 },
    increment = 5,
    step = 10,
    value = C.Aimbot.FOVRadius,
    suffix = "px",
    callback = function(value, dragging)
        C.Aimbot.FOVRadius = value
        C.Aimbot.FOVPreview = dragging == true
    end,
})

aimTab:Slider({
    name = "Aimbot Range",
    flag = "AimbotMaxDist",
    range = { 10, 300 },
    increment = 5,
    value = C.Aimbot.MaxDist,
    suffix = " studs",
    callback = function(value) C.Aimbot.MaxDist = value end,
})

aimTab:Slider({
    name = "Smoothing",
    flag = "AimbotSmooth",
    range = { 1, 20 },
    increment = 1,
    value = C.Aimbot.Smooth,
    suffix = "",
    callback = function(value) C.Aimbot.Smooth = value end,
})

aimTab:Keybind({
    name = "Toggle Aimbot",
    description = "Click the circle, press a key. Backspace clears.",
    flag = "AimbotKey",
    value = Enum.KeyCode.C,
    callback = function() aimbotToggle:Set(not aimbotToggle.value) end,
    onChanged = keyToast("Aimbot"),
})

aimTab:Keybind({
    name = "Hold Aimbot",
    description = "Aimbot is live only while this is held",
    flag = "AimbotHoldKey",
    value = Enum.KeyCode.B,
    hold = true,
    holdThreshold = 0.2,
    callback = function(held) C.Aimbot.Holding = held == true end,
    onChanged = keyToast("Aimbot hold"),
})

aimTab:Section("Target")

local targetText = aimTab:Text({ name = "Status", text = "No target", height = 54 })
local healthBar = aimTab:Progress({
    name = "Target Health", range = { 0, 100 }, value = 0,
    format = function(v) return string.format("%d%%", math.floor(v + 0.5)) end,
})
local stageBar = aimTab:Progress({
    name = "Aim Stage", steps = 3, value = 0,
    stageNames = { "Idle", "Scanning", "Armed", "Locked" },
})

local stats = aimTab:Stats({
    { name = "In FOV" },
    { name = "Nearest" },
    { name = "Closing", delta = true },
    { name = "Locks", relative = true },
})
local inFovStat, nearestStat, closingStat, locksStat = stats[1], stats[2], stats[3], stats[4]

-- Visuals tab -------------------------------------------------------------
visTab:Section("ESP")
local espGrid = visTab:Grid(2)
local espToggle = espGrid:Toggle({
    name = "ESP",
    description = "Skeleton, name, health, studs",
    flag = "VisESP",
    value = V.ESP,
    callback = function(value)
        V.ESP = value
        log(value and "esp on" or "esp off")
        window:Toast({ title = value and "ESP on" or "ESP off" })
    end,
})
espGrid:Toggle({
    name = "Chams",
    description = "Outline through walls",
    flag = "VisChams",
    value = V.Chams,
    callback = function(value) V.Chams = value end,
})

local fillSlider = visTab:Slider({
    name = "Chams Fill Alpha",
    flag = "VisChamsFillAlpha",
    range = { 0, 1 },
    increment = 0.05,
    value = V.ChamsFillAlpha,
    callback = function(value) V.ChamsFillAlpha = value end,
})

visTab:Color({
    name = "ESP Color",
    flag = "VisESPColor",
    color = V.ESPColor,
    callback = function(color) V.ESPColor = color end,
})

visTab:Color({
    name = "Chams Color",
    description = "Fill amount is set by Chams Fill Alpha",
    flag = "VisChamsColor",
    color = V.ChamsColor,
    callback = function(color) V.ChamsColor = color end,
})

visTab:Keybind({
    name = "Toggle ESP",
    flag = "ESPKey",
    value = Enum.KeyCode.X,
    callback = function() espToggle:Set(not espToggle.value) end,
    onChanged = keyToast("ESP"),
})

visTab:Section("Locked Target")

local lockRow = visTab:Grid(2)
lockRow:Toggle({
    name = "Locked Color",
    description = "Recolor the locked player",
    flag = "VisLockedColorOn",
    value = V.LockedColorOn,
    callback = function(value) V.LockedColorOn = value end,
})
lockRow:Toggle({
    name = "Target Line",
    description = "Line to the locked player",
    flag = "VisTargetLine",
    value = V.TargetLine,
    callback = function(value) V.TargetLine = value end,
})

visTab:Color({
    name = "Locked Target Color",
    flag = "VisLockedColor",
    color = V.LockedColor,
    callback = function(color) V.LockedColor = color end,
})

visTab:Section("FOV Circle")

local fovRow = visTab:Grid(2)
fovRow:Toggle({
    name = "Filled",
    flag = "VisFOVFilled",
    value = V.FOVFilled,
    callback = function(value) V.FOVFilled = value end,
})
fovRow:Toggle({
    name = "Rainbow",
    flag = "VisFOVRainbow",
    value = V.FOVRainbow,
    callback = function(value) V.FOVRainbow = value end,
})
fovRow:Toggle({
    name = "Crosshair",
    flag = "VisCrosshair",
    value = V.Crosshair,
    callback = function(value) V.Crosshair = value end,
})

visTab:Slider({
    name = "FOV Thickness",
    flag = "VisFOVThickness",
    range = { 1, 5 },
    increment = 1,
    value = V.FOVThickness,
    suffix = "px",
    callback = function(value) V.FOVThickness = value end,
})

visTab:Color({
    name = "FOV Color",
    flag = "VisFOVColor",
    color = V.FOVColor,
    callback = function(color) V.FOVColor = color end,
})

visTab:Section("World")

local worldRow = visTab:Grid(2)
worldRow:Toggle({
    name = "Fullbright",
    flag = "VisFullbright",
    value = V.Fullbright,
    callback = function(value)
        V.Fullbright = value
        applyFullbright(value)
    end,
})
worldRow:Toggle({
    name = "Radar",
    flag = "VisRadar",
    value = V.Radar,
    callback = function(value) V.Radar = value end,
})
worldRow:Toggle({
    name = "Custom Camera FOV",
    flag = "VisCamFOVOn",
    value = V.CamFOVEnabled,
    callback = function(value)
        V.CamFOVEnabled = value
        if not value then cam.FieldOfView = originalFOV end
    end,
})

visTab:Slider({
    name = "Camera FOV",
    flag = "VisCameraFOV",
    range = { 40, 120 },
    increment = 1,
    value = V.CameraFOV,
    suffix = "°",
    callback = function(value) V.CameraFOV = value end,
})

-- Misc tab ------------------------------------------------------------------
miscTab:Section("Interface")

local boot = miscTab:Progress({
    name = "Startup", range = { 0, 1 }, value = 0,
    format = function(v) return v >= 1 and "Ready" or "Loading..." end,
})

miscTab:Text({
    name = "Skyware",
    text = "Hold V to aim, Z and X toggle, RightShift hides the menu. The round logo brings it back.",
    small = true, height = 66,
})

miscTab:Cycle({
    name = "Theme",
    flag = "MiscTheme",
    options = { "default", "cobalt", "ember", "amethyst", "frost", "rose" },
    value = "cobalt",
    callback = function(selected) window:ChangeTheme(selected) end,
})

miscTab:Cycle({
    name = "Language",
    flag = "MiscLanguage",
    options = { "en", "fr", "es", "de" },
    value = "en",
    callback = function(selected) pcall(window.SetLocale, window, selected) end,
})

miscTab:Toggle({
    name = "Background Blur",
    description = "Glass blur behind the menu",
    flag = "MiscBlur",
    value = true,
    callback = function(value) window:SetBlur(value) end,
})

miscTab:Slider({
    name = "UI Size",
    flag = "MiscUIScale",
    range = { 0.6, 1.6 },
    increment = 0.05,
    value = window:GetScale(),
    callback = function(value) window:SetScale(value) end,
})

miscTab:Keybind({
    name = "Toggle UI",
    flag = "MiscUIKey",
    value = Enum.KeyCode.RightShift,
    callback = function() window:ToggleHide() end,
    onChanged = keyToast("UI"),
})

miscTab:Divider("Tools")

miscTab:Buttons({
    { name = "Changelog", glyph = "i", callback = showChangelog },
    {
        name = "Reset All", glyph = "↺", danger = true,
        callback = function()
            window:Popup({
                title = "Reset everything?",
                content = "This turns every feature off and restores default values.",
                dismissable = false,
                options = {
                    { text = "Cancel" },
                    { text = "Reset", style = "danger", callback = resetAll },
                },
            })
        end,
    },
    { name = "Go To Aim", glyph = "◎", callback = function() aimTab:Select() end },
    { name = "Go To Visuals", glyph = "◉", callback = function() window:Navigate("Visuals") end },
    {
        name = "Dump Flags", glyph = "{}",
        callback = function()
            for flag, f in pairs(window.Flags) do
                local value = f.get()
                log(flag .. " = " .. (typeof(value) == "table" and "{table}" or tostring(value)))
            end
        end,
    },
    {
        name = "List Configs", glyph = "≡",
        callback = function()
            local configs = window:ListConfigs()
            log("configs: " .. (#configs > 0 and table.concat(configs, ", ") or "none"))
        end,
    },
    {
        name = "Reset Stats", glyph = "0",
        callback = function()
            for _, s in ipairs({ inFovStat, nearestStat, closingStat, locksStat }) do s:ResetBaseline() end
        end,
    },
})

miscTab:Divider("Configs")

local newConfigName = ""
local selectedConfig = nil
local autoLoadedName      -- set when a config was auto loaded this session
local refreshAutoStatus   -- assigned below, used by the delete button

local function configList()
    local list = window:ListConfigs()
    table.sort(list)
    return list
end

local configDropdown = miscTab:Cycle({
    name = "Saved Configs",
    flag = "MiscSavedConfigs",
    options = configList(),
    placeholder = "None saved",
    forgetState = true,
    callback = function(selected)
        selectedConfig = (type(selected) == "string" and selected ~= "") and selected or nil
    end,
})

miscTab:Input({
    name = "New Config Name",
    description = "Empty = overwrite the picked config",
    flag = "MiscConfigName",
    value = "",
    placeholder = "PvP",
    forgetState = true,
    callback = function(text) newConfigName = text end,
})

local function refreshConfigs(select)
    configDropdown:Refresh(configList())
    if select then configDropdown:Set(select) end
end

miscTab:Buttons({
    {
        name = "Save Config", glyph = "↓",
        callback = function()
            local name = newConfigName ~= "" and newConfigName or selectedConfig
            if not name then
                window:Toast({ title = "Type a config name first" })
                return
            end
            window:Save(name)
            refreshConfigs(name)
            log("saved config: " .. name)
            window:Toast({ title = "Config saved", subtitle = name })
        end,
    },
    {
        name = "Load Config", glyph = "↑",
        callback = function()
            if not selectedConfig then
                window:Toast({ title = "Pick a saved config first" })
                return
            end
            window:Load(selectedConfig)
            log("loaded config: " .. selectedConfig)
            window:Toast({ title = "Config loaded", subtitle = selectedConfig })
        end,
    },
    {
        name = "Delete Config", glyph = "✕", danger = true,
        callback = function()
            local name = selectedConfig
            if not name then
                window:Toast({ title = "Pick a saved config first" })
                return
            end
            window:Popup({
                title = "Delete config?",
                content = "\"" .. name .. "\" will be removed for good.",
                dismissable = false,
                options = {
                    { text = "Cancel" },
                    {
                        text = "Delete", style = "danger",
                        callback = function()
                            window:DeleteConfig(name)
                            selectedConfig = nil
                            refreshConfigs()
                            if window:GetAutoLoad() == name then
                                window:ClearAutoLoad()
                                autoLoadedName = nil
                                log("auto load cleared (config deleted)")
                            end
                            if refreshAutoStatus then refreshAutoStatus() end
                            log("deleted config: " .. name)
                        end,
                    },
                },
            })
        end,
    },
    { name = "Refresh", glyph = "↻", callback = function() refreshConfigs(selectedConfig) end },
})

-- Auto load -----------------------------------------------------------------
local autoStatus = miscTab:Text({ name = "Auto Load Status", text = "", height = 52 })
refreshAutoStatus = function()
    local name = window:GetAutoLoad()
    if not name then
        autoStatus:Set("Off. No config loads on start.")
    elseif not window:ConfigExists(name) then
        autoStatus:Set("\"" .. name .. "\" is set to auto load but its file is missing.")
    elseif autoLoadedName == name then
        autoStatus:Set("Auto loading: " .. name .. " (loaded this session)")
    else
        autoStatus:Set("Auto loading: " .. name)
    end
end

miscTab:Buttons({
    {
        name = "Set Auto Load", glyph = "check",
        callback = function()
            if not selectedConfig then
                window:Toast({ title = "Pick a saved config first" })
                return
            end
            window:SetAutoLoad(selectedConfig)
            autoLoadedName = nil
            refreshAutoStatus()
            log("auto load set: " .. selectedConfig)
            window:Toast({ title = "Auto load set", subtitle = selectedConfig })
        end,
    },
    {
        name = "Clear Auto Load", glyph = "close",
        callback = function()
            if not window:GetAutoLoad() then
                window:Toast({ title = "No auto load set" })
                return
            end
            window:ClearAutoLoad()
            autoLoadedName = nil
            refreshAutoStatus()
            log("auto load cleared")
            window:Toast({ title = "Auto load cleared" })
        end,
    },
})

miscTab:Divider("Log")

console = miscTab:Console({ name = "Log", height = 130, follow = true, maxLines = 200 })

miscTab:Buttons({
    {
        name = "Copy Log", glyph = "C",
        callback = function()
            local ok = console:Copy()
            window:Toast({ title = ok and "Log copied" or "No clipboard access" })
        end,
    },
    { name = "Clear Log", glyph = "✕", callback = function() console:Clear() end },
})

window:Show() -- fade + scale pop-up

-- FOV circle + crosshair
local FOV = Drawing.new("Circle")
FOV.Color = Color3.fromRGB(255, 255, 255)
FOV.Thickness = 1
FOV.Filled = false
FOV.NumSides = 64

local crossH = Drawing.new("Line")
local crossV = Drawing.new("Line")
crossH.Thickness, crossV.Thickness = 1, 1
crossH.Visible, crossV.Visible = false, false

runs.RenderStepped:Connect(function()
    local center = cam.ViewportSize / 2
    local color = V.FOVRainbow and Color3.fromHSV((os.clock() * 0.3) % 1, 1, 1) or V.FOVColor

    FOV.Position = center
    FOV.Radius = C.FOVRadius
    FOV.Color = color
    FOV.Thickness = V.FOVThickness
    FOV.Filled = V.FOVFilled
    FOV.Transparency = V.FOVFilled and 0.15 or 1
    FOV.Visible = (aimActive() and C.ShowFOV) or C.FOVPreview

    crossH.Visible, crossV.Visible = V.Crosshair, V.Crosshair
    if V.Crosshair then
        crossH.Color, crossV.Color = color, color
        crossH.From, crossH.To = center - Vector2.new(8, 0), center + Vector2.new(8, 0)
        crossV.From, crossV.To = center - Vector2.new(0, 8), center + Vector2.new(0, 8)
    end
end)

-- Every entity worth drawing or targeting: tagged entities plus all player characters,
-- re-read every call so players who join or respawn are picked up immediately.
local function getEntities()
    local list, seen = {}, {}
    -- only things that are actually characters: a Humanoid, or a root part plus a head.
    -- (the "Entity" tag also covers map pieces like windows, which must never be drawn)
    local function isCharacter(m)
        if m:FindFirstChildOfClass("Humanoid") then return true end
        return m:FindFirstChild("HumanoidRootPart") ~= nil and m:FindFirstChild("Head") ~= nil
    end
    local function add(m)
        if m and m ~= lplr.Character and not seen[m] and m:IsA("Model") and m:IsDescendantOf(workspace) and isCharacter(m) then
            seen[m] = true
            table.insert(list, m)
        end
    end
    for _, m in cs:GetTagged("Entity") do add(m) end
    for _, p in plrs:GetPlayers() do add(p.Character) end
    return list
end

-- ESP + chams
local R15_BONES = {
    { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
    { "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
    { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
    { "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
    { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
}
local R6_BONES = {
    { "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
    { "Torso", "Left Leg" }, { "Torso", "Right Leg" },
}

local chamsFolder = Instance.new("Folder")
chamsFolder.Name = "VisualCache"
chamsFolder.Parent = (gethui and gethui()) or game:GetService("CoreGui")

local function newDrawing(class, props)
    local d = Drawing.new(class)
    for k, v in props do d[k] = v end
    return d
end

local espObjects = {}

local function newEsp(entity)
    local cham = Instance.new("Highlight")
    cham.Adornee = entity
    cham.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    cham.OutlineTransparency = 0
    cham.Enabled = false
    cham.Parent = chamsFolder

    local o = {
        cham = cham,
        parts = {},
        bones = {},
        hpBack = newDrawing("Line", { Thickness = 4, Color = Color3.new(0, 0, 0), Visible = false }),
        hpFill = newDrawing("Line", { Thickness = 2, Visible = false }),
        name = newDrawing("Text", { Size = 13, Center = true, Outline = true, Visible = false }),
        dist = newDrawing("Text", { Size = 13, Center = true, Outline = true, Visible = false }),
    }
    espObjects[entity] = o
    return o
end

local function destroyEsp(o)
    o.cham:Destroy()
    o.hpBack:Remove(); o.hpFill:Remove()
    o.name:Remove(); o.dist:Remove()
    for _, l in o.bones do l:Remove() end
end

local function hideDrawings(o)
    o.hpBack.Visible = false
    o.hpFill.Visible = false
    o.name.Visible = false
    o.dist.Visible = false
    for _, l in o.bones do l.Visible = false end
end

local function getPart(o, entity, partName)
    local p = o.parts[partName]
    if p and p.Parent then return p end
    p = entity:FindFirstChild(partName, true)
    o.parts[partName] = p
    return p
end

local function updateEsp(entity, o)
    local root = entity:FindFirstChild("HumanoidRootPart") or entity.PrimaryPart
    local dist = root and (cam.CFrame.Position - root.Position).Magnitude or math.huge
    local inRange = dist <= V.MaxDistance

    local isLocked = V.LockedColorOn and entity == lockedEntity
    local chamColor = isLocked and V.LockedColor or V.ChamsColor

    o.cham.Enabled = V.Chams and inRange
    o.cham.FillColor = chamColor
    o.cham.OutlineColor = chamColor
    o.cham.FillTransparency = 1 - V.ChamsFillAlpha -- alpha 0 = no fill, outline only

    if not (V.ESP and inRange) then hideDrawings(o) return end

    -- screen-space bounds, used to anchor the health bar and text
    local cf, size = entity:GetBoundingBox()
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    local allInFront = true
    for ix = -1, 1, 2 do
        for iy = -1, 1, 2 do
            for iz = -1, 1, 2 do
                local corner = cf * CFrame.new(size.X / 2 * ix, size.Y / 2 * iy, size.Z / 2 * iz)
                local p = cam:WorldToViewportPoint(corner.Position)
                if p.Z <= 0 then allInFront = false end
                minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
                minY, maxY = math.min(minY, p.Y), math.max(maxY, p.Y)
            end
        end
    end
    if not allInFront then hideDrawings(o) return end

    local color = isLocked and V.LockedColor or V.ESPColor
    local cx = (minX + maxX) / 2

    local hum = entity:FindFirstChildOfClass("Humanoid")
    local hp = hum and hum.Health or entity:GetAttribute("Health")
    local maxHp = hum and hum.MaxHealth or entity:GetAttribute("MaxHealth")
    local showHealth = hp and maxHp and maxHp > 0
    o.hpBack.Visible = showHealth
    o.hpFill.Visible = showHealth
    if showHealth then
        local pct = math.clamp(hp / maxHp, 0, 1)
        local x = minX - 5
        o.hpBack.From = Vector2.new(x, maxY + 1)
        o.hpBack.To = Vector2.new(x, minY - 1)
        o.hpFill.From = Vector2.new(x, maxY)
        o.hpFill.To = Vector2.new(x, maxY - (maxY - minY) * pct)
        o.hpFill.Color = Color3.fromRGB(255, 50, 50):Lerp(Color3.fromRGB(60, 255, 80), pct)
    end

    local plr = plrs:GetPlayerFromCharacter(entity)
    o.name.Visible = true
    o.name.Text = plr and plr.DisplayName or entity.Name
    o.name.Color = color
    o.name.Position = Vector2.new(cx, minY - 16)

    o.dist.Visible = true
    o.dist.Text = string.format("%d studs", dist)
    o.dist.Color = color
    o.dist.Position = Vector2.new(cx, maxY + 2)

    local bones = getPart(o, entity, "UpperTorso") and R15_BONES or R6_BONES
    for i, pair in bones do
        local line = o.bones[i]
        if not line then
            line = newDrawing("Line", { Thickness = 1, Visible = false })
            o.bones[i] = line
        end
        local a, b = getPart(o, entity, pair[1]), getPart(o, entity, pair[2])
        if a and b then
            local pa, onA = cam:WorldToViewportPoint(a.Position)
            local pb, onB = cam:WorldToViewportPoint(b.Position)
            line.Visible = onA and onB
            line.Color = color
            line.From = Vector2.new(pa.X, pa.Y)
            line.To = Vector2.new(pb.X, pb.Y)
        else
            line.Visible = false
        end
    end
end

runs.RenderStepped:Connect(function()
    local seen = {}
    for _, entity in getEntities() do
        seen[entity] = true
        local o = espObjects[entity]
        if not o then
            local ok, made = pcall(newEsp, entity)
            if not ok then continue end
            o = made
        end
        if not pcall(updateEsp, entity, o) then hideDrawings(o) end
    end
    for entity, o in espObjects do
        if not seen[entity] then
            destroyEsp(o)
            espObjects[entity] = nil
        end
    end
end)

-- Silent aim: closest entity to the screen center inside the FOV circle
local function findTarget()
    local center = cam.ViewportSize / 2
    local bestPart, bestEntity, bestDist = nil, nil, C.FOVRadius
    for _, entity in getEntities() do
        if entity == lplr.Character then continue end
        local part = entity:FindFirstChild(C.HitPart, true)
        if not part or not part:IsA("BasePart") then continue end
        local sp, onScreen = cam:WorldToViewportPoint(part.Position)
        if not onScreen then continue end
        local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
        if d < bestDist then bestDist, bestPart, bestEntity = d, part, entity end
    end
    return bestPart, bestEntity
end

local function target()
    if not aimActive() then return nil end
    return (findTarget())
end

-- Aimbot: turns the camera toward the closest player inside its own FOV circle.
local aimbotFOV = Drawing.new("Circle")
aimbotFOV.Thickness = 1.5
aimbotFOV.Filled = false
aimbotFOV.NumSides = 64
aimbotFOV.Transparency = 0.7
aimbotFOV.Visible = false

-- Sticky lock: once a player is picked we stay on them until they die or leave range.
-- No FOV leash, a short grace period if their parts blip out (respawn, streaming), and the
-- camera is re-asserted whenever anything else writes to it, so the lock doesn't detach.
local lockedModel, lockedPart, lostAt
local aimbotPart -- the part we're aiming at this frame (read by the camera-write guard below)
local applyingLock = false
-- Release easing: when the aimbot turns off, the game's own camera snaps back to where its
-- input says it should be (that's the flick). We blend from our last aim back to the game's
-- camera over a short moment instead.
local wasActive = false
local lastLockCF, releaseCF, releaseAt
local RELEASE_TIME = 0.3

local function resolvePart(model, K)
    local p = model:FindFirstChild(K.HitPart, true)
    if p and p:IsA("BasePart") then return p end
    local root = model:FindFirstChild("HumanoidRootPart")
    return (root and root:IsA("BasePart")) and root or nil
end

-- "ok" | "missing" (grace period applies) | "drop" (dead / out of range)
local function lockState(K)
    if not lockedModel or not lockedModel.Parent or not lockedModel:IsDescendantOf(workspace) then return "missing" end
    local hum = lockedModel:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 0 then return "drop" end
    local part = resolvePart(lockedModel, K)
    if not part then return "missing" end
    if (part.Position - cam.CFrame.Position).Magnitude > K.MaxDist * 1.25 then return "drop" end
    lockedPart = part
    return "ok"
end

local function findAimbotTarget()
    local K = C.Aimbot
    local center = cam.ViewportSize / 2

    if lockedModel then
        local state = lockState(K)
        if state == "ok" then
            lostAt = nil
            return lockedPart
        elseif state == "missing" then
            lostAt = lostAt or os.clock()
            if os.clock() - lostAt < 0.4 and lockedPart and lockedPart.Parent then
                return lockedPart -- keep aiming at the last known spot during the blip
            end
        end
        lockedModel, lockedPart, lostAt = nil, nil, nil
    end

    local best, bestModel, bestDist = nil, nil, K.FOVRadius
    for _, entity in getEntities() do
        local hum = entity:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health <= 0 then continue end
        local part = resolvePart(entity, K)
        if not part then continue end
        if (part.Position - cam.CFrame.Position).Magnitude > K.MaxDist then continue end
        local sp, onScreen = cam:WorldToViewportPoint(part.Position)
        if not onScreen then continue end
        local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
        if d < bestDist then bestDist, best, bestModel = d, part, entity end
    end
    lockedModel, lockedPart = bestModel, best
    return best
end

runs:BindToRenderStep("SkywareAimbot", Enum.RenderPriority.Last.Value, function()
    local K = C.Aimbot
    local active = K.Enabled or K.Holding
    aimbotFOV.Position = cam.ViewportSize / 2
    aimbotFOV.Radius = K.FOVRadius
    aimbotFOV.Color = V.FOVRainbow and Color3.fromHSV((os.clock() * 0.3) % 1, 1, 1) or V.FOVColor
    aimbotFOV.Visible = (active and K.ShowFOV) or K.FOVPreview
    if not active then
        lockedModel, lockedPart, lostAt, aimbotPart = nil, nil, nil, nil
        if wasActive then
            wasActive = false
            if lastLockCF then releaseCF, releaseAt = lastLockCF, os.clock() end
            lastLockCF = nil
        end
        if releaseCF then
            local t = (os.clock() - releaseAt) / RELEASE_TIME
            if t >= 1 then
                releaseCF = nil
            else
                local a = t * t * (3 - 2 * t) -- smoothstep: starts on our aim, ends on the game's camera
                local gameCF = cam.CFrame
                local fromRot = releaseCF - releaseCF.Position
                local toRot = gameCF - gameCF.Position
                applyingLock = true
                cam.CFrame = CFrame.new(gameCF.Position) * fromRot:Lerp(toRot, a)
                applyingLock = false
            end
        end
        return
    end
    wasActive = true
    releaseCF = nil

    local part = findAimbotTarget()
    aimbotPart = part
    if part then
        local goal = CFrame.lookAt(cam.CFrame.Position, part.Position)
        local alpha = 1 / math.max(K.Smooth, 1)
        applyingLock = true
        cam.CFrame = alpha >= 1 and goal or cam.CFrame:Lerp(goal, alpha)
        applyingLock = false
        lastLockCF = cam.CFrame
    else
        lastLockCF = nil
    end
end)

-- If any other script moves the camera after us, snap straight back onto the target
-- (only for a hard lock; with smoothing above 1 the softer pull is intentional).
cam:GetPropertyChangedSignal("CFrame"):Connect(function()
    if applyingLock then return end
    local K = C.Aimbot
    if K.Smooth > 1 or not (K.Enabled or K.Holding) then return end
    local part = aimbotPart
    if not part or not part.Parent then return end
    applyingLock = true
    cam.CFrame = CFrame.lookAt(cam.CFrame.Position, part.Position)
    applyingLock = false
end)

local function CFD(origin, part)
    local cf = part.CFrame
    local d = {}
    d[utf8.char(1)] = {
        [utf8.char(0)] = U:EncodeCFrame(CFrame.lookAt(origin, part.Position)),
        [utf8.char(1)] = U:EncodeCFrame(cf),
        [utf8.char(2)] = part,
        [utf8.char(3)] = U:EncodeCFrame(cf:ToObjectSpace(CFrame.new(part.Position))),
    }
    return d
end

local visual = GU.GetEntitiesFromRaycast
GU.GetEntitiesFromRaycast = function(self, envID, params, origin, dir, maxDist, ...)
    local t = target()
    if t then
        local dist = (t.Position - origin).Magnitude
        dir = (t.Position - origin).Unit
        if dist > maxDist then maxDist = dist + 5 end
    end
    return visual(self, envID, params, origin, dir, maxDist, ...)
end

local UseItem = reps.Remotes.Replication.Fighter.UseItem
local hook; hook = hookfunction(UseItem.FireServer, newcclosure(function(self, objID, enumVal, camdata, extra)
    if enumVal == EL:ToEnum("StartShooting") then
        local root = lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart")
        local t = target()
        if root and t then camdata = CFD(root.Position, t) end
    end
    return hook(self, objID, enumVal, camdata, extra)
end))

-- Locked target: updated every frame so recoloring and the target line follow it instantly
local targetLine = newDrawing("Line", { Thickness = 1, Visible = false })

runs.RenderStepped:Connect(function()
    if aimActive() then
        local part, entity = findTarget()
        lockedEntity = entity
        if V.TargetLine and part then
            local sp = cam:WorldToViewportPoint(part.Position)
            targetLine.From = cam.ViewportSize / 2
            targetLine.To = Vector2.new(sp.X, sp.Y)
            targetLine.Color = V.LockedColor
            targetLine.Visible = true
        else
            targetLine.Visible = false
        end
    else
        lockedEntity = nil
        targetLine.Visible = false
    end
end)

-- Radar: top-left, rotates with your camera, range matches the ESP range
local RADAR_RADIUS = 80
local RADAR_CENTER = Vector2.new(RADAR_RADIUS + 20, RADAR_RADIUS + 120)
local radarBack = newDrawing("Circle", {
    Radius = RADAR_RADIUS, Filled = true, Color = Color3.new(0, 0, 0), Transparency = 0.5,
    NumSides = 48, Position = RADAR_CENTER, Visible = false,
})
local radarRing = newDrawing("Circle", {
    Radius = RADAR_RADIUS, Filled = false, Thickness = 1, Color = Color3.new(1, 1, 1),
    NumSides = 48, Position = RADAR_CENTER, Visible = false,
})
local radarSelf = newDrawing("Circle", {
    Radius = 3, Filled = true, Color = Color3.new(1, 1, 1), NumSides = 12,
    Position = RADAR_CENTER, Visible = false,
})
local radarDots = {}

local function updateRadar()
    local on = V.Radar
    radarBack.Visible, radarRing.Visible, radarSelf.Visible = on, on, on
    if not on then
        for _, d in radarDots do d.Visible = false end
        return
    end

    local camPos = cam.CFrame.Position
    local look = cam.CFrame.LookVector
    local fwd = Vector3.new(look.X, 0, look.Z)
    fwd = fwd.Magnitude < 1e-3 and Vector3.new(0, 0, -1) or fwd.Unit
    local right = fwd:Cross(Vector3.yAxis)
    local scale = RADAR_RADIUS / V.MaxDistance

    local used = 0
    for _, entity in getEntities() do
        local root = entity:FindFirstChild("HumanoidRootPart") or entity.PrimaryPart
        if not root then continue end
        local d = root.Position - camPos
        local x, z = d:Dot(right), d:Dot(fwd)
        if math.sqrt(x * x + z * z) > V.MaxDistance then continue end

        used += 1
        local dot = radarDots[used]
        if not dot then
            dot = newDrawing("Circle", { Radius = 3, Filled = true, NumSides = 12, Visible = false })
            radarDots[used] = dot
        end
        dot.Position = RADAR_CENTER + Vector2.new(x, -z) * scale
        dot.Color = (V.LockedColorOn and entity == lockedEntity) and V.LockedColor or V.ESPColor
        dot.Visible = true
    end
    for i = used + 1, #radarDots do radarDots[i].Visible = false end
end

-- World: camera FOV and fullbright are re-applied each frame because games love to reset them
runs.RenderStepped:Connect(function()
    pcall(updateRadar)
    if V.CamFOVEnabled then cam.FieldOfView = V.CameraFOV end
    if V.Fullbright then applyFullbright(true) end
end)

-- Live target info (stats, stage, status text, health bar). No notifications here.
task.spawn(function()
    local lastName
    local locks = 0
    while task.wait(0.25) do
        local center = cam.ViewportSize / 2
        local inFov, nearest = 0, math.huge
        for _, entity in getEntities() do
            if entity == lplr.Character then continue end
            local root = entity:FindFirstChild("HumanoidRootPart") or entity.PrimaryPart
            if not root then continue end
            nearest = math.min(nearest, (cam.CFrame.Position - root.Position).Magnitude)
            local sp, on = cam:WorldToViewportPoint(root.Position)
            if on and (Vector2.new(sp.X, sp.Y) - center).Magnitude <= C.FOVRadius then
                inFov += 1
            end
        end

        local nearestStuds = nearest == math.huge and 0 or math.floor(nearest)
        inFovStat:Set(inFov)
        nearestStat:Set(nearestStuds)
        closingStat:Set(nearestStuds)

        local _, entity = findTarget()
        local plr = entity and plrs:GetPlayerFromCharacter(entity)
        local name, pct = nil, 0
        if entity then
            name = plr and plr.Name or entity.Name
            local hum = entity:FindFirstChildOfClass("Humanoid")
            local hp = hum and hum.Health or entity:GetAttribute("Health")
            local maxHp = hum and hum.MaxHealth or entity:GetAttribute("MaxHealth")
            if hp and maxHp and maxHp > 0 then pct = math.clamp(hp / maxHp, 0, 1) * 100 end
        end
        targetText:Set(name and ("Locked on " .. name) or "No target")
        healthBar:Set(pct)

        local active = aimActive()
        local stage = 0
        if inFov > 0 then stage = 1 end
        if stage >= 1 and active then stage = 2 end
        if active and entity then stage = 3 end
        stageBar:Set(stage)

        if not active then
            lastName = nil
        elseif name ~= lastName then
            lastName = name
            if name then
                locks += 1
                locksStat:Set(locks)
                log("target: " .. name)
            end
        end
    end
end)

do
    local auto = window:GetAutoLoad()
    if auto then
        if window:ConfigExists(auto) and window:Load(auto) then
            autoLoadedName = auto
            refreshConfigs(auto)
            log("auto loaded config: " .. auto)
            window:Toast({ title = "Auto loaded", subtitle = auto })
        else
            log("auto load failed, config missing: " .. auto)
        end
    end
    refreshAutoStatus()
end

boot:Set(1)
log("skyware loaded")
window:Notify({
    title = "Skyware",
    content = "Loaded. RightShift hides the menu.",
    icon = ICON,
    duration = 5,
})
end, debug.traceback)

if not ok then
    getgenv().SkywareLoaded = nil -- let you re-execute after fixing the error
    notify("Error: " .. tostring(err):sub(1, 200))
    warn(err)
end
]==]

local DRIVER = [=[
local SRC, DRIVER, AUTO, DELAYED, DELAY = ...
DELAY = tonumber(DELAY) or 10

-- queue the next teleport first, so it still chains if you teleport mid-countdown
if AUTO then
    local queue = queue_on_teleport
        or (syn and syn.queue_on_teleport)
        or (fluxus and fluxus.queue_on_teleport)
    if queue then
        queue(string.format(
            "getgenv().SkywareLoaded = nil\nlocal SRC = %q\nlocal DRIVER = %q\nloadstring(DRIVER)(SRC, DRIVER, true, true, %s)",
            SRC, DRIVER, tostring(DELAY)))
    else
        warn("[Skyware] Auto-execute unavailable: your executor has no queue_on_teleport.")
    end
end

local function run() loadstring(SRC)() end

if not DELAYED or DELAY <= 0 then
    run()
    return
end

task.spawn(function()
    if not game:IsLoaded() then game.Loaded:Wait() end
    local Players = game:GetService("Players")
    local lp = Players.LocalPlayer
    while not lp do task.wait() lp = Players.LocalPlayer end

    local gui = Instance.new("ScreenGui")
    gui.Name = "SkywareLoader"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 999
    local ok = pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
    if not ok or not gui.Parent then gui.Parent = lp:WaitForChild("PlayerGui") end

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(250, 96)
    frame.Position = UDim2.new(0.5, -125, 0, 40)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Parent = gui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -20, 0, 26)
    label.Position = UDim2.fromOffset(10, 8)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(235, 235, 245)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 15
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Text = "Skyware"
    label.Parent = frame

    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, -20, 0, 6)
    track.Position = UDim2.fromOffset(10, 38)
    track.BackgroundColor3 = Color3.fromRGB(45, 45, 56)
    track.BorderSizePixel = 0
    track.Parent = frame
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0, 0, 1, 0)
    bar.BackgroundColor3 = Color3.fromRGB(120, 140, 255)
    bar.BorderSizePixel = 0
    bar.Parent = track
    Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

    local function makeButton(text, x, w, color)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(w, 30)
        b.Position = UDim2.fromOffset(x, 56)
        b.BackgroundColor3 = color
        b.BorderSizePixel = 0
        b.TextColor3 = Color3.fromRGB(255, 255, 255)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 13
        b.Text = text
        b.AutoButtonColor = true
        b.Parent = frame
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
        return b
    end
    local skip = makeButton("Skip", 10, 140, Color3.fromRGB(90, 110, 235))
    local cancel = makeButton("Cancel", 158, 82, Color3.fromRGB(70, 70, 84))

    local state = "wait"
    skip.MouseButton1Click:Connect(function() if state == "wait" then state = "skip" end end)
    cancel.MouseButton1Click:Connect(function() if state == "wait" then state = "cancel" end end)

    local start = os.clock()
    while state == "wait" do
        local left = DELAY - (os.clock() - start)
        if left <= 0 then break end
        label.Text = "Skyware  -  loading in " .. math.ceil(left) .. "s"
        bar.Size = UDim2.new(1 - left / DELAY, 0, 1, 0)
        task.wait(0.05)
    end

    local cancelled = (state == "cancel")
    state = "done"
    pcall(function() gui:Destroy() end)
    if not cancelled then run() end
end)
]=]

loadstring(DRIVER)(SRC, DRIVER, AUTO_EXECUTE, LOADER_ON_FIRST_RUN, LOAD_DELAY)
