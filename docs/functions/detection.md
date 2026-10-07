# detection: function notes

What each function does and why, in full: the descriptions that used to sit in each
function's header, moved out of the code on 2026-10-07. Each header keeps a short
description with its parameters, return value and examples. Change a function's
behaviour and its notes here change with it. This folder is not packed into the mod.

## aegism_detect_fnc_addContact

`addons/detection/functions/fn_addContact.sqf`

```text
Adds a candidate contact to a System's or Network's tracked-contact
list, gated by that object's resolved Doctrine target-class allowlist
(aegism_system_fnc_resolveEngagementSettings). A contact whose class is
not on the allowlist is never added.

Contacts are stored as a HashMap keyed by the contact's key (aegism_fnc_
contactKey: a munition's own tracker id, an aircraft's netId), with value
["confidence" -> Number, "class" -> String, "object" -> Object,
"firstSeen" -> Number (time), "lastSeen" -> Number, "isMunition" ->
Boolean]. Stored on the pool owner (System or Network) as
"AEGISM_pooledContacts". "confidence" is always 1 (the engine's own
sensors decide detected-or-not); the field is kept for the entry's shape.

Re-adding an already-pooled contact updates it in place, so "firstSeen"
stays accurate across refreshes. Every add/refresh stamps "lastSeen",
and "sources" (HashMap: which sensor kinds saw it -- "activeradar",
"ir", "visual", "passiveradar", "datalink" ... -> when each last did;
the debug overlays show the recent ones).
Pools are pruned by EXPIRY (aegism_detect_fnc_pruneStaleContacts), not by
any single sensor deciding it can no longer see something -- one radar
losing sight of a contact another radar still holds must not delete it.
"isMunition" marks Fired-pipeline contacts.
```

## aegism_detect_fnc_ammoThreatInfo

`addons/detection/functions/fn_ammoThreatInfo.sqf`

```text
What a fired ammo class means to AEGIS-M, cached per class
("AEGISM_cacheAmmoThreat"): its threat class (aegism_detect_fnc_
classifyAmmoClass), whether it's a carrier (CfgAmmo simulation
"shotSubmunitions") whose released projectiles must be followed, and for
a carrier how many it releases: the count in its submunitionConeType
(R_230mm_Cluster {"randomcenter", 50}, Cluster_155mm_AMOS 35), else its
submunitionCount, else 1 (R_230mm_HE releases its one R_230mm_fly). The
server's Fired handler runs this for every round fired in the mission;
for a bullet it's one lookup.
```

## aegism_detect_fnc_antiRadiation

`addons/detection/functions/fn_antiRadiation.sqf`

```text
Whether an ammo type is an anti-radiation missile, and its seeker: one
whose own sensors (CfgAmmo "Components >> SensorsManagerComponent >>
Components") include a passive radar -- componentType
PassiveRadarSensorComponent, which homes on a radar while it emits. The
vanilla HARM and Kh-58 (ammo_Missile_AntiRadiationBase) carry one: 60
degrees wide, 16 km. Cached per ammo type ("AEGISM_cacheAntiRadiation").
```

## aegism_detect_fnc_armInbound

`addons/detection/functions/fn_armInbound.sqf`

```text
An anti-radiation missile (aegism_detect_fnc_antiRadiation) seen by an
AEGIS-M vehicle's own sensors: marks the radars it threatens among what
that vehicle protects -- every live member of its Site and the Sites
linked with it (aegism_network_fnc_linkSites), or itself if standalone
-- so they shut down (Radar Emission, aegism_system_fnc_emconUpdate):

    - the radar it's homing on (missileTarget), if that's one of them;
    - otherwise each of them that's emitting inside its seeker's view:
      within its seeker's reach, and within half its seeker's arc of its
      line of flight.

A friendly or neutral one only counts while homing on one of them.

Each mark ("AEGISM_armInbound" on the radar: munition key -> [missile,
ammo class, until, why, sensor kinds that saw it, who saw it]) lasts
until the time the missile would take to reach that radar at its
current speed (at least AEGISM_ARM_MIN_SPEED m/s), plus
AEGISM_ARM_MARGIN s, and is renewed at every sighting; the radar comes
back sooner if the missile is gone. A radar newly marked is shut down at
once, not at its next once-a-second emission update.

Called for every sighting by the munition tracker (aegism_detect_fnc_
munitionCheck), whether or not the Site engages missiles: a Site that
doesn't still protects its radars.
```

