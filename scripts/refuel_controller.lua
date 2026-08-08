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
---@field group            string
---@field group_schedule   ScheduleRecord[]
---@field group_interrupts ScheduleInterrupt[]
---@field current          integer
---@field refuel_stop_id   uint64

---@class auto_train_refuel.Storage
---@field train_groups table<uint32, auto_train_refuel.SaveGroup>
---@field last_station table<uint32, LuaEntity>

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
    ignored_train_types = {},
}

------------------------------------------------------------------------
-- init / config
------------------------------------------------------------------------

function RefuelController:init()
    storage.train_groups = storage.train_groups or {}
    storage.last_station = storage.last_station or {}

    for _, locomotive in pairs(const.ignored_locomotives) do
        if prototypes.entity[locomotive] then RefuelController:addExclusion(locomotive) end
    end
end

function RefuelController:loadConfig()
    self:initName()
    self:initFuel()
    self:initLog()

    self.enable_train_groups = settings.startup[const.settings.train_group].value --[[@as boolean]]
end

---@param old_name string?
function RefuelController:initName(old_name)
    self.default_stop_name = settings.global[const.settings.stop_name].value --[[@as string]]

    self.refuel_stops = {}

    if old_name then
        const:print { const:locale('change_stop_name'), old_name, self.default_stop_name }
    end
end

---@param old_value number?
function RefuelController:initFuel(old_value)
    self.min_fuel_value = settings.global[const.settings.min_fuel_value].value --[[@as number]]

    if old_value then
        const:print { const:locale('change_min_fuel_value'), old_value, self.min_fuel_value }
    end
end

function RefuelController:initLog()
    self.log_schedule = settings.global[const.settings.log_schedule].value --[[@as boolean]]
end

------------------------------------------------------------------------

---@return auto_train_refuel.Storage data
function RefuelController:data()
    return storage --[[@as auto_train_refuel.Storage]]
end

------------------------------------------------------------------------

---@param train LuaTrain
---@return string? name
---@return integer? id
local function get_train_name(train)
    if not train.valid then return end
    local loco = train.locomotives.front_movers and train.locomotives.front_movers[1] or train.locomotives.back_movers[1]
    if loco then return loco.backer_name, loco.unit_number end
    return nil, nil
end

---@param train LuaTrain
---@return string
local function pretty_print_train(train)
    local name, id = get_train_name(train)
    if id then return string.format('[train=%d] %s', id, name or '') end
    return '<unknown train>'
end

------------------------------------------------------------------------

--- Creates a refuel stop name. If a group is present, add it to the refuel stop name
---@param group string?
---@return string
local function create_refuel_stop_name(group)
    return group and (RefuelController.default_stop_name .. ' ' .. group) or RefuelController.default_stop_name
end

---@param stops LuaEntity[]
---@param name  string
---@return boolean current
local function all_stops_match_name(stops, name)
    assert(name) -- do not allow nil
    for _, stop in pairs(stops) do
        if not (stop.valid and stop.backer_name == name) then return false end
    end
    return true
end

---@param name string
---@return LuaEntity[] fuel_stops
local function locate_refuel_stops(name)
    assert(name)

    local cached = RefuelController.refuel_stops[name]

    -- a cached stop may have been destroyed or renamed; either one invalidates the entry
    if cached and (game.tick - MAX_CACHE_AGE < cached.tick) and all_stops_match_name(cached.refuel_stops, name) then
        return cached.refuel_stops
    end

    local stops = game.train_manager.get_train_stops {
        is_connected_to_rail = true,
        station_name = name,
    }

    if #stops > 0 then
        RefuelController.refuel_stops[name] = {
            refuel_stops = stops,
            tick = game.tick,
        }
    else
        RefuelController.refuel_stops[name] = nil
    end

    return stops
end

---@param train LuaTrain
---@return string? group the train's group, or the group saved while it is out for refueling
function group_name(train)
    if train.group ~= '' then return train.group end

    local save_group = RefuelController:data().train_groups[train.id]
    return save_group and save_group.group or nil
