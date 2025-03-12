------------------------------------------------------------------------
-- Automatic Train Refueler
------------------------------------------------------------------------

local util = require('util')

local const = require('scripts.constants')

------------------------------------------------------------------------

local MAX_CACHE_AGE = 3600 -- one minute

---@class auto_train_refuel.RefuelStationEntry
---@field refuel_stops LuaEntity[]
---@field tick number

---@class auto_train_refuel.SaveGroup
---@field group string
---@field group_schedule (ScheduleRecord[])?
---@field current integer
---@field refuel_stop LuaEntity

---@class auto_train_refuel.Storage
---@field train_groups table<number, auto_train_refuel.SaveGroup>
---@field last_station table<number, LuaEntity>
---@field temp_stop table<number, boolean>

---@class auto_train_refuel.Controller
---@field default_stop_name string
---@field min_fuel_value number
---@field log_schedule boolean
---@field enable_train_groups boolean
---@field refuel_stops table<string, auto_train_refuel.RefuelStationEntry>
local RefuelController = {
    default_stop_name = 'no_name_set',
    min_fuel_value = 100,
    log_schedule = false,
    enable_train_groups = true,
    refuel_stops = {}
}

------------------------------------------------------------------------

function RefuelController:init()
    storage.train_groups = storage.train_groups or {}
    storage.last_station = storage.last_station or {}
    storage.temp_stop = storage.temp_stop or {}
end

------------------------------------------------------------------------

function RefuelController:loadConfig()
    self:init_name()
    self:init_fuel()
    self:init_log()

    self.enable_train_groups = settings.startup[const.settings.train_group].value
end

---@param old_name string?
function RefuelController:init_name(old_name)
    self.default_stop_name = settings.global[const.settings.stop_name].value

    self.refuel_stops = {}

    if old_name then
        self:print({ 'log.change_stop_name', old_name, self.default_stop_name }, true)
    end
end

---@param old_value number?
function RefuelController:init_fuel(old_value)
    self.min_fuel_value = settings.global[const.settings.min_fuel_value].value

    if old_value then
        self:print({ 'log.change_min_fuel_value', old_value, self.min_fuel_value }, true)
    end
end

function RefuelController:init_log()
    self.log_schedule = settings.global[const.settings.log_schedule].value
end

------------------------------------------------------------------------

---@param msg any
---@param force boolean?
function RefuelController:print(msg, force)
    ---@type PrintSettings
    local print_settings = {
        skip = defines.print_skip.if_visible,
        sound = force and defines.print_sound.always or defines.print_sound.use_player_settings,
    }

    if self.log_schedule or force then
        game.print(msg, print_settings)
    end
end

------------------------------------------------------------------------

---@return auto_train_refuel.Storage data
function RefuelController:data()
    return storage
end

------------------------------------------------------------------------

---@param train LuaTrain
---@return string? name
function RefuelController:get_train_name(train)
    if not train.valid then return end
    local loco = train.locomotives.front_movers and train.locomotives.front_movers[1] or train.locomotives.back_movers[1]
    return loco and loco.backer_name or nil
end

function RefuelController:pretty_print_train(train)
    return string.format('[train=%d] %s', train.id, self:get_train_name(train) or '')
end

---@param group string?
---@return string
function RefuelController:create_stop_name(group)
    return group and (self.default_stop_name .. ' ' .. group) or self.default_stop_name
end

---@param name string
---@return LuaEntity[] fuel_stops
function RefuelController:locate_stops(name)
    if self.refuel_stops[name] and (game.tick - MAX_CACHE_AGE < self.refuel_stops[name].tick) then
        return self.refuel_stops[name].refuel_stops
    end

    local stops = game.train_manager.get_train_stops {
        is_connected_to_rail = true,
        station_name = name,
    }

    if #stops > 0 then
        self.refuel_stops[name] = {
            refuel_stops = stops,
            tick = game.tick
        }
    end

    return stops
end

---@param train LuaTrain
---@return LuaEntity[] fuel_stops
function RefuelController:get_refuel_stops(train)
    local fuel_stops
    if self.enable_train_groups and #train.group > 0 then
        fuel_stops = self:locate_stops(self:create_stop_name(train.group))
        if #fuel_stops > 0 then return fuel_stops end
    end

    return self:locate_stops(self:create_stop_name())
end

