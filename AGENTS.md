# Abyss Collectors — Project Conventions

## Project Overview
**Abyss Collectors** is a Roblox deep-sea exploration and creature collection game built with **Rojo + Knit**. Players descend through ocean depth zones, catch creatures via skill-based minigames, build aquariums, and trade rare specimens in a player-driven economy.

- **Repository:** `rafamaced/robloxtest`
- **Framework:** Rojo (file syncing) + Knit (service architecture)
- **Language:** Luau (typed where possible)
- **Package Manager:** Wally (dependencies declared in `wally.toml`)
- **Reference GDD:** `/home/team/shared/GDD.md` (Section 11 covers technical architecture)

---

## Luau Style Guide

### Naming Conventions
- **Modules / Services / Controllers:** PascalCase — `CreatureService`, `FishingController`
- **Functions / Methods:** PascalCase for public API, camelCase for private — `Service:GetPlayer()`, `local function validateInput()`
- **Variables:** camelCase — `local playerData = {}`
- **Constants:** SCREAMING_SNAKE_CASE — `MAX_PLAYER_LEVEL`, `AUTOSAVE_INTERVAL`
- **Booleans:** Prefixed with `is`, `has`, `can`, `should` — `isMVP`, `hasGear`, `canJoinZone`
- **Tables as namespaces:** PascalCase — `local CreatureData = {}`

### File Organization
- One module per file. The file name matches the returned module.
- Files are `ModuleScript` instances placed in their target service folder.
- Module header comments describe purpose, responsibilities, and GDD cross-references.

### Types
- Use Luau type annotations on all public function signatures.
- Define shared types in `ReplicatedStorage/Shared/Types.lua` (create when needed).
- Server-only types go in the service file itself.

### Requires
```lua
-- Services
local Knit = require(game:GetService("ReplicatedStorage").Knit)

-- Shared data modules
local CreatureData = require(game:GetService("ReplicatedStorage").Shared.CreatureData)
local Constants = require(game:GetService("ReplicatedStorage").Shared.Constants)
```

Dependencies go at the top of the file, grouped by source (Knit, shared modules, Roblox services).

---

## Rojo Build Workflow

### Directory Structure
All game code lives under `src/` and maps to Roblox services via `default.project.json`:

```
src/
├── ServerScriptService/     → ServerScriptService
│   ├── Knit/                → Server Knit bootstrap
│   └── Services/            → Server Knit services
├── ServerStorage/           → ServerStorage (assets)
├── ReplicatedStorage/       → ReplicatedStorage (shared code)
│   ├── Knit/                → Knit shared module (from Wally)
│   ├── Shared/              → Shared game modules
│   └── Remote/              → Remote event definitions
├── StarterPlayer/
│   ├── StarterPlayerScripts/ → Client scripts
│   │   └── Client/
│   │       ├── KnitClient.lua
│   │       └── Controllers/ → Client Knit controllers
│   └── StarterCharacterScripts/ → Per-character scripts
├── StarterGui/              → UI screens
└── Workspace/               → Static workspace objects
```

### Syncing to Roblox Studio
1. Install Rojo: `cargo install rojo` (or use the VS Code extension)
2. Run `rojo serve` from the repo root
3. In Roblox Studio, connect the Rojo plugin to `localhost:34872`

### Dependencies
```bash
wally install    # Pulls Knit and other packages into Packages/
```

The `Packages/` directory is gitignored. Run `wally install` after cloning.

---

## Service Architecture (Knit Patterns)

### Server Services (in `src/ServerScriptService/Services/`)
Every service:
1. Is created via `Knit.CreateService({ Name = "...", Client = {...} })`
2. Has `KnitStart()` and `KnitInit()` lifecycle methods
3. Is **server-authoritative** for all game logic (GDD Section 11.3)
4. Returns itself at the end of the module

**Service template:**
```lua
local Knit = require(game:GetService("ReplicatedStorage").Knit)

local MyService = Knit.CreateService({
    Name = "MyService",
    Client = {
        -- Methods exposed to client controllers
        DoSomething = "RemoteFunction",
        OnEvent = "RemoteSignal",
    },
})

function MyService.Client:DoSomething(player: Player, arg: string): table
    -- Validate, process, return result
    return { success = true }
end

function MyService:KnitStart(): nil
    print("[MyService] Started")
end

function MyService:KnitInit(): nil
    -- Setup that doesn't depend on other services
end

return MyService
```

**Service responsibilities mapped from GDD Section 11.2:**

| Service | Responsibility |
|---------|---------------|
| `CreatureService` | Spawn management, rarity rolling, attribute generation, catch validation |
| `PlayerDataService` | DataStore persistence, player state, inventory, currency |
| `TradingService` | Trade logic, marketplace, anti-scam validation |
| `ZoneService` | Zone management, atmosphere transitions, hazard systems, depth gating |
| `LeaderboardService` | Global/weekly leaderboards, tournament scoring |

### Client Controllers (in `src/StarterPlayer/StarterPlayerScripts/Client/Controllers/`)
Controllers handle client-side logic only:
- UI rendering and animations
- Input processing and visualization
- Camera controls
- Sending requests to server services

**Controller template:**
```lua
local Knit = require(game:GetService("ReplicatedStorage").Knit)

local MyController = Knit.CreateController({
    Name = "MyController",
})

function MyController:KnitStart(): nil
    print("[MyController] Started")
end

return MyController
```

Controllers communicate with services via Knit's `GetService`:
```lua
local MyService = Knit.GetService("MyService")
local result = MyService:DoSomething("arg"):await()
```

