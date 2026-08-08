------------------------------------------------------------------------
-- Automatic Train Refueler
------------------------------------------------------------------------

local Constants = {
    settings = {
        stop_name = 'auto_train_refuel-stop-name',
        min_fuel_value = 'auto_train_refuel-min-fuel-value',
        log_schedule = 'auto_train_refuel-log-schedule',
        train_group = 'auto_train_refuel-train-group'
    },

    prefix = 'hps__atf-',

    ignored_locomotives = {
        -- Electric Locomotives - https://mods.factorio.com/mod/electric-locomotives
        'et-electric-locomotive-1',
        'et-electric-locomotive-2',
        'et-electric-locomotive-3',
    },
}

------------------------------------------------------------------------

---@param value string
---@return string result
function Constants:with_prefix(value)
    return self.prefix .. value
end

---@param id string
---@return string result
function Constants:locale(id)
    return Constants:with_prefix('locale.') .. id
end

---@param msg any
---@param target (LuaPlayer|LuaForce|LuaGameScript)?
function Constants:print(msg, target)

    ---@type PrintSettings
    local print_settings = {
        skip = defines.print_skip.if_visible,
        sound = defines.print_sound.use_player_settings,
    }

    if not target then target = game end
    target.print(msg, print_settings)
end

------------------------------------------------------------------------

return Constants
