# AEGIS-M: how it works, in full

This is the long form of the README's "How it works": every mechanism, the
reasoning behind it and what was seen in testing. The README is the short
version, and it holds what isn't repeated here: the quick start, the
settings tables, Zeus editing, releasing. Like the rest of `docs/`, this
file is for development and isn't packed into the mod.

Taken from the README as it stood on 2026-10-07, when the README was
condensed. Add to it here, not there.

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
**Settings** in the README); a vehicle never synced to a Site uses the defaults.

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
rounds left** once the munitions already queued on it are served, so like
launchers share a salvo; then the soonest ready and closest warhead size. A launcher
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
wasn't allowed to engage. A missile the game itself guides is also asked for
its lock every frame: reported lost, it is ended as soon as it has passed
its target. Between targets, and before its first, a launcher
or gun stays pointed at the contact it's most likely to get next -- one no
weapon of its kind has yet, soonest impact first -- rather than going back
to its crew, which turned it away between the rockets of a salvo and left
it 40-70 degrees off the first one; it's handed back once there's nothing
left to engage.

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
and far out, for the part of a barrage they can't: the rounds the cheaper
tier has no missile or no time left for. If the cheaper tier was due to fire
at a round 3 s ago (by the plan's latest estimate) and none of its launchers
has it, or its shot missed, the reserve stops holding back for that round
(`RESERVE-MISSED`): a long-range rocket coming down too steep for the RAMs
once held every Patriot back until it was too late. One more case opens the
reserve early (`RESERVE-RELEASED`): a round that even a free launcher of the
cheaper tier could only kill too late for a long-range launcher to have a
second shot (3 s to see the miss, then a shot that meets the round before it
comes down). A high-arc rocket falls back into a RAM's reach only in its
last seconds; planned to the RAMs there, it left the Patriots no second
chance. A kill that's only that late because the cheaper tier is working
through its queue stays with the cheaper tier, so its launchers empty their
magazines before the long-range ones are spent. A launcher isn't counted in
the plan while a gun on its own turret holds another target (a Cheetah's
missiles while its gun is firing): it can't be given a round meanwhile.

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
its crew's reaction, not a whole pause between bursts. By default a CIWS
engages in parallel with a launcher already working the same contact (a
fast, close threat shouldn't wait on an unproven missile shot). Its
**Engagement Mode** can instead give it munitions of its own that the
launchers then leave alone, or hold it as a last resort (see **Settings**).
A launcher shot is
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

**ACE's missile guidance is required** (`ace_missileguidance`, with
`ace_missile_sam` and `ace_missile_manpad`, which put the game's own SAMs
under it). AEGIS-M was built and proven with it: a salvo of 46 rockets on a
Site of two RIM-116 launchers, a Cheetah and four MIM-145s was stopped 46 of
46 with one MIM-145 fired, and surface strikes land within a few metres
(RIM-116 1-4 m, MIM-145 0-1 m). Two runs of the same Site without it, on
2026-10-07, showed what the game's own guidance does instead:
- The RIM-116 reaches 4 km, not 5, so its first kills come with about 4 s
  less in hand, and the Cheetah's missile is a 4.5 km Titan in a tier of its
  own instead of a 5 km Stinger beside the RIM-116s.
- The MIM-145 hit every rocket it met 4.3 km out or more (13) and missed
  every one it met nearer (3 at about 3.6-3.9 km, 1 at about 2.6 km, by the
  missiles' logged speeds). The logs don't show why: the game reports it
  locked half a second after launch. So there is no second shot behind a
  4 km RIM-116. The first run let one rocket of 43 through; in the second
  the reserve fired all 16 MIM-145s to stop 47 of 47, three of them in
  their last 3.3 s.
- A RIM-116 the game guides onto a strike point comes down 22-24 m off.

ACE guides AI-fired missiles by default; a mission that switches that off
(`ace_missileguidance_enabled` under 2) gets one line in the RPT
(`ACE-GUIDANCE`). Another mod's missile that ACE doesn't guide (POOK's) is
still flown by the game.

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
| A launcher's real time per missile | Its back-to-back shots. | A gap longer than twice its estimate (idle) or shorter than its own shot interval allows (miscounted) is left out. So is one where the launcher was ready and waiting for its target to come into reach: only a shot fired within 0.5 s of its own reload or interval holding it counts. |
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
  each, spread over frames. Each sensor vehicle reads its sensors once a
  second, and four times a second while any munition is in flight: aircraft
  from the game's own sensor simulation, munitions by AEGIS-M's own check
  (see **Detection follows each vehicle's own sensors** above). A line of
  sight is only traced for a munition that
  passes everything else, and a clear one isn't traced again for 2 s.
- A CIWS gun's rounds in flight are tracked by one handler per gun, and a
  round is only examined once it's close to the target. The gun solves its
  full aim 20 times a second and steers between solves.
- The Site coordinator caches each munition's reserve-plan scan while the
  munition keeps to its predicted path, and skips the plan while every
  munition already has a launcher. It keeps claims indexed per turret, works
  out each launcher's timing once per run, doesn't re-judge a launcher whose
  missiles are already flying, and rules out far-off contacts with a
  distance check before the full engagement check.
- It doesn't work out again what hasn't changed. Of each munition's path it
  remembers the stretch with no launcher shot in it and goes straight past
  it; a launcher's claim waiting its turn in a queue is judged by its
  planned shot alone; and a gun's reach is checked with one distance before
  the gun's own full check.
- A munition more than 20 s from impact isn't looked at for launchers on
  every run. Its next look is 1.5 s before the crew of the launcher the
  reserve plan has firing at it would have to start on it, or 2 s on,
  whichever is sooner, and at once if it loses its launcher. Meanwhile it
  keeps the place the reserve plan last gave it, so the plan still sees a
  saturated tier and the long-range launchers still step in early. Guns are
  looked at for it as ever. Only a munition within 20 s of impact makes the
  coordinator run at once when it's first seen; one further out waits for
  the Site's next half-second turn.
- It spreads a salvo's work over runs and frames. Once a run has worked out
  5 new steps of launcher shots, the far munitions still due a look are
  put off to a later run: each keeps its place in the plan meanwhile, and
  its shots are worked out in the frames before the next run, 5 ms a frame,
  so that run finds them ready. A munition is looked at whole or not at
  all, so no decision ever waits on work half done. A look is never put off
  more than 2 s, nor past the time the launcher planned for the munition
  would have to start on it, nor at all for a munition with no launcher and
  none planned for it. A munition new to the Site gets its first look within
  2 s.
- Config values are read once per class and cached.
- Everything runs on the mission clock (`CBA_missionTime`), which follows
  time acceleration in singleplayer: each weapon's 0.1 s engagement tick and
  the sensor reads are run every frame and due by that clock, and whatever
  moves by the frame (a round's or a missile's stretch of path, a gun's
  firing time) is measured on it. Fast-forwarded 4x, a weapon still looks
  every 0.1 s of game time -- or every frame, where a frame is longer than
  that.

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
  it's actually doing. A CIWS held back by its Engagement Mode (Last Resort,
  Planned) is dashed orange.
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
saw, alarms, radar emission, anything stopping a weapon, what is changed
or ordered at a terminal (`TERMINAL`, `MANUAL`, `STRIKE`), and its setup.
Verbose adds the step-by-step detail:
- each weapon's wait: `REACTING`, `SLEWING`, `CUED`, `RANGE-HOLD`, `LOCKING`;
- CIWS bursts: `SPOTTING`, `BURST-END`, `SELF-DESTRUCT`, `LAST-DITCH`;
- missile launches: `MISSILE-TURN`, `MISSILE-SPEED`, `OFFBORE-LAUNCH`,
  `LOCK-ON`, `LOCK`, `MISSILE-TARGET`;
- per-weapon calibration: `KINEMATICS`, `MISSILE-PROFILE`, `AGILITY`, `TURRET-RATE`,
  `TARGET-SIZE`, `OPEN-FIRE-RANGE`, `FIRE-RATE`, `RELOAD-TIME`, and measurements thrown
  away as glitches (`LEAD-SAMPLE-REJECT`; see **Learning in play**);
- layered reserve: `RESERVE`, `SATURATION`; a planned gun's munitions:
  `GUN-PLAN`;
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

**Site terminal.** Sync a laptop (any object with "laptop" in its class
name -- `Land_Laptop_unfolded_F`, `Land_Laptop_device_F`...) to a Site or to
a single air-defence vehicle, and players get an **AEGIS-M: Site Terminal**
action on it (within 3 m). A laptop is never an alarm speaker.

What a terminal reaches follows what it is synced to:

| Synced to | Reaches |
|---|---|
| a vehicle | that vehicle |
| a Site | that Site and each of its vehicles |
| the Shared Site Coordinator of linked Sites | every linked Site and each of their vehicles |

What players can do at it is the laptop's own **Terminal Access** (Eden:
its attributes, under *AEGIS-M: Terminal*; Zeus, with Zeus Enhanced: its
*AEGIS-M Settings*):

- **Status Only** (default): the screen lists what the terminal reaches on
  the left, and shows the live status board of the one picked -- the same
  as the hint's, for that Site alone, with every contact it tracks --
  refreshed once a second until closed (Esc).
- **Full Control**: a **Settings** tab as well. On a Site it holds the
  Site's settings, on a vehicle that vehicle's overrides, under the same
  headings and with the same choices and tooltips as in Eden, showing the
  current values. **Apply** sends them to the server; **Revert** puts the
  form back to the current values.

Separate from that, the laptop's **Manual Interception** attribute (same
places, off by default) gives it an **Interception** tab. A terminal can have
either, both or neither.

- **The map** shows the weapons' vehicles and the radars (amber while
  emitting, grey while silent), every track, the Site's own missiles in
  flight (white; magenta if fired on an order), a line from each weapon to
  what it is on (in its engagement's colour; an order's is magenta), and
  the reach of the weapon picked. Tracks are coloured by what
  they are to the Site: red, one it engages; yellow, a hostile of a class it
  doesn't engage; blue, a friendly aircraft its sensors see; grey, anything
  else; magenta, one it holds for an order alone. Click a track to pick it.
