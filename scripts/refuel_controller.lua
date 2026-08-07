------------------------------------------------------------------------
-- Automatic Train Refueler
------------------------------------------------------------------------

local const = require('scripts.constants')

------------------------------------------------------------------------

local MAX_CACHE_AGE = 3600 -- one minute

---@class auto_train_refuel.RefuelStationEntry
---@field refuel_stops LuaEntity[]
---@field tick         number

---@class auto_train_refuel.SaveGroup
---@field group          string
---@field group_schedule ScheduleRecord[]
---@field current        integer
---@field refuel_stop    LuaEntity

---@class auto_train_refuel.Storage
---@field train_groups table<uint32, auto_train_refuel.SaveGroup>
---@field last_station table<uint32, LuaEntity>
---@field temp_stop    table<uint32, boolean>

---@class auto_train_refuel.Controller
---@field default_stop_name   string
---@field min_fuel_value      number
---@field log_schedule        boolean
---@field enable_train_groups boolean
---@field refuel_stops        table<string, auto_train_refuel.RefuelStationEntry>
---@field ignored_train_types table<string, boolean>
local RefuelController = {
    default_stop_name = 'no_name_set',
    min_fuel_value = 100,
    log_schedule = false,
    enable_train_groups = true,
    refuel_stops = {},
    ignored_train_types = {
        -- ElectricTrain mod - https://mods.factorio.com/mod/ElectricTrain2
        ['et-electric-locomotive-1'] = true,
        ['et-electric-locomotive-2'] = true,
        ['et-electric-locomotive-3'] = true,
    },
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

    self.enable_train_groups = settings.startup[const.settings.train_group].value --[[@as boolean]]
end

---@param old_name string?
function RefuelController:init_name(old_name)
    self.default_stop_name = settings.global[const.settings.stop_name].value --[[@as string]]

    self.refuel_stops = {}

    if old_name then
        const:print { const:locale('change_stop_name'), old_name, self.default_stop_name }
    end
end

---@param old_value number?
function RefuelController:init_fuel(old_value)
    self.min_fuel_value = settings.global[const.settings.min_fuel_value].value --[[@as number]]

    if old_value then
        const:print { const:locale('change_min_fuel_value'), old_value, self.min_fuel_value }
    end
end

function RefuelController:init_log()
    self.log_schedule = settings.global[const.settings.log_schedule].value --[[@as boolean]]
end

------------------------------------------------------------------------

---@return auto_train_refuel.Storage data
function RefuelController:data()
    return storage --[[@as auto_train_refuel.Storage]]
end

------------------------------------------------------------------------
-- Add exclusions for trains that do not need refuel
------------------------------------------------------------------------

---@param name string
function RefuelController:addExclusion(name)
    if not name then return end
    self.ignored_train_types[name] = true
end

---@param train LuaTrain
---@return string? name
---@return integer? id
function RefuelController:get_train_name(train)
    if not train.valid then return end
    local loco = train.locomotives.front_movers and train.locomotives.front_movers[1] or train.locomotives.back_movers[1]
    if loco then return loco.backer_name, loco.unit_number end
    return nil, nil
end

function RefuelController:pretty_print_train(train)
    local name, id = self:get_train_name(train)
    if id then return string.format('[train=%d] %s', id, name or '') end
    return '<unknown train>'
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
            tick = game.tick,
        }
    end

    return stops
end

---@param train       LuaTrain
---@param train_group string?
---@return LuaEntity[] fuel_stops
function RefuelController:get_refuel_stops(train, train_group)
    local fuel_stops
    train_group = train_group or train.group

    if self.enable_train_groups and (train_group ~= '') then
        fuel_stops = self:locate_stops(self:create_stop_name(train_group))
        if #fuel_stops > 0 then return fuel_stops end
    end

    return self:locate_stops(self:create_stop_name())
end

---@param train   LuaTrain
---@param station LuaEntity | string
---@return boolean is_refuel_stop true if station is a refuel_stop for this train
function RefuelController:is_refuel_stop(train, station)
    local data = self:data()

    local station_name = type(station) == 'string' and station or station.backer_name
    local train_group = ((train.group ~= '') and train.group) or (data.train_groups[train.id] and data.train_groups[train.id].group) or nil
    local refuel_stops = self:get_refuel_stops(train, train_group)
    for _, refuel_stop in pairs(refuel_stops) do
        if refuel_stop and refuel_stop.valid and refuel_stop.backer_name == station_name then return true end
    end
    return false
