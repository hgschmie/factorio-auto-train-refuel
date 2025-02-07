------------------------------------------------------------------------
-- Train Auto Refueler
------------------------------------------------------------------------

local RefuelController = require('scripts.refuel_controller')

local function on_train_changed_state(event)
    RefuelController:trainChangedState(event)
end

local function on_settings_changed(event)
    RefuelController:configUpdated(event)
end

local function register_events()
    script.on_event({ defines.events.on_train_changed_state }, on_train_changed_state)
    script.on_event({ defines.events.on_runtime_mod_setting_changed }, on_settings_changed)

    RefuelController:init()
end

script.on_load(register_events)
script.on_init(register_events)
