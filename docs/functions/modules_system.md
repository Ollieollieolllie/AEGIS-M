# modules_system: function notes

What each function does and why, in full: the descriptions that used to sit in each
function's header, moved out of the code on 2026-10-07. Each header keeps a short
description with its parameters, return value and examples. Change a function's
behaviour and its notes here change with it. This folder is not packed into the mod.

## aegism_system_fnc_applyOverrides

`addons/modules_system/functions/fn_applyOverrides.sqf`

```text
Applies a vehicle's own per-vehicle overrides on top of the settings it
would otherwise use (its Site's, or the defaults when standalone).

Overrides come from the vehicle's Eden attributes, category "AEGIS-M:
Vehicle Overrides" (addons/modules_system/config.cpp, Cfg3DEN), or from
script. They only apply while the master switch "AEGISM_ovr_enabled" is
true. Each setting is an object variable "AEGISM_ovr_<key>"; one that
was left on "Site setting" (or blank) is never set, so it stays nil and
that setting falls back to the Site's value.

    _vehicle setVariable ["AEGISM_ovr_enabled", true];
    _vehicle setVariable ["AEGISM_ovr_salvoSize", 2];
    _vehicle setVariable ["AEGISM_ovr_allow_artilleryShell", false];

Target classes are overridden one at a time ("AEGISM_ovr_allow_<class>"
true/false) and applied to the inherited allowlist.

"AEGISM_ovr_ciwsGuns" ("all" / "none"; nil = cannons only) isn't a
setting: it decides which guns are CIWS at all, read when the vehicle's
weapons are discovered (aegism_system_fnc_discoverCapabilities).
```

## aegism_system_fnc_debugCheckCiws

`addons/modules_system/functions/fn_debugCheckCiws.sqf`

```text
On-demand capability check for a specific vehicle, run from the debug
console: answers "why isn't this vehicle's gun/launcher being used" by
running the real aegism_system_fnc_discoverCapabilities and printing
every qualifying weapon with its real envelope (and burst time for
CIWS), every loaded magazine with its ammo class and airLock (the
air-capability gate), and the vehicle's adoption state (synced to a
Site / deferred / standalone setting). Also shows the cached
AEGISM_system, in case the loadout changed since discovery.
```

## aegism_system_fnc_defaultCrew

`addons/modules_system/functions/fn_defaultCrew.sqf`

```text
Hardcoded fallback personality used by a System (or unmanned Launcher/
CIWS) with no directly-set or Site-inherited Personality data (AEGISM_
Module_Site's own Attributes), so unmanned/uncrewed point-defense still
behaves per a sane baseline rather than having no engagement decision
logic at all.
```

## aegism_system_fnc_defaultEngagementSettings

`addons/modules_system/functions/fn_defaultEngagementSettings.sqf`

```text
Hardcoded fallback doctrine used by a System with no directly-set or
Site-inherited Doctrine data (AEGISM_Module_Site's own Attributes), so
a standalone vehicle with just a role checked -- no Site module synced
at all -- remains fully functional.
```

## aegism_system_fnc_discoverCapabilities

`addons/modules_system/functions/fn_discoverCapabilities.sqf`

