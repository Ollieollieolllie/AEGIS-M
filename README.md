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
- [Zeus Enhanced](https://github.com/zen-mod/ZEN) (optional: needed to edit
  Site settings and vehicle overrides from Zeus)
- Arma 3 2.18 or later (the `ProjectileCreated` mission event; the POOK
  compatibility addon needs 2.14's `skipWhenMissingDependencies`)

Compatibility addons ship inside the mod and load only with the mod they're
for: `aegism_compat_pook` for POOK's SAM pack (see **Other mods** below).

## How it works

**A vehicle's role is discovered, never declared.** AEGIS-M reads a
vehicle's own native config and current loadout: every sensor it has
(active radar, IR, visual, passive radar -- with each one's own reach, arc
and whether it turns with a turret); if it has guided missiles, it's a
launcher; if it also has a high-rate-of-fire cannon (a SHORAD or Tigris-style
all-in-one vehicle), it's also a CIWS/CRAM. A machine gun doesn't count (a
weapon built on the game's `MGunCore`, as every vanilla machine gun is): the
self-defence .50 or PKT on a mod SAM vehicle isn't run as a CIWS. A vehicle
override, **Guns Used as CIWS**, changes that per vehicle: Every Rapid-Fire
Gun, or None. There is no role checkbox, no detection
range/arc, no missile count, no guidance speed, no ammo classname to set
anywhere -- all of that is either read live from the vehicle's real
sensors/magazines, or is simply the game's own weapon simulation once
AEGIS-M tells it to fire. Only air-capable weapons count (ammo `airLock` >= 1),
and every weapon engages within its own real envelope read from config
(missile lock min/max distance, gun fire-mode ranges).

**Which vehicles AEGIS-M controls.** Any vehicle synced to an AEGIS-M Site
-- including one whose only use is a sensor (an IFV's IR sight feeds the
Site what it sees). Unsynced vehicles are only adopted if they are a
self-contained AA platform -- a sensor of their own (radar, IR or visual)
plus their own AA weapons (Cheetah, Tigris, or a Spartan with its
launcher-mounted IR) -- and the "Standalone Air Defence" CBA setting is on
(default). Aircraft and infantry are never adopted, so an attack helicopter
or an IFV with ATGMs keeps its normal AI.

**IFF and threats.** Hostile contacts (mission side relations) are engaged,
including munitions. A renegade (side ENEMY, e.g. a pilot whose rating fell
through friendly fire) is hostile to everyone, its own former side included.
A hostile munition is only engaged while it's a threat to a Site vehicle
(Site setting "Only Engage Munitions Threatening the Site", on by default):
- an artillery, mortar or MLRS round, an unguided rocket, or a missile that
  can't steer (the vanilla `Rocket_04_HE_F`): predicted to land within the
  threat radius of one;
- a guided missile: guided at one (`missileTarget`), flying on a line that
  passes within the threat radius of one, or -- when what it's homing on
  can't be read (ACE guidance, a laser spot) -- with one inside its seeker's
  view: within its seeker cone of its line of flight, closing (the cone from
  its config: ACE `seekerAngle`, else `missileKeepLockedCone`, e.g. 60
  degrees for the vanilla `M_Scalpel_AT`), and turning toward it: its angle
  off that line no wider than at the check before (a missile flying past a
  vehicle opens that angle). The first sighting waits one check (0.5 s);
- a bomb whose fall or line of flight does;
- or the Site's **protected area**: a circle round the Site module
  (Protected Area Radius, 750 m by default). A hostile munition guided at
  anything inside it (an ammo truck, a building), flying down into it, or
  predicted to land in it is a threat. Linked Sites each protect their own
  circle (with a Shared Site Coordinator, its radius applies round each).
  Friendly munitions are still judged on the Site's vehicles only, so
  friendly mortars firing on attackers near the Site aren't shot down.

A shell landing well clear of the Site, or a missile flying at something
else, doesn't cost a single round (`IGNORED` in the RPT, with what a missile
was homing on), and is picked up if it turns toward the Site. `TRACKING`
says why a munition counts as a threat. A
friendly or neutral munition is engaged only when it is
predicted to hit the Site (doctrine "Engage Friendly Munitions Threatening
the Site", on by default): a guided missile whose own target is a Site
member, or an unguided round whose predicted impact falls within the threat
radius. The threat radius is the round's own config danger radius
(`dangerRadiusHit`, e.g. 750 m for 155 mm artillery, 1250 m for MLRS) unless
the Site sets one. A battery never engages its own interceptors. Only real
artillery/mortar rounds (`artilleryLock`) count as artillery threats; tank
main-gun rounds don't, and multi-stage rounds (e.g. MLRS rockets) stay
tracked through their submunition handoff.

**Detection follows each vehicle's own sensors.** Every vehicle with a
radar, IR or visual sensor of its own is read from its real CfgVehicles
sensor config: each sensor's own range, arc, line of sight, fog, night and
speed limits, ground clutter, and an active radar only while it's emitting
(see **Radar emission** below). Each contact records which kinds of sensor
saw it.
- **Aircraft, helicopters, drones** are the game's own sensor simulation,
  read directly (getSensorTargets; `DETECT` in the RPT, once per new
  contact). A target's own size scales a sensor's range (`radarTargetSize`
  0.1 on a Darter: a 9 km radar sees it at 900 m).
- **Missiles, rockets, shells, bombs** can't be: a fired projectile has
  none of the target-size properties that make an object a sensor target,
  and the game's sensors never report one. So AEGIS-M judges munitions
  itself, by the rules the game's sensors work to (BI's Sensors config
  reference) and from the same config. A sensor sees a munition when:
  - it's on: a radar only while the vehicle's radar emits; none through fog
    thicker than its `maxFogSeeThrough`;
  - the munition is inside its horizontal and vertical arcs, measured from
    where it looks: along the hull, or wherever its turret points right now
    (so a turning radar sees where it has actually got to), tilted by its
    `aimDown`;
  - it's in range: against the sky (the munition above the sensor) its
    `AirTarget` range, against the ground behind it its `GroundTarget`
    range -- each the smallest of `maxRange` and the view distances times
    their limit coefficients, never under `minRange`, scaled by
    `nightRangeCoef` toward night and by the munition's signature, 2.5 (a
    target's size scales a sensor's range; 2.5 is what was settled on to
    have munitions picked up reliably);
  - its speed and height are within `min/maxTrackableSpeed` and
    `min/maxTrackableATL`;
  - seen from above, it's clear of ground clutter: farther from the ground
    behind it than `groundNoiseDistanceCoef` x the distance to that ground
    (at most `maxGroundNoiseDistance`), unless it's fast -- at or above
    `maxSpeedThreshold` it always shows (the vanilla radar: 28 m/s; munitions
    fly at hundreds);
  - the vehicle has a line of sight to it: no terrain between, and nothing
    else in the way within 5 km. A clear line isn't traced again for 2 s.

  A munition is hot for its whole flight, so IR sees it as radar does. Every
  sensor vehicle of a Site that sees a munition adds its kind to the contact,
  so a radar and a Spartan's IR both show. It's all on the server, so it
  works whoever crews the vehicles (a player gunner, a headless client). A
  cluster carrier's bomblets aren't followed at all, nor is an AEGIS-M
  interceptor unless an AEGIS-M vehicle is hostile to its side. `TRACKING`
  in the RPT names the sensors that found a munition, and how long after
  launch; `SIGHTED` (Verbose) each sensor vehicle's first sight of it.
  (Each munition used to carry an invisible vehicle for the game's sensors
  to find instead. They weren't built for it: a radar reported nothing for
  about 2.5 s after coming on, the vehicle didn't stay with every munition,
  showed no speed while attached, and could be shot. Two things went with
  it: munitions no longer show on a crew's own radar display, and only
  AEGIS-M's weapons shoot them down -- neither worked off the server
  anyway.)
