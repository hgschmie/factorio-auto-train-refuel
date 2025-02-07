# Automatic Train Refueler

Manages automatic refueling of trains by sending them to a refuel station when they are low on fuel.

Trains only check their fuel level when they arrive at a station. Make sure that they have enough fuel left to reach the refueling station.

When using this mod with automatic train schedulers, it is possible that those override the train schedule and a train needs to be scheduled to go to the fuel station multiple times.

## Mod settings

### Refuel Station Name

Sets the name of the global refuel station. Changing the name during the game will reset the schedule of any train that was going to the station.

Default is `Refuel Station`

### Minimum Fuel (in MJ)

Sets the threshold at which a train is sent to the refueling station. Setting this too low risks a train to run out of fuel before it can reach the refueling station.

Default is `360 MJ` (~ 180 pieces of wood, 90 pieces of coal, 30 pieces of solid fuel, 3.5 pieces of rocket fuel or about 1/4 of a piece of nuclear fuel).

### Log Refuel Schedule

If this setting is activated, log any scheduling to the refuel station to the game console.

----

## Legal stuff

This mod is (C) 2025 Henning Schmiedehausen (@hgschmie), licensed under the MIT license.

It is the spiritual successor to [Train Refuel Station](https://mods.factorio.com/mod/TrainRefuelStation) which was never ported to Factorio 2.0. The original code was written by @stever1388 and put into public domain.

While this retains the structure and functionality, most of the code has been rewritten for Factorio 2.0.
