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
end
