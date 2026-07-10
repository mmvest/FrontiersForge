<h1 align="center">FrontiersForge</h1>
<p align="center">
  <a href="https://github.com/mmvest/FrontiersForge/blob/main/LICENSE.txt">
    <img src="https://img.shields.io/github/license/mmvest/FrontiersForge.svg?style=flat-square"/>
  </a>
  <br>
  A framework for managing custom UI elements and accessing game data from EverQuest Online Adventures Frontiers (EQOA) on the PCSX2 emulator.
</p>

## Overview

FrontiersForge is a Lua-based API designed to help developers create custom UI addons and access game data from EverQuest Online Adventures Frontiers as run on the [Sandstorm Server](https://eqoa.live/) using the [PCSX2 emulator](https://pcsx2.net/). This project piggybacks off the [UiForge](https://github.com/mmvest/User-Interface-Forge) project, providing an easy way to interact with the game's internal structures and display that data via custom UI elements using [ImGui](https://github.com/ocornut/imgui).

### Note: This is in a "beta" state. You may anticipate the API to stay mostly consistent at this point, but until it is fully released, some aspects of the API may shift. Expect potentially breaking changes to any mods created using these modules.

### ⚠️ **WARNING**:
Use this code at your own risk. UiForge injects code into the PCSX2 emulator and grants access to the game's memory. Only place trusted scripts in the `scripts` and `scripts/modules` directory.

## Requirements

- **[PCSX2](https://pcsx2.net/)**: Tested on 64-bit versions of PCSX2 v2.0.2 and v2.2.0, running on Windows 11. Other versions may work, but they haven't been tested.
- **DirectX 11/12**: Currently UiForge only supports DirectX 11 and 12, so be sure PCSX2 is using one of those for rendering.
- **Windows OS**: This definitely works on Windows 11 64-bit. I imagine it would also work on Windows 10 and maybe Windows 7.
- **EQOA: Frontiers (US Version)**: This has only been tested on the US version of EverQuest Online Adventures: Frontiers.

## Setup and Running

1. Clone the repository:
    ```bash
    git clone --recurse-submodules https://github.com/mmvest/FrontiersForge.git
    cd FrontiersForge
    ```

   If you already cloned without submodules, run:
   ```bash
   git submodule update --init --recursive
   ```

   Note: UiForge is included as a git submodule and built binaries (like `uiforge_core.dll`) are no longer distributed directly with the repo. Use the release zip files or build locally.

1. Make sure you have **PCSX2 v2.0.0** or greater and **EQOA: Frontiers (US Version) ISO**.
1. Place your UI Lua scripts (dubbed ForgeScripts by the UiForge Project) in the `scripts` directory.
1. Run `pcsx2-qt.exe`, start EQOA, and then execute `StartFrontiersForge.bat`.

Once started, the UiForge settings icon should appear in the top-left corner. Click on it to see the UiForge menu. Click the settings icon again to close the UiForge menu.

To detach UiForge from the process and clean it up, press `Ctrl+Shift+Alt+End` (PCSX2 must be the focused window for the eject hotkey to work).

To enable a script, click the checkbox next to it. Scripts that create Lua Errors are disabled automatically.

To see script settings or debug stats, click on the script name. If it has any settings, the settings will appear in the settings tab. Debug stats can be viewed by clicking the debug tab.

For everything else about the host framework (script packages, callbacks, profiles, the config file, logging, and the `UiForge` Lua API for textures, fonts, and audio), see the [UiForge documentation](https://github.com/mmvest/User-Interface-Forge).

## Building (from source)

`BuildFrontiersForge.bat` builds the UiForge submodule and then updates this repo's `scripts/` by copying the latest scripts from `UiForge/scripts` into `scripts/` (overwriting old versions).

1. Ensure you can build UiForge (see the [UiForge repo](https://github.com/mmvest/User-Interface-Forge) for the requirements).
1. Run:
   ```bat
   BuildFrontiersForge.bat
   ```

To create a release zip:
```bat
BuildFrontiersForge.bat -zip -version 1.2.3
```

This writes `releases/FrontiersForge-v1.2.3.zip`.

## Included scripts

| Script | Description |
|--------|-------------|
| [`ff_example.lua`](scripts/ff_example.lua) | A living demo of nearly every module and function FrontiersForge provides. Start here to see how the API is used. |
| [`mini_map.lua`](scripts/mini_map.lua) | A configurable minimap showing nearby entities, with per-map settings, waypoints, and entity filtering. |
| [`retro_health_hearts.lua`](scripts/retro_health_hearts.lua) | Displays player health as a row of retro-style hearts. |

## Modules

The EQOA modules live in `scripts/modules/frontiers_forge` and are loaded with `require("frontiers_forge.<name>")`.

| Module | Description |
|--------|-------------|
| `ability.lua` | Accessors for a single ability record. Name, description, range, cast time, power cost, cooldown state, icon refs, and scope. |
| `ability_bar.lua` | The hotbar. Which ability or item occupies each hotbar slot. |
| `ability_list.lua` | The full ability list from the Abilities menu. Iteration and lookup by id or name. |
| `bank.lua` | Bank contents. |
| `camera.lua` | Camera coordinates and facing (radians and degrees). |
| `chat.lua` | Captures chat messages as they arrive, with message type classification. |
| `combat.lua` | Combat event capture (damage and healing numbers). Useful for damage meters. |
| `effects.lua` | The player's active effects (buffs and debuffs), icon hashes and names. |
| `entity.lua` | Accessors for a single entity. Name, id, level, health percent, position, disposition, and distance to a world point. |
| `entity_list.lua` | The 24-slot entity list. Lookup by index, id, or name. Slot 0 is always the player. |
| `gems.lua` | Static gem data table (gem, rarity, type, stat). |
| `group.lua` | Group membership and per-member data. |
| `icon.lua` | Decodes game icon textures straight out of emulated PS2 memory into ImGui textures, cached by resource hash. |
| `input.lua` | Controller input. Button states and raw or normalized analog stick values. |
| `inventory.lua` | Inventory slots and their item records. |
| `item.lua` | Accessors for a single item record. Name, stats, damage, range, icon refs, and more. |
| `player.lua` | Player data. Name, level, experience, stats, resists, health, power, coordinates, and current target id. |
| `quest.lua` | Accessors for a single quest log entry. |
| `quest_log.lua` | The quest log list. Count and lookup by index. |
| `ui.lua` | Toggles built-in HUD elements (ability bar, chat, health bar, etc.) and draws game UI art like disposition icons. |
| `util.lua` | Low-level helpers. EE memory reads and writes, pointer chain resolution, guest pointer validation, string conversion, distance between world points, and experience tables. |

Two additional module folders are type-hint stubs for your editor, `scripts/modules/imgui/imgui.lua` and `scripts/modules/uiforge/uiforge.lua`. They enable intellisense for the ImGui and UiForge bindings. DO NOT `require` these in your scripts, that will break your Lua environment.

## License

This project is licensed under the MIT License. See the [LICENSE.txt](LICENSE.txt) file for more details.

## Contributing

Contributions are welcome! If you want to help improve the project, open an issue or submit a pull request. Feel free to suggest features or report bugs.
