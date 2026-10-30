class_name EconomySettings
extends Resource
## Money settings (checklist step 14), stored in data/economy.tres and loaded by
## the Money autoload. Change the starting money and build prices there.
##
## Object prices are in each object's own file in data/objects/.

## Balance at the start of a new game.
@export var starting_money := 250000
## Share of the build price paid back when something is removed or sold.
@export_range(0.0, 1.0, 0.05) var sale_refund := 0.5
## Price of one terminal floor tile (1 x 1 m).
@export var floor_tile_cost := 25
## Price of one wall piece (1 m of wall).
@export var wall_cost := 150
## Price of turning a wall piece into a doorway.
@export var door_cost := 800
## Price per metre of painted taxi line.
@export var taxi_line_cost_per_metre := 5
