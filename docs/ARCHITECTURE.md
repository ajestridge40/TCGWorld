# Architecture

TCG World is a Godot 4.3 / GDScript project. The guiding rule: **rules and data
are plain, testable code; scenes only present them.** The battle engine, pack
generator, collection and decks never touch a node, so they run headlessly in
the test suite and can be reused by future modes (draft, sealed, multiplayer).

```
                         data/*.json  (cards, products, NPCs, maps, achievements)
                              │
                              ▼
 ┌──────────────── autoloads ─────────────────┐
 │ CardDB  static data, loaded once           │
 │ Game    the save: coins, cards, decks,     │
 │         time, friendship, rank, routing    │
 │ Sfx     synthesized sound + music          │
 └────────────────────────────────────────────┘
        ▲                         ▲
        │ pure logic (RefCounted) │ presentation (Nodes)
 ┌──────┴────────────┐     ┌──────┴───────────────────────────────┐
 │ CardDef, Balance  │     │ world.tscn     town / shop / home    │
 │ PackGenerator     │     │ shop_menu.tscn buy, sell, shifts     │
 │ Collection        │     │ pack_opening   rip & reveal          │
 │ Deck              │     │ binder         collection pages      │
 │ BattleEngine      │◄────┤ deck_builder                         │
 │ BattleAI          │     │ battle         table UI + AI driver  │
 │ WorldMap          │     │ tournament     Saturday Showdown     │
 └───────────────────┘     └──────────────────────────────────────┘
```

## Folder layout

| Path | What lives there |
|---|---|
| `data/sets/*.json` | One file per card set (with release day and complexity tier). Every file in the folder is loaded automatically. |
| `data/products.json` | Shop catalogue, sell/single prices, collector pack rules, tournament + shift config. |
| `data/npcs.json` | Townsfolk: looks, schedules, decks, AI aggression, dialogue by heart level, trade binders. |
| `data/starters.json` | The three starter decks offered on New Game. |
| `data/achievements.json` | Collector ranks, XP rewards, achievement list. |
| `data/maps/*.json` | Town and interiors: tiles, buildings, doors, decor, interactables. |
| `scripts/autoload/` | `CardDB`, `Game`, `Sfx` singletons. |
| `scripts/core/` | `CardDef`, `CardBalance`, `PackGenerator`, `Collection`, `Deck`. |
| `scripts/battle/` | `BattleEngine` (rules), `BattleAI` (opponent). |
| `scripts/world/` | `WorldMap` (collision + procedural pixel rendering), `Character`, `CharacterSprite`. |
| `scripts/ui/` | `UIKit` theme/palette, `CardView`, `CardArt`, dialogue box, toasts, trade popup. |
| `scripts/scenes/` | One script per scene. Scenes are tiny `.tscn` files; UI is built in code. |
| `tests/` | Headless unit tests, a scene smoke test, and a screenshot tool. |

## Core data structures

### Card (`CardDef`, from `data/sets/<set>.json`)

```jsonc
{
  "id": "hvb_flame_juggler",       // globally unique, prefixed by set code
  "name": "Flame Juggler",
  "type": "creature",              // creature | spell
  "color": "ember",                // ember tide grove sun moon, or omit for colorless
  "subtype": "Performer",
  "cost": 3,                       // Sparks
  "power": 2, "health": 2,
  "keywords": ["swift"],           // swift soar shield (tier 1) + reach sweep move (tier 2)
  "rarity": "uncommon",            // common uncommon rare ultra secret
  "effects": [ { "on": "enter", "op": "damage", "amount": 2, "target": "any" } ],
  "flavor": "Drops one torch per show. On purpose. Probably."
}
```

- **Rules text is generated** from keywords + effects (`CardDef.generate_text()`), and large
  card views add keyword reminder text, so text can never drift from behaviour.
- **Effects** are `{ on, op, ...params }`.
  - `on`: `cast` (spells), `enter`, `dies` (Last Breath), `attack` (Strike).
  - `op`: `damage`, `heal`, `draw`, `lose_life`, `drain`, `spark`, `buff`, `buff_all`, `grant`,
    `grant_all`, `token`, `destroy`, `destroy_all`, `bounce`, `freeze`, `push`.
  - `target`: `any`, `creature`, `enemy_creature`, `own_creature` (player chooses), or
    `this`, `enemy_player`, `all_enemy_creatures`, `all_creatures`, `random_enemy_creature`.
    A card has at most one *chosen* target; every chosen-target effect on it uses that target.
- Each set declares a complexity `tier`; the tests reject mechanics above that tier.
- Each set declares a `release_day`; shops, binder tabs and daily singles only show released sets.

Adding a new op = one `match` branch in `BattleEngine._apply_effect`, one in
`CardDef.describe_effect`, a price in `CardBalance.effect_value`, and (optionally) teaching
`BattleAI` to value it.