- **Blast.** When an interceptor goes off, any other tracked munition whose
  body is inside its blast radius goes with it, and so does any inside the
  blast of the munition it destroyed: an intercept among a salvo takes the
  rockets flying beside it (`BLAST-KILL`). A lost interceptor's
  self-destruct does the same.
- **Timing.** Each sensor vehicle reads its sensors once a second, and
  four times a second while any munition is in flight. A munition one of
  them sees for the first time is checked at once, and when it enters a
  Site's picture the Site's coordinator assigns weapons in the next frame
  rather than at its next half-second turn.

**Datalink doesn't count by default.** The game's datalink passes a vehicle
what other vehicles see: any friendly vehicle with datalink in the mission,
not only AEGIS-M's. A Site already shares its own members' contacts, so a
target that only datalink reports is ignored, and `DL` is dropped from what
saw a contact. The CBA setting "AEGIS-M > General > Use Datalink Contacts"
turns it on (e.g. a standalone SPAAG fed by a friendly AWACS). It's about
aircraft: the game's datalink carries no munitions.

**Passive radar cues, it doesn't aim.** A contact only passive radar hears
(an aircraft with its radar on) gives a bearing, not a track. It's pooled
and cues the Site's radars (**Radar emission**), but no weapon is assigned
to it until a radar, IR or visual sensor holds it. The debug overlays tag it
`CUE ONLY`.

The proxies exist on the server only, so a vehicle whose crew is simulated
elsewhere (a headless client, a player gunner) doesn't see munitions.

**Radar emission.** An active radar only sees while it emits, and while it
emits, enemy radar-warning receivers and anti-radiation missiles can find
it. Each Site sets when its radars emit (**Radar Emission**, a per-vehicle
override too), applied with `setVehicleRadar`:

| Mode | What its radars do |
|---|---|
| Automatic (default) | While the Site is quiet, a relay scan (below) so little is given away. It emits continuously while there's a reason to, and for at least 60 s after. The reasons are a contact anywhere in the Site's picture, the Site engaging or firing, a munition inbound, or another of its radars shut down for an anti-radiation missile (the rest take over). |
| AI decides | As without AEGIS-M. |
| Always on | Emit all the time. |
| Silent until cued | Off until another sensor finds a threat the radar covers. |
| Intermittent | As Silent until cued, but searching meanwhile with the relay scan (below). |

- **The relay scan.** While the Site is quiet (Intermittent, or Automatic with
  nothing going on), its turning radars (like the radar truck's 120 degrees,
  with those of the Sites linked to it) scan as one radar whose beam is
  handed from vehicle to vehicle. A lap steps round the whole circle one arc
  at a time (four 90-degree arcs for 120-degree radars), each lit by one
  radar for Search Burst Seconds On, then all are silent for Seconds Off.
  Each arc goes to whichever radar can swing onto it soonest, other than
  the one lit before it, picked a step ahead, so it swings there while
  silent and lights on it. Every bearing is scanned once a lap and no arc
  twice; one radar emits at a time, and the emitter keeps moving from
  vehicle to vehicle. Radars that see all round take turns bursting, as
  before.
- **Cues** are contacts in the Site's picture (the whole linked group's):
  an enemy radar heard by passive radar, an aircraft or round seen by IR or
  visual sensors, another radar's, a linked Site's, or datalink's where
  that's allowed.
- **Coverage** is the radar's own reach and arcs, horizontal and vertical.
  A radar on a turret covers whatever its turret can turn and elevate it
  to (the vanilla radar truck's 120 x 120 degree radar covers all round,
  from 70 degrees below the horizon to straight up).
- **A lit radar stays lit** while any contact is in its coverage, while a
  launcher's missiles are in flight at a target it covers (fire control),
  and for **Stay Lit After Last Contact** (10 s) after the last.
