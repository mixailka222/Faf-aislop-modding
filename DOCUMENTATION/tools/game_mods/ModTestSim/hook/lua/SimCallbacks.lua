do
    -- game_test.py fails the run if anything but this mod is listed here: a UI mod stays out of the sim.
    Callbacks.ModTestLogSimMods = function(data)
        local uids = {}
        for _, mod in __active_mods do
            table.insert(uids, mod.uid)
        end
        LOG("[MODTEST] sim mods: " .. table.concat(uids, " "))
    end

    Callbacks.ModTestSpawn = function(data)
        local brain = ArmyBrains[data.army]
        local position = brain:GetListOfUnits(categories.COMMAND, false)[1]:GetPosition()
        local x, y, z = position[1], position[2], position[3]
        local unit = CreateUnitHPR(data.id, data.army, x + data.dx, y, z + data.dz, 0, 0, 0)
        for _, point in data.patrol or {} do
            IssuePatrol({ unit }, { x + point[1], y, z + point[2] })
        end
    end

    Callbacks.ModTestReclaim = function(data)
        IssueReclaim({ GetEntityById(data.unit) }, GetEntityById(data.target))
    end

    Callbacks.ModTestTakeMass = function(data)
        ArmyBrains[data.army]:TakeResource("MASS", data.amount)
    end

    Callbacks.ModTestGiveMass = function(data)
        ArmyBrains[data.army]:GiveResource("MASS", data.amount)
    end

    local function NearCommander(army, dx, dz)
        local position = ArmyBrains[army]:GetListOfUnits(categories.COMMAND, false)[1]:GetPosition()
        return position[1] + dx, position[2], position[3] + dz
    end

    Callbacks.ModTestWreck = function(data)
        local x, y, z = NearCommander(data.army, data.dx, data.dz)
        local source = CreateUnitHPR(data.id, data.army, x, y, z, 0, 0, 0)
        local wreck = source:CreateWreckageProp(0)
        source:Destroy()
        IssueReclaim({ GetEntityById(data.unit) }, wreck)
    end

    Callbacks.ModTestBuild = function(data)
        local x, y, z = NearCommander(data.army, data.dx, data.dz)
        local unit = GetEntityById(data.unit)
        IssueBuildMobile({ unit }, { x, y, z }, data.id, {})
        x, y, z = NearCommander(data.army, 0, 0)
        for _, point in data.patrol do
            IssuePatrol({ unit }, { x + point[1], y, z + point[2] })
        end
    end

    Callbacks.ModTestAllies = function(data)
        local kept = { [data.army] = true }
        for _, list in { data.givers, data.takers } do
            for _, army in list do
                kept[army] = true
            end
        end
        for army in kept do
            for other in kept do
                if army < other then
                    SetAlliance(army, other, "Ally")
                end
            end
        end
        -- The AI keeps running, a commander on pause does not spend what the scenario counts.
        for army, brain in ArmyBrains do
            if army ~= data.army and not ArmyIsCivilian(army) then
                local commander = brain:GetListOfUnits(categories.COMMAND, false)[1]
                IssueClearCommands({ commander })
                commander:SetPaused(true)
            end
        end
        for _, army in data.givers do
            local commander = ArmyBrains[army]:GetListOfUnits(categories.COMMAND, false)[1]
            commander:SetProductionPerSecondMass(data.mass)
            commander:SetProductionPerSecondEnergy(data.energy)
        end
        -- GiveStorage does not raise the mass storage, so what a taker gets is taken away.
        for _, army in data.takers do
            local brain = ArmyBrains[army]
            ForkThread(function()
                while true do
                    brain:TakeResource("MASS", brain:GetEconomyStored("MASS"))
                    brain:TakeResource("ENERGY", brain:GetEconomyStored("ENERGY"))
                    WaitTicks(1)
                end
            end)
        end
    end
end