```text
Reads a vehicle's own native config and current loadout to determine
what AEGIS-M capabilities it has, rather than relying on a mission
designer to declare a role by hand: if it has a radar, it has a radar;
if it has guided missiles, it's a launcher; if it also has a high-rate-
of-fire gun (because it's a SHORAD or Tigris-style all-in-one vehicle),
it's also a CIWS/CRAM. AEGIS-M never spawns or tracks its own ammo --
everything here points back at the vehicle's real turrets/weapons/
magazines, used later via BIS_fnc_fire and magazineTurretAmmo.

Sensors: every sensor component in the vehicle's CfgVehicles config
(its own sensor config, and every turret's) whose componentType is one
AEGIS-M uses -- whatever the component class itself is called:
    radar   - ActiveRadarSensorComponent
    passive - PassiveRadarSensorComponent (hears only what emits: a
              radar that's on). What it hears cues the Site's radars
              (Radar Emission), but isn't engaged on its own (aegism_
              fnc_hasTrack).
    ir      - IRSensorComponent
    visual  - VisualSensorComponent
This is exactly the config the engine's own getSensorTargets reads. The
engine detects aircraft with it; munitions, which its sensors can't
target at all, AEGIS-M judges from the same config itself (aegism_
detect_fnc_sensorView, aegism_detect_fnc_munitionSeen). What's read here
also says what a vehicle has: whether it has a radar, or any sensor of
its own (for adoption, aegism_system_fnc_moduleInit), and each sensor's
reach and arc for the debug overlays.

Each sensor's reach is its AirTarget maxRange (the largest maxRange of
any target-type sub-class if it has no AirTarget), and its arc its
angleRangeHorizontal (360 if undefined) -- both inherited from the
vanilla templates where the vehicle doesn't set them: the vanilla
Radar_System_01's radar is 120 degrees from SensorTemplateActiveRadar.
Where it points: a sensor with an animDirection (e.g. "mainGun") turns
with the turret whose gun or body is that selection -- the Spartan's
IR sensor looks wherever its launcher points. Without one it's fixed to
the hull, or, inside a turret's own config, treated as all-round.

The sensor component actually lives under "Components >>
SensorsManagerComponent >> Components" in every vanilla Arma 3 vehicle
checked (this is the real, current nesting per BIS's own Sensors Config
Reference and the Arma 3 sensor-overhaul devblog; a bare top-level
"Sensors" class was an earlier assumption in this codebase that turned
out to be wrong -- confirmed the hard way when B_Radar_System_01_F, the
vanilla AA radar unit, never once registered as having radar during
testing despite very obviously having one in-game). Both paths are
checked (Components-nested first, since that's the real one; the older
bare "Sensors" path is kept as a fallback for any mod vehicle that might
still use it) rather than assuming either is universal.

Launcher/CIWS: walks every currently-loaded magazine (magazinesAllTurrets)
and resolves which weapon on that turret fires it (CfgWeapons magazines[]
plus any CfgMagazineWells listed in magazineWell[]).

Only AIR-CAPABLE weapons qualify: the loaded ammo's own CfgAmmo airLock
must be >= 1 (the engine's own "can engage air targets" flag). Without
this, an IFV's ATGM or a tank's coax would count as air defence.

Launcher: ammo classifying as "missile" (guided). Unguided rockets can't
intercept anything and are not launcher weapons.

CIWS: non-missile ammo whose FIRING WEAPON has a fire mode faster than
AEGISM_CIWS_ROF_THRESHOLD. Rate of fire is a CfgWeapons per-mode
reloadTime, NOT CfgAmmo reloadTime (an unrelated submunition field that
real CIWS rounds like B_35mm_AA don't define at all). Cannons only, not
machine guns: a weapon built on CfgWeapons MGunCore (the base of every
vanilla machine gun, which mods build on) is left out -- POOK's SAM
vehicles' self-defence M2HB and PKT were being run as CIWS against
rockets. Its ball rounds don't burst (vanilla .50 ball: hit 30,
indirectHit 0; the Phalanx and 20-35 mm AA rounds: hit 60-70,
indirectHit 6-25). The vehicle override "Guns Used as CIWS" (AEGISM_
ovr_ciwsGuns) changes this per vehicle: "all" every rapid-fire gun,
machine guns too; "none" no gun at all.

Every weapon also carries its own REAL engagement envelope, read from
config and never scaled by the AEGIS-M range-scale setting:
    missile - CfgAmmo missileLockMinDistance/missileLockMaxDistance
        (falling back to maxControlRange, then the weapon's modes)
    gun - min/max of CfgWeapons mode minRange/maxRange (the engine's own
        AI engagement bands, e.g. 0-2500m for autocannon_35mm)
and CIWS weapons carry their burst duration (mode reloadTime x burst,
longest AI mode) so the engagement loop fires one burst per burst-time
rather than on missile salvo rules.
```

