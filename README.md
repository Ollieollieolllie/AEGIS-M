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

**Intercepting a munition needs a proximity fuse, because Arma has no
projectile-vs-projectile hit detection at all.** A fired interceptor is
tracked frame-by-frame (closest-point-of-approach to its target, the same
technique ACE's own missile-defense system uses) and detonated for real
(triggerAmmo, genuine splash effects) once it closes within its own real
blast radius or starts moving away again having already passed its closest
point. A munition target has no hitpoints/damage pipeline for that splash
to actually kill it through, so it's separately detonated too; a real
platform target (helicopter/drone) is left to its own genuine hitpoints and
the interceptor's real splash damage, since it can legitimately survive a
near miss.

**AEGISM_Module_Site** is the one placeable/syncable AEGIS-M module. Sync
it to every vehicle that makes up a site (its radar, its launchers, its
CIWS) to link them into a battery: contacts are pooled, and a Site-wide
coordinator matches each contact to the best-fit weapon across every member
System before any of them fire, rather than each System independently
guessing what to shoot at. The Site's own Doctrine (engagement envelope,
target-priority rule, salvo policy, target-class allowlist, whether CIWS
holds fire until a launcher shot has failed) and Personality (skill tier x
temperament, which modulates the doctrine's timing/reliability rather than
owning its own numbers) apply battery-wide. A vehicle synced to more than
one Site, or never synced at all, still resolves sensibly per the object ->
network -> default fallback order.

**Engagement is coordinated, not just deconflicted.** A launcher's fit for
a contact is scored by how closely its loaded interceptor's real warhead
size (CfgAmmo indirectHitRange -- never a hand-set number) matches the
threat's own size, so a small inbound rocket doesn't burn a heavy
interceptor when a lighter one is available, and vice versa. CIWS can
engage in parallel with a launcher already working the same contact by
default (a fast/close threat shouldn't wait on an unproven missile shot),
or only as a last resort if the Site's Doctrine says so. If an assigned
shot doesn't result in a kill within a plausible flight-time window, the
contact is freed up for reassignment -- to the same System again, a
different/better-fit weapon, or CIWS -- rather than the System stubbornly
re-engaging under stale state.

Syncing or unsyncing a vehicle to a Site, or editing the Site's own
Attributes, takes effect live -- nothing requires re-placing modules or
restarting the mission.

**A weapon under AEGIS-M control can only fire through AEGIS-M.** Every
launcher/CIWS turret AEGIS-M recognizes has its crew's own independent
targeting and engagement disabled, so a shot only ever happens because
AEGIS-M's own gates (a real assignment, live ammo, crew reaction time,
shot-interval cooldown, salvo cap, a real line-of-sight check, a crew-
reliability roll) all passed -- not because the crew spotted something and
decided to engage on its own. A vehicle synced to a Site has this applied
the moment it's synced, independent of whether AEGIS-M ends up recognizing
it as a System at all, so a misconfigured or unrecognized vehicle goes
quiet rather than fighting uncontrolled.

**Debug 3D draw** (CBA setting "AEGIS-M > Debug > Enable Debug 3D Draw",
off by default, client-side/no gameplay effect) draws pooled contacts,
radar range, and every active engagement -- Site-wide assignments or a
standalone System's own acquired target, including live LOS state --
directly from the same variables the detection/intercept pipeline itself
reads and writes, similar in spirit to ACE missileguidance's own debug
draw.

## License

APL-ND (Arma Public License No Derivatives). See `LICENSE`.

## Coding convention

Every function begins with a standardized header docblock (see any file
under `addons/*/functions/`). Author is always Snow(Dryden).
