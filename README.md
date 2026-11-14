# Industry Upgrades (private fork)

A private fork of the Transport Fever 3 mod [Industry Upgrades](https://mod.io/g/transportfever3/m/industry-upgrades). The fork is for personal use and is not published.

## Start point

The first commit of this repository is the original, revision 8 (mod.io item 6427516), without changes. The game cache file `texture_metadata_cache.lua` is left out. `git diff <first commit>` shows every difference from the original.

## Differences from the original

The fork keeps the mod ID `stardorn_industry_upgrades`, and its folder in the staging area has the same name.

| Area | Original | Fork |
|---|---|---|
| Refused rebuild | The bought levels show "Upgrading to level X in a few seconds" for ever, and every later purchase at the industry waits in the same rebuild | The game script notices that the levels are still missing after the rebuild, logs a warning once, and keeps the retry every month. The Upgrades tab (or the card) shows a Rebuild refused section with the usual cause and what to do |
| Refund | None | While a rebuild is refused and upgrades cost points, a button drops the waiting levels and returns their points at the current cost settings |
| Monthly check (EXP, upkeep) | Once per month of game time at the default calendar speed, so at 1/8 calendar speed it runs 8 times per calendar month | Once per calendar month, at every calendar speed. With a calendar that stands still, once per month of game time as before |
| Efficiency lot | A production cycle can use up to 20 times the game's amounts (a saw mill 77 logs instead of 4 at -4 %) | At most 5 times (`core.MAX_RECIPE_SCALE`). The saving of a level is rounded to whole units, so some levels save nothing until the next one |
| Worker limit | The worker boost counts at most 20 workers, so with "Workers needed per level" the workplaces stop at 40 | While "Workers needed per level" is on, industries with worker boost levels count up to 40 workers, and their workplaces stop at 80. Every other industry keeps 20. Only then does the fork replace the base game's worker script, and not when another mod has already replaced it |
| Partial worker boost | All or nothing: the boost comes only once all the workers needed arrive | While "Workers needed per level" is on, every industry gets the boost in proportion to its workers (15 of 40 workers: 15/40 of the boost). The worker row in the industry window shows the boost now with "Max." and the full boost under it, and ticks only at the full boost. The EXP condition "worker boost active" counts only the full boost |
| Worker boost levels | 5 | The setting "Worker boost: number of levels": 5 or 10 |
| Settings | The order of the original, with `[E]` and `[D]` marks for the EXP and delivery settings | Grouped in this order, each name starting with its group: Throughput, Storage, Efficiency, Booster, Environmental filter, Worker boost, Upkeep, the "Upgrade costs" switch, EXP points, Deliveries. The game's mod settings screen has no dividers and shows no tooltips, so the maximum of 40 workers is in the name of "Workers needed per level" |
| Texts | None | The worker boost card shows the calculation of the workers the next level needs, in red above 20, and says that more than 20 need the fork's copy of the worker script. The booster card says when its inputs were built under another "Booster demand per level". The help says that a changed setting reaches built levels at the next upgrade |

Delivery orders keep their timing in game time: at a slow calendar speed an order is shorter in calendar months than its minimum duration. An industry built before the efficiency change keeps its large lots until its next upgrade. When a savegame is loaded, the industries whose workplaces no longer fit "Workers needed per level" are rebuilt, for example after it was switched on or off.

## Refused rebuild

Buying a level rebuilds the industry construction. The game can refuse that rebuild with a critical error, so no build option can force it. A known cause is the access road of the industry. The rebuild also rebuilds the access road from the industry's layout, but keeps the junction where it meets roads that were built or changed later. When the new piece of road would bend too sharply there, the game logs `Too Much Curvature` and `Construction Not Possible`.

Disconnecting the roads at the entrance lets the next monthly retry build the levels. Then the roads can be connected again.

## Tests

Run each test from the mod folder with `lua55 tests/<name>.lua`. `tests/support.lua` is the stub of the game they share.

| Test | What it checks |
|---|---|
| `refusal_test.lua` | The check after a rebuild, the refund, and the refund sum |
| `calendar_test.lua` | One monthly check and one upkeep booking per calendar month at calendar speeds ×1, ×0.25 and ×0.125, a state saved before the calendar month was kept, and a calendar that stands still |
| `efficiency_test.lua` | The lot cap for every step setting, that no level needs more input than the one before, the recorded recipe scale, and that the preview matches the rebuild |
| `booster_test.lua` | The check for booster inputs built under another "Booster demand per level" |
| `workers_test.lua` | The worker limit with "Workers needed per level" off and on, the workplaces it allows, the number of worker boost levels, the partial and the all-or-nothing boost, the workers the worker script keeps with and without worker boost levels and the boost it sets, and the replacement of the base game's worker script, which gives way to another mod's |

## Use

The game finds the fork in the staging area. The mod.io copy of the original MUST NOT be installed at the same time, because both have the same mod ID.

A savegame made with the original keeps its upgrade state with the fork. The game script, the mod settings, and the construction parameters all belong to the mod ID, and the ID is the same.
