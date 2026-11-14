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

## Refused rebuild

Buying a level rebuilds the industry construction. The game can refuse that rebuild with a critical error, so no build option can force it. A known cause is the access road of the industry. The rebuild also rebuilds the access road from the industry's layout, but keeps the junction where it meets roads that were built or changed later. When the new piece of road would bend too sharply there, the game logs `Too Much Curvature` and `Construction Not Possible`.

Disconnecting the roads at the entrance lets the next monthly retry build the levels. Then the roads can be connected again.

## Tests

`lua55 tests/refusal_test.lua` from the mod folder runs the game script against a stub of the game: the check after a rebuild, the refund, and the refund sum.

## Use

The game finds the fork in the staging area. The mod.io copy of the original MUST NOT be installed at the same time, because both have the same mod ID.

A savegame made with the original keeps its upgrade state with the fork. The game script, the mod settings, and the construction parameters all belong to the mod ID, and the ID is the same.