## aegism_detect_fnc_blastMunitions

`addons/detection/functions/fn_blastMunitions.sqf`

```text
Destroys every tracked munition caught in a blast AEGIS-M set off: one
whose body (its box, aegism_intercept_fnc_bodyPass) is within the blast's
radius of where it went off -- the same rule an interceptor's own fuse
kills its target by. An intercept among a salvo takes the rockets flying
beside it too: POOK's PAC-3 (a 40 m blast) took five MLRS rockets in one
burst. That used to happen through the munitions' sensor proxies, which
the blast damaged; with those gone it's judged here.

Called for an interceptor going off and for the warhead of the munition
it destroyed (aegism_intercept_fnc_interceptHit), and for a lost
interceptor's self-destruct (aegism_intercept_fnc_interceptorLost). Not
carried on from the munitions it destroys in turn, and never an AEGIS-M
interceptor ("AEGISM_fromSystem"). Logged as BLAST-KILL.
```

## aegism_detect_fnc_classifyAmmoClass

`addons/detection/functions/fn_classifyAmmoClass.sqf`

```text
Pure CfgAmmo classifier, extracted from aegism_detect_fnc_classifyTarget
so the same inheritance-chain logic can classify an ammo classname
directly (e.g. from a magazine's "ammo" config entry) as well as a live
fired-projectile object -- used both for incoming-threat classification
and for aegism_system_fnc_discoverCapabilities classifying a vehicle's
OWN loaded ammo to determine whether it has launcher/CIWS capability.

Checks the CfgAmmo inheritance chain against the vanilla base classes
ShellCore (artillery/mortar shells -- only those with artilleryLock = 1;
direct-fire tank rounds also inherit ShellCore and are deliberately
excluded), BombCore (aircraft bombs), MissileCore (guided missiles), and
RocketCore (unguided rockets) -- inheritance is a more reliable
discriminator than simulation-string matching, since mods reuse
simulation types across different ammo roles but rarely break the base
class chain.

Cached per ammo class ("AEGISM_cacheAmmoClass"): this runs for every
round fired in the mission (the server's Fired handler), and from the aim
and fuse code every frame. The inheritance test is the engine's own
isKindOf on CfgAmmo (it used to be four CBA_fnc_inheritsFrom walks, each
an SQF loop up the whole chain).
```

## aegism_detect_fnc_classifyTarget

`addons/detection/functions/fn_classifyTarget.sqf`

```text
Classifies a candidate contact (a fired munition object, or a detected
platform) into one of the AEGIS-M target-class allowlist categories, so
aegism_detect_fnc_addContact can gate it against a Site's Doctrine
allowlist before it ever enters the tracked-contact list.

Munitions are classified via aegism_detect_fnc_classifyAmmoClass (CfgAmmo
inheritance). Platforms are classified via isKindOf against the vanilla
base classes Helicopter, Plane, and UAV (checked independently, since a
vehicle can be both e.g. a UAV helicopter).

The answer depends only on the object's type, so it's cached per type
("AEGISM_cacheTargetClass") -- the aim, fuse and selection code call this
every frame.
```

## aegism_detect_fnc_confidenceLoop

`addons/detection/functions/fn_confidenceLoop.sqf`