## aegism_system_fnc_emconUpdate

`addons/modules_system/functions/fn_emconUpdate.sqf`

```text
Emission control for one radar vehicle, once a second on the server
(aegism_system_fnc_moduleInit's detection loop, before its sensors are
read): whether its active radar emits, from its Radar Emission setting
("emcon": the Site's, or the vehicle's own override). An active radar
only sees while it emits, aircraft and munitions alike; while it emits,
enemy radar-warning receivers and anti-radiation missiles can find it.
Set with setVehicleRadar (0 the AI decides, 1 on, 2 off) when what it
wants changes -- and again whenever the radar isn't doing what it was
set to, two seconds running: something else changed it (POOK's SA-8,
SA-11 and Patriot launch scripts turn their radar on at every launch and
hand it back to the AI when the missile's gone), logged once per
vehicle (RADAR-OVERRIDE).

    auto - Automatic (the default): while the Site is quiet, short
        search bursts as intermittent's below -- the Site's radars in
        turn, giving little away; emitting continuously while there's
        reason to ("alert"): a contact anywhere in the Site's picture,
        the Site engaging or firing (within its Warning Lasts After
        Last Shot), a munition inbound on it, or another of its radars
        shut down for an anti-radiation missile (the others take over
        its sector) -- and for at least AEGISM_AUTO_HOLD s after. Lit
        for a contact it covers and for fire control as cued is.
    ai - the AI decides, as without AEGIS-M. A radar AEGIS-M had set is
        handed back once; one it never set isn't touched.
    on - always emitting.
    cued - silent until a threat it covers turns up (aegism_system_fnc_
        radarCovers): any contact in its Site's picture -- its whole
        linked group's (aegism_network_fnc_linkSites) -- found by
        another sensor: heard by passive radar, seen by IR or visual
        sensors, by datalink where that's allowed (aegism_detect_fnc_
        confidenceLoop), or by another radar. It stays lit while any
        contact is in its coverage, while a launcher's missiles are in
        flight at a target it covers (fire control: the Site's track
        must not drop while they guide), and for emconHold s after the
        last, then goes silent.
    intermittent - as cued, but searching meanwhile, in bursts:
        turning radars (aegism_system_fnc_turningRadar) - the relay scan
            (aegism_system_fnc_radarRelay): one radar lit at a time, each
            on the next arc round, emconBurstOn s an arc, a pause of
            emconBurstOff s after each lap of the circle;
        any other radar - emconBurstOn s on every emconBurstOn +
            emconBurstOff s, a linked group's taking turns, their bursts
            spread evenly over the cycle (three radars at 5 s on, 15 s
            off: one on every 6.7 s, silent gaps of 1.7 s between them).

Anti-radiation missiles, in every mode (armShutdown on, the default): a
radar an inbound one is homing on, or has in its seeker's view, shuts
down whether or not that saves it (aegism_detect_fnc_armInbound marks
it), until the missile is gone or past when it would have arrived. Its
Site's other radars that cover the missile are cued by it, to keep the
track (in cued and intermittent modes); in auto they all emit.

A narrow radar on a turret with no AEGIS-M weapon on it (the vanilla
radar truck's 120 degrees) is pointed by AEGIS-M in every mode, AI
decides included -- fire control, tracking and searching in turn
(aegism_system_fnc_radarSchedule) -- rather than left facing wherever
its crew looked; in the relay scan, onto its arc, swinging there while
silent.

Records on the vehicle ("AEGISM_emcon", for the debug overlays, aegism_
fnc_emconText): mode, applied (the last setVehicleRadar value, -1
none), desired, reason ("ai", "on", "arm", "guiding", "cued", "alert",
"holding", "burst", "pause", "silent"), detail, since.

Logged: EMCON (its mode; going silent, or back to searching), CUE (lit
by a contact, with what found it), ARM-SHUTDOWN (shut down, and back).

2026-10-07: "AEGISM_radarOrder" on the vehicle ("on" / "off", "" for
none), set from a terminal's Interception page (aegism_network_fnc_
terminalOrder). Reasons "orderedOn" / "orderedOff", placed after the
anti-radiation shutdown and before every mode, so an order stands in any
mode (AI decides included) but a radar ordered on still shuts down for an
ARM inbound on it when armShutdown is set (my choice: the setting is the
mission maker's protection). A radar under an order is left out of the
burst slots (_searchers), and the relay scan already leaves out any radar
whose reason isn't a burst or a pause.
```

