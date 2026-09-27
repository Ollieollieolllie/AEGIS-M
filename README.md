# AEGIS-M

A modular, Eden/Zeus-configurable integrated air-defense framework for Arma 3.

AEGIS-M is not a faction or vehicle pack. It is a framework: take any
existing radar, SAM, SHORAD, or CIWS/CRAM vehicle -- no setup, no
Attributes to check -- and sync it to one AEGIS-M: Site module to assemble
intelligent, human-feeling air-defense networks, with engagement behavior
driven by a configurable crew skill/temperament system rather than a fixed
reaction timer.

## Status

Early development.

## Dependencies

- [CBA_A3](https://github.com/CBATeam/CBA_A3) (hard dependency)

## How it works

**A vehicle's role is discovered, never declared.** AEGIS-M reads a
vehicle's own native config and current loadout: if it has a real radar
sensor, it has a radar; if it has guided missiles, it's a launcher; if it
also has a high-rate-of-fire gun (a SHORAD or Tigris-style all-in-one
vehicle), it's also a CIWS/CRAM. There is no role checkbox, no detection
range/arc, no missile count, no guidance speed, no ammo classname to set
anywhere -- all of that is either read live from the vehicle's real
sensors/magazines, or is simply the game's own weapon simulation once
AEGIS-M tells it to fire. A qualifying vehicle works standalone with sane
default Doctrine/Personality; no module has to be placed on it at all.

**Detection is hybrid, by necessity.** Aircraft/helicopters/drones are read
straight off the vehicle's own native sensors (getSensorTargets) -- the
same radar/IR/visual/datalink simulation already running against its real
CfgVehicles config. Incoming missiles/rockets/shells can't use that path:
a fired projectile has none of the target-size properties that make a
CfgVehicles object sensor-visible, so it's never a valid getSensorTargets
result no matter how good the radar is. Those are tracked by a dedicated
Fired-event pipeline instead, gated by the same radar's own real detection
range/arc (read from its config, not a made-up number) plus a line-of-
sight check. **Firing commands the vehicle's own real weapon**
(fireAtTarget) with its actual loaded ammo, so ballistics, guidance, and
damage are entirely the game's simulation, not a scripted projectile
AEGIS-M spawns and steers itself. If [ACE3](https://github.com/acemod/ACE3)
is loaded and the fired ammo declares real ACE missile guidance, AEGIS-M
also hands the target to ACE's own guidance system (fireAtTarget alone
never does this) so the shot actually homes rather than flying ballistic --
note ACE's own "Missile Guidance" setting must allow AI-fired shots for
this to take effect.

**AEGISM_Module_Site** is the one placeable/syncable AEGIS-M module. Sync
it to every vehicle that makes up a site (its radar, its launchers, its
CIWS) to link them into a battery: contacts are pooled and deconflicted
across the group, and the Site's own Doctrine (engagement envelope,
target-priority rule, salvo policy, target-class allowlist) and
Personality (skill tier x temperament, which modulates the doctrine's
timing/reliability rather than owning its own numbers) apply battery-wide.
A vehicle synced to more than one Site, or never synced at all, still
resolves sensibly per the object -> network -> default fallback order.

Syncing or unsyncing a vehicle to a Site, or editing the Site's own
Attributes, takes effect live -- nothing requires re-placing modules or
restarting the mission.

**Debug 3D draw** (CBA setting "AEGIS-M > Debug > Enable Debug 3D Draw",
off by default, client-side/no gameplay effect) draws pooled contacts,
network claims, radar range, and each System's acquired target + live LOS
check directly from the same variables the detection/intercept pipeline
itself reads and writes -- similar in spirit to ACE missileguidance's own
debug draw.

## License

APL-ND (Arma Public License No Derivatives). See `LICENSE`.

## Coding convention

Every function begins with a standardized header docblock (see any file
under `addons/*/functions/`). Author is always Snow(Dryden).