```text
Interval-based (not true per-frame, for performance) scan run once per
System with a sensor of its own that finds aircraft -- an active radar,
an IR or a visual sensor (aegism_system_fnc_discoverCapabilities
"hasSensor": the Spartan's launcher-mounted IR counts) -- that reads
the vehicle's OWN native sensor detections via getSensorTargets -- the
engine's own radar/IR/visual/passive/datalink simulation, already
running against that vehicle's real CfgVehicles sensor config -- rather
than AEGIS-M re-implementing its own LOS/distance/confidence estimate
on top of it. Detection is binary here (the engine already decided
detected-or-not using its own, more complete simulation); every
allowlisted, genuinely hostile (IFF, see aegism_detect_fnc_isHostile),
non-destroyed sensor target is pooled at full confidence, with the
sensor kinds the engine says saw it (getSensorTargets' 4th element,
e.g. "activeradar", "ir"). What the game's datalink passes on from
other vehicles ("datalink") only counts with the CBA setting Use
Datalink Contacts on: off (the default), a target only datalink reports
is skipped, aircraft and munitions alike. A target the game lists with
no sensor on it at all (lost, or only known of) is skipped too. A contact new to this
vehicle's pool is logged once (DETECT) with them. A contact only
passive radar hears is pooled, but only cues the Site's radars (aegism_
fnc_hasTrack). Contacts no longer refreshed by any
sensor expire (aegism_detect_fnc_pruneStaleContacts) rather than being
deleted the instant one sensor loses them.

Munitions are judged here too, on the same read, but by AEGIS-M: a
fired projectile is never a getSensorTargets result (CfgAmmo has no
radar/IR/visual target properties), so every tracked munition (aegism_
detect_fnc_trackMunition) is checked against this vehicle's sensors
from their own config (aegism_detect_fnc_sensorView, aegism_detect_fnc_
munitionSeen). One that's seen isn't a contact here: it's recorded as
seen by this vehicle, with the sensor kinds ("AEGISM_seenMunitions":
[read at, munition key -> sensor kinds]), and the munition tracker
(aegism_detect_fnc_munitionCheck) takes it from there -- IFF, whether it
threatens a Site, which pools it goes in. (The game's datalink carries
no munitions: Use Datalink Contacts is about aircraft.)

A detected contact is added/removed on both the scanning System's own
pool AND its Network's pool (if synced), so a Launcher/CIWS-only System
with no sensor of its own, relying purely on a Network's shared
contacts, still sees everything a sensor-equipped sibling detects.

2026-10-07: "AEGISM_otherTracks" on the vehicle, [time, [[object, class,
sensor kinds], ...]], rewritten on every read: the aircraft its own sensors
see that don't go into a pool -- not hostile, or hostile of a class it
doesn't engage. For a terminal's Interception page
(aegism_network_fnc_terminalPicture) and for orders onto them
(aegism_intercept_fnc_assignEngagements). Only isKindOf "Air" is classified
for it, so ground targets cost nothing.
```

## aegism_detect_fnc_destroyMunition

`addons/detection/functions/fn_destroyMunition.sqf`

```text
Destroys an incoming munition where it is (triggerAmmo: it detonates in
the air). The engine has no projectile-vs-projectile collision, so an
incoming round has no hitpoints of its own for a hit to act on: an
interceptor that reaches it (aegism_intercept_fnc_interceptHit) ends it
here.

A CARRIER (CfgAmmo simulation "shotSubmunitions") is triggered the same
way, but everything it releases is deleted the moment it's created (its
"SubmunitionCreated" event). Triggering a carrier doesn't destroy it --
it makes it release its payload on the spot: every MLRS R_230mm_HE
"kill" used to hand the Site a live R_230mm_fly warhead (1250m danger
radius) to shoot at again. The carrier is flagged "AEGISM_intercepted"
first so aegism_detect_fnc_watchProjectile doesn't start tracking the
payload.
```

## aegism_detect_fnc_firedEventHandler

`addons/detection/functions/fn_firedEventHandler.sqf`

```text
CBA_fnc_addClassEventHandler "Fired" callback, registered once on the
server for every unit and vehicle (see XEH_preInit.sqf). Hands every
threat-class munition (missile/rocket/bomb/artillery shell) or carrier
to aegism_detect_fnc_watchProjectile, which starts tracking it.

This runs for every round fired in the mission, so the first thing it
does is the cached ammo lookup (aegism_detect_fnc_ammoThreatInfo): a
bullet returns after that one lookup. It also returns straight away in
a mission with no AEGIS-M radar or Site at all.

An AEGIS-M System's own interceptors are tagged "AEGISM_fromSystem"
(never friendly threats; a HOSTILE side's radars still track them).
```

## aegism_detect_fnc_isHostile