## aegism_system_fnc_guardSystems

`addons/modules_system/functions/fn_guardSystems.sqf`

```text
Keeps what AEGIS-M has set on its vehicles set, against other mods'
scripts and the game itself. Every machine, every couple of seconds
(this addon's XEH_postInit, with the discovery scan):

The crew's own targeting and firing on every AEGIS-M weapon turret (off
since AEGIS-M took it, aegism_fnc_setWeaponAiSuppressed): a gunner here
-- where it's simulated -- with AUTOTARGET or FIREWEAPON back on is set
off again. Another mod's AI script can turn them on (enableAI), and a
crewman new to the seat (a replacement, a Zeus swap) never had them
off: either way the crew would pick its own targets and fire them,
outside AEGIS-M (UNCOMMANDED-FIRE). "TARGET" is left alone: AEGIS-M
turns it on itself while a gunner holds a lock (aegism_intercept_fnc_
gunnerLock). Logged once per gunner (AI-RESTORED). A player gunner is
never touched.

On the server, each armed vehicle's Fired handler (aegism_intercept_fnc_
firedHandler): there from its first look, before AEGIS-M has fired it, so
a shot it fires by itself is seen (UNCOMMANDED-FIRE); and AEGIS-M's
mission-wide catch for munitions nothing reported fired (aegism_detect_
fnc_projectileCreated). Either is re-added if something removed it
(logged, EH-RESTORED).

The list is the vehicles this machine set up ("AEGISM_guardedSystems",
aegism_system_fnc_moduleInit); gone ones are dropped.
```

## aegism_system_fnc_moduleInit

`addons/modules_system/functions/fn_moduleInit.sqf`

```text
Per-vehicle AEGIS-M System setup. There is no role checkbox or
per-vehicle Attribute anymore -- capability is discovered entirely from
the vehicle's own native config and current loadout (see aegism_system_
fnc_discoverCapabilities): if it has a radar, it has a radar; if it has
guided missiles, it's a launcher; if it also has a high-rate-of-fire gun
(SHORAD or Tigris-style all-in-one vehicle), it's also a CIWS/CRAM.
Called for every vehicle exactly once by aegism_system_fnc_
scanForRoles's periodic discovery sweep (this addon's XEH_postInit.sqf).
Guarded by "AEGISM_systemInitialized", set immediately regardless of
outcome, so a vehicle with no AEGIS-M-relevant capability is checked
once and never re-scanned, and a repeat call for one that does qualify
is a harmless no-op.

Stores the discovered capabilities on the vehicle ("AEGISM_system") and
suppresses the crew's own independent AI targeting/engagement on every
discovered launcher/CIWS turret (aegism_fnc_setWeaponAiSuppressed), so
that weapon only ever fires via aegism_intercept_fnc_fireWeapon. That
much runs on every machine: disableAI is local, and has to happen
wherever the crew is simulated (a headless client, a player's AI group).
A vehicle synced to a Site gets a broader version of the same
suppression at sync time (aegism_network_fnc_moduleInit).

The rest is the engagement pipeline, and runs on the server only (the
single source of truth in singleplayer, hosted and dedicated games):
    - resolves and caches its Doctrine and Personality
      ("AEGISM_resolvedEngagementSettings", "AEGISM_resolvedCrew", and the
      crew's modifiers, "AEGISM_resolvedCrewMods" -- what the engagement
      loop and the coordinator read every tick), and its contact source
      ("AEGISM_resolvedContactSource", for aegism_system_fnc_
      resolveContactSource's own warning). These depend on
      "AEGISM_engagement"/"AEGISM_crew"/"AEGISM_network", which CAN
      change later (a Zeus operator syncing a Site), so a 5-second poll
      re-resolves them.
    - with a sensor of its own (radar, IR or visual): its own pool
      ("AEGISM_pooledContacts") and a detection loop (aegism_detect_fnc_
      confidenceLoop): once a second, four times a second while any
      munition is in flight. Once a second, it also sets whether its
      radar emits, if it has one (Radar Emission, aegism_system_fnc_
      emconUpdate).
    - one 0.1-second engagement loop per weapon role (aegism_intercept_
      fnc_engagementLoop).
Registering the loops on every machine would make every client detect
the same contact and fire its own redundant shot.

Capability discovery only ever happens once -- a vehicle's turrets and
sensors are fixed for its lifetime; ammo is re-checked at fire time.
```

