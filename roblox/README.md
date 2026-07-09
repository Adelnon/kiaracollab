# Roblox RNG Simulator — Scaffolding

An RNG (roll-for-rarity) simulator, written so everything — the map, the
UI, the remote event, the sounds, the shop, persistence — is built from
scripts at run-time. No manual Studio placement is needed beyond
dropping each file into the location commented at the top of it.

## Files and where they go

| File | Roblox Studio location | Script type |
| --- | --- | --- |
| `ReplicatedStorage/RNGConfig.lua` | `ReplicatedStorage > RNGConfig` | ModuleScript |
| `ServerScriptService/GameSetup.server.lua` | `ServerScriptService > GameSetup` | Script (Server) |
| `ServerScriptService/RollService.server.lua` | `ServerScriptService > RollService` | Script (Server) |
| `ServerScriptService/ShopService.server.lua` | `ServerScriptService > ShopService` | Script (Server) |
| `StarterPlayer/StarterPlayerScripts/RNGSimulatorClient.client.lua` | `StarterPlayer > StarterPlayerScripts > RNGSimulatorClient` | LocalScript (Client) |

Each file repeats the placement in a header comment so it's obvious
even after the files are copied around.

## What it does

### World

- `GameSetup` wipes any previous `Workspace.RNGMap` folder and rebuilds:
  - a **600 × 600 baseplate** with a grass overlay and a short dirt path
    from spawn to the pedestal,
  - a **ring of 12 chunky mountains** around the perimeter, each a
    three-tier stack with a snowy peak — these read as barriers so the
    play area feels bounded,
  - **34 scattered trees** (cylinder trunk + ball of leaves) and
    **42 rocks** across the play area, placed with a seeded RNG so they
    stay put between iterations,
  - a **central roll pedestal** and its four aura pillars (kept from
    the previous iteration — `RollService` still lights the top on
    every roll),
  - a dusk `Lighting` preset with subtle fog,
  - a looping background-music `Sound` in `SoundService`.

### Roll / stats

- `RollService` owns the `RNGSimulatorRemote` RemoteEvent, enforces the
  roll cooldown (0.8 s), picks a rarity from the weighted table in
  `RNGConfig`, updates a per-player `leaderstats` folder
  (`Rolls`, `Best`, `Gems`), keeps an **inventory** of every rarity
  ever rolled (`player.Inventory` folder with an `IntValue` per rarity),
  and pops the pedestal color for the whole server.
- All of the above is **persisted** through `DataStoreService` — loads
  on join, autosaves every 60 s, and flushes on `BindToClose` /
  `PlayerRemoving`.
- Exposes three `_G` hooks that `ShopService` calls to grant rewards:
  `RNG_GrantGems`, `RNG_QueueGuaranteedRarity`, `RNG_ApplyLuckMultiplier`.

### Shop

- `ShopService` wires `MarketplaceService.ProcessReceipt` to the entries
  in `RNGConfig.Shop`. Shop items already scaffolded: gem bags (small /
  medium / large), 2× luck for 10 minutes, and a guaranteed-Godly roll.
- Each entry has a `productId` field. Leave it `0` while you're
  developing and the shop card shows a "coming soon" toast on click. Fill
  it in with a real Developer Product ID (Studio > Game Settings >
  Monetization) to enable real Robux purchases.

### Currency (unused for now)

- `Gems` — added as an `IntValue` in `leaderstats`, displayed in the HUD,
  granted by the gem-bag shop items. Nothing in gameplay spends or earns
  it yet; the plumbing is in place for a future feature.

### Client UI

- `RNGSimulatorClient` builds its own `ScreenGui`. **Nothing is placed
  in the top-left corner** because Roblox's own CoreGui (leaderboard,
  chat) lives there.
- Regions used:
  - **Top-right** — stats HUD with `Best`, `Rolls`, `Gems`.
  - **Bottom-right** — Inventory / Shop toggle buttons.
  - **Bottom-center** — big `ROLL` button.
  - **Center** — the horizontal rolling reel and result banner.
- **Spam-clickable roll button** — every press animates (`UIScale`
  bounce + click SFX) even during the local cooldown. The button never
  greys out; the server still enforces the delay authoritatively.
- **Rolling reel** — a horizontal slot-machine strip of 30 rarity tiles
  that decelerates onto the winning tile using `TweenService`
  (`Quart / Out`). Ticks play as tiles pass, and a `Win` fanfare plays
  when the result is `Legendary` or above.
- **Inventory panel** — one row per configured rarity, colored by the
  rarity color, count bound live to the `Inventory` folder IntValues.
- **Shop panel** — one card per `RNGConfig.Shop` entry with title,
  description, and a Robux-label buy button.

### Sounds

- Sound IDs live in `RNGConfig.Sounds`. The four hooked up are
  `Background` (SoundService, looped), `RollTick`, `Win`, `UIClick`.
  Playback on the client is wrapped in `pcall` so a missing/moderated
  asset just fails silently.

## Extending

Ideas that fit naturally on top of this:

- Wire up `Gems` earn (per roll of Rare+) and a Gems shop within the
  Shop panel.
- Real Developer Products — fill in the `productId` values in
  `RNGConfig.Shop`.
- A global leaderboard GUI backed by an `OrderedDataStore`.
- Multi-roll ("roll ×10") — the server would loop `pickRarity` and the
  client would run several reels in parallel or in sequence.
- Pets/auras — spawn a decorative aura Part next to the player when
  they roll a rare, colored by the rarity color already sent to the
  client.
