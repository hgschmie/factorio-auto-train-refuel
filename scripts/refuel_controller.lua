------------------------------------------------------------------------
-- Automatic Train Refueler
------------------------------------------------------------------------

local util = require('util')

local const = require('scripts.constants')

------------------------------------------------------------------------

---@class auto_train_refuel.Controller
---@field station_name string
---@field min_fuel_value number
---@field log_schedule boolean
---@field refuel_station_record ScheduleRecord?
local RefuelController = {
    station_name = 'no_name_set',
    min_fuel_value = 100,
    log_schedule = false,
}

------------------------------------------------------------------------

function RefuelController:init()
    self:init_name()
    self:init_fuel()
    self:init_log()
end

---@param old_name string?
function RefuelController:init_name(old_name)
    self.station_name = settings.global[const.settings.station_name].value
    self.refuel_station_record = {
        station = self.station_name,
        temporary = true,
        wait_conditions = { { type = 'inactivity', compare_type = 'and', ticks = 120 } },
    }
    if old_name then
        self:print ({ 'log.change_station_name', old_name, self.station_name }, true)
    end
end

---@param old_value number?
function RefuelController:init_fuel(old_value)
    self.min_fuel_value = settings.global[const.settings.min_fuel_value].value

    if old_value then
        self:print ({ 'log.change_min_fuel_value', old_value, self.min_fuel_value }, true)
    end
end

function RefuelController:init_log()
    self.log_schedule = settings.global[const.settings.log_schedule].value
end

------------------------------------------------------------------------

---@param msg any
---@param force boolean?
function RefuelController:print(msg, force)
    if self.log_schedule or force then
        game.print(msg)
    end
end

------------------------------------------------------------------------

---@param train LuaTrain
function RefuelController:add_station_to_schedule(train)
    if not train.schedule then return end

    local current_schedule = util.copy(train.schedule)
    table.insert(current_schedule.records, current_schedule.current + 1, self.refuel_station_record)
    train.schedule = current_schedule
end

---@param train LuaTrain
---@return boolean
function RefuelController:check_for_station_in_schedule(train)
    if not train.schedule then return false end

    for _, record in pairs(train.schedule.records) do
        if record.station == self.station_name then return true end
    end
    return false
end

---@param train LuaTrain
function RefuelController:remove_station_from_schedule(train)
    if not train.schedule then return end

    local current_schedule = util.copy(train.schedule)
    local records = {}
    for _, record in pairs(current_schedule.records) do
        if record.station ~= self.station_name then
            table.insert(records, record)
        end
    end

    if #records > 0 then
        current_schedule.records = records
        train.schedule = current_schedule
    else
        train.schedule = nil
    end
end

---@param event EventData.on_train_changed_state
function RefuelController:trainChangedState(event)
    local train = event.train
    if not (train.state == defines.train_state.wait_station and train.station and train.station.backer_name ~= self.station_name) then return end
    -- train is stopped at a station

    local needs_refuel = false
    local locomotives = train.locomotives --[[@as table<string, LuaEntity[]>]]
    for _, movers in pairs(locomotives) do
        for _, locomotive in ipairs(movers) do
            local fuelInventory = locomotive.get_fuel_inventory()
            local totalFuelValue = locomotive.burner.remaining_burning_fuel

            if fuelInventory then
                for _, item in pairs(fuelInventory.get_contents()) do
                    totalFuelValue = item.count * prototypes.item[item.name].fuel_value
                end
            end
            needs_refuel = needs_refuel or ((totalFuelValue / 1000000) <= self.min_fuel_value)
        end
    end

    local station_is_in_schedule = self:check_for_station_in_schedule(train)

    if needs_refuel and not station_is_in_schedule then
        self:print { 'log.schedule_refuel', train.id, self.station_name }
        self:add_station_to_schedule(train)
    elseif station_is_in_schedule and not needs_refuel then
        self:print { 'log.cancel_refuel', train.id, self.station_name }
        self:remove_station_from_schedule(train)
    end
end

function RefuelController:clean_schedule()
    for _, force in pairs(game.forces) do
        for _, train in pairs(game.train_manager.get_trains {
            force = force,
        }) do
            if self:check_for_station_in_schedule(train) then
                self:remove_station_from_schedule(train)
            end
        end
    end
end

local config_table = {
    [const.settings.station_name] = function(self)
        self:clean_schedule()
        self:init_name(self.station_name)
    end,
    [const.settings.min_fuel_value] = function(self)
        self:init_fuel(self.min_fuel_value)
    end,
    [const.settings.log_schedule] = function(self)
        self:init_log()
    end,
}

---@param event EventData.on_runtime_mod_setting_changed
function RefuelController:configUpdated(event)
    if config_table[event.setting] then
        config_table[event.setting](self)
    end
end

return RefuelController
