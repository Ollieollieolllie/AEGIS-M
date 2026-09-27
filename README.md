# AEGIS-M

A modular, Eden/Zeus-configurable integrated air-defense framework for Arma 3.

AEGIS-M is not a faction or vehicle pack. It is a framework: mission
designers place and sync a small set of modules onto existing vehicles and
units to assemble radar, SAM, CIWS, and CRAM sites into intelligent,
human-feeling air-defense networks -- with engagement behavior driven by a
configurable crew skill/temperament system rather than a fixed reaction
timer.

## Status

Early development. See `.claude/plans` (or the project's plan document) for
the full architecture writeup.

## Dependencies

- [CBA_A3](https://github.com/CBATeam/CBA_A3) (hard dependency)

## Modules

- **AEGISM_Module_System** -- placed on a single vehicle; declares which
  capability role(s) it performs (Radar / Launcher / CIWS). Self-contained
  vehicles (e.g. a Tigris- or ZSU-style all-in-one system) check all three
  roles on one instance with no other modules required.
- **AEGISM_Module_EngagementSettings** -- doctrine: engagement envelope,
  target-priority rule, salvo policy, target-class allowlist.
- **AEGISM_Module_Crew** -- personality: skill tier x temperament, modulates
  the linked doctrine's timing and reliability rather than owning its own
  numbers.
- **AEGISM_Module_Network** -- groups a battery: pools radar contacts across
  synced Systems and acts as a fallback sync target for Engagement Settings
  and Crew.

## License

APL-ND (Arma Public License No Derivatives). See `LICENSE`.

## Coding convention

Every function begins with a standardized header docblock (see any file
under `addons/*/functions/`). Author is always Snow(Dryden).