### Server Authority Rules (non-negotiable)
Per GDD Section 11.3, the following must be server-authoritative:
- All catch outcomes (rarity rolls, attribute generation)
- All trade executions
- All currency transactions
- Tournament scoring
- Creature spawning
- Anti-cheat validation

Client handles only: movement, UI, minigame input visualization, camera.

---

## How to Add New Creatures

1. **Define the creature** in `src/ReplicatedStorage/Shared/CreatureData.lua`:
   ```lua
   {
       id = "new_fish",
       name = "New Fish",
       rarity = "Rare",
       zone = "KelpForest",
       sizeRange = {2, 6},
       weightRange = {1, 5},
       baseCatchDifficulty = 5,
       description = "A fascinating new species.",
   }
   ```
2. The `id` must be unique and lowercase_snake_case.
3. Rarity must match one of: Common, Uncommon, Rare, Epic, Legendary, Mythic.
4. Zone must match a `zoneId` in `ZoneData.lua`.
5. `CreatureService` will automatically pick up the new creature from the shared data.
6. Add the creature model/asset to `src/ServerStorage/Assets/Models/Creatures/`.
7. Update the creature pool count in the GDD if the total changes.

## How to Add New Zones

1. **Define the zone** in `src/ReplicatedStorage/Shared/ZoneData.lua`:
   ```lua
   {
       id = "NewZone",
       name = "New Zone Name",
       depthRange = {min, max},
       depthLevelRequired = N,
       gearRequired = "GearId",
       crewRequired = 0,
       isHub = false,
       isMVP = false,
       atmosphere = { ... },
       hazards = { ... },
       catchMechanics = { "Rod" },
       maxPlayers = 20,
   }
   ```
2. Add a rarity distribution in `CreatureData.RarityDistributions`.
3. Add creatures to `CreatureData.Creatures` with `zone = "NewZone"`.
4. Implement zone-specific logic in `ZoneService` (atmosphere, hazards).
5. Build zone terrain in Roblox Studio; save to `src/Workspace/Zones/`.

---

## Mobile-First Performance Guidelines

Target: **30+ FPS on mid-range mobile devices** (iPhone 8 / equivalent Android).

### Rendering Budgets
- Max 50 active creatures rendered simultaneously per zone
- Max 20 particle emitters active at once
- Creature models: < 2,000 triangles for Common-Rare, < 4,000 for Epic-Mythic
- Aquarium: max 30 creatures visible per tank before LOD

### Optimization Techniques (always apply)
- **LOD models** for all creatures (3 tiers). Use `ModelStreamingMode` when available.
- **StreamingEnabled** for large zones.
- **Object pooling** for creature spawns — reuse instead of instantiate/destroy.
- **Particle throttling** based on device performance tier. Check `UserSettings():GetPerformanceSetting()`.
- **UI lazy loading** — load screens on demand, not all at startup.
- **Zone fog** used strategically as a render distance cap (gameplay-justified).

### Network
- Max 20 players per public zone instance.
- Private servers: up to 12 players.
- Rate-limit all server calls from clients.

---

## Git Workflow

### Branches
- `main` — stable, reviewed code
- `feature/<description>` — new features
- `fix/<description>` — bug fixes
- `refactor/<description>` — code restructuring

### Commit Messages
- Present tense, short summary: `Add CreatureService rarity rolling`
- Reference GDD sections when relevant: `Implement zone unlocking (GDD 5.3)`

### PRs
- Open against `main`
- Use squash merge (handled by team lead)
- After merge, return to `main` with a clean working tree

### What NOT to commit
- `Packages/` (from Wally — gitignored)
- `build/`, `out/` (Rojo build artifacts — gitignored)
- `.rbxl`, `.rbxlx` files
- Secrets or API keys
- `rojo-config.local.json`

---

## Testing & Debugging

- Use `print()` and `warn()` for server logs. Prefix with service name: `[CreatureService]`.
- Knit's `KnitStart()` fires after all services are ready — use it for initialization that depends on other services.
- `KnitInit()` fires before `KnitStart()` — use for standalone setup that doesn't depend on other services.
- Test all server-authoritative logic on the server — never trust client input.
- For local testing: `rojo serve` + Roblox Studio connected via Rojo plugin.

---

## Key GDD References

| Section | Topic | Relevance |
|---------|-------|-----------|
| 3.1 | Depth Tiers | Zone unlocking, gear requirements |
| 3.2 | Gear Progression | Rod stats, catch bonuses |
| 4.1-4.5 | Creature System | Rarity, attributes, mutations, catching mechanics |
| 5.1-5.3 | World & Zones | Hub design, zone breakdown, unlock flow |
| 6.1-6.3 | Aquarium | Tank system, customization, research station |
| 7.1-7.3 | Trading | Trade flow, anti-scam, economy principles |
| 8.1-8.4 | Monetization | Launch passes, battle pass, what we never monetize |
| 9.1-9.4 | Social | Crews, co-op, tournaments, sharing |
| 10.1-10.4 | Visual/Audio | Art style, zone atmospheres, VFX, audio direction |
| 11.1-11.7 | Technical | Water/swimming, framework, server auth, performance, data, networking, anti-cheat |

---

## Quick Reference

```bash
# Clone and set up
git clone git@github.com:rafamaced/robloxtest.git
cd robloxtest
wally install
rojo serve

# New feature
git checkout -b feature/my-feature
# ... make changes ...
git add -A && git commit -m "Description of changes"
git push -u origin feature/my-feature
# Open PR on GitHub
```
