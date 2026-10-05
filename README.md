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

## How it works

**A vehicle's role is discovered, never declared.** AEGIS-M reads a
vehicle's own native config and current loadout: every sensor it has
(active radar, IR, visual, passive radar -- with each one's own reach, arc
and whether it turns with a turret); if it has guided missiles, it's a
launcher; if it also has a high-rate-of-fire gun (a SHORAD or Tigris-style
all-in-one vehicle), it's also a CIWS/CRAM. There is no role checkbox, no detection
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

**Detection is the game's own sensors.** Every vehicle with a radar, IR or
visual sensor of its own reads what its sensors hold (getSensorTargets) --
the same radar/IR/visual/passive/datalink simulation already running
against its real CfgVehicles config, with each sensor's own range, arc,
line of sight, fog, night and speed limits, ground clutter, and an active
radar only while it's emitting (see **Radar emission** below). Each contact
records which kinds of sensor saw it.
- **Aircraft, helicopters, drones** are read directly (`DETECT` in the
  RPT, once per new contact). A target's own size scales a sensor's range
  (`radarTargetSize` 0.1 on a Darter: a 9 km radar sees it at 900 m).
- **Missiles, rockets, shells, bombs** can't be: a fired projectile has
  none of the target-size properties that make an object sensor-visible.
  So every tracked munition carries an invisible **sensor proxy** -- a
  vehicle on the supply-drop crate's model with its texture blanked (a
  sensor target needs real geometry: with an empty model nothing saw it),
  size 2.5 on radar, IR and visual (a target's size scales a
  sensor's range: raised from 1 to help sensors pick munitions up), and
  hot -- its engine running (an IR sensor only sees a vehicle
  whose engine is on; the proxy's is silent) and `setVehicleTIPars` -- that
  the sensors see instead. Every sensor vehicle of a Site that sees a
  munition adds its kind to the contact, so a radar and a Spartan's IR both
  show.
  It's created a tenth of a second after launch and attached 5 m behind its
  munition at once, so the engine carries it; an ammo type that doesn't
  carry an attached object (`PROXY-ATTACH` in the RPT, once per type -- the
  MLRS carrier stage `R_230mm_HE` doesn't) has its proxies moved every
  frame instead, at the munition's own velocity. A proxy moved that way is
  a free vehicle, so it isn't made until its munition is clear of whatever
  fired it (the shooter's size, plus the proxy's, plus 5 m), half a second
  after launch at the latest. An attached proxy shows no speed of its own,
  and sensors filter targets out of ground clutter by their speed (the
  vanilla radar template's clutter reaches 200 m up, with a 21 m/s speed
  threshold) -- rockets and missiles skimming the ground with attached
  proxies were never seen at all. So once a munition comes below the
  highest any AEGIS-M sensor's clutter reaches (each sensor's own
  `maxGroundNoiseDistance`), its proxy is detached and moved with it at its
  velocity from then on (`PROXY-LOW`, once per type). It's deleted with its
  munition. There's one
  proxy class per kind of munition (`AEGISM_MunitionProxy_missile` /
  `_rocket` / `_bomb` / `_artilleryShell`), so each can carry its own
  signature. A cluster carrier's bomblets get none (they're not followed at
  all), nor does an AEGIS-M interceptor unless an AEGIS-M vehicle is
  hostile to its side. `TRACKING` in the RPT names the sensors that found
  a munition, and how long after launch.
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
turns it on (e.g. a standalone SPAAG fed by a friendly AWACS).

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
| AI decides (default) | As without AEGIS-M. |
| Always on | Emit all the time. |
| Silent until cued | Off until another sensor finds a threat the radar covers. |
| Intermittent | As Silent until cued, but searching meanwhile: 5 s on every 20 s by default. A linked group's intermittent radars take turns, their bursts spread evenly over the cycle (three radars: one comes on every 6.7 s, with 1.7 s gaps). |

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
  radar truck's) is turned by AEGIS-M while lit: onto its most urgent
  contact, or sweeping round in steps of three quarters of its arc every
  2 s. It's handed back to its crew while silent.
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
intercept is inside its **open-fire range**: where one burst is at least the
Site's "Open Fire at Hit Chance" (40 % by default) likely to put a round
within hitting distance. That's worked out from measurable things only:
- the gun's own measured scatter: every spotted round's miss, square to the
  line of sight, over its range. Until it has fired, the fire mode's
  `dispersion` stands in for it.
- how far the target strays from its predicted track per second of flight
  (measured the same way)
- the round's flight time (`initSpeed`, `airFriction`)
- the hit radius: the round's own blast radius, or the target's size
- the rounds in a burst: the gun's measured rate of fire times the burst
  length

It never fires beyond the round's reach in its lifetime (`timeToLive`), or
inside its arming distance (`fuseDistance`) against a munition. The range
moves as the gun learns its own accuracy: `OPEN-FIRE-RANGE` logs it with
every input, `RANGE-HOLD` while a gun waits, and `TARGET-SIZE` logs each
target type's measured size. Given a choice, the gun takes a target it can
open fire on now over one it can only track. It fires only while the barrel's error at the
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
can fire at in time (`LATE` in the RPT when none can: it's left to the
guns). A queued round it can no longer reach in time (by more than half a
second), or has no missile left for, is **handed off** to a launcher that
can (`HANDOFF`), or released if none can; an empty launcher gives its
targets back at once. Between targets a launcher or gun stays pointed at
the contact it's most likely to get next -- one no weapon of its kind has
yet, soonest impact first -- rather than going back to its crew, which
turned it away between the rockets of a salvo; it's handed back once
there's nothing left to engage.

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

A launcher that can move never fires more than **Max Off-Bore Launch**
(15 deg by default) off the intercept -- it swings round instead; a fixed
mount is only limited by its missile. And a launch more than 2 deg off the
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

An assigned weapon that isn't firing always logs why: `REACTING`, `SLEWING`, `NO-SOLUTION`, `LOS-BLOCKED` (the line from the weapon's own muzzle to the target, naming what's in the way: terrain, or the object, its class and how far its top is above the muzzle), `FIRE-SKIP`, or
`ASSIGN-CLEAR` with a reason. Every AEGIS-M RPT line carries the mission's
game time (`[AEGIS-M] t=123.4 ...`): the RPT's own timestamp is wall-clock
time, which keeps running while the game is paused.

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
| Min Range (m) | 0 | Extra minimum on top of the missile's own (MIM-145: 1000 m). |
| Max Range (m) | 0 | 0 = the missile's own reach (MIM-145: 16000 m). |
| Missiles per Target | 1 | Missiles fired before waiting for the result; re-engages if all miss. |
| Seconds Between Missiles | 0 | Minimum gap between missiles from one launcher. 0 = Auto: each launcher's own fire rate, the `reloadTime` of its weapon's fire mode, which scales with the missile (MIM-145 Defender 4 s, Mk49 Spartan 2 s, Mk21 Centurion 1 s). The RPT logs each launcher's rate as `FIRE-RATE`. |
| Max Off-Bore Launch (deg) | 15 | The most a launcher that can move may fire away from the intercept and leave the missile to turn (firing before its turret is round, or from a turret at its limit). A fixed mount -- a vertical launch cell -- is exempt: it can only fire off-bore. See **Launching off-bore**. |

**CIWS (Guns)**

| Setting | Default | What it does |
|---|---|---|
| Max Range (m) | 0 | 0 = the gun's own reach (Cheetah 35 mm: 2500 m). |
| Min Elevation (deg) | 5 | Never engages below it; holds fire while the barrel is below it. |
| Open Fire at Hit Chance (%) | 40 | Tracks from its full reach, but only fires where one burst is at least this likely to hit -- from the gun's measured scatter (its rounds' misses about where it now aims: an aiming error its spotting has since corrected doesn't count), the target's straying, the round's flight time, the hit radius and the rounds per burst; never past the round's lifetime reach or inside its arming distance. Lower = earlier, farther, more rounds per hit. 0 = its full reach. |
| Cue Before In Range (s) | 2 | A gun is assigned a target this long before it comes into reach (judged on where the target will be by then), so its crew's reaction and its barrel's swing are done by the time it can fire; it holds meanwhile (`CUED` in the RPT). 0 = assigned only once in reach. |
| Burst Length Min / Max (s) | 3 / 5 | Each burst lasts a random length in this range, at the gun's own rate of fire. |
| Pause Between Bursts (s) | 1 | Gap after a burst before firing again at the same target. After a kill the gun goes straight on to its next target. |
| Last Resort Only | Off | Hold while a launcher covers the contact, until it fails or the contact closes inside 40 % of the gun's reach. |
| Self-Destruct Rounds | Off | A round that hits nothing detonates once it has passed the gun's reach (CIWS Max Range, or the gun's own config reach), like a C-RAM round's self-destruct fuze, instead of flying on until its lifetime runs out and disappearing in mid-air -- or just before that lifetime, if it comes first. The fuze time is the round's flight to the gun's reach under its own drag, from its real muzzle speed; each ammo's lifetime (`timeToLive`) and drag are read once per ammo type -- they differ between weapon systems and mods (the vanilla 35 mm lives 6 s, 30 s with ACE). Each gun's fuze time is logged (`SELF-DESTRUCT-FUZE`), and the rounds that went off after each burst (`SELF-DESTRUCT`). |