end

---@param train LuaTrain
---@return string? stop_name the refuel stop name that applies to this train
local function get_refuel_stop_name(train)
    local train_group = group_name(train)

    local refuel_stop_name = nil
    if RefuelController.enable_train_groups and train_group then
        refuel_stop_name = create_refuel_stop_name(train_group)
        if #locate_refuel_stops(refuel_stop_name) > 0 then return refuel_stop_name end
    end

    refuel_stop_name = create_refuel_stop_name()
    if #locate_refuel_stops(refuel_stop_name) > 0 then return refuel_stop_name end

    return nil
end

---@param train LuaTrain
---@return LuaEntity[] fuel_stops
local function get_refuel_stops(train)
    local name = get_refuel_stop_name(train)
    return name and locate_refuel_stops(name) or {}
end

---@param train   LuaTrain
---@param station LuaEntity | string
---@return boolean is_refuel_stop true if station is a refuel_stop for this train
local function is_refuel_stop(train, station)
    -- every stop locate_refuel_stops returns is named for the key it was queried with, so this is a name test
    local station_name = type(station) == 'string' and station or station.backer_name
    if not station_name then return false end

    return station_name == get_refuel_stop_name(train)
end

------------------------------------------------------------------------

---@param train LuaTrain
---@return uint64? refuel_stop_id unit number of the stop the train was sent to
function RefuelController:schedule_refueling(train)
    local schedule = train.get_schedule()

    local refuel_stops = get_refuel_stops(train)
    if #refuel_stops == 0 then
        const:print { const:locale('stop_not_found'), pretty_print_train(train) }
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
        const:print { const:locale('stop_not_accessible'), pretty_print_train(train), assert(refuel_stops[1]).unit_number }
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
        local interrupts = schedule.get_interrupts()
        local current = schedule.current
        local record = assert(records[current]) --[[@as AddRecordData ]]
        -- refueling on a temporary record is not supported
        if record.temporary then
            const:print { const:locale('temp_stop_not_supported'), pretty_print_train(train) }
            return nil
        end

        ---@type auto_train_refuel.SaveGroup
        local save_group = {
            current = current,
            group = train.group,
            group_schedule = records,
            group_interrupts = interrupts,
            refuel_stop_id = assert(refuel_stop.unit_number),
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

    return refuel_stop.unit_number
end

---@param train LuaTrain
---@return boolean has_stop true if any refuel stop is already scheduled for this train
local function check_for_stop_in_schedule(train)
    local schedule = train.get_schedule()
    local records = schedule.get_records()

    if not records then return false end

    -- temporary records must be included; schedule_refueling adds its refuel stop as a temporary record
    local stop_name = get_refuel_stop_name(train)
    if not stop_name then return false end

    for _, record in pairs(records) do
        if record.station == stop_name then return true end
    end

    return false
end

---@param train LuaTrain
---@return uint64? refuel_stop_id unit number of the stop the train was sent to
local function restore_schedule(train)
    local schedule = train.get_schedule()

    local data = RefuelController:data()

    local save_group = data.train_groups[train.id]
    data.train_groups[train.id] = nil

    if not (RefuelController.enable_train_groups and save_group) then return nil end

    -- restore train group
    schedule.set_records(save_group.group_schedule)
    schedule.group = save_group.group

    -- add_interrupt is a no-op when an interrupt of that name already exists, so this only fills in
    -- what was lost if the group was deleted along with its last train
    for _, interrupt in pairs(save_group.group_interrupts or {}) do
        schedule.add_interrupt(interrupt)
    end

    -- the group schedule may have shrunk while the train was away
    local record_count = schedule.get_record_count() or 0
    if record_count > 0 then
        local index = save_group.current <= record_count and save_group.current or record_count
        schedule.go_to_station(index)
    end

    return save_group.refuel_stop_id
end

------------------------------------------------------------------------

local function check_refuel(train)
    if not (train and train.valid) then return false end

    local locomotives = train.locomotives --[[@as table<string, LuaEntity[]>]]
    for _, movers in pairs(locomotives) do
        for _, locomotive in ipairs(movers) do
            if not RefuelController.ignored_train_types[locomotive.name] then
                local fuelInventory = locomotive.get_fuel_inventory()
                local totalFuelValue = locomotive.burner and locomotive.burner.remaining_burning_fuel or 0

                if fuelInventory then
                    for _, item in pairs(fuelInventory.get_contents()) do
                        totalFuelValue = totalFuelValue + item.count * prototypes.item[item.name].fuel_value
                    end
                end
                if (totalFuelValue / 1000000) <= RefuelController.min_fuel_value then return true end
            end
        end
    end

    return false
end

local function clean_schedule()
    local data = RefuelController:data()

    -- iterate the dispatch records, not every train; this does not depend on the stop name still matching
    for train_id in pairs(data.train_groups) do
        local train = game.train_manager.get_train_by_id(train_id)
        if train and train.valid then
            restore_schedule(train)
        else
            data.train_groups[train_id] = nil
        end
    end
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

---@param name string
function RefuelController:addExclusion(name)
    if not name then return end
    self.ignored_train_types[name] = true
end

--- Trains deleted outright raise no event, so entries can only be pruned by checking existence.
function RefuelController:cleanupStorage()
    local data = self:data()

    for _, entries in pairs { data.train_groups, data.last_station } do
        for train_id in pairs(entries) do
            local train = game.train_manager.get_train_by_id(train_id)
            if not (train and train.valid) then entries[train_id] = nil end
        end
    end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

---@param event EventData.on_train_created
function RefuelController:trainCreated(event)
    local data = self:data()
    local new_id = event.train.id

    -- coupling/decoupling gives the train a new id; carry the bookkeeping over so a train that is
    -- out for refueling is still recognized when it comes back
    for _, old_id in pairs { event.old_train_id_1, event.old_train_id_2 } do
        if old_id ~= new_id then
            data.train_groups[new_id] = data.train_groups[new_id] or data.train_groups[old_id]
            data.last_station[new_id] = data.last_station[new_id] or data.last_station[old_id]

            data.train_groups[old_id] = nil
            data.last_station[old_id] = nil
        end
    end
end

---@param event EventData.on_train_changed_state
function RefuelController:trainStateWaitStation(event)
    local train = event.train
    local data = self:data()

    local schedule = train.get_schedule()
    local current_stop = schedule.get_record { schedule_index = schedule.current }
    local temp_stop = current_stop and current_stop.temporary or false

    data.last_station[train.id] = nil

    if not (train.station and train.station.valid) then return end

    -- record the stop if it is not a temp stop or is a refuel stop
    if (not temp_stop) or is_refuel_stop(train, train.station) then
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

    if is_refuel_stop(train, station) then
        -- train left a refuel station.
        restore_schedule(train)
    else
        -- train left a regular station
        local needs_refuel = check_refuel(train)
        local stop_is_in_schedule = check_for_stop_in_schedule(train)

        if needs_refuel and not stop_is_in_schedule then
            local stop_id = self:schedule_refueling(train)
            if stop_id and self.log_schedule then
                const:print { const:locale('schedule_refuel'), pretty_print_train(train), stop_id }
            end
        elseif stop_is_in_schedule and not needs_refuel then
            local stop_id = restore_schedule(train)
            if stop_id and self.log_schedule then
                const:print { const:locale('cancel_refuel'), pretty_print_train(train), stop_id }
            end
        end
    end
end

local config_table = {
    [const.settings.stop_name] = function(self)
        clean_schedule()
        self:initName(self.default_stop_name)
    end,
    [const.settings.min_fuel_value] = function(self)
        self:initFuel(self.min_fuel_value)
    end,
    [const.settings.log_schedule] = function(self)
        self:initLog()
    end,
}

---@param event EventData.on_runtime_mod_setting_changed
function RefuelController:configUpdated(event)
    if config_table[event.setting] then
        config_table[event.setting](self)
    end
end

return RefuelController