### Balance model (`CardBalance`)

Every keyword and effect has a price; every card must sit within ±1.25 of
`2 × cost + 1` (creatures) or `1.25 × cost + 1.5` (spells) plus a rarity allowance.
See [GAME_RULES.md](GAME_RULES.md#keeping-it-balanced).

### Pack rules (per set, in the set JSON)

```json
"pack": {
  "slots": [
    { "rarity": "common", "count": 5 },
    { "rarity": "uncommon", "count": 2 },
    { "weights": { "rare": 78, "ultra": 18, "secret": 4 }, "count": 1 }
  ],
  "foil_chance": 0.25,
  "foil_weights": { "common": 60, "uncommon": 25, "rare": 10, "ultra": 4, "secret": 1 }
}
```

`PackGenerator.open_pack(set_id, rng, variant)` returns `[{ id, foil }]`, with no
duplicates inside a slot group, **sorted so the best card is revealed last**.
Variants (e.g. `collector`) swap in a different slot table from `products.json`.
The test suite opens 2,000 packs per set and checks the observed rates.

### Collection

`Collection.counts` maps `"card_id"` → copies and `"card_id*f"` → foil copies.
Foils are tracked separately for display, trading and selling, but both count
toward deck ownership. Completion % and per-rarity progress are derived.

### Deck

`Deck = { name, cards: { card_id: count } }`. `validate(collection)` returns
human-readable problems: exactly 30 cards, at most two colors (colorless is free),
copy limits by rarity (C/U 3, R 2, UR/SR 1), and ownership.

### Save game (`user://save.json`)

Everything in `Game` (coins, day/time, map position, collection, decks, sealed
packs, supplies, friendship, flags, XP/rank, achievements, stats, trophies,
daily shop stock) is serialized as one versioned JSON document.

## Battle engine

Sparkfolk's full rules are in [GAME_RULES.md](GAME_RULES.md). In code:

- `BattleEngine` is a small state machine (`Phase.PLAY / GAME_OVER`) with action methods
  `play(player, card, lane, target)`, `move(player, uid, lane)`, `attack(uids)` and
  `end_turn()`. Each validates legality and emits `event(kind, data)` (`play`, `enter`,
  `leave`, `clash`, `player_damage`, `creature_damage`, `shield_pop`, `move`, `freeze`, …).
- There is no stack and no opponent-turn interaction: all decisions happen on your own
  turn, which keeps the UI simple and makes the engine deterministic for a seed.
- The battle scene queues events during an action and animates them afterwards
  (lunges, damage numbers, shield pops, poofs), then redraws from engine state.

### AI (`BattleAI`)

Heuristic, no cheating (it sees only its own hand). Personality comes from one
`aggression` number per NPC.

- **Plays**: biggest affordable useful card first. Creatures go to the lane with the best
  score: favourable fights, guarding against the creature across, or open lanes for face
  damage. It only plays over its own creature for a real upgrade.
- **Targets**: kill the best creature it can, pop shields, buff a creature to win its lane,
  freeze or push the biggest threat, burn face when lethal.
- **Attacks**: everything if the open-lane damage is lethal; otherwise free hits, good
  trades and anything that won't die for nothing.
- **Moves**: steps a Move creature into a better lane.

## World

Maps are JSON: a base tile, rectangles of other tiles, trees, buildings (with
doors that link maps), decor and interactables. `WorldMap` builds collision and
**paints the entire map into two Images** (ground + an overlay layer for tree
canopies and lamp tops, so characters walk "behind" them). Characters are 16×16
sprites generated from a look palette. All of this is placeholder-by-design: it
can be swapped for a real TileSet and sprite sheets without touching game logic.

Time runs while you walk around (10 in-game minutes per 7 seconds). NPCs follow
schedules (`days`, `from`, `to`, `map`, `pos`). Outdoors gets a dusk/night tint.
At 2am you pass out and wake at home.

## Presentation conventions

- 960×540 base resolution, `canvas_items` stretch, nearest-neighbour filtering.
- `UIKit` owns the palette and a code-built Theme applied to the root window.
- `CardView` draws a card at any size (compact on the battlefield, full rules + flavor when large), with a foil shader and rarity glow.
- `CardArt` generates a unique 48×32 pixel illustration per card id. Drop `res://assets/cards/<card_id>.png` to replace any of them with real art.
- `Sfx` synthesizes all sound effects and a music-box loop at startup, so the prototype ships with zero audio files.

## Testing

```
godot --headless --path . res://tests/test_runner.tscn   # rules, balance budget, packs, decks, AI matchups, saves, maps
godot --headless --path . res://tests/balance_sim.tscn -- <deckA> <deckB> [games]
godot --headless --path . res://tests/smoke_test.tscn    # every scene + 2 full autopilot battles
xvfb-run godot --path . res://tests/screenshot.tscn -- battle out.png midgame 3
```
