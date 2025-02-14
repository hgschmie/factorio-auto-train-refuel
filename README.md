# Automatic Train Refueler

Manages automatic refueling of trains by sending them to a refuel stop when they are low on fuel.

Trains only check their fuel level when they arrive at a stop. Make sure that they have enough fuel left to reach the refueling stop.

When using this mod with automatic train schedulers, it is possible that those override the train schedule and a train needs to be scheduled to go to the fuel stop multiple times.

## Train Group support (experimental!)

If Train group support is enabled and a train is in a train group, the refueler behaves different:

- It first looks for a train group specific refuel stop which is the Refuel stop name (see below) + the train group name. If a stop with that name is found, it will use it for refueling.
- When the train is sent for refueling, it is temporarily removed from the train group. After refueling, it is re-added again. The train group will be temporarily one train short. This is a current limitation (as of 2.0.34) of the Factorio API (see [this forum post](https://forums.factorio.com/viewtopic.php?t=126811)).

## Mod settings

### Support for Train Groups (Startup)

Enable support for trains in train groups. If this setting is not active, trains will be removed from their train group when they are sent for refueling.

### Refuel Stop Name (Map)

Sets the name of the global refuel stop. Changing the name during the game will reset the schedule of any train that was going to the stop.

Default is `Refuel Stop`

### Minimum Fuel (in MJ) (Map)

Sets the threshold at which a train is sent to the refueling stop. Setting this too low risks a train to run out of fuel before it can reach the refueling stop.

Default is `360 MJ` (~ 180 pieces of wood, 90 pieces of coal, 30 pieces of solid fuel, 3.5 pieces of rocket fuel or about 1/4 of a piece of nuclear fuel).

### Log Refuel Schedule (Map)

If this setting is activated, log any scheduling to the refuel stop to the game console.

----

## Legal stuff

This mod is (C) 2025 Henning Schmiedehausen (@hgschmie), licensed under the MIT license.

It is the spiritual successor to [Train Refuel stop](https://mods.factorio.com/mod/TrainRefuelstop) which was never ported to Factorio 2.0. The original code was written by @stever1388 and put into public domain. Most of the code has been rewritten for Factorio 2.0.
