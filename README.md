# TCG World: Maplebrook

A cozy 2D pixel-art life sim about the local card-shop scene. Move to the small
town of Maplebrook, rip booster packs at **The Gilded Deck**, fill your binder,
trade with the townsfolk, and play **Sparkfolk**, the town's own trading card
game, at the kitchen table or in the Saturday Showdown.

Built with **Godot 4.3** and GDScript. No external assets yet: card art,
characters, the town and all audio are generated procedurally at runtime, so
the project runs straight from a clone.

## Running

1. Install [Godot 4.3](https://godotengine.org/download) (standard build, not .NET).
2. Open `project.godot` in the editor and press **F5**, or run `godot --path .`.

### Controls

| Key | Action |
|---|---|
| WASD / arrows | Walk |
| E / Space | Talk, interact, advance dialogue |
| B | Binder |
| K | Deck builder |
| P | Open your sealed packs |
| Esc | Menu (achievements, music, save & quit) |

In battle: click a card in your hand, then a lane (creatures) or a target (spells).
**Attack...** picks attackers; badges preview each fight. Click a creature with Move
to step it sideways. Right-click or Esc cancels.

## Sparkfolk in 30 seconds

You gain one more Spark every turn (no lands). Decks are 30 cards, two colors.
Creatures go into one of four lanes and attack straight across: they fight the
creature opposite, or hit the opponent's Heart if the lane is open. Defending is
automatic. First to 0 Heart loses. Full rules: [docs/GAME_RULES.md](docs/GAME_RULES.md).

## What's in the vertical slice

- **Hearthvale Beginnings** (47 cards, simple) and **Tidefall Festival** (30 cards, adds lane tactics; releases on day 15), across five colors plus colorless, Common to Secret Rare, with foils
- Pack opening with drag-to-rip, rarity anticipation, foil shimmer, glow and sparkles
- Binder, deck builder, three starter decks
- Sparkfolk battles against an AI with six personalities, kept fair by a stat-budget model and simulated matchups
- A walkable town, card shop and home with a clock, NPC schedules and day/night
- Shop: boosters, bundles, mystery boxes, collector boosters, supplies, daily singles, selling, part-time shifts
- Friendship hearts, daily trades, Collector Rank, achievements, the Saturday Showdown tournament

## Docs

- [Sparkfolk rules & balance process](docs/GAME_RULES.md)
- [Architecture & data formats](docs/ARCHITECTURE.md)
- [Roadmap](docs/ROADMAP.md)

## Tests

```bash
godot --headless --path . res://tests/test_runner.tscn   # rules / balance / packs / decks / AI matchups / save
godot --headless --path . res://tests/smoke_test.tscn    # loads every scene, plays the tutorial + 2 battles
godot --headless --path . res://tests/balance_report.tscn -- 2.0   # ~40k-game balance report
godot --headless --path . res://tests/npc_ladder.tscn -- 200 base  # townsfolk difficulty ladder
godot --headless --path . res://tests/economy_sim.tscn -- 200 112  # coins, packs and set completion over time
```

These run automatically on GitHub for every push (`.github/workflows/tests.yml`).

## Adding a card set

Drop a new JSON file in `data/sets/` following `hearthvale.json`. It's picked up
automatically: packs, binder, deck builder and shop prices all read from it.
When exporting builds, add `*.json` to *Filters to export non-resource files*.