## aegism_system_fnc_radarCovers

`addons/modules_system/functions/fn_radarCovers.sqf`

```text
Whether one of a vehicle's active radars (aegism_system_fnc_
discoverCapabilities "sensors") can see a position: within its reach,
and
    fixed to the hull - inside its horizontal arc either side of the
        vehicle's forward, and its vertical arc either side of its
        boresight (level, or tilted down by its aimDown);
    turning with a turret - inside what the turret can bring into its
        arcs: its traverse limits widened by half the horizontal arc,
        its elevation limits by half the vertical arc (aegism_intercept_
        fnc_turretConfig) -- the vanilla radar truck's 120 x 120 degree
        radar, on a turret that turns all the way round and elevates
        -10 to 75, covers 70 degrees below the horizon to straight up;
    all round (360 degrees) - anywhere in reach, inside its vertical arc.
The vehicle's own tilt is ignored. Used by Radar Emission (aegism_
system_fnc_emconUpdate) to light the radars covering a threat.
```

## aegism_system_fnc_radarRelay

`addons/modules_system/functions/fn_radarRelay.sqf`

```text
The relay scan. While its Site is quiet, the turning radars searching in
bursts (aegism_system_fnc_turningRadar; Radar Emission Intermittent, or
Automatic with nothing going on) work as one radar whose beam is handed
from vehicle to vehicle:

    - a lap steps round the whole circle one arc at a time -- as many
      arcs as it takes, each a little under the narrowest radar's arc
      (AEGISM_RELAY_ARC_SHARE), spread evenly (four of 90 degrees for
      120-degree radars);
    - each arc is lit by one radar for Search Burst Seconds On, and after
      a lap they're all silent for Search Burst Seconds Off;
    - each arc goes to whichever radar can swing onto it soonest, other
      than the one lit before it (unless it's the only one), picked a
      step ahead -- so it swings there while silent, and lights on it.

Every bearing is scanned once a lap and no arc twice, one radar emits at
a time, and the emitter keeps moving from vehicle to vehicle. (Bursting
each on its own timer while turning, a radar lit up wherever its turn
had got to -- often an arc another had just scanned, while one nobody
had waited.)

The timing is the mission clock, the same for every radar. The picks are
shared on the Site's link group lead ("AEGISM_radarRelay": [lap, step] ->
radar netId), made by whichever radar asks first. A radar that's cued,
guiding, on alert, holding or shut down for an anti-radiation missile is
out of the relay -- it's emitting anyway, or mustn't.

Called by aegism_system_fnc_emconUpdate for a quiet radar in those modes.
```

## aegism_system_fnc_radarSchedule

`addons/modules_system/functions/fn_radarSchedule.sqf`

