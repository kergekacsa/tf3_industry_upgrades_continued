# Industry Upgrades (private fork)

A private fork of the Transport Fever 3 mod [Industry Upgrades](https://mod.io/g/transportfever3/m/industry-upgrades). The fork is for personal use and is not published.

## Start point

The first commit of this repository is the original, revision 8 (mod.io item 6427516), without changes. The game cache file `texture_metadata_cache.lua` is left out. `git diff <first commit>` shows every difference from the original.

## Differences from the original

| Area | Original | Fork |
|---|---|---|
| Mod ID and folder | `stardorn_industry_upgrades` | `kacsa_industry_upgrades` |

## Use

The fork and the original wrap the same industries. Only one of them MUST be active in a game.

The saved upgrade state belongs to the game script of the mod ID. A savegame that switches from the original to the fork keeps the built levels, because they are construction parameters with the same names. It loses the points, the EXP, the bought levels that wait for their rebuild, and the open delivery orders.