end

---@param train LuaTrain
---@return LuaEntity?
function RefuelController:schedule_refueling(train)
    local schedule = train.get_schedule()

    local refuel_stops = self:get_refuel_stops(train)
    if #refuel_stops == 0 then
        const:print { const:locale('stop_not_found'), self:pretty_print_train(train) }
        return nil
    end

    ---@cast result TrainPathFinderOneGoalResult
    local result = game.train_manager.request_train_path {
        type = 'any-goal-accessible',
        train = train,
        goals = refuel_stops,
        search_direction = 'any-direction-with-locomotives',
    }

    if not result.found_path then
        const:print { const:locale('stop_not_accessible'), self:pretty_print_train(train), assert(refuel_stops[1]).unit_number }
        return nil
    end

    ---@diagnostic disable-next-line: undefined-field
    -- result.goal_index is always defined when result.found_path is true
    ---@type LuaEntity
    local refuel_stop = refuel_stops[result.goal_index]

    ---@type AddRecordData
    local fuel_stop_record = {
        ---@diagnostic disable-next-line: assign-type-mismatch, need-check-nil
        station = refuel_stop.backer_name,
        wait_conditions = { { type = 'inactivity', compare_type = 'and', ticks = 120 } },
        allows_unloading = false,
    }

    local data = self:data()

    if self.enable_train_groups and train.group ~= '' then
        local records = assert(schedule.get_records())
        local current = schedule.current
        local record = assert(records[current]) --[[@as AddRecordData ]]
        -- refueling on a temporary record is not supported
        if record.temporary then
            const:print { const:locale('temp_stop_not_supported'), self:pretty_print_train(train) }
            return nil
        end

        ---@type auto_train_refuel.SaveGroup
        local save_group = {
            current = current,
            group = train.group,
            group_schedule = records,
            refuel_stop = refuel_stop,
        }

        data.train_groups[train.id] = save_group

        schedule.group = ''
        fuel_stop_record.temporary = true

        schedule.clear_records()
        schedule.add_record(fuel_stop_record)

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
---@return boolean has_stop true if any refuel stop is already scheduled for this train
function RefuelController:check_for_stop_in_schedule(train)
    local schedule = train.get_schedule()
    local records = schedule.get_records()

    if not records then return false end

    -- temporary records must be included; schedule_refueling adds its refuel stop as a temporary record
    for _, record in pairs(records) do
        if self:is_refuel_stop(train, record.station or '') then return true end
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
            if not self.ignored_train_types[locomotive.name] then
                local fuelInventory = locomotive.get_fuel_inventory()
                local totalFuelValue = locomotive.burner and locomotive.burner.remaining_burning_fuel or 0

                if fuelInventory then
                    for _, item in pairs(fuelInventory.get_contents()) do
                        totalFuelValue = totalFuelValue + item.count * prototypes.item[item.name].fuel_value
                    end
                end
                if (totalFuelValue / 1000000) <= self.min_fuel_value then return true end
            end
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

    if not (train.station and train.station.valid) then return end

    -- record the stop if it is not a temp stop or is a refuel stop
    if (not data.temp_stop[train.id]) or self:is_refuel_stop(train, train.station) then
        data.last_station[train.id] = train.station
    end
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

    if self:is_refuel_stop(train, station) then
        -- train left a refuel station.
        self:restore_schedule(train)
    else
        -- train left a regular station
        local needs_refuel = self:check_refuel(train)
        local stop_is_in_schedule = self:check_for_stop_in_schedule(train)

        if needs_refuel and not stop_is_in_schedule then
            local stop = self:schedule_refueling(train)
            if stop and self.log_schedule then
                const:print { const:locale('schedule_refuel'), self:pretty_print_train(train), stop.unit_number }
            end
        elseif stop_is_in_schedule and not needs_refuel then
            local stop = self:restore_schedule(train)
            if stop and self.log_schedule then
                const:print { const:locale('cancel_refuel'), self:pretty_print_train(train), stop.unit_number }
            end
        end
    end
end

function RefuelController:clean_schedule()
    local data = self:data()

    -- iterate the dispatch records, not every train; this does not depend on the stop name still matching
    for train_id in pairs(data.train_groups) do
        local train = game.train_manager.get_train_by_id(train_id)
        if train and train.valid then
            self:restore_schedule(train)
        else
            data.train_groups[train_id] = nil
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
