------------------------------------------------------------------------
-- Automatic Train Refueler
------------------------------------------------------------------------

local RefuelController = require('scripts.refuel_controller')
local Console = require('scripts.console')

local CLEANUP_INTERVAL = 36000 -- ten minutes

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

---@param event EventData.on_train_created
local function on_train_created(event)
    RefuelController:trainCreated(event)
end

local function on_cleanup()
    RefuelController:cleanup_storage()
end

---@param event EventData.on_runtime_mod_setting_changed
local function on_settings_changed(event)
    RefuelController:configUpdated(event)
end

local function on_configuration_changed()
    RefuelController:init()
    RefuelController:loadConfig()

    -- a prototype or mod change can delete trains outright; drop what they left behind
    RefuelController:cleanup_storage()
end

local function register_events()
    script.on_event(defines.events.on_train_changed_state, on_train_changed_state)
    script.on_event(defines.events.on_train_created, on_train_created)
    script.on_event(defines.events.on_runtime_mod_setting_changed, on_settings_changed)

    script.on_nth_tick(CLEANUP_INTERVAL, on_cleanup)

    script.on_configuration_changed(on_configuration_changed)

    Console:registerCommands()
    RefuelController:loadConfig()

    Console.refuel_controller = RefuelController
end

local function register_remote()
    if not remote.interfaces['FuelTrainStop'] then
        remote.add_interface('FuelTrainStop', { exclude_from_fuel_schedule = function(name) RefuelController:addExclusion(name) end })
    end
end

local function on_init()
    RefuelController:init()
    register_events()
end

local function on_load()
    register_events()
end

-- register APIs early (before on_init/on_load)
register_remote()

script.on_load(on_load)
script.on_init(on_init)
