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

**IFF and threats.** Hostile contacts (mission side relations) are engaged,
including munitions -- but a hostile artillery, mortar or MLRS round (or
unguided rocket) only while its predicted impact falls within the threat
radius of a Site vehicle (Site setting "Only Engage Munitions Threatening
the Site", on by default): a shell landing well clear of the Site doesn't
cost a single round (`IGNORED` in the RPT). Guided missiles and bombs are
always engaged -- they steer or glide, so a ballistic prediction says
nothing. A friendly or neutral munition is engaged only when it is
predicted to hit the Site (doctrine "Engage Friendly Munitions Threatening
the Site", on by default): a guided missile whose own target is a Site
member, or an unguided round whose predicted impact falls within the threat
radius. The threat radius is the round's own config danger radius
(`dangerRadiusHit`, e.g. 750 m for 155 mm artillery, 1250 m for MLRS) unless
the Site sets one. A battery never engages its own interceptors. Only real
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
meeting point instead of turning hard after launch: a launcher fires only
with its barrel within 2 degrees of that point, or once its turret has
stopped closing on it (at its elevation limit, or trailing a fast lead
point) with the target inside the missile's own lock cone
(`missileLockCone`). The RPT's `FIRE` line gives the launch angle.

**CIWS guns fire only when a round could hit, and correct their own aim
from their rounds (closed-loop spotting, as a real Phalanx does).** A gun
tracks its target every frame from the moment it has one -- not just while a
burst is running, so it is already on the intercept point when the first
burst can open: the full intercept is solved 20 times a second, and every
frame in between the turret follows the aim point's own motion. The
intercept is solved from the round's real flight: muzzle velocity, drag
(`airFriction`) and gravity, with the drop damped by the same drag that
slows the round -- checked against a step-by-step simulation of the
engine's own bullet physics, the round passes within 5 cm of the aim point
out to 2.4 km, and arrives within 4 ms of the predicted time out to 2 km.
The gun
tracks a target from as far as it can reach, but only opens fire once the
intercept is inside its **open-fire range**: where its own config hit
probability (its fire modes' `minRangeProbab`/`midRangeProbab`/
`maxRangeProbab`, what the game's AI uses) still reaches the Site's "Open
Fire at Hit Chance" -- 50 % by default, about 2.1 km for a Phalanx whose
config reach is 3 km at 10 % (`OPEN-FIRE-RANGE` once per gun, `RANGE-HOLD`
while it waits). Given a choice, it takes a target it can open fire on now
over one it can only track. It fires only while the barrel's error at the
intercept is within the target's own size plus the gun's own spread there
(its fire mode's `dispersion`) -- about 0.3 degrees for a Phalanx at a shell
2 km out. In the last-ditch
window (the target due to impact within the gun's own longest burst,
`Burst Length Max`) it also fires once its turret has settled as close as it
can get, as long as that's within 5 times that gate: there is no better
shot coming (`LAST-DITCH` in the RPT); further off than that, a hit is out
of the question and it holds its ammunition (`LAST-DITCH-HOLD`). Every
third round it fires is measured as it passes the track the target was
*predicted* to fly: how far ahead of or behind the crossing motion, and how
far high or low square to that motion (a shell coming down in the gun's own
vertical plane crosses up/down, so all its miss is "ahead/behind"). That
miss is the gun's own error alone (turret lag,
flight-time estimate, drop, zeroing), kept apart from the target's evasion,
so a jinking helicopter can't drag the aim around. The gun keeps a running
estimate of the lead-time and elevation correction it needs for each kind
of target (shells, rockets, helicopters, ...), weighting each round by how
precisely it measures it and letting old rounds fade slowly, until it
changes ammunition. After each burst a `SPOTTING` line in the RPT gives the
average miss against the predicted track, how far the target strayed from
that track (evasion no fire control can foresee), and the correction in
use for that kind of target. Two guns on one vehicle each gate their own
fire. A gun never takes a target whose aim point is
beyond its turret's own elevation limits (`minElev`/`maxElev`) -- a shell
diving steeply beside a Praetorian (max 85 degrees) is released rather than
held with the barrel pinned short -- and a standalone gun keeps its target
while it can still engage it instead of re-picking every tick. A standalone
System's weapon turrets each work their own target, and a standalone
launcher moves on to its next target as soon as its missiles are away
(`MISSED` if they all miss, and the target is back on its list). A target with **no
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
near miss. A **carrier** round (one that releases a payload in flight, like
the MLRS rocket `R_230mm_HE` and its `R_230mm_fly` warhead, or a cluster
round) is detonated too, but whatever it releases is deleted as it's
created -- detonating a carrier on its own just releases the warhead, which
used to cost a second interceptor for every rocket.

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
re-aiming included), and is never queued past its **last missile**. A
queued round it can no longer reach in time, or has no missile left for, is
**handed off** early to a launcher that can (`HANDOFF` in the RPT); an
empty launcher gives its targets back at once.

**Layered reserve.** Against incoming munitions, long-range launchers hold
their missiles while the cheaper, shorter-range layer can cope. Every half
second the Site plays each launcher tier forward (shortest reach first):
its launchers' queues, cooldowns, measured shot spacing and missiles left,
and when each incoming round will enter each launcher's envelope along its
ballistic path. A round a cheaper tier is predicted to kill in time is left
to it (`RESERVE` in the RPT); only rounds no cheaper tier can take in time
-- the volume has saturated it -- open up the long-range launchers
(`SATURATION`). So a Patriot battery sitting behind RAM launchers doesn't
spend its missiles on MLRS rockets the RAMs will handle, but steps in, early
and far out, for the part of a barrage they can't.

Guns are matched by warhead size, then distance. Automated (drone-crewed)
systems ignore the crew model by default -- no reaction delay, no skipped
fire cycles (Site setting "Crew Skill on Automated Systems"). When a crewed
launcher's reliability roll fails, the Site is told: the target is re-tasked
to the rest of the Site straight away, and that launcher can't take it back
until its lost fire cycle is over, so another weapon gets the next try
(`ASSIGN-CLEAR ... crew failed to fire`). CIWS can
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

**Server load.** All of the detection and engagement work runs on the
server; other machines only suppress the AI targeting of crews they
simulate themselves, and nothing is broadcast. On the server:
- An idle weapon (nothing assigned to it, or nothing in a standalone
  System's pool) costs a quick check ten times a second.
- Every round fired in the mission passes through one cached lookup; only
  threat munitions go further.
- Incoming munitions are tracked by one shared tracker, twice a second
  each, spread over frames. A Site stops looking for a munition once one of
  its radars has it, and each radar re-traces its line of sight to a
  munition at most once a second.
- A CIWS gun's rounds in flight are tracked by one handler per gun, and a
  round is only examined once it's close to the target. The gun solves its
  full aim 20 times a second and steers between solves.
- The Site coordinator caches each munition's reserve-plan scan while the
  munition keeps to its predicted path, and skips the plan while every
  munition already has a launcher.
- Config values are read once per class and cached.

The `PERF` line (below) shows all of this. An AA crew that another machine
simulates (a headless client, a player's AI group) is moved to the server
the first time it has to fire (`NONLOCAL` in the RPT) -- a missile can only
be given its target where it's simulated. A player gunner can't be moved:
missiles fired from that turret fly without AEGIS-M's target.

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
`ASSIGN-CLEAR` with a reason. Every AEGIS-M RPT line carries the mission's
game time (`[AEGIS-M] t=123.4 ...`): the RPT's own timestamp is wall-clock
time, which keeps running while the game is paused.

**Site status hint** (CBA setting "AEGIS-M > Debug > Site Status Hint", off
by default) shows a live board in the hint box: the nearest Site's vehicles
with their roles, colour-coded status (READY, TRACKING, REACTING, SLEWING,
ENGAGING, FIRING, NO SOLUTION, LOS BLOCKED, NO AMMO, DESTROYED), target and
ammo, then its contacts and which weapons are on each; other Sites and
standalone Systems in summary. It shows data wherever AEGIS-M runs its
engagement logic: singleplayer, Eden Preview, or a hosted game's host.

**RPT performance summary** (CBA setting "AEGIS-M > Debug > RPT Performance
Summary", on by default) -- every 10 s, while AEGIS-M is doing anything, the
server writes one `PERF` line: coordinator runs and time (total and worst),
engagement ticks with work, aim solves and per-frame steers, CIWS rounds
tracked / checked near the target / skipped in flight / time, engageability
checks, standalone target re-evaluations, Fired events seen / threats among
them / munitions ignored as landing clear, munition tracker checks / line-
of-sight rays / time, reserve-plan cache hits and rebuilds, and server FPS.
Idle, it writes nothing. The timings come from a 32-bit clock that only
resolves to about 0.25 ms after an hour of game time, so treat them as
rough. Each weapon's config values are logged once when first used
(`KINEMATICS`).

**Benchmark** -- from the debug console (singleplayer, Eden Preview or a
host), looking at a System, with any live object as the target:
`[cursorObject, heli1] call aegism_intercept_fnc_debugBenchmark` times
AEGIS-M's per-call hot paths (classification, engageability check, aim
solve, per-frame steer, muzzle points, intercept solve) with
`diag_codePerformance` and writes one `BENCHMARK` line per function to the
RPT. Multiply by the counts in a `PERF` line for real milliseconds per
second.

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
| Only Engage Munitions Threatening the Site | On | A hostile artillery/mortar/MLRS round or unguided rocket is only engaged while predicted to land within the Threat Radius of a Site vehicle (`IGNORED` in the RPT otherwise). Guided missiles and bombs are always engaged. Off: every hostile munition in reach is engaged. |
| Threat Radius (m) | 0 | How close to a Site vehicle a predicted impact counts as a threat, for both settings above. 0 = the round's own config danger radius (`dangerRadiusHit`). |

**Launchers (Missiles)**

| Setting | Default | What it does |
|---|---|---|
| Min Range (m) | 0 | Extra minimum on top of the missile's own (MIM-145: 1000 m). |
| Max Range (m) | 0 | 0 = the missile's own reach (MIM-145: 16000 m). |
| Missiles per Target | 1 | Missiles fired before waiting for the result; re-engages if all miss. |
| Seconds Between Missiles | 0 | Minimum gap between missiles from one launcher. 0 = Auto: each launcher's own fire rate, the `reloadTime` of its weapon's fire mode, which scales with the missile (MIM-145 Defender 4 s, Mk49 Spartan 2 s, Mk21 Centurion 1 s). The RPT logs each launcher's rate as `FIRE-RATE`. |

**CIWS (Guns)**

| Setting | Default | What it does |
|---|---|---|
| Max Range (m) | 0 | 0 = the gun's own reach (Cheetah 35 mm: 2500 m). |
| Min Elevation (deg) | 5 | Never engages below it; holds fire while the barrel is below it. |
| Open Fire at Hit Chance (%) | 50 | Tracks from its full reach, but only fires inside the range where the gun's own config hit probability reaches this (Phalanx: about 2.1 km of 3 km). Lower = earlier, farther, more rounds per hit. 0 = its full reach. |
| Burst Length Min / Max (s) | 3 / 5 | Each burst lasts a random length in this range, at the gun's own rate of fire. |
| Pause Between Bursts (s) | 1 | Gap after a burst before firing again at the same target. After a kill the gun goes straight on to its next target. |
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
Interception Targets (what it reports, and which munitions it treats as
threats). A vehicle's active overrides are logged at start
(`OVERRIDES:` in the RPT). Script equivalent, e.g. for a Zeus-placed
vehicle: `_veh setVariable ["AEGISM_ovr_enabled", true]` plus
`_veh setVariable ["AEGISM_ovr_<setting>", value]`
(see `aegism_system_fnc_applyOverrides`).

## License

APL-ND (Arma Public License No Derivatives). See `LICENSE`.

## Coding convention

Every function begins with a standardized header docblock (see any file
under `addons/*/functions/`). Author is always Snow(Dryden).