`addons/detection/functions/fn_isHostile.sqf`

```text
IFF check: true if _otherSide is hostile to _ownSide per the mission's
own side relations (getFriend < 0.6, the engine's own enemy threshold).
A renegade (sideEnemy) is always hostile, as it is to every side in the
game. Civilian, empty, logic and unknown sides are never hostile -- an empty
parked aircraft, a civilian helicopter, or an AEGIS-M Site logic must
never become a contact.

Used for platforms (so a friendly jet the radar hasn't identified yet,
getSensorTargets relationship "unknown", isn't shot down -- real IADS
have IFF) and for munitions (so the battery's own outgoing interceptors
and friendly artillery are never tracked as incoming threats).
```

## aegism_detect_fnc_munitionCheck

`addons/detection/functions/fn_munitionCheck.sqf`

```text
One check of one tracked munition (aegism_detect_fnc_munitionTracker)
against every AEGIS-M vehicle with a sensor of its own (AEGISM_
allPoolOwners). Site logics are never checked directly -- they have no
sensor of their own; a Site only receives a munition from a member that
genuinely sees it.

Detection: the vehicle's own sensors saw the munition on their last
read (aegism_detect_fnc_confidenceLoop, "AEGISM_seenMunitions", four
times a second while a munition flies; a read older than
AEGISM_SEEN_FRESH s doesn't count) -- AEGIS-M's own judgement, from each
sensor's config (aegism_detect_fnc_munitionSeen): radar, IR and visual
each by their own range, arc, line of sight, fog, night, ground clutter
and speed limits, an active radar only while it emits. The contact
records the sensor kinds that saw it ("activeradar", "ir", "visual").

Where it goes:
    standalone vehicle - its own pool
    networked vehicle - its Site's pool (if the class is one this
        vehicle's own settings engage). Once one member of a Site has
        judged the munition, the Site's other members aren't judged
        again this check; those that see it too only add their sensor
        kinds to the contact (a radar and a Spartan's IR both show).
        (A networked vehicle's own pool isn't kept for munitions:
        nothing engages from it.)

IFF and threat:
    hostile shooter - tracked outright, unless the Site's doctrine
        engageOnlyThreats is on (the default): then only while it's a
        threat to a Site vehicle or to a Site's protected area (aegism_
        detect_fnc_munitionThreat) --
        a shell or rocket predicted to land within the threat radius, a
        missile guided at a Site vehicle or flying on a line that passes
        within it, a bomb whose fall or line of flight does. One landing
        3km away, or a missile flying at something else, isn't worth a
        single round, and never becomes a contact, a claim or a burst.
        Logged once (IGNORED); re-judged every check, so one that turns
        toward the Site is picked up.
    friendly/neutral shooter - only while predicted to hit the Site, and
        only if its doctrine engageFriendlyThreats is on. An AEGIS-M
        System's own interceptors ("AEGISM_fromSystem") never are.

An anti-radiation missile one of a Site's vehicles sees also marks the
radars it threatens, so they shut down (aegism_detect_fnc_armInbound),
whatever the Site engages.
```

## aegism_detect_fnc_munitionSeen

`addons/detection/functions/fn_munitionSeen.sqf`

```text
Which of a vehicle's sensors see one tracked munition right now, against
the vehicle's sensor view for this read (aegism_detect_fnc_sensorView).
A sensor sees it if all of these hold, cheapest first:
    - it's within the sensor's reach, and its speed and height above the
      terrain are within what the sensor can track at all;
    - it's inside the sensor's horizontal and vertical arcs, measured
      from where the sensor looks;
    - against the sky (seen from below: it's above the sensor) it's
      within the sensor's AirTarget range. Seen from above, the line
      from the sensor through it is carried on to the ground or the sea
      behind it: with ground there it has to be within the GroundTarget
      range, and clear of ground clutter -- farther from that ground
      than groundNoiseDistanceCoef x the sensor-to-ground distance (at
      most maxGroundNoiseDistance), unless it's fast: at or above
      maxSpeedThreshold it always shows, and between the two thresholds
      the clutter shrinks in proportion. (Munitions fly at hundreds of
      m/s; the vanilla radar's thresholds are 21 and 28 m/s.) Ground
      behind a munition that's above the sensor (a mountainside) isn't
      looked for;
    - the vehicle has a line of sight to it: no terrain between them, and
      nothing else in the first AEGISM_LOS_OBJECT_REACH m (the line
      command's own limit). One ray per vehicle, not per sensor, and a
      clear one isn't traced again for AEGISM_LOS_REUSE s (sensing.hpp).
A munition is hot for its whole flight (its motor, the air it pushes
through), so IR sees it as radar does.
```

