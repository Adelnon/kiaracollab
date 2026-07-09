# Roblox RNG Simulator

An RNG (roll-for-rarity) simulator with 5 themed zones, an upgrade tree,
dual currencies (Coins & Gems), pets, and gem rocks. Everything is built
from scripts at run-time — no manual Studio placement needed beyond
dropping each file into the location commented at its top.

## Files and where they go

| File | Roblox Studio location | Script type |
| --- | --- | --- |
| `ReplicatedStorage/RNGConfig.lua` | `ReplicatedStorage > RNGConfig` | ModuleScript |
| `ServerScriptService/GameSetup.server.lua` | `ServerScriptService > GameSetup` | Script (Server) |
| `ServerScriptService/RollService.server.lua` | `ServerScriptService > RollService` | Script (Server) |
| `ServerScriptService/ShopService.server.lua` | `ServerScriptService > ShopService` | Script (Server) |
| `StarterPlayer/StarterPlayerScripts/RNGSimulatorClient.client.lua` | `StarterPlayer > StarterPlayerScripts > RNGSimulatorClient` | LocalScript (Client) |

## Features

### 5 Themed Zones

1. **Grasslands** (free) — green stud-themed starting area
2. **Desert** (500 Coins) — sandy terrain with warm accents
3. **Frozen Tundra** (2,000 Coins) — icy blue blocks
4. **Volcanic** (8,000 Coins) — dark ground with fiery details
5. **Celestial** (25,000 Coins) — deep purple space-themed zone

Zones are laid out left-to-right with barrier walls between them. Click
a barrier to unlock the next zone with Coins. Each zone has its own roll
pedestal, decorations, and gem rocks. All use stud surfaces for a
classic blocky look.

### Dual Currency

- **Coins** — earned from every roll (5 per roll). Used to unlock zones.
- **Gems** — earned from rolling (1-500 based on rarity) and from
  breaking gem rocks with pets. Used for the upgrade tree.

### Upgrade Tree

Accessible via the square button left of the ROLL button. Opens a
full-screen dark overlay with a hexagonal node tree:

- **Center node**: Faster Rolls (50 Gems) — reduces cooldown by 30%
- **Pet branch**: Swift Pets → Lucky Pets → Extra Pet Slot
- **Roll branch**: Lucky Rolls → Super Rolls → Multi-Roll
- **Gem branch**: Gem Finder → Gem Hunter → Gem Magnet

Nodes show owned/locked/available state and cost.

### Pets & Gem Rocks

Each zone has scattered gem rocks (green blocks with +Gems labels).
Click them with a pet equipped to break them and earn gems. Rocks
respawn after 15 seconds. Higher zones give more gems per rock.
Players start with the "Buddy" pet. Pet upgrades increase speed and
gem yield.

### Profile

The Profile button (bottom-right) opens a panel showing total rolls,
best rarity, coin/gem counts, and a per-rarity roll history.

### Rolling

The slot-machine reel scrolls horizontally and decelerates onto the
rolled rarity. Fixed: the send-lock now uses a single timer based on
the server's cooldown response, preventing double-roll desync.

### UI Layout

- **Top-left** — Gems and Coins display
- **Top-right** — Best rarity and total Rolls
- **Bottom-right** — Profile, Inventory, Shop buttons
- **Bottom-center** — ROLL button + Upgrade Tree button
- **Center** — rolling reel and result banner

### Lighting

Bright daytime lighting (ClockTime 14) with subtle atmosphere. No neon
parts — the world uses SmoothPlastic with stud surfaces throughout.

### Shop

Robux developer-product shop with gem bags, coin chest, and luck boost.
Set `productId` values in `RNGConfig.Shop` to enable real purchases.

### Persistence

All player data (rolls, currencies, inventory, unlocked zones, upgrades,
pets) is saved to DataStoreService. Autosaves every 60s and flushes on
leave/shutdown.