- **A narrow radar on its own turret** (no AEGIS-M weapon on it, like the
  radar truck's) is turned by AEGIS-M in every mode, AI decides included.
  A Site's turning radars, and those of the Sites linked with it, **divide
  the sky** into equal home sectors, one each, measured from the middle of
  them. With one radar the sector is the whole circle; with two, halves;
  with three, thirds, the first centred on north. Each looks after its own
  sector:
  - **Fire control:** while the Site's missiles fly at targets in its
    sector, it holds as many of them as it can and doesn't search.
  - **Track:** otherwise it centres on the contacts in its sector, holding
    the most important at once. A contact under engagement counts most,
    then munitions by time to impact, then one only passive radar hears (a
    radar look turns it into a track), then aircraft. A contact another
    Site sensor holds counts for less: the radar is for what nobody holds.
    It stays put unless another centre is clearly better. Every 6 s it
    takes a look at the rest of its sector, then swings back.
  - **Search:** with nothing to track, the turning radars rotate round
    together, evenly spaced (two face opposite ways, three are 120 degrees
    apart). They step on together, three quarters of the narrowest arc at a
    time, paced for the slowest turret (the radar truck: 90 degrees every
    4 s), by the mission clock, so they always keep their places. Every
    radar looks all the way round, so radars far apart each see past their
    own hills. At any moment their beams are spread round the sky; three
    120-degree radars keep all round covered as they turn. Silent radars
    turn too, so each is in place the moment it lights. With the Site
    setting **Turning Radars Hold Their Sector** on, a radar whose arc
    covers its sector holds it still instead.
  - **A contact belongs to the radar whose sector it's in.** Another radar
    tracks it only if the owner can't reach it, and then only one of them,
    so radars don't leave their sectors uncovered to double up.

  Each dwell starts once the turret has had time to swing there (its own
  traverse rate). A silent radar keeps pointing where it would look, so
  it's on it the moment it lights. The debug overlays show its job and
  sector (`SEARCH 120 deg, sector 60-180`, `(swinging)`, `TRACK 2 (045
  deg, ...)`, `FIRE CONTROL 1 (...)`), and at RPT Detail Verbose each new
  task and search position is logged (`RADAR-TASK`).
- A Site with no sensor but its radars never lights in Silent until cued:
  use Intermittent. Munitions don't emit, so passive radar never cues on
  them; IR, visual and other radars do.
- The trade-off: a munition released while every radar is silent goes
  unseen until a radar comes on or it closes into IR or visual range. A
  hostile aircraft is usually found and held before it releases, which
  keeps the radars covering it lit. A friendly aircraft never cues (it
  isn't a contact), so friendly rounds falling on the Site get the least
  warning. `TRACKING` in the RPT gives how long after launch each munition
  was first seen.

**Anti-radiation missiles.** A missile whose own seeker is a passive radar
(the vanilla HARM and Kh-58) is recognised from its config. When a Site
sees one homing on one of its radars (`missileTarget`), or one with a Site
radar emitting in its seeker's view, that radar shuts down, in every mode,
whether or not that saves it (**Shut Down for Anti-Radiation Missiles**, on
by default). It stays down until the missile is gone, or 5 s past when it
would have arrived. The Site's other radars that cover the missile light up
for it, so its guns keep a track. This works whether or not the Site
engages missiles.

RPT lines: `EMCON` (each radar's mode, going silent, back to searching),
`CUE` (lit for a contact, and what found it), `ARM-SHUTDOWN` (shut down,
with which other radars are still emitting, and back), `ARM-END` (how each
anti-radiation missile ended: what it was homing on at its last check, how
far it was from the nearest AEGIS-M radar and whether that radar was
emitting, and whether any AEGIS-M sensor saw it). The status board,
the laptop terminal and the 3D draw show each radar's state and why:
`EMITTING`, `SILENT`, `SHUT DOWN`, or `AI: ...` while the AI decides. If a
radar doesn't follow what AEGIS-M set within 2 s, they say so.

**Firing commands the vehicle's own real weapon** with its
actual loaded ammo, so ballistics, guidance, and damage are entirely the
game's simulation, not a scripted projectile AEGIS-M spawns and steers
itself. Aiming and firing themselves are scripted directly (lockCameraTo on
the weapon's own turret path -- the command ACE's Hunter-Killer uses to slew
a gunner's turret -- from the moment a target is assigned, a real angle
check against the barrel's live direction, then firing once aligned)
rather than handed to fireAtTarget's own AI judgement. Every weapon aims at
its **intercept point**: where its round or missile would meet the target,
from real config kinematics (gun: muzzle velocity, drag, drop; missile: its
flight simulated from config) and the target's measured velocity and
acceleration. A missile's flight follows the engine's documented rules:
launch speed, the motor lighting after `initTime`, thrust at full for 75% of
`thrustTime` then fading out, and drag of 0.00225 x `airFriction` x speed^2
along its nose. `airFriction` is each missile's own; the 0.00225 is the
engine's, in no config, fitted to AEGIS-M's own missiles' measured speeds.
`maxSpeed` is not applied: some missiles stop at it and some run well past
it. That's only where a missile starts: each one's own flights then teach
AEGIS-M its real speed, second by second (see **Learning in play**), so a
launcher from any mod is predicted on what its missiles actually do. The
RPT's `MISSILE-PROFILE` line gives each missile's simulated speeds and
times, and `MISSILE-SPEED` compares every flight's real speed with the
prediction, second by second, however it ended (both Verbose). Launchers
leave the rail already pointed at the meeting point instead of turning
hard after launch: a launcher fires only
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
Like a missile, a gun is judged where its rounds meet the target, not where
the target is now: it opens fire so its rounds arrive just as an incoming
round comes into reach. The gun
tracks a target from as far as it can reach, but only opens fire once the
intercept is inside its **open-fire range**: where one burst is at least the
Site's "Open Fire at Hit Chance" (40 % by default) likely to put a round
within hitting distance. That's worked out from measurable things only:
- the gun's own measured scatter: every spotted round's miss, square to the
  line of sight, over its range. Until it has fired, the fire mode's
  `dispersion` stands in for it.
- how far the target strays from its predicted track per second of flight
  (measured the same way)
- the round's flight time (`initSpeed`, `airFriction`)
- the hit radius: the target's size to the gun -- a munition's body as
  seen along the line of fire plus the round's own blast or proximity
  radius (as its fuse counts a hit), an aircraft's half-size
- the rounds in a burst: the gun's measured rate of fire times the burst
  length

It never fires beyond the round's reach in its lifetime (`timeToLive`, or
until an airburst round bursts), or
inside its arming distance (`fuseDistance`) against a munition. The range
moves as the gun learns its own accuracy: `OPEN-FIRE-RANGE` logs it with
every input, `RANGE-HOLD` while a gun waits, and `TARGET-SIZE` logs each
target type's measured size. Given a choice, the gun takes a target it can
open fire on now over one it can only track. It fires only while the barrel's error at the
intercept is within the target's size to the gun plus the gun's own spread there
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
tracked frame-by-frame (its path relative to the target, both moving) and,
once past its own real arming distance (`fuseDistance`), detonated for real
(triggerAmmo, genuine splash effects) when its path comes within its own
radius -- its blast (`indirectHitRange`) or its own proximity fuse
(`proximityExplosionDistance`), whichever is larger -- of the munition's
body: its model's bounding box, turned the way it's flying. A kinetic round
(a .50, with no blast) has to pass through the box itself. Nothing finer
exists: no LOD of a projectile can be hit by a line (tested in game), so the
box is the body, and how true it is depends on the model -- FZA's Hellfire
is 0.24 x 1.63 m, vanilla's 230 mm rocket 2.29 x 11.96 m. It used to be a
sphere round the box (6.19 m round that rocket), and a .50 scored kills 4-5
m off it. A gun's fire gate and open-fire range use the same size: the box
as seen along the line of fire, plus the round's own radius. Against an
aircraft, the interceptor's blast reaches from the aircraft's centre. An
**airburst** gun round -- one that turns into a bursting submunition
(`triggerTime`, then the submunition's own `explosionTime`; POOK's 20-30 mm
AA) -- flies only until it bursts, which caps the gun's reach, and kills
where it bursts if the target's body is within the burst's blast; any mod's
round is read this way. A munition target has no hitpoints/damage pipeline for that splash
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

**Linked Sites.** Sites can be linked into one in three ways, as many at
once as you like: a vehicle synced to both (say two batteries, each 4
launchers, a radar and a CIWS, that both sync a shared long-range radar); a
vehicle of one synced to a vehicle of the other (held while both are
alive); or the two Site modules synced to each other. Losing one of several
links keeps the Sites linked (`LINK-CHANGE` in the RPT); they split when the
last one goes. While linked, the Sites share one contact pool and one set of
assignments, and one coordinator assigns every target across all their
vehicles, so two batteries never fire on the same target unless that's the
plan (a CIWS alongside a launcher). The coordinator is the Site ticked
**Shared Site Coordinator**: its settings (doctrine, crew, alarms) then
apply to every vehicle of the group, each vehicle's own overrides still on
top. With none ticked, the first Site set up coordinates and each vehicle
keeps its own Site's settings. Only one Site of a group can be its
coordinator: ticking it on one unticks it on every Site synced or linked to
it, in Eden and in Zeus. A munition threatening any of the group's vehicles
is a threat to all of it, and the Sites' alarms sound together. Links chain
(A linked to B and B to C make one group of three). When the link goes --
the linking vehicle destroyed or unsynced, the modules unsynced -- the
group splits back into independent Sites with their own settings: each
keeps its own vehicles' assignments (a missile already in flight is still
followed) and a copy of the contacts. Logged as `LINK` / `UNLINK`.

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
soonest-impact first (time to impact from the round's ballistic arc) --
except that the round its turret is already on keeps its place unless one
5 s more urgent comes, so rounds of a salvo don't swap places as their
estimates move and swing the turret between them. It plans the queue with
its own **measured** time per missile (lost reliability rolls and
re-aiming included, and its crew's quicker reaction once in combat), and is
never queued past its **last missile**. A launcher is only given a round it
can kill in time (`LATE` in the RPT when none can: it's left to the
guns). For a launcher that isn't ready yet -- between missiles, or with
rounds ahead on its queue -- that's judged from when it will be: a shot from
then on that meets the round inside its envelope before impact. Not where
the round is now, and not the flight of a shot fired now (a rocket 11 km out
is a 16 s flight; by the time a busy launcher is free it's a few seconds).
So a slow launcher -- POOK's S-300 fires every 30 s -- isn't handed the next
round due if that will be inside its minimum range or too steep by the time
it can fire: its place goes to the first one due that it can kill. A queued
round it can no longer kill in time (by more than half a
second), or has no missile left for, is **handed off** to a launcher that
can (`HANDOFF`), or released if none can; an empty launcher gives its
targets back at once. A round at the front of a queue that the launcher
never fires at (it can't bear, no line of sight) is released after 15 s --
not counting the time the launcher itself wasn't ready. A missile whose target is gone before it gets there
(another weapon killed it first), or whose seeker turns to something else,
follows another incoming munition the Site is tracking if that's what its
seeker took. Otherwise it self-destructs where it is (`INTERCEPTOR-LOST`).
Left free, such missiles found
the next thing in their seeker's view and shot down an aircraft the Site
wasn't allowed to engage. Between targets a launcher or gun stays pointed at
the contact it's most likely to get next -- one no weapon of its kind has
yet, soonest impact first -- rather than going back to its crew, which
turned it away between the rockets of a salvo; it's handed back once
there's nothing left to engage.

**Layered reserve.** Against incoming munitions, long-range launchers hold
their missiles while the cheaper, shorter-range layer can cope. Every half
second the Site plays each launcher tier forward (shortest reach first):
its launchers' queues, cooldowns, measured shot spacing and missiles left,
and the first moment along each incoming round's ballistic path that a
missile fired at it would meet it inside each launcher's envelope. A round a cheaper tier is predicted to kill in time is left
to it (`RESERVE` in the RPT); only rounds no cheaper tier can take in time
-- the volume has saturated it -- open up the long-range launchers
(`SATURATION`). So a Patriot battery sitting behind RAM launchers doesn't
spend its missiles on MLRS rockets the RAMs will handle, but steps in, early
and far out, for the part of a barrage they can't. If the cheaper tier was
due to fire at a round 3 s ago and none of its launchers has it, or its shot
missed, the reserve stops holding back for that round (`RESERVE-MISSED`):
a long-range rocket coming down too steep for the RAMs once held every
Patriot back until it was too late. And it only holds back at all if a
long-range launcher would still have a second shot should the cheaper
tier's planned kill miss (3 s to see the miss, then a shot that meets the
round before it comes down). A high-arc rocket falls back into a RAM's
reach only in its last seconds; planned to the RAMs there, it left the
Patriots no second chance, so now the Patriots take it early
(`RESERVE-RELEASED`).

Guns are matched by warhead size, then distance. A gun is only given an
incoming munition it has its **Minimum Firing Window** on (CIWS setting, 3 s
by default): after its crew's reaction, its barrel's swing and the rounds'
flight, that long left to fire before impact, with the barrel still able to
follow it (a rocket diving steeply goes past a Cheetah's 80-degree limit in
its last seconds). A munition with less is a last-ditch shot: a gun takes
one only when it has nothing better to do (`ASSIGN ... last-ditch`), and
drops it the moment a munition it has its full window on comes. Handed
rockets 2-5 s from impact one after another, a Cheetah hit 2 of 21, and
swung away from the rest of the volley each time; with 6-9 s it hit 14 of
19.

Automated (drone-crewed)
systems ignore the crew model by default -- no reaction delay, no skipped
fire cycles (Site setting "Crew Skill on Automated Systems"). When a crewed
launcher's reliability roll fails, the Site is told: the target is re-tasked
to the rest of the Site straight away, and that launcher can't take it back
until its lost fire cycle is over, so another weapon gets the next try
(`ASSIGN-CLEAR ... crew failed to fire`). A crewed gun's failed roll costs it
its crew's reaction, not a whole pause between bursts. CIWS can
engage in parallel with a launcher already working the same contact by
default (a fast/close threat shouldn't wait on an unproven missile shot),
or only as a last resort if the Site's Doctrine says so. A launcher shot is
judged a miss only once its missiles are actually gone and the target still
lives; the contact is then freed for reassignment -- to the same System
again, a different/better-fit weapon, or CIWS. Two weapons sharing a turret
are never assigned to different targets.

**Launchers fire to meet the target at the edge of their reach.** A
launcher is judged by where its missile would meet the target, not where
the target is now. Against an incoming round it fires while the round is
still beyond its reach (the missile's own lock range, `missileLockMaxDistance`,
or the Site's Max Range), so the missile meets it out near the edge instead
of well inside, with time left for a second shot. If a missile fired that
far out loses its target, `INTERCEPTOR-LOST` shows it (see above).

**Only what a weapon can actually reach.** Every turret's elevation and
traverse limits, rotation rates and mount type (trainable, fixed bearing,
fixed elevation, or fixed -- a vertical launch cell or a hull-fixed
launcher) come from its config (`TURRET-RATE`). A gun is only given a
target it can slew onto and reach before impact: slew time from its
rates, plus the round's flight, must beat the impact, or it's released
(`can't get on it in time`) and the gun moves on to one it can still kill.

**Launching off-bore.** A missile doesn't have to leave pointing at its
target: a vertical launch cell can't point at all, a turret stops at its
limits, and one still swinging round could fire now and let the missile
turn. For every launcher and target AEGIS-M works out how to launch:
- **swing, then launch** (the normal way): the turret goes to the closest
  direction it can reach -- straight at the intercept if it can -- and the
  swing time counts. At the start of an engagement, with time in hand, it
  always swings fully first.
- **launch now**, before the turret is round: a last resort, only for an
  intercept it otherwise couldn't make -- swinging first would get the
  missile there after the target comes down.
- **fixed mount**: along its barrel, whatever it points at.

A launcher that can move has two limits on how far off the intercept it
fires. **Max Off-Bore Launch While Swinging** (20 deg by default) applies
while its turret is still swinging round; further off, it finishes the
swing instead. **Max Off-Bore Launch At Turret Limit** (30 deg by default)
applies once the turret is as close as it can get: at its elevation or
traverse limit, or a mount that can't move on one axis. A Spartan's RAM
turret stops at 40 deg, and a high-arc rocket can only be met 55 deg up
or more, so it fires from the limit and lets the missile turn up the rest
of the way. A fixed mount is only limited by its missile. And a launch more than 2 deg off the
intercept needs the missile to be able to get there after launch (`AGILITY`
in the RPT, once per missile):
- **Its post-launch cone**: vanilla `missileKeepLockedCone` (MIM-145 120
  deg, RIM-116 180 deg); for ACE-guided missiles 180 deg when they lock on
  after launch, or their seeker angle when they must lock before (ACE's RAM:
  45 deg).
- **Its turn rate**: ACE's own configured rate for ACE-guided missiles
  (Patriot 30 deg/s, S-400 25, ESSM 15, RAM 50). Missiles the game guides
  have no turn rate in config, so it's **measured**: every AEGIS-M missile's
  body rotation is followed in flight, and the fastest sustained turn on a
  flight that had to turn becomes that missile's rate (`MISSILE-TURN`, with
  predicted vs actual flight time). Until one has been seen turning, an
  off-bore shot is only taken where there's no better choice, flown as if
  straight -- and that flight measures it.
- A missile ACE hands to its own guidance (`maneuvrability` 0) can't be
  steered at all when ACE isn't guiding AI shots, so it's only launched
  straight.

With a turn rate, the flight is modelled as a turn onto the intercept at
that rate, then a straight run: honest flight times, and a minimum range
inside which the missile can't turn in time. Against an incoming munition
the swing plus the flight must beat its impact (`can't get a missile onto
it in time`), so a launcher isn't queued something it can't kill -- a RAM
launcher limited to 40 deg elevation used to freeze its whole queue on
high-arc rockets it could never lock. An off-bore launch's first leg must
be clear (`LAUNCH-PATH-BLOCKED`). Each off-bore shot is logged as
`OFFBORE-LAUNCH` with its predicted turn and flight.

**Learning in play.** Some things AEGIS-M can't read from config, or that
config gets wrong, so each weapon measures them during the mission. Every
one starts from config and resets at the next mission. A measurement that
can't be right is taken as a problem with the measuring (a frame hitch, a
position or velocity that jumped, a round fired off its gate, a missile
that changed target) and thrown away. One odd measurement can't move what's
learned far. The limits are all in `addons/intercept/calibration.hpp`.

| What's learned | From | Safeguards |
|---|---|---|
| A missile's speed curve | Every AEGIS-M missile, however its flight ends: its real speed each second after launch (`MISSILE-SPEED`). Each second's median replaces the config simulation's speed there; beyond the last second learned, the simulation's curve carries on, scaled as there. That takes in whatever the simulation gets wrong: a `maxSpeed` that caps one missile and not another, gravity on a climb, speed lost turning, a mod that flies its missiles by script. | A speed under 0.2x or over 5x the config simulation's at that second is a measuring problem, and isn't used. Each second uses the median of the last 15 flights to reach it, once there are 3. |
| A missile's turn rate (missiles the game guides; ACE's give theirs in config) | The fastest sustained turn of each flight launched off the intercept (`MISSILE-TURN`). | A flight whose seeker changed target isn't used, nor a turn over 180 deg/s. Once two flights have turned, the rate is the second fastest, so no one flight sets it. |
| A gun's aim correction (lead and elevation) | Every third round, measured against the track it was aimed at (`SPOTTING`). | A round missing over 4x the median of its last 30 rounds' misses is an outlier, left out (counted in `SPOTTING`). A round saying the gun needs over 0.5 s of lead or 10 mrad of elevation isn't believed. Rounds fired only by the last-ditch rule, off the gate, are never measured. |
| A gun's scatter, and how far targets stray from their predicted track (its open-fire range) | The same rounds. | The same outlier check. A target's straying is only believed up to what it could accelerate away in the round's flight. |
| A gun's real rate of fire | Each burst (`BURST-END`). | A burst measured over 1.25x its config rate was miscounted, and is left out. |
| A launcher's real time per missile | Its back-to-back shots. | A gap longer than twice its estimate (idle) or shorter than its own shot interval allows (miscounted) is left out. |
| A target's acceleration (the lead solver's) | Its velocity, sampled while a weapon aims at it. | A sample beyond 15 g for an aircraft or 100 g for a munition is a glitch (`LEAD-SAMPLE-REJECT`), and the last good one stands. |

Syncing or unsyncing a vehicle to a Site, or editing the Site's own
Attributes, takes effect live -- nothing requires re-placing modules or
restarting the mission.

**Server load.** All of the detection and engagement work runs on the
server; other machines only suppress the AI targeting of crews they
simulate themselves, and nothing is broadcast but a Site alarm's change of
state (its sound sources) and Zeus edits. On the server:
- An idle weapon (nothing assigned to it, or nothing in a standalone
  System's pool) costs a quick check ten times a second.
- Every round fired in the mission passes through one cached lookup; only
  threat munitions go further.
- Incoming munitions are tracked by one shared tracker, twice a second
  each, spread over frames. Sensor proxies are attached, so the engine
  carries them; only those of an ammo type that doesn't carry attachments
  are moved by the tracker each frame (two commands each). A Site stops looking for a
  munition once one of its vehicles has it. Each sensor vehicle reads its
  sensors once a second, for aircraft and munitions alike; seeing them is
  the game's own sensor simulation.
- A CIWS gun's rounds in flight are tracked by one handler per gun, and a
  round is only examined once it's close to the target. The gun solves its
  full aim 20 times a second and steers between solves.
- The Site coordinator caches each munition's reserve-plan scan while the
  munition keeps to its predicted path, and skips the plan while every
  munition already has a launcher. It keeps claims indexed per turret, works
  out each launcher's timing once per run, doesn't re-judge a launcher whose
  missiles are already flying, and rules out far-off contacts with a
  distance check before the full engagement check.
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
off by default, client-side/no gameplay effect) draws what AEGIS-M is doing,
straight from the variables its detection/intercept pipeline reads and
writes, laid out to be read at a glance -- one colour scheme, one label per
thing, labels stacked rather than drawn over each other:
- **Colour** is always an engagement's state: queued (blue), assigned
  (green), reacting / slewing (amber), reloading (orange), range hold (teal),
  firing (red), in flight (gold), no LOS / no solution (purple), crew failed
  / fire held / no ammo (grey).
- **Contacts**: one icon each (plane, helicopter, or a target mark for a
  munition or drone), white until something is on it, then the colour of
  the most urgent engagement on it. Label: its class, for an incoming
  munition seconds to impact, and the kinds of sensor that saw it in the
  last 3 s (`[RDR IR]`: active radar, IR, `VIS` visual, `PAS` passive
  radar, `DL` datalink); `CUE ONLY` if only passive radar hears it.
- **Engagements**: a line from weapon to target in its state's colour.
  Waiting ones (queued behind the launcher's current target, missiles in
  flight, held) are faint, so a launcher's queue doesn't drown out what
  it's actually doing. A CIWS held back by Last Resort Only is dashed orange.
- **Sight**: a faint light-blue line from each sensor vehicle to each
  contact its own sensors saw in the last 3 s (lighter violet if only its
  passive radar hears it). A Site's contacts are all its members' together;
  this shows which vehicle actually sees which.
- **Vehicles**: a shield (a radar mark for a sensor-only vehicle) and three
  lines:
  1. its name;
  2. network and sensor status, in light blue: its own sensors, the
     longest of each kind -- reach, arc, `turret` if it turns with one, and
     for a radar its emission and why (it sees nothing while silent; see
     **Radar emission**) -- and how many contacts its own sensors see now
     (`sees 2`, `hears 1` for passive radar alone); then its Site's sensor
     vehicles and every contact in the Site's picture (`RDR 16km 120deg
     turret EMITTING (holding: silent in 6s)  PAS 16km 360: sees 1  |  SITE:
     2 radars + 4 IR/visual, 7 tracks`), or `STANDALONE` with its own
     tracks. `NO SENSOR
     ON SITE` in orange if it's networked but no vehicle of its Site has a
     sensor of its own;
  3. each weapon with rounds left and what it's doing (`MSL 4: firing +3
     queued`, `GUN 680: slewing`), or `NO AMMO` in red.

  Name and weapons are in the vehicle's most urgent engagement's colour,
  grey while idle.
- **Radars**: a faint ring at each one's detection range: blue while the
  AI decides its emission, amber while AEGIS-M has it emitting, grey while
  silent, red while shut down for an anti-radiation missile.
- **Not active**: a vehicle AEGIS-M found capable but hasn't activated is
  grey with `NOT ACTIVE:` and why -- e.g. a launcher with no sensor of its
  own placed without a Site (`no sensor of its own -- sync it to a Site with
  a radar`). Only a vehicle with a sensor of its own and its own AA weapons
  works standalone. A vehicle whose only capability is an IR or visual
  sensor (most tanks and IFVs) isn't shown: it's only used synced to a
  Site.

Each hit is logged as `INTERCEPT`, with where: its distance from the vehicle
that fired and its height above the ground, and how far it passed from the
munition's body against the round's own radius.

**Other mods.** AEGIS-M keeps what it sets on its vehicles set, whoever
changes it, and logs each case once:
- a radar it has forced on or off that something else switched
  (`RADAR-OVERRIDE`; POOK's SA-8, SA-11 and Patriot launch scripts do) is
  set back;
- a gunner on an AEGIS-M weapon whose own targeting or firing (`AUTOTARGET`,
  `FIREWEAPON`) was turned back on -- another mod's AI script, or a crewman
  new to the seat -- has it turned off again (`AI-RESTORED`);
- its Fired event handler on a vehicle, and its mission-wide projectile
  catch, are added again if something removed them (`EH-RESTORED`);
- a munition nothing reported fired -- spawned by a script (Zeus
  ordnance), or from a shooter whose Fired event handlers another mod
  removed -- is tracked anyway (`MUNITION-UNREPORTED`, once per ammo type).
  With no shooter it has no side, so it's engaged like friendly fire: only
  if it threatens a Site;
- a weapon fired without an AEGIS-M command is logged (`UNCOMMANDED-FIRE`):
  a gun once per vehicle, a missile every time, with what its gunner was
  on and which of its own targeting was switched on. The handler that sees
  it is on every armed vehicle from the start, not from its first AEGIS-M
  shot.

A launcher's weapon can take longer to ready its next missile than its
config says: POOK's 9K332 (`reloadTime` 6.5) fired every 9.7-10 s, its S-400
launcher (25) took 37 and 42 s. AEGIS-M reads how far along each reload is
from the game (`weaponState`), times how fast that falls, and plans the
launcher's queue on the measured time (`RELOAD-TIME`, logged when first
measured). Planned on the config's time, such a launcher was booked for
shots it never got to, and its targets were released one after another as
their turn failed to come.

**POOK's SAM pack** gets its own compatibility addon (`aegism_compat_pook`,
loaded only with POOK's pack). Its 20, 23 and 30 mm AA rounds burst 1 s after
firing, about 700-900 m out, whatever they're aimed at; they now burst at
the end of their own life instead (30 mm about 2 km, 20 mm 1.9 km, 23 mm
2.5 km, the drag-free 23 mm HET capped at 6 km -- POOK's drag keeps the
rest well short of that). POOK's scripts that aim and fire a vehicle's
weapons themselves are switched off (`COMPAT`, once per function) -- a
SHORAD firing at any missile fired at a POOK vehicle nearby, and the
57-100 mm guns' airburst fuse, which bursts rounds at the height of a target
AEGIS-M never assigns (250 m without one). That's for every POOK vehicle
while both mods are loaded, AEGIS-M's or not: AEGIS-M never runs or calls
POOK's scripts, it only stops those. POOK's missile launch scripts are left
alone (three of them are the vertical launch itself). Build AEGIS-M Sites
from POOK's vehicles placed one by one, not POOK's site spawners: their
radar scripts fire the site's launchers themselves.

An assigned weapon that can't fire logs why: `NO-SOLUTION`, `LOS-BLOCKED` (the line from the weapon's own muzzle to the target, naming what's in the way: terrain, or the object, its class and how far its top is above the muzzle), `FIRE-SKIP`, `RELOADING`, or
`ASSIGN-CLEAR` with a reason. A launcher never fires while its weapon is
still loading its next magazine: the game already shows the new magazine's
count, and a fire command then fires nothing. Mod launchers can take minutes
(POOK's S-125: 900 s), and the Site gives their targets to other weapons
meanwhile. A fire command that still fires nothing is logged `FIRE-FAILED`
and isn't counted as a shot, so the target isn't taken for missed. A threat munition 10 s from impact with no
weapon on it at all is logged once (`UNENGAGED`), with each weapon's reason:
held in reserve, out of its reach, busy or too late. Every AEGIS-M RPT line carries the mission's
game time (`[AEGIS-M] t=123.4 ...`): the RPT's own timestamp is wall-clock
time, which keeps running while the game is paused.

**RPT Detail** (CBA setting "AEGIS-M > Debug > RPT Detail", server): at
Normal, the default, the RPT gets what AEGIS-M decides and why. That covers
detections, assignments, shots, intercepts, munitions it ignored or never
saw, alarms, radar emission, anything stopping a weapon, and its setup.
Verbose adds the step-by-step detail:
- each weapon's wait: `REACTING`, `SLEWING`, `CUED`, `RANGE-HOLD`, `LOCKING`;
- CIWS bursts: `SPOTTING`, `BURST-END`, `SELF-DESTRUCT`, `LAST-DITCH`;
- missile launches: `MISSILE-TURN`, `MISSILE-SPEED`, `OFFBORE-LAUNCH`,
  `LOCK-ON`, `LOCK`;
- per-weapon calibration: `KINEMATICS`, `MISSILE-PROFILE`, `AGILITY`, `TURRET-RATE`,
  `TARGET-SIZE`, `OPEN-FIRE-RANGE`, `FIRE-RATE`, `RELOAD-TIME`, and measurements thrown
  away as glitches (`LEAD-SAMPLE-REJECT`; see **Learning in play**);
- layered reserve: `RESERVE`, `SATURATION`;
- every enemy shot fired (`MUNITION`);
- rejected detections (`DETECT-REJECT`) and per-weapon `DISCOVERY` lines;
- each turning radar's task and search dwells (`RADAR-TASK`);
- each sensor vehicle's first sight of each munition (`SIGHTED`): how long
  after it was fired, how long its radar had been on, and where its beam
  pointed.

**Munition probe** (debug console, on the server): `[] call
aegism_intercept_fnc_debugProbeMunitions;` measures each new ammo type in
flight against every LOD `lineIntersectsSurfaces` knows (`PROBE`): whether
any can hit that projectile, and if so its real length, width and height.
`[false] call ...` stops it.

**Site status hint** (CBA setting "AEGIS-M > Debug > Site Status Hint", off
by default) shows a live board in the hint box: the nearest Site's vehicles
with their roles (`R` radar, `I` IR, `V` visual sensor, `L` launcher, `C`
CIWS), colour-coded status (READY, TRACKING, REACTING, SLEWING, ENGAGING,
FIRING, NO SOLUTION, LOS BLOCKED, NO AMMO, DESTROYED), target and ammo,
with each weapon's worked engagements in their state colours (and how many
more are queued); then other Sites and standalone Systems in summary; then
**Not active** vehicles with why (e.g. a launcher with no sensor placed
without a Site). Under each radar vehicle, its emission and why (`RDR
EMITTING cued: ...`, `RDR SILENT silent until cued`, `RDR SHUT DOWN
anti-radiation missile inbound ...`). Last, the nearest Site's contacts,
the sensors that saw each (`cue only` for one only passive radar hears),
and which weapons are on each (coloured the same way) -- the longest
section, so it's the one a full hint box cuts off. It shows data wherever AEGIS-M runs its engagement
logic: singleplayer, Eden Preview, or a hosted game's host.

**Site status terminal.** Sync a laptop (any object with "laptop" in its
class name -- `Land_Laptop_unfolded_F`, `Land_Laptop_device_F`...) to a
Site, and players get an **AEGIS-M: Site Status** action on it (within
3 m): a scrollable screen with that Site's live board -- the same as the
hint's, for that Site alone, with every contact it tracks -- refreshed once
a second until closed (Esc). The server builds the board and sends it to
the player using the terminal, so it works on a dedicated server too. A
laptop is never an alarm speaker.

For a Site linked with others, the board (terminal and hint alike) shows
the whole group: which Site coordinates it and whether its settings apply
to every vehicle, every link holding it together, one per line (a vehicle
synced to both, a vehicle-to-vehicle pair with each one's Site, or the
modules synced to each other), and each Site's vehicles under its own
heading -- the coordinator first, the terminal's own Site marked, each
vehicle forming a link tagged `LINK` and listed once -- then the group's
shared contacts. Other Sites in the hint's summary say what they're linked
with. In the 3D draw a linked Site's vehicles read "LINKED, n Sites by n
links", a vehicle forming a link is tagged `LINK`, and a vehicle-to-vehicle
or module-to-module link is a dashed cyan line.

Short codes, everywhere in the debug: `RDR` radar, `IR`, `VIS` visual,
`PAS` passive radar, `DL` datalink (a contact the game's datalink shared,
with Use Datalink Contacts on, or a vehicle with no sensor of its own, fed
by its Site); `L` launcher, `C` CIWS.

**RPT performance summary** (CBA setting "AEGIS-M > Debug > RPT Performance
Summary", on by default) -- every 10 s, while AEGIS-M is doing anything, the
server writes one `PERF` line: coordinator runs and time (total and worst),
engagement ticks with work, aim solves and per-frame steers, CIWS rounds
tracked / checked near the target / skipped in flight / time, engageability
checks, standalone target re-evaluations, Fired events seen / threats among
them / munitions ignored as landing clear, munition tracker checks / time
(proxies created and moved included), sensor reads: munitions seen / time, reserve-plan cache hits,
rebuilds and the intercept solves it ran, and the server's frames over the whole interval: average fps,
worst frame and frames slower than 50 ms (paused time isn't counted).
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

The Site module's attributes are in six sections. Every default is chosen
so a Site works out of the box: each weapon uses its own real config
envelope, and all threat classes are engaged.

**Site Settings**

| Setting | Default | What it does |
|---|---|---|
| Target Priority | Soonest Impact | Which contacts get weapons first when threats outnumber free weapons: Soonest Impact (whatever reaches the Site first -- an incoming salvo is worked front to back), Nearest (to any Site vehicle), Fastest Closing, or Highest Value (missile > bomb > aircraft > drone/rocket > artillery). |
| Crew Skill | Regular | Reaction time and reliability: Green 4.0 s / 55 %, Regular 2.5 s / 70 %, Veteran 1.2 s / 85 %, Elite 0.5 s / 95 %. Reliability is rolled once per missile or CIWS burst; CIWS reaction is capped at 1 s. |
| Crew Temperament | Standard | Scales reaction, reliability and the pause between shots (Cautious / Standard / Aggressive / Nervous). |
| Reaction Once in Combat (%) | 50 | Once the Site is in combat (it fired within Warning Lasts After Last Shot, 10 s by default), crews are at their stations, weapons free, and take this percentage of their reaction on each new target -- about one skill tier quicker (Regular 2.5 s becomes 1.25 s; a CIWS's 1 s cap becomes 0.5 s). The first target of an engagement always gets the full reaction. 100 = no change. |
| Crew Skill on Automated Systems | Off | Off: automated systems (crewed by UAV AI -- Phalanx, RAM, MIM-145, radars) ignore Crew Skill and Temperament -- no reaction delay, no skipped fire cycles, no interval scaling. On: they get the same crew model as manned systems. |
| Save Ammo for Bigger Threats | Off | Hold fire if firing would leave fewer rounds than tracked higher-value contacts. |
| Shared Site Coordinator | Off | For linked Sites (see **Linked Sites**): this Site coordinates the group, and its settings apply to every vehicle of it while linked. Ticking it unticks it on every Site synced or linked to this one, in Eden and Zeus. |
| Threat Rings on Map | Off | When the Site starts, draws the reach of each of its weapons and sensors on the map, in its side's channel, as markers a player could have placed (players can delete them): launchers red (the range they engage to), CIWS orange (the gun's reach), sensors blue (their reach against an aircraft; one fixed to the hull as its sector). Rings of one kind with similar reaches (within a tenth of each other) on vehicles close together (within a tenth of the reach) are drawn as one, whatever the weapon or vehicle, sized to cover every ring it replaces, and its label lists every system on it ("4x MIM-145 Defender: MIM-145 16.0 km \| Mk49 Spartan: RIM-116 15.5 km"). Labels sit on the ring's edge at north-east -- or, where another label is already there (a radar's and a launcher's ring the same size), on the next clear diagonal; a sector's in the middle of its arc. Linked Sites are drawn together as one set, so the same systems on different Sites merge too; with a Shared Site Coordinator, its setting decides for the whole group. Drawn once, when the Site starts: they don't move with the vehicles. In Zeus, ticking it draws them and unticking deletes them. Logged as `THREAT-RINGS`. |

**Interception Targets**

| Setting | Default | What it does |
|---|---|---|
| Engage Missiles / Rockets / Bombs / Artillery, Mortar and MLRS Rounds / Fixed-Wing / Helicopters / Drones | all on | Which threat classes the Site engages. |
| Target Min / Max Height (m above ground) | 0 / 0 | Ignore contacts outside this height band. Max 0 = no limit. |
| Engage Friendly Munitions Threatening the Site | On | Also engage a friendly/neutral round predicted to hit the Site. |
| Only Engage Munitions Threatening the Site | On | A hostile munition is only engaged while it's a threat to a Site vehicle: a shell/rocket predicted to land within the Threat Radius of one, a missile guided or flying at one, or with one inside its seeker's view when its target can't be read, a bomb falling or flying at one (`IGNORED` in the RPT otherwise; see **IFF and threats**). Off: every hostile munition in reach is engaged. |
| Threat Radius (m) | 0 | How close to a Site vehicle a predicted impact counts as a threat, for both settings above. 0 = the round's own config danger radius (`dangerRadiusHit`). |
| Protected Area Radius (m) | 750 | The Site also defends a circle this size round its module: a hostile munition guided at anything inside it, flying down into it, or predicted to land in it is a threat (and sounds the Incoming Alarm). 0 = only the Site's vehicles. Not scaled by Range Scale. Drawn as a green ring with the threat rings (Threat Rings on Map), and a line on the status board. |

**Launchers (Missiles)**

| Setting | Default | What it does |
|---|---|---|
| Min Range (m) | 0 | Extra minimum on top of the missile's own (MIM-145: 1000 m), for where the missile meets the target. |
| Max Range (m) | 0 | 0 = the missile's own reach (MIM-145: 16000 m). Judged where the missile meets the target, so it fires at an incoming round still beyond this. |
| Missiles per Target | 1 | Missiles fired before waiting for the result; re-engages if all miss. |
| Seconds Between Missiles | 0 | Minimum gap between missiles from one launcher. 0 = Auto: each launcher's own fire rate, the `reloadTime` of its weapon's fire mode, which scales with the missile (MIM-145 Defender 4 s, Mk49 Spartan 2 s, Mk21 Centurion 1 s). The RPT logs each launcher's rate as `FIRE-RATE`. The game may ready the next missile more slowly than that; AEGIS-M measures it and plans on the longer of the two (`RELOAD-TIME`). |
| Max Off-Bore Launch While Swinging (deg) | 20 | The most a launcher that can move may fire away from the intercept before its turret is round, leaving the missile to turn. A fixed mount -- a vertical launch cell -- is exempt: it can only fire off-bore. See **Launching off-bore**. |
| Max Off-Bore Launch At Turret Limit (deg) | 30 | The same, once its turret is as close as it can get: at its elevation or traverse limit, or a mount that can't move on one axis. |

**CIWS (Guns)**

| Setting | Default | What it does |
|---|---|---|
| Max Range (m) | 0 | 0 = the gun's own reach (Cheetah 35 mm: 2500 m). |
| Min Elevation (deg) | 5 | Never engages below it; holds fire while the barrel is below it. |
| Open Fire at Hit Chance (%) | 40 | Tracks from its full reach, but only fires where one burst is at least this likely to hit -- from the gun's measured scatter (its rounds' misses about where it now aims: an aiming error its spotting has since corrected doesn't count), the target's straying, the round's flight time, the hit radius and the rounds per burst; never past the round's lifetime reach or inside its arming distance. Lower = earlier, farther, more rounds per hit. 0 = its full reach. |
| Cue Before In Range (s) | 5 | A gun is assigned a target this long before it comes into reach (judged on where the target will be by then), so its crew's reaction and its barrel's swing are done by the time it can fire; it holds meanwhile (`CUED` in the RPT). 0 = assigned only once in reach. |
| Minimum Firing Window (s) | 3 | A gun is only given an incoming munition it will have this long to fire at before impact (after its crew's reaction, its barrel's swing and the rounds' flight, with the barrel still able to follow it). One with less is a last-ditch shot, taken only with nothing better and dropped for a munition it has its full window on. 0 = any munition it can reach in time. |
| Burst Length Min / Max (s) | 3 / 5 | Each burst lasts a random length in this range, at the gun's own rate of fire. |
| Pause Between Bursts (s) | 1 | Gap after a burst before firing again at the same target. After a kill the gun goes straight on to its next target. |
| Last Resort Only | Off | Hold while a launcher covers the contact, until it fails or the contact closes inside 40 % of the gun's reach. |
| Self-Destruct Rounds | Off | A round that hits nothing detonates once it has passed the gun's reach (CIWS Max Range, or the gun's own config reach), like a C-RAM round's self-destruct fuze, instead of flying on until its lifetime runs out and disappearing in mid-air -- or just before that lifetime, if it comes first. The fuze time is the round's flight to the gun's reach under its own drag, from its real muzzle speed; each ammo's lifetime (`timeToLive`) and drag are read once per ammo type -- they differ between weapon systems and mods (the vanilla 35 mm lives 6 s, 30 s with ACE). Each gun's fuze time is logged (`SELF-DESTRUCT-FUZE`), and the rounds that went off after each burst (`SELF-DESTRUCT`). |

**Radar Emission** (see **Radar emission** above)

| Setting | Default | What it does |
|---|---|---|
| Radar Emission | Automatic | When the Site's active radars emit: Automatic, AI decides, Always on, Silent until cued, or Intermittent. |
| Stay Lit After Last Contact (s) | 10 | Silent until cued and Intermittent: how long a radar stays lit after the last contact leaves its coverage (Automatic: at least 60 s). |
| Search Burst: Seconds On / Off | 5 / 15 | Intermittent, and Automatic while quiet. Turning radars: how long each arc of the relay scan is lit, and the silent pause after each lap (four arcs of 5 s and a 15 s pause revisit every bearing every 35 s). Other radars: each burst's length, and the silence between bursts. |
| Shut Down for Anti-Radiation Missiles | On | In every mode, a radar shuts down while the Site sees an anti-radiation missile homing on it, or with it emitting in the missile's seeker view. |
| Turning Radars Hold Their Sector | Off | Off: the turning radars rotate round together, evenly spaced, so each looks all the way round (radars far apart see past different hills). On: one whose arc covers its sector holds it still, all round seen at once with no movement. |

**Alarms**

| Setting | Default | What it does |
|---|---|---|
| Going-Live Warning | Base alarm | Sounds from the moment the Site commits a weapon to a target (before its first shot) until the time below after its last shot. |
| Incoming Alarm | Auto | Sounds while a munition threatening a Site vehicle is inbound (seen by a Site radar in the last 3 s -- the pool's own contact expiry), and replaces the warning meanwhile. Auto: BLUFOR the NATO helicopter warning, OPFOR the CSAT one, anyone else the Klaxon. |
| All Clear Sound | Off | Played once from every speaker when the Site goes quiet (both alarms over), heard by players within the Alarm Range at that moment. Any of the tones below. |
| Alarm Range | 400 m | How far the alarms are heard from each speaker: 200 m, 400 m (vanilla's own alarm), 800 m, 1.5 km, 3 km or 5 km. A custom sound keeps its own range. |
| Warning Lasts After Last Shot (s) | 10 | How long the warning keeps going after the last missile or gun round. |
| Custom Warning / Incoming / All Clear Sound | blank | Any sound source class (CfgVehicles, like vanilla's `Sound_Alarm`) -- e.g. from a sound mod with a real national siren or a spoken "incoming" -- replacing that state's tone. A custom All Clear plays even with the tone set to Off. |

The tones are the distinct alarm recordings in the base game: Base alarm
(6.6 s cycle), Klaxon (1.6 s), Klaxon 2 (2.1 s), Siren (1.4 s),
Restricted-zone warning (4.6 s), Helicopter warning NATO (2.0 s) and CSAT
(1.5 s), Missile-lock tone (0.2 s beep), or Off. (Vanilla's BLUFOR, OPFOR
and Independent alarms are the same recording, so they're one tone here.)
Each plays like vanilla's own alarm sound source: volume 1, heard to the
Alarm Range (400 m by default, as vanilla's is), one cycle after another.
The speakers are the non-vehicle objects synced to
the Site -- a loudspeaker prop, a lamp post, a Game Logic, but not a
laptop (that's a status terminal) -- or the Site module itself when none
is. The server only decides the alarm; each player's machine plays it for
itself, wherever its camera is -- the player, Zeus or a spectator -- and
starts it the moment the camera comes within the Alarm Range of a speaker
(a looping engine sound source, as before, went unheard after the camera
had been away). Players joining mid-alarm hear it too. Only a change of
alarm state crosses the network. Logged as `ALARM`; a custom sound class
with no file this machine can play is logged once as `ALARM-SOUND`.

Range settings are real-world metres, scaled by the CBA setting AEGIS-M
Range Scale. Launcher ranges never apply to guns, and vice versa.

**Per-vehicle overrides.** Every vehicle has an **AEGIS-M: Vehicle
Overrides** category in its own Eden attributes, with the same sections
(not Alarms). Tick **Override Site Settings**, then change only what should
differ for that vehicle; everything left on "Site setting" (or blank) keeps
following the Site. Nothing below it applies while it's unticked: in Zeus,
settings entered with it off are saved but ignored, and AEGIS-M says so on
screen and in the RPT (`OVERRIDES: ... OFF ... entered but NOT applied`).
Ranges are in metres (3500, not 3.5). Examples: set a long-range SAM's "Artillery, Mortar and
MLRS Rounds" to Ignore so it never spends missiles on shells, or give one
CIWS a shorter Max Range as an inner layer, or keep one long-range search
radar Always on while the rest stay Silent until cued, or set **Guns Used as
CIWS** to Every Rapid-Fire Gun on a vehicle whose machine gun should still
work as one. Overrides on a radar
affect its Interception Targets (what it reports, and which munitions it
treats as threats) and its Radar Emission. A vehicle's active overrides are logged at start
(`OVERRIDES:` in the RPT). Script equivalent:
`_veh setVariable ["AEGISM_ovr_enabled", true]` plus
`_veh setVariable ["AEGISM_ovr_<setting>", value]`
(see `aegism_system_fnc_applyOverrides`).

## Zeus

With Zeus Enhanced loaded, every Site setting and every vehicle override
can be edited live from Zeus, in a dialog built from the same attributes as
Eden (same names, tooltips and choices, current values filled in):

- **A Site:** double-click it, or place one (its dialog opens straight
  away).
- **An air-defence vehicle** (a radar, SAM launcher or CIWS AEGIS-M has
  recognised): the **AEGIS-M** button in its Zeus attributes window.
- **Either:** right-click it for **AEGIS-M Settings**, or place the module
  **AEGIS-M > Edit Air Defence** on it (or within 50 m of a Site).

An edit reaches every machine, including players who join later, and the
Site's vehicles pick it up at once (`SITE-SETTINGS` / `OVERRIDES` in the
RPT) rather than at their next 5-second refresh.

## License

APL-ND (Arma Public License No Derivatives). See `LICENSE`.

## Coding convention

Every function begins with a standardized header docblock (see any file
under `addons/*/functions/`). Author is always Snow(Dryden).
