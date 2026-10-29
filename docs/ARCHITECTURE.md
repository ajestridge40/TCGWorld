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
 │ CardDef           │     │ world.tscn     town / shop / home    │
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
| `data/sets/*.json` | One file per card set. Every file in the folder is loaded automatically. |
| `data/products.json` | Shop catalogue, sell/single prices, collector pack rules, tournament + shift config. |
| `data/npcs.json` | Townsfolk: looks, schedules, decks, AI aggression, dialogue by heart level, trade binders. |
| `data/starters.json` | The three starter decks offered on New Game. |
| `data/achievements.json` | Collector ranks, XP rewards, achievement list. |
| `data/maps/*.json` | Town and interiors: tiles, buildings, doors, decor, interactables. |
| `scripts/autoload/` | `CardDB`, `Game`, `Sfx` singletons. |
| `scripts/core/` | `CardDef`, `PackGenerator`, `Collection`, `Deck`. |
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
  "type": "creature",              // creature | spell | land
  "speed": "sorcery",              // spells: instant | sorcery
  "subtype": "Performer",
  "cost": "2E",                    // digits = generic, letters = colored pips
  "power": 2, "toughness": 2,
  "keywords": ["haste"],           // flying reach haste lifelink deathtouch trample vigilance defender first_strike
  "rarity": "uncommon",            // common uncommon rare ultra secret
  "effects": [ { "on": "etb", "op": "damage", "amount": 1, "target": "any" } ],
  "flavor": "Drops one torch per show. On purpose. Probably."
}
```

- **Colors**: `E` Ember, `T` Tide, `G` Grove, `S` Sun, `M` Moon. Colorless cards have only generic cost.
- **Rules text is generated** from keywords + effects (`CardDef.generate_text()`), so text can never drift from behaviour. A `"text"` field overrides it for special wording.
- **Effects** are `{ on, op, ...params }`.
  - `on`: `cast` (spells), `etb` (enters the battlefield), `attack`, `dies`.
  - `op`: `damage`, `heal`, `draw`, `lose_life`, `drain`, `discard`, `pump`, `grant`, `buff_all`, `bounce`, `tap`, `destroy`, `token`, `ramp`.
  - `target`: `any`, `creature`, `enemy_creature`, `own_creature` (player chooses), or `this`, `all_enemy_creatures`, `all_creatures` (automatic). A card has at most one *chosen* target; every chosen-target effect on the card uses it.
- Basic lands (`land_ember` …) are generated in code, unlimited, and never appear in packs.

Adding a new op = one `match` branch in `BattleEngine._apply_effect`, one in `CardDef.describe_effect`, and (optionally) teaching `BattleAI` to value it.

### Pack rules (per set, in the set JSON)

```json
"pack": {
  "slots": [
    { "rarity": "common", "count": 6 },
    { "rarity": "uncommon", "count": 3 },
    { "weights": { "rare": 78, "ultra": 18, "secret": 4 }, "count": 1 }
  ],
  "foil_chance": 0.25,
  "foil_weights": { "common": 60, "uncommon": 25, "rare": 10, "ultra": 4, "secret": 1 }
}
```

`PackGenerator.open_pack(set_id, rng, variant)` returns `[{ id, foil }]`, with no
duplicates inside a slot group, **sorted so the best card is revealed last**.
Variants (e.g. `collector`) swap in a different slot table from `products.json`.
The test suite opens 2,000 packs and checks the observed rates.

### Collection

`Collection.counts` maps `"card_id"` → copies and `"card_id*f"` → foil copies.
Foils are tracked separately for display, trading and selling, but both count
toward deck ownership. Completion % and per-rarity progress are derived.

### Deck

`Deck = { name, cards: { card_id: count } }`. `validate(collection)` returns
human-readable problems: size 40–60, copy limits by rarity (C/U 4, R 2, UR/SR 1),
and ownership. Basic lands are free and unlimited.

### Save game (`user://save.json`)

Everything in `Game` (coins, day/time, map position, collection, decks, sealed
packs, supplies, friendship, flags, XP/rank, achievements, stats, trophies,
daily shop stock) is serialized as one versioned JSON document.

## Battle engine

A Magic-style duel, deliberately simplified so it's cozy but still has real decisions:

- 20 life, 7-card hands, one land per turn, lands tap for one mana of their color, auto-payment chooses lands smartly.
- Turn: untap → draw (not on the very first turn) → **main** → optional **combat** → main → end.
- Combat: declare attackers → defender assigns blockers (one per attacker) → **trick window** (attacker, then defender, may cast instants) → first-strike damage → regular damage.
- Keywords: flying/reach, haste, vigilance, defender, lifelink, deathtouch, trample, first strike.
- Summoning sickness, damage wears off at end of turn, temporary pumps expire, decking out loses.
- **Cozy mulligan**: an opening hand with ≤1 or ≥6 lands is reshuffled once for free.
- No stack: spells resolve immediately. Instants are castable in your own main phase or in a combat trick window.

The engine is a state machine (`Phase.MAIN / BLOCKS / TRICKS / GAME_OVER`) with
action methods (`play_land`, `cast`, `declare_attackers`, `declare_blocks`,
`pass_tricks`, `end_turn`) that validate legality and emit `event(kind, data)`
for the UI to animate (`cast`, `enter`, `leave`, `player_damage`, `creature_damage`, …).

### AI (`BattleAI`)

Heuristic, no cheating (it sees only its own hand). Personality comes from one
`aggression` number per NPC.

- **Main phase**: land drop that best fixes colors → cast the most expensive useful spell, choosing targets by value (kill the best creature it can, burn face when lethal or aggressive, skip spells with no good target).
- **Attacks**: alpha strike if lethal through possible blocks; otherwise attack where no blocker gives a bad trade; hold back defenders when the opponent's board threatens lethal.
- **Blocks**: free/winning blocks first, then favourable trades, then chump blocks only to survive.
- **Combat tricks**: simulates the pending combat with each instant + target and casts the one that improves the outcome most (`_combat_score`).

Headless AI-vs-AI runs (60 games across all NPC decks) finish in about 21 turns on average.

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
godot --headless --path . res://tests/test_runner.tscn   # rules, packs, decks, AI, saves, maps
godot --headless --path . res://tests/smoke_test.tscn    # every scene + 2 full autopilot battles
xvfb-run godot --path . res://tests/screenshot.tscn -- battle out.png midgame 3
```
