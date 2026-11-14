# Industry Upgrades (private fork)

A private fork of the Transport Fever 3 mod [Industry Upgrades](https://mod.io/g/transportfever3/m/industry-upgrades). The fork is for personal use and is not published.

## Start point

The first commit of this repository is the original, revision 8 (mod.io item 6427516), without changes. The game cache file `texture_metadata_cache.lua` is left out. `git diff <first commit>` shows every difference from the original.

## Differences from the original

None yet. The fork keeps the mod ID `stardorn_industry_upgrades`, and its folder in the staging area has the same name.

## Use

The game finds the fork in the staging area. The mod.io copy of the original MUST NOT be installed at the same time, because both have the same mod ID.

A savegame made with the original keeps its upgrade state with the fork. The game script, the mod settings, and the construction parameters all belong to the mod ID, and the ID is the same.
