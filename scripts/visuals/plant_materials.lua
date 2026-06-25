-- ============================================================================
-- 植物视觉材质模块
-- Grow A Garden
-- ============================================================================
-- 只负责材质创建、材质初始化和作物材质解析，不改变 PlantVisual 对外接口。
-- ============================================================================

local PlantMaterials = {}

function PlantMaterials.Bind(PlantVisual, colorKey)
    function PlantVisual.CreateMaterial(name, color, metallic, roughness, emissive)
        local mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        mat:SetShaderParameter("MatDiffColor", Variant(color))
        mat:SetShaderParameter("MatSpecColor", Variant(Color(0.55, 0.55, 0.55, 1.0)))
        mat:SetShaderParameter("Metallic", Variant(metallic or 0.0))
        mat:SetShaderParameter("Roughness", Variant(roughness or 0.55))
        if emissive ~= nil then
            mat:SetShaderParameter("MatEmissiveColor", Variant(emissive))
        end
        PlantVisual.materials[name] = mat
        return mat
    end

    function PlantVisual.CreateTransparentMaterial(name, color)
        local mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
        mat:SetShaderParameter("MatDiffColor", Variant(color))
        mat:SetShaderParameter("MatSpecColor", Variant(Color(0.8, 0.8, 0.8, 1.0)))
        mat:SetShaderParameter("Metallic", Variant(0.0))
        mat:SetShaderParameter("Roughness", Variant(0.2))
        PlantVisual.materials[name] = mat
        return mat
    end

    function PlantVisual.CreateUnlitMaterial(name, color)
        local mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
        mat:SetShaderParameter("MatDiffColor", Variant(color))
        PlantVisual.materials[name] = mat
        return mat
    end

    function PlantVisual.CreateGlowMaterial(name, color, intensity)
        local mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        mat:SetShaderParameter("MatDiffColor", Variant(color))
        mat:SetShaderParameter("MatSpecColor", Variant(Color(0.7, 0.7, 0.7, 1.0)))
        mat:SetShaderParameter("Metallic", Variant(0.0))
        mat:SetShaderParameter("Roughness", Variant(0.24))
        local power = intensity or 1.0
        mat:SetShaderParameter("MatEmissiveColor", Variant(Color(color.r * power, color.g * power, color.b * power, 1.0)))
        PlantVisual.materials[name] = mat
        return mat
    end

    function PlantVisual.CreateBillboardMaterial(name, texturePath, color)
        local mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
        mat:SetTexture(TU_DIFFUSE, cache:GetResource("Texture2D", texturePath))
        mat:SetShaderParameter("MatDiffColor", Variant(color or Color(1, 1, 1, 1)))
        mat:SetCullMode(CULL_NONE)
        PlantVisual.materials[name] = mat
        return mat
    end

    function PlantVisual.InitMaterials()
        PlantVisual.CreateMaterial("grass", Color(0.12, 0.42, 0.16, 1.0), 0.0, 0.9)
        PlantVisual.CreateMaterial("grassTop", Color(0.28, 0.72, 0.18, 1.0), 0.0, 0.55)
        PlantVisual.CreateMaterial("soilSide", Color(0.28, 0.72, 0.18, 1.0), 0.0, 0.78)
        PlantVisual.CreateMaterial("soil", Color(0.45, 0.28, 0.12, 1.0), 0.0, 0.72)
        PlantVisual.CreateMaterial("soilLocked", Color(0.34, 0.37, 0.34, 1.0), 0.0, 0.85)
        PlantVisual.CreateMaterial("soilSelected", Color(0.67, 0.42, 0.2, 1.0), 0.0, 0.58)
        PlantVisual.CreateMaterial("seed", Color(0.32, 0.18, 0.075, 1.0), 0.0, 0.62)
        PlantVisual.CreateMaterial("path", Color(0.48, 0.36, 0.22, 1.0), 0.0, 0.8)
        PlantVisual.CreateMaterial("stem", Color(0.14, 0.55, 0.18, 1.0), 0.0, 0.65)
        PlantVisual.CreateMaterial("leaf", Color(0.08, 0.72, 0.19, 1.0), 0.0, 0.55)
        PlantVisual.CreateMaterial("wood", Color(0.45, 0.25, 0.1, 1.0), 0.0, 0.72)
        PlantVisual.CreateMaterial("gold", Color(1.0, 0.72, 0.18, 1.0), 0.65, 0.12, Color(0.8, 0.42, 0.06, 1.0))
        PlantVisual.CreateMaterial("frozen", Color(0.55, 0.88, 1.0, 1.0), 0.0, 0.08, Color(0.04, 0.16, 0.25, 1.0))
        PlantVisual.CreateMaterial("wet", Color(0.46, 0.88, 0.98, 1.0), 0.0, 0.06, Color(0.035, 0.14, 0.22, 1.0))
        PlantVisual.CreateMaterial("cloudPlant", Color(0.72, 0.92, 0.72, 1.0), 0.0, 0.5, Color(0.04, 0.08, 0.04, 1.0))
        PlantVisual.CreateMaterial("pollenPlant", Color(0.96, 0.46, 0.74, 1.0), 0.0, 0.38, Color(0.12, 0.035, 0.085, 1.0))
        PlantVisual.CreateMaterial("glow", Color(0.36, 0.16, 0.58, 1.0), 0.0, 0.34, Color(0.12, 0.03, 0.22, 1.0))
        PlantVisual.CreateMaterial("chocolate", Color(0.24, 0.1, 0.035, 1.0), 0.0, 0.38)
        PlantVisual.CreateMaterial("ceramic", Color(0.66, 0.32, 0.16, 1.0), 0.0, 0.18, Color(0.045, 0.018, 0.008, 1.0))
        PlantVisual.CreateMaterial("ceramicBlue", Color(0.86, 0.47, 0.22, 1.0), 0.0, 0.22, Color(0.035, 0.012, 0.004, 1.0))
        PlantVisual.CreateMaterial("ceramicDeepBlue", Color(0.28, 0.12, 0.055, 1.0), 0.0, 0.34, Color(0.015, 0.004, 0.0, 1.0))
        PlantVisual.CreateMaterial("void", Color(0.008, 0.002, 0.025, 1.0), 0.0, 0.42, Color(0.07, 0.0, 0.18, 1.0))
        PlantVisual.CreateUnlitMaterial("select", Color(0.46, 0.82, 0.42, 1.0))
        PlantVisual.CreateGlowMaterial("waterDrop", Color(0.16, 0.78, 1.0, 1.0), 1.15)
        PlantVisual.CreateMaterial("wetRipple", Color(0.76, 0.98, 1.0, 1.0), 0.0, 0.05, Color(0.045, 0.16, 0.2, 1.0))
        PlantVisual.CreateGlowMaterial("cloud", Color(0.82, 1.0, 0.86, 1.0), 0.45)
        PlantVisual.CreateGlowMaterial("star", Color(1.0, 0.94, 0.28, 1.0), 1.25)
        PlantVisual.CreateGlowMaterial("pollen", Color(1.0, 0.44, 0.78, 1.0), 0.95)
        PlantVisual.CreateMaterial("pollenOrange", Color(1.0, 0.24, 0.58, 1.0), 0.0, 0.42, Color(0.14, 0.018, 0.06, 1.0))
        PlantVisual.CreateGlowMaterial("auraGold", Color(1.0, 0.78, 0.16, 1.0), 1.25)
        PlantVisual.CreateGlowMaterial("auraBlue", Color(0.16, 0.82, 1.0, 1.0), 1.05)
        PlantVisual.CreateGlowMaterial("auraPurple", Color(0.62, 0.16, 0.78, 1.0), 0.62)
        PlantVisual.CreateGlowMaterial("auraGreen", Color(0.28, 1.0, 0.36, 1.0), 0.8)
        PlantVisual.CreateGlowMaterial("iceCrystal", Color(0.62, 0.94, 1.0, 1.0), 1.05)
        PlantVisual.CreateGlowMaterial("rainbowRed", Color(1.0, 0.12, 0.08, 1.0), 1.25)
        PlantVisual.CreateGlowMaterial("rainbowGreen", Color(0.12, 1.0, 0.34, 1.0), 1.25)
        PlantVisual.CreateGlowMaterial("rainbowBlue", Color(0.12, 0.55, 1.0, 1.0), 1.25)
        PlantVisual.CreateGlowMaterial("magicSpark", Color(0.56, 0.18, 0.72, 1.0), 0.5)
        PlantVisual.CreateGlowMaterial("voidSpark", Color(0.24, 0.015, 0.48, 1.0), 0.55)
        PlantVisual.CreateGlowMaterial("candyCrystal", Color(1.0, 0.52, 0.86, 1.0), 1.05)
        PlantVisual.CreateGlowMaterial("honeyGlow", Color(1.0, 0.68, 0.10, 1.0), 0.95)
        PlantVisual.CreateGlowMaterial("alienGlow", Color(0.28, 1.0, 0.56, 1.0), 1.15)
        PlantVisual.CreateGlowMaterial("alienEye", Color(0.30, 0.72, 1.0, 1.0), 1.10)
        PlantVisual.CreateGlowMaterial("darkCore", Color(0.18, 0.02, 0.34, 1.0), 0.85)
        PlantVisual.CreateGlowMaterial("devourEdge", Color(0.52, 0.05, 0.10, 1.0), 0.75)
        PlantVisual.CreateGlowMaterial("chocolateSpark", Color(0.9, 0.42, 0.12, 1.0), 0.65)
        PlantVisual.CreateTransparentMaterial("softSmoke", Color(0.86, 0.92, 0.88, 0.28))
        PlantVisual.CreateTransparentMaterial("magicSmoke", Color(0.72, 0.86, 1.0, 0.22))
        PlantVisual.CreateTransparentMaterial("iceShell", Color(0.62, 0.9, 1.0, 0.2))
        PlantVisual.CreateBillboardMaterial("smokeBillboard", "image/clean_mutation_smoke.png", Color(1.0, 1.0, 1.0, 0.42))
        PlantVisual.CreateBillboardMaterial("sparkBillboard", "image/clean_mutation_glow.png", Color(1.0, 1.0, 1.0, 0.9))
        PlantVisual.CreateBillboardMaterial("goldDustBillboard", "image/mutation_gold_dust_20260623162436.png", Color(1.0, 1.0, 1.0, 0.82))
        PlantVisual.CreateBillboardMaterial("starSparkBillboard", "image/mutation_star_spark_20260623162432.png", Color(1.0, 1.0, 1.0, 0.84))
        PlantVisual.CreateBillboardMaterial("wetStarBillboard", "image/mutation_wet_star_style_particle_20260623181155.png", Color(1.0, 1.0, 1.0, 0.2))
        PlantVisual.CreateBillboardMaterial("cloudStarBillboard", "image/mutation_cloud_round_particle_20260623184031.png", Color(1.0, 1.0, 1.0, 0.25))
        PlantVisual.CreateBillboardMaterial("pollenStarBillboard", "image/mutation_pollen_single_petal_particle_20260623184535.png", Color(1.0, 1.0, 1.0, 0.25))
        PlantVisual.CreateBillboardMaterial("iceCrystalBillboard", "image/mutation_ice_crystal_20260623162431.png", Color(1.0, 1.0, 1.0, 0.76))
        PlantVisual.CreateBillboardMaterial("voidShardBillboard", "image/mutation_void_shard_20260623162619.png", Color(1.0, 1.0, 1.0, 0.9))
        PlantVisual.CreateBillboardMaterial("electricArcBillboard", "image/mutation_electric_arc_20260623162429.png", Color(1.0, 1.0, 1.0, 0.8))
    end

    function PlantVisual.ResolvePlantMaterial(plant, mutation)
        local color = plant.color
        if mutation.colorMutation ~= nil then
            color = mutation.colorMutation.color
        end
        if PlantVisual.HasSpecial(mutation, "rainbow") then
            local key = "plant_rainbow_" .. plant.name .. tostring(math.random(100000, 999999))
            return PlantVisual.CreateMaterial(key, color, 0.0, 0.32, Color(0.2, 0.2, 0.2, 1.0))
        end
        if PlantVisual.HasSpecial(mutation, "gold") then
            return PlantVisual.materials.gold
        end
        if PlantVisual.HasSpecial(mutation, "frozen") then
            return PlantVisual.materials.frozen
        end
        if PlantVisual.HasSpecial(mutation, "wet") then
            return PlantVisual.materials.wet
        end
        if PlantVisual.HasSpecial(mutation, "cloud") then
            return PlantVisual.materials.cloudPlant
        end
        if PlantVisual.HasSpecial(mutation, "pollen") then
            return PlantVisual.materials.pollenPlant
        end
        if PlantVisual.HasSpecial(mutation, "glow") then
            return PlantVisual.materials.glow
        end
        if PlantVisual.HasSpecial(mutation, "chocolate") then
            return PlantVisual.materials.chocolate
        end
        if PlantVisual.HasSpecial(mutation, "ceramic") then
            return PlantVisual.materials.ceramic
        end
        if PlantVisual.HasSpecial(mutation, "void") then
            return PlantVisual.materials.void
        end
        if PlantVisual.HasSpecial(mutation, "devour") then
            return PlantVisual.materials.darkCore
        end
        if PlantVisual.HasSpecial(mutation, "honey") then
            return PlantVisual.materials.honeyGlow
        end
        if PlantVisual.HasSpecial(mutation, "candy") then
            return PlantVisual.materials.candyCrystal
        end

        if plant.visualTheme == "dark_moss" or plant.visualTheme == "dark_rift" or plant.visualTheme == "void_crown" then
            return PlantVisual.materials.darkCore
        end
        if plant.visualTheme == "alien_pulse" or plant.visualTheme == "alien_eye" or plant.visualTheme == "zero_gravity" then
            return PlantVisual.materials.alienGlow
        end
        if plant.visualTheme == "honey_hive" then
            return PlantVisual.materials.honeyGlow
        end
        if plant.visualTheme == "crystal_sweet" or plant.visualTheme == "dream_candy" then
            return PlantVisual.materials.candyCrystal
        end

        local key = "plant_" .. plant.name .. "_" .. colorKey(color)
        if PlantVisual.materials[key] ~= nil then
            return PlantVisual.materials[key]
        end
        return PlantVisual.CreateMaterial(key, color, 0.0, 0.42)
    end
end

return PlantMaterials
