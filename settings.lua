------------------------------------------------------------------------
-- Automatic Train Refueler
------------------------------------------------------------------------

local const = require('scripts.constants')

data:extend {
    {
        type = 'string-setting',
        name = const.settings.station_name,
        setting_type = 'runtime-global',
        default_value = 'Refuel Station',
        order = 'aa',
    },
    {
        type = 'int-setting',
        name = const.settings.min_fuel_value,
        setting_type = 'runtime-global',
        minimum_value = 0,
        maximum_value = 10000,
        default_value = 360,
        order = 'ab',
    },
    {
        type = 'bool-setting',
        name = const.settings.log_schedule,
        setting_type = 'runtime-global',
        default_value = false,
        order = 'ba',
    },
}
