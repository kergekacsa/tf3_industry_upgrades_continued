# Industry Upgrades

The terms of the Industry Upgrades mod and its private fork.

## Language

**Workplaces**:
The jobs an industry offers. The worker boost upgrade with "Workers needed per level" raises them.
_Avoid_: person capacity, workers

**Workers**:
The people who reach an industry by line within two years. The worker boost comes when the workers reach half of the workplaces.
_Avoid_: visitors, arrivals

**Worker limit**:
The most workers an industry can count towards its worker boost: 20 in the base game, 40 at an industry with worker boost levels while "Workers needed per level" is on. Every other industry keeps 20. The workplaces stop at twice the worker limit.
_Avoid_: worker cap, KeepHistoryCount

**Partial worker boost**:
The share of the worker boost an industry gets while fewer workers arrive than its boost needs: 15 of 40 workers give 15/40 of the boost. Only while "Workers needed per level" is on; the base game gives all or nothing. The **Full worker boost** is the whole boost, when all the workers needed arrive.
_Avoid_: reduced efficiency, half boost

**Setting group**:
The upgrade or the cost system that a mod setting belongs to. Its name starts the setting's name, for example "Worker boost: number of levels".
_Avoid_: section, divider

## Relationships

- An industry's worker boost needs **Workers** equal to half of its **Workplaces**.
- An industry whose **Workplaces** exceed twice the **Worker limit** can never get the worker boost.

## Example dialogue

> **Dev:** "The saw mill has 60 **Workplaces** after three worker boost levels. Does it get the boost?"
> **Domain expert:** "Only with the 40 **Worker limit**: it needs 30 **Workers**, and the base game counts at most 20."

## Flagged ambiguities

- "raise workers to 40" meant the **Worker limit** (workers counted for the boost), not 40 **Workplaces**.
- "Worker limit" was briefly a mod setting. It is now fixed: 40 while "Workers needed per level" is on.