## aegism_detect_fnc_munitionThreat

`addons/detection/functions/fn_munitionThreat.sqf`

```text
Whether a munition is a threat to what a pool owner protects: every live
member of its Site (of every Site linked with it, aegism_network_fnc_
linkSites), or just itself if standalone. Asked of a friendly or
neutral munition (engaged only if so), and of any hostile munition when
the Site only engages threats (aegism_detect_fnc_munitionCheck).

    missile - its own seeker target (missileTarget) is one of the
        protected vehicles ("guided"), or its current line of flight
        passes within the threat radius of one, closing ("heading"), or,
        its target not readable (ACE guidance, a laser spot), one is
        inside its seeker's view: within its seeker cone (aegism_detect_
        fnc_seekerCone) of its line of flight, closing, and its angle off
        that line no wider than at the last check ("seeker"). An
        unguided one (a shotMissile that can't steer, like the vanilla
        Rocket_04_HE_F) is judged like a rocket, its fall included.
    bomb - its line of flight passes within the threat radius, or its
        predicted fall lands within it
    artillery round, rocket - its predicted impact falls within the
        threat radius of one of them ("ballistic"). Prediction is a
        drag-free ballistic fall from the current position and velocity
        to each protected vehicle's own height. Vanilla artillery really
        is drag-free (Sh_155mm_AMOS and the MLRS R_230mm_fly have
        airFriction 0, mortar rounds ~-0.0003), so this is accurate for
        the rounds that matter; a still-burning rocket is under-predicted
        until burnout, and re-evaluated every tracker tick anyway.

Protected areas (a hostile munition's verdict only, _useAreas): each
Site of the group also protects a circle round its own module, of the
Site's Protected Area Radius (protectRadius; the Shared Site
Coordinator's when there is one; 0 = none). A munition is a threat
("area") if it's guided at anything inside one (an ammo truck, a
building), its descending line of flight comes down inside one (a
missile or bomb), or its predicted fall lands inside one (a round,
rocket, bomb or unguided missile) -- each to the area centre's height.
The protected vehicles' own tests above come first.

Threat radius: the doctrine friendlyThreatRadius if > 0, else the
munition's own CfgAmmo dangerRadiusHit (the radius the game's AI keeps
friendlies out of, e.g. 750m for 155mm, 1250m for the MLRS rocket,
1000m for bombs), else its blast radius (indirectHitRange) when
dangerRadiusHit is unset (-1). A carrier round uses its payload's
radius (see below).
```

## aegism_detect_fnc_munitionTracker

`addons/detection/functions/fn_munitionTracker.sqf`

```text
One frame of the munition tracker: works through every tracked munition
("AEGISM_trackedMunitions", aegism_detect_fnc_trackMunition), checking
each one that's due (aegism_detect_fnc_munitionCheck) and then again
AEGISM_TRACK_INTERVAL s later. Munitions come in at their own fire
times, so a barrage's checks are spread over frames rather than all
landing on one.

A munition that's gone (impact, intercept, leaves simulation) is
removed from every pool it was added to, by its own key -- it used to be
looked up by netId after it was already deleted, which never matched.
One that never came into any Site's picture is logged (UNSEEN): whether
any sensor saw it, and how near and how low it came. An anti-radiation missile's end is logged
(ARM-END): what it was homing on at its last check, how far it then was
from the nearest AEGIS-M radar and whether that radar was emitting, and
whether any AEGIS-M sensor saw it.
```

## aegism_detect_fnc_projectileCreated

`addons/detection/functions/fn_projectileCreated.sqf`