- **Tracks** lists the same, soonest impact first. **Weapons** lists every
  launcher and gun of the Site or vehicle picked on the left, with its
  munition and rounds, and, once a track is picked, whether it has a shot at
  it or why not. With the Shared Site Coordinator of linked Sites picked, it
  lists the weapons of every one of them. Launchers of one type standing
  together (within 150 m of another of them, same weapon) are a single row
  -- a battery of four Patriots is one row with its missiles added up and
  "3 OF 4 HAVE A SHOT" -- and an order to that row goes to whichever of them
  is best placed: one with a shot that isn't already on that track, then the
  least busy, then the fullest. So another missile at the same track comes
  from the next launcher instead of waiting on the first one's reload.
- **Radars** lists each radar of the Site or vehicle picked with what it is
  doing (hover a row for why), and three buttons for the one picked, or for
  all of them with the first row picked: **Emit** (on until taken back),
  **Silent** (off until taken back) and **Radar: Auto** (back to its own
  Radar Emission setting). An order stands over every emission mode. A
  radar ordered on still shuts down for an anti-radiation missile inbound on
  it, if Shut Down for Anti-Radiation Missiles is on.
- **Engage** orders the weapon picked onto the track picked: one missile, or
  a gun's fire until the track is down. Press it again for another missile.
  It works on any track listed, whatever the Site would do on its own -- a
  threat a launcher already has, an aircraft of a class the Site doesn't
  engage, a friendly. The server refuses an order the weapon has no shot
  for, and says why.
