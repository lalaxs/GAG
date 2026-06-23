function Start()
    local ok, err = pcall(function()
        local outDir = "/workspace/assets/image/"
        local size = 128

        local function clamp(v, lo, hi)
            if v < lo then
                return lo
            end
            if v > hi then
                return hi
            end
            return v
        end

        local function smoothstep(edge0, edge1, x)
            local t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
            return t * t * (3.0 - 2.0 * t)
        end

        local function makeSmoke(path)
            local img = Image()
            img:SetSize(size, size, 4)
            local cx = (size - 1) * 0.5
            local cy = (size - 1) * 0.5
            for y = 0, size - 1 do
                for x = 0, size - 1 do
                    local nx = (x - cx) / cx
                    local ny = (y - cy) / cy
                    local dist = math.sqrt(nx * nx + ny * ny)
                    local base = 1.0 - smoothstep(0.34, 0.82, dist)

                    local lobeA = 1.0 - smoothstep(0.0, 0.62, math.sqrt((nx + 0.18) * (nx + 0.18) + (ny + 0.05) * (ny + 0.05)))
                    local lobeB = 1.0 - smoothstep(0.0, 0.52, math.sqrt((nx - 0.18) * (nx - 0.18) + (ny - 0.12) * (ny - 0.12)))
                    local lobeC = 1.0 - smoothstep(0.0, 0.48, math.sqrt(nx * nx + (ny + 0.22) * (ny + 0.22)))
                    local shape = math.max(base * 0.72, math.max(lobeA * 0.7, math.max(lobeB * 0.65, lobeC * 0.58)))

                    local grain = (math.sin(x * 0.31 + y * 0.17) + math.sin(x * 0.13 - y * 0.29)) * 0.035
                    local alpha = clamp((shape + grain) * (1.0 - smoothstep(0.72, 0.96, dist)), 0.0, 1.0)
                    alpha = alpha * 0.58
                    local shade = 0.9 + alpha * 0.1
                    img:SetPixel(x, y, Color(shade, shade, shade, alpha))
                end
            end
            assert(img:SavePNG(path), "SavePNG failed: " .. path)
        end

        local function makeGlow(path)
            local img = Image()
            img:SetSize(size, size, 4)
            local cx = (size - 1) * 0.5
            local cy = (size - 1) * 0.5
            for y = 0, size - 1 do
                for x = 0, size - 1 do
                    local nx = (x - cx) / cx
                    local ny = (y - cy) / cy
                    local dist = math.sqrt(nx * nx + ny * ny)
                    local core = 1.0 - smoothstep(0.0, 0.16, dist)
                    local halo = 1.0 - smoothstep(0.08, 0.58, dist)
                    local alpha = clamp(core * 0.95 + halo * 0.38, 0.0, 1.0)
                    img:SetPixel(x, y, Color(1.0, 1.0, 1.0, alpha))
                end
            end
            assert(img:SavePNG(path), "SavePNG failed: " .. path)
        end

        makeSmoke(outDir .. "clean_mutation_smoke.png")
        makeGlow(outDir .. "clean_mutation_glow.png")
        print("[procedural] wrote clean mutation particle textures")
    end)
    if not ok then
        log:Write(LOG_ERROR, "[procedural] " .. tostring(err))
    end
    engine:Exit()
end
