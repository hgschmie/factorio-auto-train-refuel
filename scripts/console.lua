------------------------------------------------------------------------
-- Automatic Train Refueler
------------------------------------------------------------------------

local const = require('scripts.constants')

---@class auto_train_refuel.Console
---@field refuel_controller auto_train_refuel.Controller
local Console = {}

---@param data CustomCommandData
local function list_excluded(data)
    local player = data.player_index and game.players[data.player_index]

    ---@type LocalisedString[]
    local excluded_locos = { '' }

    for name, status in pairs(Console.refuel_controller.ignored_train_types) do
        if status then
            local local_name = prototypes.entity[name] and prototypes.entity[name].localised_name or name or '<unknown>'
            excluded_locos[#excluded_locos + 1] = local_name
            excluded_locos[#excluded_locos + 1] = ', '
        end
    end
    excluded_locos[#excluded_locos] = nil

    const:print({ '', { const:locale('command_list_excluded_msg') }, ' ', excluded_locos }, player)
end

function Console:registerCommands()
    commands.add_command('auto-train-refuel-list-excluded', { const:locale('command_list_excluded') }, list_excluded)
end

return Console