- **Cease Fire** ends the orders on the track picked, or every order with
  none picked. A missile already in flight flies on.
- **Automation** switches the Site's own decisions off or on, for what is
  picked on the left and everything under it: the Shared Site Coordinator's
  switch is every linked Site's, a Site's is all of its vehicles', a
  vehicle's is that vehicle's alone. Off, those weapons fire on orders only:
  what they hadn't fired at yet is let go, and nothing new is given them.
  Sensors, radars and alarms carry on as before. A linked Site that isn't
  the coordinator and is switched off leaves the rest of the group running.

An order goes to the front of its launcher's queue and stays with that
launcher: it isn't handed to another, a lost crew fire cycle is tried
again, and it ends when its missiles have missed, its target is down or
lost to the Site's sensors, the weapon has had no shot for 15 s, or it is
ceased. What became of the last orders is listed under the weapons, on
every terminal of the Site, and in the RPT (`MANUAL`). Orders work through
the Site's coordinator, so a vehicle on its own, in no Site, takes none.

**Surface Strike** is a third laptop attribute (same places, off by
default; it needs Manual Interception). It adds a **Surface** switch to the
Interception page. Switched on, a click on the map where no track is puts a
**strike point** on the ground there; pick a weapon and **Engage**:

- **A launcher** fires one guided missile. It is first sent for a point
  above the strike point -- 0.35 m up for every metre of ground beyond the
  last 400 m, 3 km at most -- and that point comes down as the missile
  closes, so it climbs over what is between and comes down on the strike
  point from above. Not nearer than 300 m, nor beyond the launcher's reach.
  Small missiles aren't offered: one whose warhead's blast radius is under
  8 m (a Stinger or Titan AA has 6; the RIM-116 has 10, the Patriot 30).