```text
Points a narrow radar that turns on a turret no AEGIS-M weapon uses (the
vanilla radar truck's 120 degrees), whatever its Radar Emission: called
once a second by aegism_system_fnc_emconUpdate. It's never left idle
facing wherever its crew last looked.

The Site's turning radars -- its whole linked group's (aegism_network_
fnc_linkSites) -- divide the sky between them: 360 degrees in equal home
sectors, one each, measured from the middle of them, in a fixed order
(by netId), the first centred on north. A sector decides which radar
looks after which contacts:

    fire control - while a Site launcher's missiles fly at a target in
        its sector, it holds as many of them as it can, and doesn't
        search.
    track - on the contacts in its sector, centred to hold the most
        important at once: a threat under engagement, then munitions by
        time to impact, a contact only passive radar hears (a radar look
        makes it a track), aircraft. A contact another Site sensor saw in
        the last AEGISM_HELD_FOR s counts for a quarter: the radar is for
        what nobody holds. It stays centred where it is while that scores
        AEGISM_TRACK_KEEP of the best centre, rather than hopping between
        near-equal ones. Every AEGISM_SEARCH_REVISIT s it takes a look at
        its search position, if its track doesn't already hold that, and
        comes back.
    search - nothing worth tracking: the Site's turning radars rotate
        round together, evenly spaced -- each starts on its own sector
        and turns on one step (three quarters of the narrowest arc among
        them) every period (the slowest turret's swing for a step, then
        AEGISM_SEARCH_DWELL s), by the mission clock, so all of them are
        always at the same step. Every radar looks all the way round --
        radars far apart see past different hills -- and at any moment
        their beams are spread evenly round the sky (three 120-degree
        radars keep all round covered as they turn). Silent ones turn too,
        so each is in its place when it lights. With the Site's Turning
        Radars Hold Their Sector on, a radar whose arc covers its sector
        stays on it instead. (Searching on their own, two radars each
        swung across their own half and never turned round; three ended
        up facing north, east and south with the west uncovered; four
        drifted until two pointed the same way.) Pitched up a quarter of
        its vertical arc (within its elevation limits), covering the
        horizon and well above it.

A contact belongs to the radar whose sector it's in. Another of the
Site's radars tracks it only if that one can't reach it -- and then only
one: each radar posts what it's tracking ("AEGISM_radarTracks": contact
key -> [radar netId, until]), and a contact another is tracking counts
for a tenth.

Every dwell starts once the turret has had time to swing there, from its
traverse rate (aegism_intercept_fnc_turretConfig). Logged as RADAR-TASK
at RPT Detail Verbose when it starts tracking, holds fire control, starts
searching, or the rotation changes (a turning radar joins or leaves).

Records on the vehicle ("AEGISM_radarBeam", for the debug overlays):
task, taskUntil, lastSearchAt, bearing (where it points), search (its
search position), dwellFrom, fenceCount, text.
```

## aegism_system_fnc_resolveContactSource

`addons/modules_system/functions/fn_resolveContactSource.sqf`

```text
Resolves where a Launcher/CIWS-capable System draws tracked contacts
from: its own sensors (self-contained case: a radar, IR or visual
sensor of its own -- a Tigris/ZSU-style vehicle, or a Spartan with its
launcher-mounted IR), its Network's pooled contact list (networked
case), both together, or neither -- logging a diag_log warning for
either dead end, since that System would otherwise silently never
engage anything. A synced Network only counts as a real contact source
if at least one of its current members (per the live
"AEGISM_networkMembers" list, see aegism_network_fnc_moduleInit) has a
sensor of its own -- a Network with none anywhere in it can never
populate its own pool, so a Launcher relying solely on it would
otherwise pass this check yet still never see a single contact.

Called periodically (not just once at init, see aegism_system_fnc_
moduleInit's re-resolution poll) so a Network gaining or losing its
only sensor-equipped member is reflected without a mission restart; the
warning message is only re-logged when it actually changes, so a
persisting problem doesn't spam the RPT log every poll.

Reads "AEGISM_system" (HashMap, key "hasSensor", aegism_system_fnc_
discoverCapabilities) and "AEGISM_network" (Object or objNull) from the
system object.
```

## aegism_system_fnc_resolveCrew

`addons/modules_system/functions/fn_resolveCrew.sqf`

