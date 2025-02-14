------------------------------------------------------------------------
-- Automatic Train Refueler
------------------------------------------------------------------------

local RefuelController = require('scripts.refuel_controller')

---@param event EventData.on_train_changed_state
local function on_train_changed_state(event)
    local train = event.train
    if not (train and train.valid) then return end

    if train.state == defines.train_state.wait_station then
        RefuelController:trainStateWaitStation(event)
    end

    if event.old_state == defines.train_state.wait_station then
        RefuelController:trainStateLeaveStation(event)
    end
end

local function on_settings_changed(event)
    RefuelController:configUpdated(event)
end

local function on_configuration_changed(event)
    RefuelController:init()
    RefuelController:loadConfig()
end

local function register_events()
    script.on_event(defines.events.on_train_changed_state, on_train_changed_state)
    script.on_event(defines.events.on_runtime_mod_setting_changed, on_settings_changed)

    script.on_configuration_changed(on_configuration_changed)

    RefuelController:loadConfig()
end

local function on_init()
    RefuelController:init()
    register_events()
end

local function on_load()
    register_events()
end

script.on_load(on_load)
script.on_init(on_init)