**Radar Emission** (see **Radar emission** above)

| Setting | Default | What it does |
|---|---|---|
| Radar Emission | AI decides | When the Site's active radars emit: AI decides, Always on, Silent until cued, or Intermittent. |
| Stay Lit After Last Contact (s) | 10 | Silent until cued and Intermittent: how long a radar stays lit after the last contact leaves its coverage. |
| Intermittent: Seconds On / Off | 5 / 15 | Intermittent: each search burst's length, and the silence between bursts. |
| Shut Down for Anti-Radiation Missiles | On | In every mode, a radar shuts down while the Site sees an anti-radiation missile homing on it, or with it emitting in the missile's seeker view. |

**Alarms**

| Setting | Default | What it does |
|---|---|---|
| Going-Live Warning | Base alarm | Sounds from the moment the Site commits a weapon to a target (before its first shot) until the time below after its last shot. |
| Incoming Alarm | Auto | Sounds while a munition threatening a Site vehicle is inbound (seen by a Site radar in the last 3 s -- the pool's own contact expiry), and replaces the warning meanwhile. Auto: BLUFOR the NATO helicopter warning, OPFOR the CSAT one, anyone else the Klaxon. |
| Warning Lasts After Last Shot (s) | 10 | How long the warning keeps going after the last missile or gun round. |
| Custom Warning / Incoming Sound | blank | Any looping sound source class (CfgVehicles, like vanilla's `Sound_Alarm`) -- e.g. from a sound mod with a real national siren or a spoken "incoming" -- replacing that state's tone. |

The tones are the distinct alarm recordings in the base game: Base alarm
(6.6 s cycle), Klaxon (1.6 s), Klaxon 2 (2.1 s), Siren (1.4 s),
Restricted-zone warning (4.6 s), Helicopter warning NATO (2.0 s) and CSAT
(1.5 s), Missile-lock tone (0.2 s beep), or Off. (Vanilla's BLUFOR, OPFOR
and Independent alarms are the same recording, so they're one tone here.)
Each plays like vanilla's own alarm sound source: volume 1, heard to 400 m,
looped by the engine. The speakers are the non-vehicle objects synced to
the Site -- a loudspeaker prop, a lamp post, a Game Logic, but not a
laptop (that's a status terminal) -- or the Site module itself when none
is. Only a change of alarm state crosses the
network. Logged as `ALARM`.

Range settings are real-world metres, scaled by the CBA setting AEGIS-M
Range Scale. Launcher ranges never apply to guns, and vice versa.

**Per-vehicle overrides.** Every vehicle has an **AEGIS-M: Vehicle
Overrides** category in its own Eden attributes, with the same sections
(not Alarms). Tick **Override Site Settings**, then change only what should
differ for that vehicle; everything left on "Site setting" (or blank) keeps
following the Site. Examples: set a long-range SAM's "Artillery, Mortar and
MLRS Rounds" to Ignore so it never spends missiles on shells, or give one
CIWS a shorter Max Range as an inner layer, or keep one long-range search
radar Always on while the rest stay Silent until cued. Overrides on a radar
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