```text
Resolves which Personality data applies to a given System vehicle --
same order as aegism_system_fnc_resolveEngagementSettings: the Site's
personality ("AEGISM_crew" on the vehicle or its Site logic) -- or its
linked group's Shared Site Coordinator's (aegism_fnc_
siteSettingsSource) -- or the defaults when standalone, then the
vehicle's own per-vehicle overrides on top (aegism_system_fnc_
applyOverrides).
```

## aegism_system_fnc_resolveEngagementSettings

`addons/modules_system/functions/fn_resolveEngagementSettings.sqf`

```text
Resolves which Doctrine data applies to a given System vehicle:
    1. the base -- the Site's doctrine (AEGISM_Module_Site's moduleInit
       copies it onto every member as "AEGISM_engagement", and it is
       also read from the Site logic via "AEGISM_network"), or, while
       the Site is linked with others under a Shared Site Coordinator,
       that Site's (aegism_fnc_siteSettingsSource), or the hardcoded
       defaults for a standalone vehicle;
    2. then the vehicle's own per-vehicle overrides on top, if it has
       any enabled (aegism_system_fnc_applyOverrides) -- each setting
       left on "Site setting" keeps the base value.
```

## aegism_system_fnc_resolveSettings

`addons/modules_system/functions/fn_resolveSettings.sqf`

```text
Resolves and caches a System's settings from its Site (or the defaults),
with its own overrides applied: its contact source ("AEGISM_
resolvedContactSource"), Doctrine ("AEGISM_resolvedEngagementSettings"),
Personality ("AEGISM_resolvedCrew") and the crew's timing/reliability
modifiers ("AEGISM_resolvedCrewMods") -- what the engagement loop and the
coordinator read every tick. Server only.

Run when the System initializes, every 5 seconds after (a Site synced or
unsynced later), and at once when a Zeus edit changes its Site's
settings or its own overrides.
```

## aegism_system_fnc_scanForRoles

`addons/modules_system/functions/fn_scanForRoles.sqf`

```text
One tick of the periodic discovery scan (registered in XEH_postInit.sqf)
that calls aegism_system_fnc_moduleInit on any vehicle not yet
processed. There is no role checkbox to read anymore -- every vehicle
in the mission gets exactly one discovery pass (aegism_system_fnc_
moduleInit itself decides whether it actually has any AEGIS-M-relevant
capability -- real radar, guided missiles, or a high-rate-of-fire gun --
and marks it processed either way so it's never re-scanned), which is
what makes "just take an existing radar/launcher/CIWS vehicle, no setup
needed" actually work.

Runs on every machine: a machine that simulates a vehicle's crew (a
headless client, a player's AI group) has to suppress that crew's own
targeting itself (disableAI is local). Everything else in aegism_
system_fnc_moduleInit is server only. Off the server, only vehicles
local to this machine are scanned -- the rest are nothing to do with it
(and are picked up if they become local later).
```

## aegism_system_fnc_turningRadar

`addons/modules_system/functions/fn_turningRadar.sqf`

```text
A vehicle's turning radar: an active radar that turns with a turret,
narrower than all round, on a turret no AEGIS-M weapon uses (the vanilla
radar truck's 120 degrees) -- the one AEGIS-M points (aegism_system_fnc_
radarSchedule) and hands the relay scan to (aegism_system_fnc_
radarRelay).
```

## aegism_system_fnc_zeusApplyOverrides

`addons/modules_system/functions/fn_zeusApplyOverrides.sqf`

```text
Applies a vehicle's AEGIS-M overrides as edited in Zeus (aegism_fnc_
zeusAttributeDialog), on every machine: each override's own Eden
expression runs (aegism_fnc_applyAttributeValues), so the same
"AEGISM_ovr_*" variables are set as by the vehicle's Eden attributes.
On the server the vehicle's settings are then re-resolved at once
rather than at its next 5-second poll, and the result is logged
(OVERRIDES).

Nothing applies unless "Override Site Settings" is ticked. Settings
entered with it off are saved and ignored -- five edits in one test went
that way, each a minimum range that never took effect -- so that's said
to whoever is in Zeus here (a hint and a chat line), and in the log, with
the settings it left out.
```