- **A gun** fires one burst (its shortest Burst Length) along its own
  ballistic path. It needs a turret that can point there and a line to the
  point clear of the ground; trees and buildings don't count.
- The weapon's turret is the strike's until its missile is away or its
  burst is over; what the Site had it doing waits. **Cease Fire** with the
  strike point (or nothing) picked calls off a strike that hasn't fired yet
  and stops a burst.

Nothing of this is automatic: the Site never fires at the ground on its
own, a strike doesn't sound its alarm, and its rounds and missile are left
to the game -- no AEGIS-M fuse, no self-destruct. `STRIKE` in the RPT says
how each one ended and how near its missile came. A missile is given an
object to chase there: one guided by a mod (ACE) from launch -- for a radar
seeker, which only keeps munitions and aircraft, a chemlight held above the
point and kept moving along the missile's line of sight (an infrared one
where there is one) -- and one the game guides (another mod's) as its forced
target: the game only takes a position for a missile with `manualControl`,
which no SAM has.

The server builds the board and the picture, applies the changes and takes
the orders, so all of it works on a dedicated server. It takes a change only
from a Full Control terminal and an order only from one with Manual
Interception, for something within that terminal's reach, from a player
within 10 m of it (`TERMINAL` and `MANUAL` in the RPT, taken or refused),
and applies a change exactly as a Zeus edit of the same Site or vehicle. A vehicle with no Site shows the
whole board, since there is no board for one vehicle.

**Which Sites are linked.** A Site has the same name everywhere in the
debug -- the RPT, the board, the 3D draw, the terminals: its Eden variable
name, or `Site 1`, `Site 2`... in the order the Sites were set up.

For a Site linked with others, the board (terminal and hint alike) shows
the whole group: which Site coordinates it and whether its settings apply
to every vehicle; every link holding it together, one per line, as the two
Sites it joins and what forms it (`Site 1 <-> Site 3 by Bardelas, a vehicle
of both`; `... by Spartan synced to Patriot`; `... by their modules, synced
to each other`); and each Site's vehicles under its own heading, which
says whether it is the coordinator, whose settings its vehicles use and
which Sites it is linked to directly. A vehicle forming a link is tagged
`LINK` and listed once. Then come the group's shared contacts. Other Sites
in the hint's summary say what they're linked with.

In the 3D draw every Site module is labelled in a colour of its own with
its name, `COORDINATOR` if it leads a linked group, how many vehicles it
has, the Sites it is linked with and whose settings its vehicles use, and
has a faint line of that colour to each of its vehicles. Each link is a
dashed white line between the two Site modules, captioned with the two
Sites and what forms it; a link made by two vehicles synced to each other
is also drawn between those two. A linked Site's vehicles read "LINKED, n
Sites by n links", and a vehicle forming a link is tagged `LINK`. The RPT's
`LINK` line lists the same links the same way.

Short codes, everywhere in the debug: `RDR` radar, `IR`, `VIS` visual,
`PAS` passive radar, `DL` datalink (a contact the game's datalink shared,
with Use Datalink Contacts on, or a vehicle with no sensor of its own, fed
by its Site); `L` launcher, `C` CIWS.

**RPT performance summary** (CBA setting "AEGIS-M > Debug > RPT Performance
Summary", on by default) -- every 10 s, while AEGIS-M is doing anything, the
server writes one `PERF` line: coordinator runs and time (total and worst;
the total split into reviewing its claims, the reserve plan and assigning;
the time spent between runs working out launcher shots ahead, and how many
looks at a munition the runs put off for that),
engagement ticks with work, aim solves and per-frame steers, CIWS rounds
tracked / checked near the target / skipped in flight / time, engageability
checks, standalone target re-evaluations, Fired events seen / threats among
them / munitions ignored as landing clear, munition tracker checks / time,
sensor reads: munitions seen / lines of sight traced / time, reserve-plan
cache hits, rebuilds and the intercept solves it ran, open-fire ranges
worked out, and the server's frames over the whole interval: average fps,
worst frame and frames slower than 50 ms (paused time isn't counted), and
how far the mission clock and the game's own clock each moved in the real
time the interval took (fast-forwarded, both outrun real time; if the
game's falls behind the mission clock's, the engine isn't keeping pace).
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