---@param train LuaTrain
---@return LuaEntity?
function RefuelController:schedule_refueling(train)
    local schedule = train.get_schedule()

    local refuel_stops = self:get_refuel_stops(train)
    if #refuel_stops == 0 then
        self:print({ 'log.stop_not_found', self:pretty_print_train(train) }, true)
        return
    end

    ---@type TrainPathFinderOneGoalResult
    local result = game.train_manager.request_train_path {
        type = 'any-goal-accessible',
        train = train,
        goals = refuel_stops,
        search_direction = 'any-direction-with-locomotives',
    }

    if not result.found_path then
        self:print({ 'log.stop_not_accessible', self:pretty_print_train(train), refuel_stops[1].unit_number }, true)
        return
    end

    local refuel_stop = refuel_stops[result.goal_index]

    ---@type AddRecordData
    local fuel_stop_record = {
        station = refuel_stop.backer_name,
        wait_conditions = { { type = 'inactivity', compare_type = 'and', ticks = 120 } },
        allows_unloading = false,
    }

    local data = self:data()

    if self.enable_train_groups and #train.group > 0 then
        local records = assert(schedule.get_records())
        local current = schedule.current
        ---@type auto_train_refuel.SaveGroup
        local save_group = {
            current = current,
            group = train.group,
            group_schedule = records,
            refuel_stop = refuel_stop,
        }

        data.train_groups[train.id] = save_group

        schedule.group = ''
        schedule.clear_records()
        schedule.add_record(fuel_stop_record)

        local record = assert(records[current]) --[[@as AddRecordData ]]
        assert(not record.temporary)

        schedule.add_record(record)
    else
        -- either not a train in a train group or it should ignore train groups

        data.train_groups[train.id] = nil

        local current = schedule.current
        -- add as the next stop
        fuel_stop_record.index = { schedule_index = current }
        fuel_stop_record.temporary = true

        schedule.add_record(fuel_stop_record)
        schedule.go_to_station(current)
    end

    return refuel_stop
end

---@param train LuaTrain
---@return boolean
function RefuelController:check_for_stop_in_schedule(train)
    local schedule = train.get_schedule()
    local records = schedule.get_records()

    if not records then return false end

    for _, record in pairs(records) do
        if self.refuel_stops[record.station] then return true end
    end

    return false
end

---@param train LuaTrain
---@return LuaEntity?
function RefuelController:restore_schedule(train)
    local schedule = train.get_schedule()

    local data = self:data()

    local save_group = data.train_groups[train.id]
    data.train_groups[train.id] = nil

    if not (self.enable_train_groups and save_group) then return nil end

    -- restore train group
    schedule.set_records(save_group.group_schedule)
    schedule.group = save_group.group
    schedule.go_to_station(save_group.current)

    return save_group.refuel_stop
end

function RefuelController:check_refuel(train)
    if not (train and train.valid) then return false end

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
            if (totalFuelValue / 1000000) <= self.min_fuel_value then return true end
        end
    end

    return false
end

---@param event EventData.on_train_changed_state
function RefuelController:trainStateWaitStation(event)
    local train = event.train
    local data = self:data()

    local schedule = train.get_schedule()
    local current_stop = schedule.get_record { schedule_index = schedule.current }
    data.temp_stop[train.id] = current_stop and current_stop.temporary or false
    data.last_station[train.id] = nil

    -- if this is a temp stop, don't record it in the schedule
    if data.temp_stop[train.id] or not (train.station and train.station.valid) then return end

    data.last_station[train.id] = train.station
end

---@param event EventData.on_train_changed_state
function RefuelController:trainStateLeaveStation(event)
    local train = event.train

    local data = self:data()

    ---@type LuaEntity
    local station = data.last_station[train.id]

    if not (station and station.valid) then
        data.last_station[train.id] = nil
        return
    end

    if self.refuel_stops[station.backer_name] then
        -- train left a refuel station.
        self:restore_schedule(train)
    else
        -- train left a regular station
        local needs_refuel = self:check_refuel(train)
        local stop_is_in_schedule = self:check_for_stop_in_schedule(train)

        if needs_refuel and not stop_is_in_schedule then
            local stop = self:schedule_refueling(train)
            if stop then
                self:print { 'log.schedule_refuel', self:pretty_print_train(train), stop.unit_number }
            end
        elseif stop_is_in_schedule and not needs_refuel then
            local stop = self:restore_schedule(train)
            if stop then
                self:print { 'log.cancel_refuel', self:pretty_print_train(train), stop.unit_number }
            end
        end
    end
end

function RefuelController:clean_schedule()
    for _, force in pairs(game.forces) do
        for _, train in pairs(game.train_manager.get_trains {
            force = force,
        }) do
            if self:check_for_stop_in_schedule(train) then
                self:restore_schedule(train)
            end
        end
    end
end

local config_table = {
    [const.settings.stop_name] = function(self)
        self:clean_schedule()
        self:init_name(self.default_stop_name)
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