```text
AEGIS-M's catch for munitions nothing reported fired: the server's
"ProjectileCreated" mission event (Arma 3 2.18), which comes for every
projectile however it was made. Munitions are otherwise found through
each shooter's "Fired" event (aegism_detect_fnc_firedEventHandler),
which misses two kinds:
    - a shell spawned by script (createVehicle: Zeus ordnance, a
      mission's artillery effects), which nobody fired;
    - one from a shooter whose Fired event handlers another mod removed
      (removeAllEventHandlers).
A threat-class munition (aegism_detect_fnc_ammoThreatInfo; a bullet
returns after that one cached lookup) is looked at the next frame: one
the Fired path has handled by then is marked ("AEGISM_seen", aegism_
detect_fnc_watchProjectile), and anything else is tracked here, from
its shot parents -- a shell with none has no side (sideUnknown): never
hostile by IFF, so it's engaged as a friendly round would be, only if
it threatens a Site (doctrine: Engage Friendly Threats). Logged once
per ammo type (MUNITION-UNREPORTED).

The event handler is put back if something removes it (aegism_system_
fnc_guardSystems).
```

## aegism_detect_fnc_pruneStaleContacts

`addons/detection/functions/fn_pruneStaleContacts.sqf`

```text
Removes contacts from a pool (System or Site) whose object is gone/dead
or that no sensor has refreshed for AEGISM_CONTACT_STALE_TIME seconds.
This is the ONLY way a contact leaves a shared Site pool while still
alive -- see aegism_detect_fnc_addContact for why individual sensors no
longer delete from shared pools directly.

AEGISM_CONTACT_STALE_TIME is three platform scan intervals (the radar
confidence loop runs at 1s, the munition tracker at 0.5s), so a single
missed scan never drops a contact, but a contact every sensor has lost
is gone within a few seconds.
```

## aegism_detect_fnc_removeContact

`addons/detection/functions/fn_removeContact.sqf`

```text
Removes a contact from a System's or Network's tracked-contact pool
(e.g. once a tracked munition is destroyed or lands). Companion to
aegism_detect_fnc_addContact. Takes the contact's key (aegism_fnc_
contactKey) or the object: a munition is usually already deleted when
this is called, and a deleted object no longer tells you its key.
```

## aegism_detect_fnc_seekerCone

`addons/detection/functions/fn_seekerCone.sqf`

```text
How far off its line of flight an incoming missile's guidance can be on
a target -- what it could be homing on when its target can't be read
(aegism_detect_fnc_munitionThreat). From its config, cached per ammo
type ("AEGISM_cacheSeekerCone"):

    ACE-guided (the ammo declares its own ace_missileguidance class,
        enabled = 1) - its ACE seekerAngle, a half-angle
    engine-guided (CfgAmmo simulation shotMissile, maneuvrability > 0) -
        missileKeepLockedCone, else missileLockCone (the same reading as
        aegism_intercept_fnc_missileAgility): vanilla M_Scalpel_AT 60,
        Missile_AGM_01_F 20, Missile_AGM_02_F 30
    unguided - a shotMissile that can't steer (maneuvrability 0 and no
        ACE guidance: vanilla Rocket_03_HE_F, Rocket_04_HE_F), or any
        other simulation
```

## aegism_detect_fnc_sensorAxis

`addons/detection/functions/fn_sensorAxis.sqf`

```text
World-space direction one of a vehicle's sensors is looking along right
now (its arcs are measured from it). A hull-fixed sensor looks along the
hull. A turret-mounted one (its animDirection is a turret's gun or body,
aegism_system_fnc_discoverCapabilities) looks where that turret points:
the turret's barrel direction (aegism_intercept_fnc_barrelDirection --
weaponDirection of the turret's first weapon, then its barrel memory
points; the vanilla radar's turret carries "FakeWeapon" for this). So a
radar AEGIS-M turns (aegism_system_fnc_radarSchedule) sees where it has
actually got to, not where it was told to go.

If the turret's direction can't be read, the hull's is used, and that's
logged once per vehicle type and turret (SENSOR-AIM).
```

## aegism_detect_fnc_sensorView

`addons/detection/functions/fn_sensorView.sqf`

