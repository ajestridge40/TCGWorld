# Roadmap

## Milestone 0 — Foundation & vertical slice ✅ (this commit)

- [x] Data-driven card sets (JSON), first set **Hearthvale Beginnings** (52 cards, 5 rarities, 3 secret rares)
- [x] Pack generator with slot rules, foils, collector boosters; best card revealed last
- [x] Premium pack opening: drag-to-rip, anticipation by rarity, flip, glow, flash, sparkles, NEW badges, summary
- [x] Collection with foil tracking, binder with 3×3 pages, completion % by rarity, filters, inspect
- [x] Deck builder: copy limits by rarity, ownership checks, basic lands, mana curve, multiple decks
- [x] ~~Magic-style battle engine~~ (replaced by Sparkfolk in 0.5)
- [x] AI opponents with per-NPC personality and decks; Bo1 and Bo3
- [x] Walkable town, card shop and home; doors; NPC schedules; day/night; sleep; pass out at 2am
- [x] Gilded Deck shop: packs, bundles, mystery box, collector packs, supplies, daily singles, selling, shifts
- [x] Six townsfolk with heart levels, tiered dialogue, daily trades
- [x] Saturday Showdown tournament (3 best-of-one rounds, prizes, trophies)
- [x] Collector Rank XP, 16 achievements, toasts
- [x] Save/load, procedural audio, headless tests + smoke test + screenshot tool

## Milestone 0.5 — Our own card game: Sparkfolk ✅

- [x] Replaced the Magic-style rules with **Sparkfolk**: +1 Spark per turn (no lands), 30-card two-color decks, 4 lanes, attacks go straight across
- [x] Rebuilt Set 1 (47 cards, tier 1: Swift / Soar / Shield / Enter) and added Set 2 **Tidefall Festival** (30 cards, tier 2: Reach / Sweep / Move / Last Breath / Strike / Freeze / Push / Bounce), releasing on day 15
- [x] Stat-budget balance model + tests that reject off-budget cards and too-complex mechanics per tier
- [x] AI round-robin matchup test; balance simulator with card-swap experiments
- [x] NPC decks evolve when a set releases; shops, binder and singles respect release dates
- [x] New battle UI: lane placement, play-over-your-own-creature, Move, attack forecast badges, Spark meter

## Milestone 1 — Make the slice feel finished (next)

Focus: polish what exists before adding systems.

- [ ] **Real art pass**: 16×16 tileset + character sheets (4-dir walk cycles), card frame art per color, hand-drawn card illustrations for rares+ (the `assets/cards/<id>.png` override hook already exists)
- [ ] Pixel font (e.g. a 5×7 bitmap font) for the whole UI
- [ ] Real music (3–4 loops: town day, town night, shop, battle) and recorded foley for pack rips
- [ ] Battle polish: card-move tweens between zones, attack lunge animation, graveyard viewer, "undo" before confirming attackers
- [ ] Hand size + deck count shown for opponent as card backs; mulligan screen
- [ ] Controller support and rebindable keys
- [ ] Settings menu (volume, text speed, window scale)
- [ ] Tutorial: Gus teaches a scripted first game

## Milestone 2 — Deeper card game

- [ ] Set 3 **Lanternlight Fair** (tier 3): Kindle (grows each turn), Ally (bonus beside a friend), Echo (replay from discard), lane terrain
- [ ] Set 4 **Frostfall Market** (tier 4): "choose one" spells, Charge counters, a second Spark sink
- [ ] Teach the AI tier-2 mechanics better (it under-uses Push and Move today)
- [ ] Rotation/format options: "Hearthvale only" casual tables, "all sets" Showdown
- [ ] Sideboarding between Bo3 games (10-card sideboard)
- [ ] **Draft** and **Sealed** events at the shop (Game already tracks sealed packs; needs pick UI + AI drafters)
- [ ] AI: deck-aware mulligans, bluffing with open mana, smarter racing math
- [ ] Deck import/export as text

## Milestone 3 — Deeper life sim

- [ ] House decoration: place binders, playmats, posters, card display frames, trophies (grid placement on the home map)
- [ ] Small garden plot (plant → water → harvest → sell at the bakery) to keep some Stardew DNA
- [ ] Gifts and favourite items per NPC; heart events (short cutscenes at 2/4/6 hearts)
- [ ] Shop quests ("Bring Gus 3 Moon commons", "Teach Pip about trample") on the bulletin board
- [ ] Community Center restoration bundle (complete set goals to reopen it → unlocks Regionals)
- [ ] Seasonal festivals (Spring Lantern Night prerelease, Summer beach league, etc.)
- [ ] Card condition / grading (send cards to a grader for a fee; graded slabs display at home)

## Milestone 4 — Bigger world & competition

- [ ] Regional tournaments in a second town; travel by bus
- [ ] Rival story arc with Corwin; Mira as a road-trip partner
- [ ] Ranked ladder vs AI with seasonal rewards
- [ ] Optional online trading / battles (the engine is already deterministic given a seed and command list, which is the right shape for lockstep netcode)

## Design guardrails

- Cozy first: losing still pays a little, the AI never cheats, mulligans are forgiving, and nothing is time-limited except the Saturday tournament.
- The pack opening is the dopamine core; any change to it should be play-tested.
- Card behaviour lives in data. If a new card needs code, add a reusable `op`, not a special case.
