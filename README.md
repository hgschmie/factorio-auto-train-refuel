# Automatic Train Refueler

Manages automatic refueling of trains by sending them to a refuel stop when they are low on fuel.

*Refueling is global!* Using this mod means that all trains will be evaluated by the refueler. If you are using train groups, ensure that the 'Support for Train Groups' option is active (it is by default).

Trains only check their fuel level when they leave a stop. Make sure that they have enough fuel left to reach the refueling stop from any stop they leave.

When using this mod with automatic train schedulers, it is possible that those override the train schedule and a train needs to be scheduled to go to the fuel stop multiple times.

With [LTN](https://mods.factorio.com/mod/LogisticTrainNetwork), this can happen if 'delivery ends at requester' is active and the mod schedules a refuel operation between the requester and the depot. In this case, the train will be refueling when it leaves the depot.

Starting with Release 1.2.0, the refueler will not modify existing train schedule interrupts.

## Train Group support

If Train group support is enabled and a train is in a train group, the refueler behaves different:

- It looks for a train group specific refuel stop first. This is designated by using the Refuel stop name (see below) + the train group name. E.g. if the Refuel stop name is 'Refuel Station' and the train group name is 'ore delivery', then the refueler will first look for 'Refuel Station ore delivery' before looking for the more generic 'Refuel Station' name. If a stop with either name is found, it will be used for refueling.

- When the train is sent for refueling, it is temporarily removed from the train group. After refueling, it is re-added again. The train group will be temporarily one train short. As all trains in the train group have the same schedule, this can not be avoided.

If a train is the last train in a train group, the train group temporarily disappears. It will be re-added when the train leaves the refuel station.

## Mod settings

### Refuel Stop Name (auto_train_refuel-stop-name) - per Map, string, default is 'Refuel Stop'

Sets the name of the global refuel stop. Changing the name during the game will reset the schedule of any train that was going to the stop.

### Minimum Fuel (in MJ) (auto_train_refuel-min-fuel-value) - per Map, integer, default is '360'

Sets the threshold at which a train is sent to the refueling stop. Setting this too low risks a train to run out of fuel before it can reach the refueling stop.

The default value of `360 MJ` is

* ~ 180 pieces of wood
* 90 pieces of coal
* 30 pieces of solid fuel
* 3.5 pieces of rocket fuel
* ~1/4 of a piece of nuclear fuel

### Log Refuel Schedule (auto_train_refuel-log-schedule) - per Map, boolean, default is 'false'

If this setting is activated, log any scheduling to the refuel stop to the game console.

### Support for Train Groups (auto_train_refuel-train-group) - Startup, boolean, default is 'true'

Enable support for trains in train groups. If this setting is not active, trains will be permanently removed from their train group when they are sent for refueling.

----

## Legal stuff

This mod is (C) 2025 Henning Schmiedehausen (@hgschmie), licensed under the MIT license.

It is the spiritual successor to [Train Refuel stop](https://mods.factorio.com/mod/TrainRefuelstop) which was never ported to Factorio 2.0. The original code was written by @stever1388 and put into public domain. Most of the code has been rewritten for Factorio 2.0.
