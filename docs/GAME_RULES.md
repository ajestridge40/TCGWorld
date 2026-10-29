# Sparkfolk: Rules

*Sparkfolk* is the trading card game everyone in Maplebrook plays. It's built
to be learnable in one game and to grow deeper one set at a time.

## The basics

- Each player starts with **20 Heart**. Bring the other player to 0 to win.
- Decks are **exactly 30 cards** from **at most two colors** (Ember, Tide, Grove,
  Sun, Moon). Colorless cards fit in any deck.
- Copy limits: **3** of a Common or Uncommon, **2** of a Rare, **1** of an Ultra or Secret Rare.

## Sparks (no lands!)

- At the start of each of your turns you gain **+1 maximum Spark** (up to 10)
  and your Sparks refill.
- Every card has a Spark cost in its gold gem. Pay it to play the card.
- Turn 1 you have 1 Spark, turn 2 you have 2, and so on.

## Setting up

- Shuffle. The first player draws **3** cards; the second draws **4** and also
  gets a **Lucky Penny** (0 Sparks: gain 1 Spark this turn, once).
- **Cozy mulligan:** if your opening hand has nothing costing 2 or less, it's
  reshuffled and redrawn once, for free.
- Everyone draws a card at the start of each of their turns, including the very first.
  Hand size is capped at 10. If you need to draw from an empty deck you lose
  1 Heart, then 2, then 3...

## The board: four lanes

Each player has **4 lanes**. Your lane 1 faces the opponent's lane 1, and so on.

- **Creatures** are played into one of your lanes. If you play into a lane you
  already hold, the creature there **goes home** (to your discard) to make room.
  It doesn't "die", so Last Breath doesn't trigger.
- **Spells** happen immediately and go to your discard.

## Your turn

1. Gain a Spark, refill, draw a card.
2. Play cards in any order.
3. **Attack** (once per turn): choose any of your creatures that can attack.
   Lanes resolve from left to right:
   - If there's an enemy creature across from the attacker, **they fight**:
     each deals its power to the other at the same time.
   - If the lane across is empty, the attacker deals its power to the
     opponent's **Heart**.
4. You may keep playing cards after attacking. Then end your turn.

Creatures can't attack on the turn they're played (they're *fresh*: shown with
"zzz"), but they **always guard their lane**: there is no separate blocking step.
Damage on creatures **stays** until they die. Buffs are permanent unless a card
says "this turn".

## Keywords and triggers

### Set 1: Hearthvale Beginnings (tier 1)
| | |
|---|---|
| **Swift** | Can attack the turn it's played. |
| **Soar** | Flies over the creature across from it and hits Heart, unless that creature also has Soar (or Reach). |
| **Shield** | Ignores the first damage it would take. Then it's gone. |
| **Enter** | Happens when the creature is played. |

### Set 2: Tidefall Festival (tier 2, releases on day 15)
| | |
|---|---|
| **Reach** | Can fight creatures with Soar. |
| **Sweep** | When attacking, also deals its power to the enemies in the neighboring lanes (they don't hit back). |
| **Move** | Once per turn, may step into a neighboring empty lane. |
| **Last Breath** | Happens when the creature dies. |
| **Strike** | Happens each time the creature attacks. |
| **Freeze** | The creature can't attack on its next turn. |
| **Push** | Shoves an enemy creature into a neighboring empty lane, opening its lane. |
| **Bounce** | Returns a creature to its owner's hand. |

## Complexity ladder

Each new set is allowed one step more complexity than the last, and the test
suite enforces it (`tests/test_runner.gd`, `test_balance`):

| Tier | Set | Adds |
|---|---|---|
| 1 | Hearthvale Beginnings | Stats, Swift / Soar / Shield, Enter effects, simple spells |
| 2 | Tidefall Festival | Lane play: Reach, Sweep, Move, Push. Timing: Last Breath, Strike, Freeze |
| 3 | *Lanternlight Fair* (planned) | Synergy: Kindle (grows each turn), Ally (bonus when next to a friend), Echo (cast again from discard), lane-wide terrain |
| 4 | *Frostfall Market* (planned) | Choices: modal "choose one" spells, Charge counters, a second resource sink |

## Keeping it balanced

1. **Stat budget.** `scripts/core/card_balance.gd` prices every keyword and
   effect. A creature's budget is `2 × cost + 1` stat points; a spell's is
   `1.25 × cost + 1.5`; rarer cards get a small allowance (up to +2 for Secret Rares).
   Every card must land within **±1.25** of its budget, or the tests fail.
2. **Simulation.** The test suite plays round-robin AI matches between the
   starter decks and fails if any deck wins less than 30% or more than 70%.
   `tests/balance_sim.tscn` gives detailed stats for any two decks and can
   swap cards in and out for experiments:
   ```
   godot --headless --path . res://tests/balance_sim.tscn -- hearthfire_pals lighthouse_watch 300
   godot --headless --path . res://tests/balance_sim.tscn -- "lighthouse_watch~hvb_mist_heron>hvb_cobblestone_golem" twilight_garden 300
   godot --headless --path . res://tests/balance_sim.tscn -- mira@tff mira 200   # new-set deck vs old
   ```
3. **Power creep check.** When a set releases, townsfolk switch to updated
   decks (`set_decks` in `data/npcs.json`). These are simulated against the old
   decks: they should be a sidegrade or mild upgrade (roughly 40–65%), never a blowout.

### What the first balance pass found

- Soar was underpriced: in a lane game, an evasive attacker is close to
  unblockable. Its cost rose from `1 + 0.25 × power` to `1.5 + 0.5 × power`.
- Shield was underpriced: it absorbs a whole hit while still striking back.
  It went from 1.5 to 2.5, and Soar + Shield on one card pays an extra +1.
- Healing and drain were underpriced relative to direct damage.
- Lanes could clog with cheap creatures, starving decks of plays. That led to
  the "play over your own creature" rule.
- After these fixes, the three starters land between 48% and 53% in 300-game
  round-robins, and the first player wins about 47% of games.
