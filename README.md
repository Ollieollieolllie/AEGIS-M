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
AEGIS-M tells it to fire. Only air-capable weapons count (ammo `airLock` >= 1),
and every weapon engages within its own real envelope read from config
(missile lock min/max distance, gun fire-mode ranges).

**Which vehicles AEGIS-M controls.** Any vehicle synced to an AEGIS-M Site.
Unsynced vehicles are only adopted if they are a self-contained AA platform
-- their own radar plus their own AA weapons (Cheetah, Tigris) -- and the
"Standalone Air Defence" CBA setting is on (default). Aircraft and infantry
are never adopted, so an attack helicopter or an IFV with ATGMs keeps its
normal AI.

**IFF.** Hostile contacts (mission side relations) are engaged, including
munitions. A friendly or neutral munition is engaged only when it is
predicted to hit the Site (doctrine "Engage Friendly Munitions Threatening
the Site", on by default): a guided missile whose own target is a Site
member, or an unguided round whose predicted impact falls within its own
config danger radius (`dangerRadiusHit`, e.g. 750 m for 155 mm artillery)
of a Site member. A battery never engages its own interceptors. Only real
artillery/mortar rounds (`artilleryLock`) count as artillery threats; tank
main-gun rounds don't, and multi-stage rounds (e.g. MLRS rockets) stay
tracked through their submunition handoff.

**Detection is hybrid, by necessity.** Aircraft/helicopters/drones are read
straight off the vehicle's own native sensors (getSensorTargets) -- the
same radar/IR/visual/datalink simulation already running against its real
CfgVehicles config. Incoming missiles/rockets/shells can't use that path:
a fired projectile has none of the target-size properties that make a
CfgVehicles object sensor-visible, so it's never a valid getSensorTargets
result no matter how good the radar is. Those are tracked by a dedicated
Fired-event pipeline instead, gated by the same radar's own real detection
range/arc (read from its config, not a made-up number) plus a line-of-
sight check. **Firing commands the vehicle's own real weapon** with its
actual loaded ammo, so ballistics, guidance, and damage are entirely the
game's simulation, not a scripted projectile AEGIS-M spawns and steers
itself. Aiming and firing themselves are scripted directly (lockCameraTo on
the weapon's own turret path -- the command ACE's Hunter-Killer uses to slew
a gunner's turret -- from the moment a target is assigned, a real angle
check against the barrel's live direction, then firing once aligned)
rather than handed to fireAtTarget's own AI judgement. Every weapon aims at
its **intercept point**: where its round or missile would meet the target,
from real config kinematics (gun: muzzle velocity, drag, drop; missile:
launch speed, thrust, top speed) and the target's measured velocity and
acceleration. Launchers therefore leave the rail already pointed at the
meeting point instead of turning hard after launch. A target with **no
feasible intercept** -- receding faster than the round can close, or
meeting point beyond the weapon's reach or the round's lifetime -- is not
engaged, and a weapon already on it is released (`NO-SOLUTION` /
`ASSIGN-CLEAR`), so a gun doesn't burn ammo on a jet flying away from it.
A launched missile is handed its target (`setMissileTarget`) so vanilla
guidance actually homes. CIWS guns fire sustained bursts at the gun's own rate of fire
(doctrine: burst length 3-5 s by default, 1 s pause between bursts),
holding fire whenever the turret drifts off the lead point or the barrel
drops below the CIWS minimum elevation (doctrine, 5 degrees by default; a
target below it is never assigned to a CIWS). If a third-party scripted
missile guidance mod is loaded and the fired ammo declares real scripted
missile guidance, AEGIS-M also hands the target to that mod's own guidance
system so the shot actually homes rather than flying ballistic -- note
that mod's own missile guidance setting must allow AI-fired shots for this
to take effect.

**Intercepting a munition needs a proximity fuse, because Arma has no
projectile-vs-projectile hit detection at all.** A fired interceptor is
tracked frame-by-frame (closest approach on relative motion) and, once past
its own real arming distance (`fuseDistance`), detonated for real
(triggerAmmo, genuine splash effects) when it passes within its own blast
radius -- or, against a munition, within that munition's own physical size,
so a kinetic CIWS round that passes through an incoming missile counts as a
hit. A munition target has no hitpoints/damage pipeline for that splash
to actually kill it through, so it's separately detonated too; a real
platform target (helicopter/drone) is left to its own genuine hitpoints and
the interceptor's real splash damage, since it can legitimately survive a
near miss.

**AEGISM_Module_Site** ("AEGIS-M: Site", in the AEGIS-M module folder in
both Eden and Zeus) is the one placeable/syncable AEGIS-M module. Sync
it to every vehicle that makes up a site (its radar, its launchers, its
CIWS) to link them into a battery: contacts are pooled, and a Site-wide
coordinator matches each contact to the best-fit weapon across every member
System before any of them fire, rather than each System independently
guessing what to shoot at. The Site's settings apply battery-wide (see
**Settings** below); a vehicle never synced to a Site uses the defaults.

**Engagement is coordinated, not just deconflicted.** Launchers are chosen
by layered-defence doctrine, from each launcher's real values: first, one
that can fire in time (its readiness, its queue, its own Seconds Between
Missiles and the missile's flight time, against the threat's time to
impact); then the **shortest-reach** interceptor, keeping long-range
missiles for threats only they can reach; then the one with the **most
rounds left**; then the soonest ready and closest warhead size. A launcher
is free for its next target as soon as its missiles are away (they guide
themselves), and can **queue** several incoming munitions -- so a deep,
fast-cycling magazine like a RAM launcher takes the bulk of a rocket
barrage instead of a long-range SAM. Each launcher works its queue
soonest-impact first (time to impact from the round's ballistic arc), plans
it with its own **measured** time per missile (lost reliability rolls and
re-aiming included), and a queued round it can no longer reach in time is
**handed off** early to a launcher that can (`HANDOFF` in the RPT).
Guns are matched by warhead size, then distance. Automated (drone-crewed)
systems ignore the crew model by default -- no reaction delay, no skipped
fire cycles (Site setting "Crew Skill on Automated Systems"). CIWS can
engage in parallel with a launcher already working the same contact by
default (a fast/close threat shouldn't wait on an unproven missile shot),
or only as a last resort if the Site's Doctrine says so. A launcher shot is
judged a miss only once its missiles are actually gone and the target still
lives; the contact is then freed for reassignment -- to the same System
again, a different/better-fit weapon, or CIWS. Two weapons sharing a turret
are never assigned to different targets.

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
reads and writes. Every System also shows a live status label (networked/
standalone, contact source, per-role ammo, ASSIGNED, and live barrel
alignment while aiming). An assigned weapon that isn't firing always logs
why: `REACTING`, `SLEWING`, `NO-SOLUTION`, `LOS-BLOCKED`, `FIRE-SKIP`, or
`ASSIGN-CLEAR` with a reason.

**Site status hint** (CBA setting "AEGIS-M > Debug > Site Status Hint", off
by default) shows a live board in the hint box: the nearest Site's vehicles
with their roles, colour-coded status (READY, TRACKING, REACTING, SLEWING,
ENGAGING, FIRING, NO SOLUTION, LOS BLOCKED, NO AMMO, DESTROYED), target and
ammo, then its contacts and which weapons are on each; other Sites and
standalone Systems in summary. It shows data wherever AEGIS-M runs its
engagement logic: singleplayer, Eden Preview, or a hosted game's host.

## Settings

The Site module's attributes are in four sections. Every default is chosen
so a Site works out of the box: each weapon uses its own real config
envelope, and all threat classes are engaged.

**Site Settings**

| Setting | Default | What it does |
|---|---|---|
| Target Priority | Soonest Impact | Which contacts get weapons first when threats outnumber free weapons: Soonest Impact (whatever reaches the Site first -- an incoming salvo is worked front to back), Nearest (to any Site vehicle), Fastest Closing, or Highest Value (missile > bomb > aircraft > drone/rocket > artillery). |
| Crew Skill | Regular | Reaction time and reliability: Green 4.0 s / 55 %, Regular 2.5 s / 70 %, Veteran 1.2 s / 85 %, Elite 0.5 s / 95 %. Reliability is rolled once per missile or CIWS burst; CIWS reaction is capped at 1 s. |
| Crew Temperament | Standard | Scales reaction, reliability and the pause between shots (Cautious / Standard / Aggressive / Nervous). |
| Crew Skill on Automated Systems | Off | Off: automated systems (crewed by UAV AI -- Phalanx, RAM, MIM-145, radars) ignore Crew Skill and Temperament -- no reaction delay, no skipped fire cycles, no interval scaling. On: they get the same crew model as manned systems. |
| Save Ammo for Bigger Threats | Off | Hold fire if firing would leave fewer rounds than tracked higher-value contacts. |

**Interception Targets**

| Setting | Default | What it does |
|---|---|---|
| Engage Missiles / Rockets / Bombs / Artillery, Mortar and MLRS Rounds / Fixed-Wing / Helicopters / Drones | all on | Which threat classes the Site engages. |
| Target Min / Max Height (m above ground) | 0 / 0 | Ignore contacts outside this height band. Max 0 = no limit. |
| Engage Friendly Munitions Threatening the Site | On | Also engage a friendly/neutral round predicted to hit the Site. |
| Friendly Threat Radius (m) | 0 | 0 = the round's own config danger radius (`dangerRadiusHit`). |

**Launchers (Missiles)**

| Setting | Default | What it does |
|---|---|---|
| Min Range (m) | 0 | Extra minimum on top of the missile's own (MIM-145: 1000 m). |
| Max Range (m) | 0 | 0 = the missile's own reach (MIM-145: 16000 m). |
| Missiles per Target | 1 | Missiles fired before waiting for the result; re-engages if all miss. |
| Seconds Between Missiles | 4 | Minimum gap between missiles from one launcher. |

**CIWS (Guns)**

| Setting | Default | What it does |
|---|---|---|
| Max Range (m) | 0 | 0 = the gun's own reach (Cheetah 35 mm: 2500 m). |
| Min Elevation (deg) | 5 | Never engages below it; holds fire while the barrel is below it. |
| Burst Length Min / Max (s) | 3 / 5 | Each burst lasts a random length in this range, at the gun's own rate of fire. |
| Pause Between Bursts (s) | 1 | Gap after each burst. |
| Last Resort Only | Off | Hold while a launcher covers the contact, until it fails or the contact closes inside 40 % of the gun's reach. |

Range settings are real-world metres, scaled by the CBA setting AEGIS-M
Range Scale. Launcher ranges never apply to guns, and vice versa.

**Per-vehicle overrides.** Every vehicle has an **AEGIS-M: Vehicle
Overrides** category in its own Eden attributes, with the same four
sections. Tick **Override Site Settings**, then change only what should
differ for that vehicle; everything left on "Site setting" (or blank) keeps
following the Site. Examples: set a long-range SAM's "Artillery, Mortar and
MLRS Rounds" to Ignore so it never spends missiles on shells, or give one
CIWS a shorter Max Range as an inner layer. Overrides on a radar affect its
Interception Targets (what it reports, and which friendly munitions it
treats as threats). A vehicle's active overrides are logged at start
(`OVERRIDES:` in the RPT). Script equivalent, e.g. for a Zeus-placed
vehicle: `_veh setVariable ["AEGISM_ovr_enabled", true]` plus
`_veh setVariable ["AEGISM_ovr_<setting>", value]`
(see `aegism_system_fnc_applyOverrides`).

## License

APL-ND (Arma Public License No Derivatives). See `LICENSE`.

## Coding convention

Every function begins with a standardized header docblock (see any file
under `addons/*/functions/`). Author is always Snow(Dryden).