```text
What one vehicle's sensors can see of a munition right now: worked out
once per sensor read (aegism_detect_fnc_confidenceLoop), then every
tracked munition is judged against it (aegism_detect_fnc_munitionSeen).

The game's sensors can't target a projectile at all (CfgAmmo has no
radar/IR/visual target properties), so AEGIS-M judges munitions itself,
by the rules the engine's sensors work to and from the same config (BI's
Sensors config reference; aegism_system_fnc_discoverCapabilities reads
it). Each munition used to carry an invisible vehicle for the game's
sensors to find instead, which they weren't built for: radars reported
nothing for ~2.5 s after coming on, the vehicle didn't always stay with
its munition, showed no speed while attached (so low munitions vanished
in ground clutter), and could be shot. For each sensor that finds
things in the air -- radar, IR, visual:
    on - a radar only while the vehicle's radar emits (isVehicleRadarOn:
        Radar Emission, aegism_system_fnc_emconUpdate); none through fog
        thicker than its maxFogSeeThrough
    where it looks - along the hull, or where its turret points
        (aegism_detect_fnc_sensorAxis), tilted down by its aimDown; its
        horizontal and vertical arcs either side of that
    how far - against the sky its AirTarget range, against the ground
        its GroundTarget range: the smallest of maxRange, the object
        view distance x objectDistanceLimitCoef and the view distance x
        viewDistanceLimitCoef (where those are set), never less than
        minRange; scaled by its nightRangeCoef toward night (sunOrMoon:
        1 by day, 0 at night) and by the munition's signature
        (AEGISM_MUNITION_SIGNATURE, sensing.hpp)
    ground clutter and limits - passed on for each munition: its
        groundNoiseDistanceCoef / maxGroundNoiseDistance and
        min/maxSpeedThreshold, min/maxTrackableSpeed and min/max
        TrackableATL
On a dedicated server the view distances are the server's.
```

## aegism_detect_fnc_trackMunition

`addons/detection/functions/fn_trackMunition.sqf`

```text
Starts tracking a freshly-fired, already-classified munition.

Gives the munition its own contact key ("AEGISM_contactKey" = "m<n>", see
aegism_fnc_contactKey) and adds it to the list the single munition
tracker works through (aegism_detect_fnc_munitionTracker: every tracked
munition checked every AEGISM_TRACK_INTERVAL s, spread over frames by
fire time). What a check does (seen by a sensor, IFF, whether it
threatens a Site): aegism_detect_fnc_munitionCheck.

Whether a sensor sees it is AEGIS-M's own judgement, from each sensor's
config (aegism_detect_fnc_munitionSeen), made on every vehicle's sensor
read (aegism_detect_fnc_confidenceLoop) from the moment it's tracked: a
fired projectile can't be a target of the game's sensors itself (CfgAmmo
has no radar/IR/visual target properties). All on the server, whoever
crews the vehicles. An AEGIS-M System's own interceptor is only watched
for if some AEGIS-M vehicle is hostile to the side that fired it
("watched"): nobody else would track it.
```

## aegism_detect_fnc_watchProjectile

`addons/detection/functions/fn_watchProjectile.sqf`

```text
Starts tracking one fired projectile if it classifies as a threat
(aegism_detect_fnc_trackMunition), and follows it through submunition
handoffs.

A carrier (CfgAmmo simulation "shotSubmunitions") is deleted mid-flight
and replaced by the projectile(s) it releases. The MLRS rocket
R_230mm_HE, for example, becomes R_230mm_fly after triggerDistance =
500m, which then flies the rest of the way. Without following that, the
tracker saw the carrier vanish and dropped the contact for good. The
handoff uses the projectile "SubmunitionCreated" event (as ACE's CLGP
code does) and runs this same function on each released projectile, so
multi-stage carriers work too. Only a carrier that releases ONE round
(aegism_detect_fnc_ammoThreatInfo, from its config) is followed: a
cluster carrier's dozens of bomblets (R_230mm_Cluster 50,
Cluster_155mm_AMOS 35) can't be intercepted one by one, and every tracked
round is checked against every sensor. Released projectiles that don't classify are
ignored the normal way anyway (Mo_cluster_AP has no artilleryLock).
```
