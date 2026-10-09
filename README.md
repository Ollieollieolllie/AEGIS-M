# AEGIS-M

A modular, Eden/Zeus-configurable integrated air-defense framework for Arma 3.

AEGIS-M is not a faction or vehicle pack. It is a framework: take any
existing radar, SAM, SHORAD, or CIWS/CRAM vehicle -- no setup, no
Attributes to check -- and sync it to one AEGIS-M: Site module to assemble
intelligent, human-feeling air-defense networks, with engagement behavior
driven by a configurable crew skill/temperament system rather than a fixed
reaction timer.

This page is the short version. How each part works in full, with the
reasoning and the test results behind it, is in
[docs/design.md](docs/design.md).

- [Quick start](#quick-start)
- [How it works](#how-it-works)
- [Settings](#settings)
- [Zeus](#zeus)
- [Site terminal](#site-terminal)
- [Debugging](#debugging)
- [Other mods](#other-mods)
- [Releasing](#releasing)

## Status

Version 1.0, the first full release. What changed in each version is in
[CHANGELOG.md](CHANGELOG.md).

## Dependencies

- [CBA_A3](https://github.com/CBATeam/CBA_A3) (hard dependency)
- [ACE3](https://github.com/acemod/ACE3) (heavily recommended, not
  required: AEGIS-M is built and tested with ACE's missile guidance flying
  its missiles. Without it the game guides them, and does it worse: the
  RIM-116 reaches 4 km, not 5, the MIM-145 missed every rocket it met
  inside about 4 km, and a RIM-116's surface strike came down some 20 m
  off its point; the MIM-145 takes no surface strike at all without it.
  `ACE-GUIDANCE` in the RPT says when ACE isn't guiding)
- [Zeus Enhanced](https://github.com/zen-mod/ZEN) (optional: needed to edit
  Site settings, vehicle overrides and a terminal laptop's options from Zeus)
- Arma 3 2.18 or later (the `ProjectileCreated` mission event; the POOK
  compatibility addon needs 2.14's `skipWhenMissingDependencies`)

Compatibility addons ship inside the mod and load only with the mod they're
for: `aegism_compat_pook` for POOK's SAM pack (see **Other mods**).

## Quick start

1. Place the vehicles: any radar, SAM launcher, SHORAD or CIWS, vanilla or
   from a mod.
2. Place the **AEGIS-M: Site** module (the AEGIS-M module folder, in Eden
   or Zeus) and sync it to every vehicle of the site.
3. Play. Every default is chosen so a Site works out of the box.

From there, as needed: the Site's attributes and each vehicle's overrides
(**Settings**), editing them live (**Zeus**), and a laptop for players
(**Site terminal**). Syncing or unsyncing a vehicle, or editing a Site,
takes effect live; nothing needs re-placing or a restart.

A vehicle that isn't synced to a Site is only used if it is a
self-contained AA platform -- a sensor of its own plus its own AA weapons
(Cheetah, Tigris, a Spartan with its launcher-mounted IR) -- and the CBA
setting "Standalone Air Defence" is on (default). Aircraft and infantry are
never adopted.

## How it works

### Vehicles and roles

- **A vehicle's role is discovered, never declared.** AEGIS-M reads its
  config and loadout: every sensor it has (active radar, IR, visual,
  passive radar, each with its own reach and arc), guided missiles make it
  a launcher, a high-rate-of-fire cannon makes it a CIWS. There is no role
  checkbox, range, missile count or ammo classname to set.
- A machine gun doesn't count as a CIWS (the vehicle override **Guns Used
  as CIWS** changes that). Only air-capable weapons count (ammo `airLock`
  >= 1), each within its own real envelope from config.
- A synced vehicle is used even if its only use is a sensor: an IFV's IR
  sight feeds the Site what it sees.
- **It fires the vehicle's own real weapon** with its loaded ammo, so
  ballistics, guidance and damage are the game's. Aiming and the decision
  to fire are AEGIS-M's.
- **A weapon under AEGIS-M control only fires through AEGIS-M.** Its crew's
  own targeting is switched off the moment the vehicle is synced, so an
  unrecognised vehicle goes quiet rather than fighting uncontrolled.

### What it engages

- Hostile contacts, by the mission's side relations. A renegade is hostile
  to everyone.
- A hostile munition, only while it is a threat to the Site (**Only Engage
  Munitions Threatening the Site**, on by default):
  - a shell, mortar round, rocket or unguided missile predicted to land
    within the threat radius of a Site vehicle;
  - a guided missile guided or flying at one, or with one inside its
    seeker's view when what it homes on can't be read;
  - a bomb falling or flying at one;
  - any of those aimed into the Site's **protected area**, a circle round
    the Site module (750 m by default).
- A friendly or neutral munition, only when it is predicted to hit the Site
  (on by default). A battery never engages its own interceptors.

The threat radius is the round's own config danger radius
(`dangerRadiusHit`: 750 m for 155 mm artillery, 1250 m for MLRS) unless the
Site sets one. A round landing clear costs nothing (`IGNORED`) and is picked
up if it turns toward the Site; `TRACKING` says why one counts as a threat.

### Detection

Every vehicle with a radar, IR or visual sensor is read from its real
sensor config: range, arcs, line of sight, fog, night and speed limits,
ground clutter, and an active radar only while it emits.

- **Aircraft, helicopters and drones** come from the game's own sensor
  simulation (`DETECT`).
- **Missiles, rockets, shells and bombs** don't: the game's sensors never
  report a projectile. AEGIS-M judges those itself, by the same rules and
  from the same config values, including line of sight. A munition is hot
  for its whole flight, so IR sees it as radar does.
- It all runs on the server, so it works whoever crews the vehicles. Each
  sensor vehicle reads its sensors once a second, and four times a second
  while a munition is in flight.
- **Datalink doesn't count by default** (CBA setting "Use Datalink
  Contacts"): a Site already shares its own members' contacts.
- **Passive radar cues, it doesn't aim.** A contact only passive radar
  hears lights the Site's radars but gets no weapon until another sensor
  holds it (`CUE ONLY`).

### Radar emission

An active radar only sees while it emits, and while it emits it can be
found. Each Site sets when its radars emit (**Radar Emission**, also a
per-vehicle override):

| Mode | What its radars do |
|---|---|
| Automatic (default) | While the Site is quiet, a relay scan so little is given away. It emits continuously while there's a reason to (a contact in the Site's picture, the Site engaging, a munition inbound, another of its radars shut down), and for at least 60 s after. |
| AI decides | As without AEGIS-M. |
| Always on | Emit all the time. |
| Silent until cued | Off until another sensor finds a threat the radar covers. |
| Intermittent | As Silent until cued, but searching meanwhile with the relay scan. |

- **The relay scan:** the Site's turning radars scan as one radar whose
  beam is handed from vehicle to vehicle, one arc at a time, then all are
  silent for a pause. One radar emits at a time, and the emitter keeps
  moving.
- **A lit radar stays lit** while a contact is in its coverage or a
  missile is in flight at a target it covers, and for **Stay Lit After
  Last Contact** (10 s) after.
- **Turning radars divide the sky** into sectors, one each. Each holds the
  Site's missiles' targets in its sector first (fire control), then tracks
  the contacts there, then searches.
- **Anti-radiation missiles:** a radar shuts down while the Site sees one
  homing on it, in every mode (on by default), and the Site's other radars
  that cover the missile light up for it.
- A Site whose only sensors are radars never lights in Silent until cued:
  use Intermittent. The trade-off of silence is that a munition released
  while every radar is silent goes unseen until one comes on.

RPT: `EMCON`, `CUE`, `ARM-SHUTDOWN`, `ARM-END`.

### Engagement

A Site's coordinator pools every member's contacts and matches each one to
the best-fit weapon across the whole Site, every half second (and at once
for a munition close to impact).

- **Launchers** are chosen by layered-defence doctrine: one that can fire
  in time; then the shortest reach, keeping long-range missiles for what
  only they can reach; then the most rounds left; then the soonest ready
  and the closest warhead size. A launcher queues several incoming
  munitions, soonest impact first, planned on its own measured time per
  missile, and is only given a round it can kill in time. One it can no
  longer make is handed to a launcher that can (`HANDOFF`) or released
  (`LATE`).
- **Layered reserve:** long-range launchers hold their missiles while the
  cheaper, shorter-range tier can cope (`RESERVE`), and step in early and
  far out for what that tier has no missile or no time left for
  (`SATURATION`, `RESERVE-MISSED`, `RESERVE-RELEASED`).
- **Launchers fire to meet the target at the edge of their reach**, while
  an incoming round is still beyond it, leaving time for a second shot.
- **Launching off-bore:** a turret at its limit, or a vertical launch
  cell, fires as close as it gets and lets the missile turn, if the
  missile can (its post-launch cone and turn rate; `AGILITY`,
  `OFFBORE-LAUNCH`). The limits are the Launcher settings Max Off-Bore
  Launch.
- **Guns** are matched by warhead size, then distance, and only given a
  munition they have their **Minimum Firing Window** on; one with less is
  a last-ditch shot, taken only with nothing better. A gun works beside
  the launchers by its **Engagement Mode**.
- **Crews:** reaction time and a reliability roll per missile or burst
  (Crew Skill, Crew Temperament). A failed roll re-tasks the target to the
  rest of the Site. Automated systems ignore the crew model by default.
- **A missile that loses its target** follows another incoming munition
  the Site is tracking if its seeker took one; otherwise it self-destructs
  (`INTERCEPTOR-LOST`), so it can't find something the Site wasn't allowed
  to engage. One the game reports as having lost its lock is ended once it
  has passed its target.
- Between targets a turret stays pointed at the contact it is most likely
  to get next.

### Intercepting a munition

Arma has no projectile-against-projectile hit detection. AEGIS-M tracks
each interceptor frame by frame and, once it is past its arming distance,
detonates it for real when its path comes within its own radius (its blast
or its proximity fuse, whichever is larger) of the munition's body. The
munition is destroyed with it; an aircraft is left to the interceptor's
real damage. A carrier round (an MLRS rocket and its warhead, a cluster
round) goes with what it would have released. Any other tracked munition
inside the blast goes too (`BLAST-KILL`). Each hit is logged as `INTERCEPT`.

### CIWS guns

- A gun tracks its target every frame and solves its full aim 20 times a
  second, from the round's real muzzle velocity, drag and drop.
- It tracks from its full reach but only opens fire inside its
  **open-fire range**: where one burst is at least **Open Fire at Hit
  Chance** (40 %) likely to hit, worked out from its own measured scatter
  (`OPEN-FIRE-RANGE`, `RANGE-HOLD`).
- It fires only while the barrel is on, and in the last seconds before
  impact takes the best shot it will get (`LAST-DITCH`).
- **It corrects its own aim from its rounds.** Every third round is
  measured against the track the target was predicted to fly, and the
  gun's lead and elevation are corrected per kind of target (`SPOTTING`).
- Bursts are 3-5 s with a 1 s pause by default. A gun never takes a target
  its turret can't elevate or traverse to, or one below its minimum
  elevation (5 degrees).

### Linked Sites

Sites become one group when a vehicle is synced to both, a vehicle of one
is synced to a vehicle of the other, or the two modules are synced to each
other. A group shares one contact pool and one coordinator, so two
batteries never fire on the same target unless that's the plan.

- The coordinator is the Site ticked **Shared Site Coordinator**: its
  settings then apply to every vehicle of the group, each vehicle's own
  overrides still on top. With none ticked, the first Site set up
  coordinates and each vehicle keeps its own Site's settings.
- A threat to any vehicle of the group is a threat to all of it, and the
  Sites' alarms sound together.
- When the last link goes, the group splits back into independent Sites.

RPT: `LINK`, `LINK-CHANGE`, `UNLINK`.

### Learning in play

Some things can't be read from config, or config gets them wrong, so each
weapon measures them during the mission, starting from config and
resetting at the next mission. A measurement that can't be right is thrown
away, and one odd measurement can't move what's learned far (limits in
`addons/intercept/calibration.hpp`).

| What's learned | From |
|---|---|
| A missile's speed curve | Every missile's real speed each second after launch (`MISSILE-SPEED`). |
| A missile's turn rate (missiles the game guides) | The fastest sustained turn of each off-bore flight (`MISSILE-TURN`). |
| A gun's aim correction, scatter and open-fire range | Every third round, against the track it was aimed at (`SPOTTING`). |
| A gun's real rate of fire | Each burst (`BURST-END`). |
| A launcher's real time per missile, and its real reload | Its back-to-back shots; the game's own reload state (`RELOAD-TIME`). |
| A target's acceleration | Its velocity, sampled while a weapon aims at it. |

### Server load

All detection and engagement work runs on the server. Other machines only
switch off the AI targeting of crews they simulate, and nothing is
broadcast but a Site alarm's change of state, Zeus edits and what an open
terminal asks for.

- An idle weapon costs a quick check ten times a second. Config values are
  read once per class and cached.
- The coordinator doesn't work out again what hasn't changed, looks at
  munitions far from impact less often, and spreads a large salvo's work
  over runs and frames.
- Everything runs on the mission clock (`CBA_missionTime`), so it follows
  time acceleration in singleplayer.
- An AA crew another machine simulates is moved to the server the first
  time it has to fire (`NONLOCAL`). A player gunner can't be: missiles
  fired from that turret fly without AEGIS-M's target.

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
| Infinite Ammo | Off | The Site's launchers and guns never run out: a magazine that still has rounds is topped up after every missile and at the start of every burst, and one that is used up is replaced (the weapon loads the new one in its own time). The time between shots doesn't change. |
| Shared Site Coordinator | Off | For linked Sites (see **Linked Sites**): this Site coordinates the group, and its settings apply to every vehicle of it while linked. Ticking it unticks it on every Site synced or linked to this one, in Eden and Zeus. |
| Threat Rings on Map | Off | When the Site starts, draws the reach of each of its weapons and sensors on the map, in its side's channel, as markers players can delete: launchers red, CIWS orange, sensors blue. Similar rings on vehicles close together are drawn as one, labelled with every system on it; linked Sites are drawn as one set. Drawn once: they don't move with the vehicles. In Zeus, ticking it draws them and unticking deletes them. Logged as `THREAT-RINGS`. |

**Interception Targets**

| Setting | Default | What it does |
|---|---|---|
| Engage Missiles / Rockets / Bombs / Artillery, Mortar and MLRS Rounds / Fixed-Wing / Helicopters / Drones | all on | Which threat classes the Site engages. |
| Target Min / Max Height (m above ground) | 0 / 0 | Ignore contacts outside this height band. Max 0 = no limit. |
| Engage Friendly Munitions Threatening the Site | On | Also engage a friendly/neutral round predicted to hit the Site. |
| Only Engage Munitions Threatening the Site | On | A hostile munition is only engaged while it's a threat to a Site vehicle: a shell/rocket predicted to land within the Threat Radius of one, a missile guided or flying at one, or with one inside its seeker's view when its target can't be read, a bomb falling or flying at one (`IGNORED` in the RPT otherwise; see **What it engages**). Off: every hostile munition in reach is engaged. |
| Threat Radius (m) | 0 | How close to a Site vehicle a predicted impact counts as a threat, for both settings above. 0 = the round's own config danger radius (`dangerRadiusHit`). |
| Protected Area Radius (m) | 750 | The Site also defends a circle this size round its module: a hostile munition guided at anything inside it, flying down into it, or predicted to land in it is a threat (and sounds the Incoming Alarm). 0 = only the Site's vehicles. Not scaled by Range Scale. Drawn as a green ring with the threat rings (Threat Rings on Map), and a line on the status board. |

**Launchers (Missiles)**

| Setting | Default | What it does |
|---|---|---|
| Min Range (m) | 0 | Extra minimum on top of the missile's own (MIM-145: 1000 m), for where the missile meets the target. |
| Max Range (m) | 0 | 0 = the missile's own reach (MIM-145: 16000 m). Judged where the missile meets the target, so it fires at an incoming round still beyond this. |
| Missiles per Target | 1 | Missiles fired before waiting for the result; re-engages if all miss. |
| Seconds Between Missiles | 0 | Minimum gap between missiles from one launcher. 0 = Auto: each launcher's own fire rate, the `reloadTime` of its weapon's fire mode, which scales with the missile (MIM-145 Defender 4 s, Mk49 Spartan 2 s, Mk21 Centurion 1 s). The RPT logs each launcher's rate as `FIRE-RATE`. The game may ready the next missile more slowly than that; AEGIS-M measures it and plans on the longer of the two (`RELOAD-TIME`). |
| Max Off-Bore Launch While Swinging (deg) | 20 | The most a launcher that can move may fire away from the intercept before its turret is round, leaving the missile to turn. A fixed mount -- a vertical launch cell -- is exempt: it can only fire off-bore. See **Engagement**. |
| Max Off-Bore Launch At Turret Limit (deg) | 30 | The same, once its turret is as close as it can get: at its elevation or traverse limit, or a mount that can't move on one axis. |

**CIWS (Guns)**

| Setting | Default | What it does |
|---|---|---|
| Max Range (m) | 0 | 0 = the gun's own reach (Cheetah 35 mm: 2500 m). |
| Min Elevation (deg) | 5 | Never engages below it; holds fire while the barrel is below it. |
| Open Fire at Hit Chance (%) | 40 | Tracks from its full reach, but only fires where one burst is at least this likely to hit, from the gun's measured scatter, the target's straying, the round's flight time, the hit radius and the rounds per burst; never past the round's lifetime reach or inside its arming distance. Lower = earlier, farther, more rounds per hit. 0 = its full reach. |
| Cue Before In Range (s) | 5 | A gun is assigned a target this long before it comes into reach (judged on where the target will be by then), so its crew's reaction and its barrel's swing are done by the time it can fire; it holds meanwhile (`CUED` in the RPT). 0 = assigned only once in reach. |
| Minimum Firing Window (s) | 3 | A gun is only given an incoming munition it will have this long to fire at before impact (after its crew's reaction, its barrel's swing and the rounds' flight, with the barrel still able to follow it). One with less is a last-ditch shot, taken only with nothing better and dropped for a munition it has its full window on. 0 = any munition it can reach in time. |
| Burst Length Min / Max (s) | 3 / 5 | Each burst lasts a random length in this range, at the gun's own rate of fire. |
| Pause Between Bursts (s) | 1 | Gap after a burst before firing again at the same target. After a kill the gun goes straight on to its next target. |
| Engagement Mode | Overlapping | How a gun works beside the Site's launchers. **Overlapping**: it engages whatever it can reach, including a contact a launcher is already on. **Planned**: it is given incoming munitions of its own, and the launchers leave those to it, so a gun and a missile are never on the same contact; a gun counts as busy on each for its Minimum Firing Window (and no less than one longest burst and its pause, 6 s by default), and what it can't take goes to the launchers (`GUN-PLAN-RELEASED`). **Last Resort**: it holds while a launcher covers the contact, until that fails or the contact closes inside 40 % of the gun's reach. |
| Self-Destruct Rounds | Off | A round that hits nothing detonates once it has passed the gun's reach (or just before its lifetime runs out, if that comes first), like a C-RAM round's self-destruct fuze, instead of flying on. The fuze time is worked out per ammo type from its real muzzle speed and drag (`SELF-DESTRUCT-FUZE`, `SELF-DESTRUCT`). |

**Radar Emission**

| Setting | Default | What it does |
|---|---|---|
| Radar Emission | Automatic | When the Site's active radars emit: Automatic, AI decides, Always on, Silent until cued, or Intermittent (see **Radar emission**). |
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
| Alarm Range | 400 m | How far the alarms are heard from each speaker: 200 m, 400 m (vanilla's own alarm), 800 m, 1.5 km, 3 km or 5 km. They fade out toward that range, from the speaker's direction. A custom sound keeps its own range. |
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
laptop (that's a terminal) -- or the Site module itself when none
is. The server only decides the alarm; each player's machine plays it for
itself, wherever its camera is -- the player, Zeus or a spectator -- and
starts it the moment the camera comes within the Alarm Range of a speaker.
Players joining mid-alarm hear it too. Only a change of
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
- **A terminal laptop:** the same right-click or button sets its Terminal
  Access (Status Only or Full Control), Manual Interception, Surface
  Strike and Fixed in Place (see **Site terminal**).

An edit reaches every machine, including players who join later, and the
Site's vehicles pick it up at once (`SITE-SETTINGS` / `OVERRIDES` in the
RPT) rather than at their next 5-second refresh.

## Site terminal

Sync a laptop (any object with "laptop" in its class name) to a Site or to
a single air-defence vehicle, and players get an **AEGIS-M: Site Terminal**
action on it. What it reaches follows what it is synced to:

| Synced to | Reaches |
|---|---|
| a vehicle | that vehicle |
| a Site | that Site and each of its vehicles |
| the Shared Site Coordinator of linked Sites | every linked Site and each of their vehicles |

What players can do at it is set by four attributes of the laptop itself
(Eden: under *AEGIS-M: Terminal*; Zeus, with Zeus Enhanced: its *AEGIS-M
Settings*):

| Attribute | Default | Gives the terminal |
|---|---|---|
| Terminal Access | Status Only | **Status Only**: the live status board of the Site or vehicle picked, refreshed once a second. **Full Control**: a Settings tab as well, with the Site's settings or the vehicle's overrides as in Eden; Apply sends them to the server. |
| Manual Interception | Off | An **Interception** tab: a map, the tracks, the weapons and the radars, for ordering them yourself. |
| Surface Strike | Off | With Manual Interception: a **Surface** switch on that tab, for firing at a point on the ground. |
| Fixed in Place | Off | For a laptop that is an inventory item. **Off**: it can be picked up and keeps its connection (below). **On**: it can't be taken. |

**Carrying it off.** A laptop that is an inventory item (one a player can
pick up) keeps its connection when it's taken: whoever carries it has
**AEGIS-M: Site Terminal (carried)** on the action menu, and it is a
terminal again wherever it's put down. In a crate, a vehicle or a body it
stays connected until it's taken out. A prop laptop can't be picked up at
all.

**Interception.** The map shows the weapons' vehicles, the radars, every
track, the Site's own missiles in flight and which weapon is on which
track. Tracks are coloured by what they are to the Site: red, one it
engages; yellow, a hostile of a class it doesn't engage; blue, a friendly
aircraft its sensors see; magenta, one held for an order. Click a track, or
pick it in the list.

- **Weapons** lists every launcher and gun of what is picked on the left,
  and once a track is picked, whether each has a shot at it or why not.
  Launchers of one type standing together (within 150 m) are a single row;
  an order to it goes to whichever of them is best placed.
- **Engage** orders the weapon picked onto the track picked: one missile,
  or a gun's fire until it is down. Again for another missile. It works on
  any track listed, a friendly included. The server refuses an order the
  weapon has no shot for, and says why.
- **Cease Fire** ends the orders on the track picked, or every order with
  none picked. A missile in flight flies on.
- **Automation** off: the weapons of what is picked fire on orders only.
  The Shared Site Coordinator's switch covers every linked Site, a Site's
  its own vehicles, a vehicle's that vehicle alone. Sensors, radars and
  alarms carry on.
- **Radars:** each radar can be ordered to **Emit**, to stay **Silent**,
  or back to **Auto** (its own Radar Emission setting). A radar ordered on
  still shuts down for an anti-radiation missile inbound on it.

An order goes to the front of its launcher's queue and stays with that
launcher. It ends when its missiles have missed, its target is down or
lost to the Site's sensors, the weapon has had no shot for 15 s, or it is
ceased. Orders work through the Site's coordinator, so a vehicle in no
Site takes none.

**Surface Strike.** With the Surface switch on, a click on the map where no
track is puts a strike point on the ground; pick a weapon and Engage.

- **A launcher** fires one guided missile, lofted: it climbs over what is
  between and comes down on the point from above. Not nearer than 300 m,
  nor beyond the launcher's reach, nor a small missile (a warhead under
  8 m blast radius: a Stinger has 6, the RIM-116 10, the Patriot 30).
  A missile that locks on after launch (the MIM-145, S-750, RIM-162)
  needs ACE's guidance for it: without, its launcher is refused and the
  weapons list says why. The others strike on the game's own guidance
  without ACE, less accurately (a RIM-116 came down some 20 m off).
- **A gun** fires one burst on its own ballistic path. It needs a turret
  that can point there and a line to the point clear of the ground; trees
  and buildings don't count.
- The weapon's turret is the strike's until its missile is away or its
  burst is over. The Site never fires at the ground on its own, and a
  strike doesn't sound its alarm.

The server builds everything a terminal shows and takes every change and
order, so it works on a dedicated server. It takes them only from a
terminal with the right attribute, for something within that terminal's
reach, from a player within 10 m of it. RPT: `TERMINAL`, `MANUAL`,
`STRIKE`.

## Debugging

All of these are CBA settings under "AEGIS-M > Debug", or debug-console
calls on the server.

- **Site Status Hint:** a live board in the hint box for the nearest Site:
  its vehicles with their roles (`R` radar, `I` IR, `V` visual, `L`
  launcher, `C` CIWS), what each weapon is doing, each radar's emission
  and why, the Site's contacts and which weapons are on each, and for
  linked Sites every link and whose settings apply. The laptop's Status
  tab shows the same.
- **Enable Debug 3D Draw:** the same in the world. One icon a contact, a
  line from each weapon to its target in its engagement's colour (queued
  blue, assigned green, reacting or slewing amber, reloading orange, range
  hold teal, firing red, in flight gold, no line of sight or no solution
  purple, held or no ammo grey), a line from each sensor vehicle to what
  it sees, three lines of status a vehicle, each radar's range ring, and
  each Site module with its vehicles and links.
- **RPT Detail:** at Normal, the default, the RPT gets what AEGIS-M decides
  and why: detections, assignments, shots, intercepts, munitions ignored,
  alarms, radar emission, anything stopping a weapon, terminal changes and
  orders, and its setup. Verbose adds the step-by-step detail (each
  weapon's wait, every burst and missile flight, calibration, the reserve
  plan, every enemy shot). Every line carries the mission's game time
  (`[AEGIS-M] t=123.4 ...`).
- **RPT Performance Summary** (on by default): one `PERF` line every 10 s
  while AEGIS-M is doing anything -- the coordinator's runs and time, each
  weapon's work, sensor reads, and the server's frame rate.
- **Why a weapon didn't fire:** `NO-SOLUTION`, `LOS-BLOCKED`, `FIRE-SKIP`,
  `RELOADING`, `FIRE-FAILED`, or `ASSIGN-CLEAR` with its reason. A threat
  10 s from impact with no weapon on it is logged once (`UNENGAGED`) with
  each weapon's reason.
- **Benchmark:** `[cursorObject, heli1] call
  aegism_intercept_fnc_debugBenchmark` times the hot paths (`BENCHMARK`).
  **Munition probe:** `[] call aegism_intercept_fnc_debugProbeMunitions`
  measures each new ammo type's body in flight (`PROBE`).

Short codes, everywhere in the debug: `RDR` radar, `IR`, `VIS` visual,
`PAS` passive radar, `DL` datalink; `L` launcher, `C` CIWS. A Site has the
same name everywhere: its Eden variable name, or `Site 1`, `Site 2`... in
the order the Sites were set up.

## Other mods

AEGIS-M keeps what it sets on its vehicles set, whoever changes it, and
logs each case once: a radar something else switched (`RADAR-OVERRIDE`), a
gunner whose own targeting was turned back on (`AI-RESTORED`), its event
handlers removed (`EH-RESTORED`), a munition nothing reported fired
(`MUNITION-UNREPORTED`), and a weapon fired without an AEGIS-M command
(`UNCOMMANDED-FIRE`).

A launcher that readies its next missile more slowly than its config says
is timed from the game's own reload state and planned on that
(`RELOAD-TIME`); one loading a new magazine isn't fired until it's ready.

With ACE loaded (heavily recommended, see **Dependencies**), its missile
guidance flies the missiles of the game's own launchers, and has to be left
guiding AI-fired shots (its default). AEGIS-M hands it each missile's
target. Without ACE, and for a missile of another mod that ACE doesn't
guide, the game's own guidance flies it. `ACE-GUIDANCE` in the RPT says
once when ACE isn't guiding.

**POOK's SAM pack** gets its own compatibility addon
(`aegism_compat_pook`, loaded only with it). It gives POOK's 20, 23 and
30 mm AA rounds their full flight instead of bursting 1 s after firing,
and switches off POOK's scripts that aim and fire a vehicle's weapons
themselves (`COMPAT`). AEGIS-M never runs or calls POOK's scripts. Build
Sites from POOK's vehicles placed one by one, not from POOK's site
spawners, whose radar scripts fire the launchers themselves.

## Releasing

For whoever maintains the repository. Both scripts are in `tools/` and run
from a terminal in the repository (or by double-click):

- **`tools\github-setup.cmd`**, once: creates the GitHub repository if
  there is no `origin` remote yet (asking private or public) and pushes the
  current branch.
- **`tools\release.cmd`**: shows the current version and asks for the new
  one (patch, minor, major, build, one you type, or unchanged), asks before
  anything leaves the PC, then commits the version, builds with
  `hemtt release`, pushes the branch and a `vX.Y.Z` tag, publishes a
  GitHub release with the zipped mod attached, and updates the Steam
  Workshop item (its ID is in `workshop/item-id.txt`) with the same build
  and a change note made from the commits since the last release. The
  Workshop step needs Steam running, logged in as the item's owner, and
  Arma 3 Tools; if it fails the GitHub release stands, and
  `-WorkshopOnly` sends it later. `-DryRun` shows what it would do and
  changes nothing; `-Draft` publishes a draft (and leaves the Workshop
  alone, as does `-NoWorkshop`); `-Bump patch` or `-Version 1.2.3` skip
  the question.

They need [HEMTT](https://github.com/BrettMayson/HEMTT) and the GitHub
CLI (`winget install GitHub.cli`); if it isn't logged in yet, the script
starts the login in your browser. The version lives in
`.hemtt/project.toml`. A release is built from what is committed: if
something isn't, the script lists it and asks for a commit message to
commit it with, or stops. If the build fails, its version commit is taken
back and nothing is pushed.

## License

APL-ND (Arma Public License No Derivatives). See `LICENSE`.

## Coding convention

Every function begins with a standardized header docblock (see any file
under `addons/*/functions/`): a short description, its parameters, what it
returns and an example. Author is always Snow(Dryden).

The long version of each description -- how the function works, why, and
what was seen in testing -- is kept out of the code, in
`docs/functions/<addon>.md`, one section per function. That folder is for
development and isn't packed into the mod, and the build strips every
comment from the packed copies of the code (a HEMTT pre-build hook), so
comments cost nothing in the released mod.
