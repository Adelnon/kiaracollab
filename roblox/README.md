# Roblox RNG Simulator — Groundwork

Ground-level scaffold for an RNG (roll-for-rarity) simulator, written so
everything — the map, the UI, the remote event — is built by scripts at
run-time. No manual Studio placement is needed beyond dropping each file
into the location commented at the top of it.

## Files and where they go

| File | Roblox Studio location | Script type |
| --- | --- | --- |
| `ReplicatedStorage/RNGConfig.lua` | `ReplicatedStorage > RNGConfig` | ModuleScript |
| `ServerScriptService/GameSetup.server.lua` | `ServerScriptService > GameSetup` | Script (Server) |
| `ServerScriptService/RollService.server.lua` | `ServerScriptService > RollService` | Script (Server) |
| `StarterPlayer/StarterPlayerScripts/RNGSimulatorClient.client.lua` | `StarterPlayer > StarterPlayerScripts > RNGSimulatorClient` | LocalScript (Client) |

Each file repeats the placement in a header comment so it's obvious even
after the files are copied around.

## What it does today

- `GameSetup` wipes any previous `Workspace.RNGMap` folder and rebuilds a
  baseplate, spawn, central roll pedestal, and four decorative aura
  pillars. Also nudges `Lighting` for a dusk look.
- `RollService` owns the `RNGSimulatorRemote` RemoteEvent, enforces the
  roll cooldown, picks a rarity from the weighted table in `RNGConfig`,
  updates a per-player `leaderstats` folder (`Rolls`, `Best`), and flashes
  the pedestal top the rarity's color so the whole server sees the pop.
- `RNGSimulatorClient` builds its own `ScreenGui` — a big center-bottom
  ROLL button, a result banner that pops/fades, and a top-left `Best: …`
  tag bound to `leaderstats.Best`.
- `RNGConfig` is the single source of truth for rarity names, colors,
  weights, cooldown, and the remote event name. Change values there to
  rebalance the game.

## Extending

Ideas that fit naturally on top of the current groundwork:

- Persist `Rolls` / `Best` with `DataStoreService` so progress survives
  rejoins.
- Spawn a pet/aura part next to the player when a rare rolls, colored by
  the rarity's color (the color is already sent to the client).
- Multi-roll ("roll x10") — the server would loop `pickRarity` and send an
  array; the client already knows how to render a single result.
- A global leaderboard GUI that lists the top `Best` rarities across the
  server.
