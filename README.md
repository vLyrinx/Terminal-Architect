# Terminal Architect

A 3D airport management game in the spirit of Airport CEO. Pick a plot, build your terminal, sign airlines and keep the flights moving.

> **Status: early prototype.** Camera, build grid, build mode and the menus are working. Flights, passengers and money are still being built.

## Download

Grab the latest prototype from the [Releases page](https://github.com/vLyrinx/Terminal-Architect/releases).

- Windows only (64-bit).
- Unzip the file and run `TerminalArchitect.exe`.
- Windows may show a SmartScreen warning. Click **More info**, then **Run anyway**.
- There is no save or load yet, so your airport resets when you close the game.

## Controls

| Input | Action |
|---|---|
| Right mouse drag | Rotate and tilt the camera |
| Middle mouse drag, WASD or arrows | Pan |
| Q / E | Rotate |
| Mouse wheel | Zoom |
| G | Show or hide the build grid |
| B | Build mode (test cube) |
| Left click | Place |
| Right click or Esc | Cancel the build tool |
| Space | Pause or resume |
| 1 / 2 / 3 | Game speed |
| Esc (no build tool active) | Pause menu |

## Progress

Terminal Architect is being built in milestones. Each milestone is a playable step up from the last.

### Prototype (complete)
- **Setup and rendering:** project structure, Forward+ renderer
- **Core:** game clock, pause and 1x, 2x and 4x speed
- **Camera:** free orbit camera, roof and wall cutaway
- **Building:** 1 m build grid, build mode, floor tiles, walls and doors, zones, placeable objects
- **Terminal objects:** check-in desks, security scanner, seating, toilets, gate desks
- **Economy:** money and construction costs, basic income and costs
- **Airside:** runway, taxiways with a route graph, medium stands
- **Aircraft:** A320 and 737-800 models and type data, first fictional airline
- **Flights:** flight schedule, stand allocation, landing and take-off, taxiing, timed turnaround and pushback
- **Passengers:** instanced passenger figures, terminal pathfinding, check-in, security and gate queues, boarding, arrivals, missed flights
- **UI:** top bar and build menu, click to inspect, flight list, basic alerts
- **Also:** main menu, settings and pause menu

## Planned

### 1. Operations
Staff hiring, shifts and energy, staff working at desks. Service roads, vehicle depots, ground vehicle models and driving. Turnaround tasks for refuelling, catering, cleaning and baggage. Pushback tugs, delays and on-time tracking. Small stands with regional aircraft (ATR 72, E175).

### 2. Baggage and passengers
Bags tracked from check-in to aircraft. Conveyor belts, bag screening, sorting and make-up areas, loading bags onto aircraft, arrivals reclaim, lost and late bags. Passenger needs, happiness, shops and food outlets, passport control, passenger types (business, leisure, low-cost), information screens and signage, cleanliness and bins.

### 3. Economy and career
Save and load, main menu and new game setup. Airline contract offers and requirements, airline satisfaction. Finance screen, loans, bankruptcy. Airport star rating. Research tree and research screen. Career goals.

### 4. World
Globe screen for choosing a region, with plots of different sizes. Regional airlines and destinations. Passenger demand based on city size and season. Weather system, wind and runway direction. Runway queue and separation. Weather delays and diversions, de-icing and snow clearing.

### 5. Expansion
Multiple floors, stairs, lifts and escalators. Free placement and rotation for objects like seats and bins. Jet bridges, large stands, and wide-body (787-9, A330-300, A350-900) and very large aircraft (777-300ER, 747-8, A380). Second runway with safe crossings. Sandbox settings.

### 6. Multiplayer
Up to 4-player co-op, with host and join, synced building and clock, joining a game in progress, player cursors and chat, and a shared bank balance with host-set permissions. Steam invites are optional.

### 7. Polish
Sound effects, ambience and music, UI theme, settings menu, tutorial, performance pass, balancing pass, and the Windows release build.

## Help wanted

I'd love help from people who want to build a game like this, I have little experience, so i'm using the dreaded overlord AI tools to help. You don't need to be an expert, But someone with more experience than me would be awesome! Some areas where help would make a real difference:

- **Godot and GDScript developers:** building systems such as flights, pathfinding, the economy and multiplayer.
- **3D artists:** low-poly aircraft, terminal objects and vehicles in a clean, bright style.
- **UI and UX designers:** the build menu, top bar and finance screens.
- **Playtesters:** try the prototype, break it, and tell us what's confusing or fun.
- **Game designers:** airline contracts, passenger behaviour and balancing.

To get involved, open an issue describing what you'd like to help with, or read [CONTRIBUTING.md](CONTRIBUTING.md) to get set up.

## Built with

- Godot 4.7.2 and GDScript
- Built with help from AI tools

## Licence

To be decided before public release. Third-party assets will be credited here as they're added.
