# main: function notes

What each function does and why, in full: the descriptions that used to sit in each
function's header, moved out of the code on 2026-10-07. Each header keeps a short
description with its parameters, return value and examples. Change a function's
behaviour and its notes here change with it. This folder is not packed into the mod.

## aegism_fnc_applyAttributeValues

`addons/main/functions/fn_applyAttributeValues.sqf`

```text
Sets an object's Eden attributes from script, the way Eden itself does:
each attribute's own "expression" runs with _this = the object and
_value = the new value. Used by the Zeus dialogs (aegism_fnc_
zeusAttributeDialog), so a Zeus edit sets exactly the same variables an
Eden edit would.

Each attribute's variable is cleared first: an override left on "Site
setting" (or blank) has an expression that sets nothing, and has to go
back to nil (inheriting from the Site) rather than keep its old value.
```

## aegism_fnc_contactKey

`addons/main/functions/fn_contactKey.sqf`

```text
The key a contact is stored under in every pool and claims HashMap.

    munition - the id the munition tracker gave it when tracking started
        ("AEGISM_contactKey", aegism_detect_fnc_trackMunition): "m<n>"
    anything else (aircraft) - its netId

Munitions don't use netId: the server's copy of a projectile fired on
another machine isn't a network object, and netId isn't guaranteed to
tell such local objects apart -- two shells sharing one key would share
one pool entry, and the Site would engage them one at a time.
```

## aegism_fnc_debugCheckSite

`addons/main/functions/fn_debugCheckSite.sqf`

```text
On-demand sync/capability sanity check, meant to be run from the Arma
debug console (or any script) while testing a mission, rather than
reading RPT log output after the fact -- answers "is my radar/launcher
actually linked to this Site, and did AEGIS-M even recognize it as
something it can use" directly and immediately.

With no argument, reports on every Site currently registered
(AEGISM_allPoolOwners' Network-type entries, i.e. every placed and
activated AEGISM_Module_Site). With a specific Site logic object, reports
on just that one.

For each Site: member count, and per member -- its class, whether
AEGISM_network actually points back at this Site (catches a vehicle that
LOOKS synced in Eden's sync-line view but whose module init never ran or
targeted a different Site, e.g. from a stale isGlobal netId issue), and
its discovered capability (its sensors with reach and arc, launcher
weapon count, CIWS weapon count) -- or "NOT AN AEGIS-M SYSTEM" if
aegism_system_fnc_moduleInit never found it to have any qualifying
capability at all (the single most common reason "nothing happens": a
vehicle synced to the Site that AEGIS-M itself never recognized, e.g.
wrong vehicle, no real sensor/missile/CIWS loadout).

Prints to hint (visible in-game immediately) AND diag_log (so it's also
captured in the RPT for later reference) -- deliberately not gated
behind the "aegism_main_debugDraw" CBA setting, since this is a one-shot
manual check a mission tester runs on demand, not a continuous overlay.
```

## aegism_fnc_debugDraw

`addons/main/functions/fn_debugDraw.sqf`

```text
Per-frame 3D debug overlay of AEGIS-M's live detection/engagement
state, drawn straight from the variables the pipeline itself reads and
writes -- what's on screen is what the mod is doing, not a separate
simulation of it. CBA setting "aegism_main_debugDraw" (client-side, no
gameplay effect). Only has data where the engagement pipeline runs
(singleplayer, Eden Preview, a hosted game's host).

Built to be read at a glance: one colour scheme, one label per thing,
labels stacked (at a spacing that scales with distance, so they stay
apart at any range) rather than drawn on top of each other.

    Colour = an engagement's state (aegism_fnc_statusStyle): queued
        blue, assigned green, reacting / slewing amber, reloading
        orange, range hold teal, firing red, in flight gold, no LOS /
        no solution purple, crew failed / fire held / no ammo grey.

    Contact - one icon per contact, however many pools hold it: a
        plane, a helicopter, or a target mark for a munition or drone.
        White while nothing is on it, otherwise the colour of the most
        urgent engagement on it. One short label: its class, for an
        incoming munition seconds to impact (the coordinator's own
        figure, aegism_intercept_fnc_assignEngagements), and the sensor
        kinds that saw it in the last 3 s ([RDR IR], aegism_fnc_
        sensorTags).

    Engagement - a line from the weapon to its target in the state's
        colour. Waiting ones (queued behind the launcher's current
        target, missiles already in flight, held) are faint, so a
        launcher's queue doesn't drown out what it's actually doing. A
        CIWS held back by its Engagement Mode (Last Resort, Planned)
        is a dashed orange line.

    System - a shield over each AEGIS-M vehicle (a radar mark for a
        radar-only one), and stacked labels:
        1. its name
        2. network and sensor status (light blue): its own sensors, the
           longest of each kind -- reach, arc, "turret" if it turns with
           one, and for a radar its emission (Radar Emission, aegism_fnc_
           emconText: EMITTING, SILENT, SHUT DOWN, AI: ..., and why; a
           silent radar sees nothing, aircraft or munitions), how many
           contacts its own sensors see now ("sees 2", "hears 1" for
           passive radar alone) -- and its Site's sensor vehicles and
           tracks, or STANDALONE with its own tracks. NO SENSOR ON SITE
           in orange when networked but no member of its Site has a
           sensor of its own (aegism_system_fnc_resolveContactSource).
        3. each weapon role with rounds left and what it's doing ("MSL
           4: firing +3 queued", "GUN 680: slewing"), or NO AMMO (red)
        Name and weapons in its most urgent engagement's colour; grey
        while idle.

    Sight - a faint light-blue line from each sensor vehicle to each
        contact its own sensors saw in the last 3 s (a lighter violet
        one if only its passive radar hears it). A Site's contacts are
        every member's together; this shows which vehicle sees which.

    Radar - a faint ring at each radar's own detection range: blue while
        the AI decides its emission, amber while AEGIS-M has it emitting,
        grey while it keeps it silent, red while it's shut down for an
        anti-radiation missile.

    A contact only passive radar hears is tagged CUE ONLY: it cues the
    Site's radars, but nothing engages it (aegism_fnc_hasTrack).
    Linked Sites (aegism_network_fnc_linkSites) - a vehicle's Site status
        reads "(LINKED, n Sites by n links, coordinating / coordinated by
        ...)"; a vehicle forming a link is tagged LINK; a vehicle-to-
        vehicle link, or two modules synced to each other, is a dashed
        cyan line between them. Sensor codes: RDR radar, PAS passive, IR,
        VIS visual; DL a vehicle with none, fed by its Site.

    Not active - a vehicle AEGIS-M found capable but hasn't activated
        (deferred until synced, AEGISM_deferredSystems): grey, with
        "NOT ACTIVE:" and why -- e.g. a launcher with no sensor of its
        own placed without a Site.

Reads only published state (AEGISM_allPoolOwners, AEGISM_allSystems,
AEGISM_system, AEGISM_pooledContacts, AEGISM_seenMunitions, AEGISM_
claims, AEGISM_withheldCiws, each System's AEGISM_turrets
"standalone_<role>" states)
and calls no function of the addons that publish it: this lives in
aegism_main, which they all depend on.
```

## aegism_fnc_debugHint

`addons/main/functions/fn_debugHint.sqf`

```text
Live status board in the hint box, refreshed once a second while the
CBA setting "AEGIS-M > Debug > Site Status Hint" is on: the Site nearest
the camera in detail, and everything else in summary (aegism_fnc_
statusBoard, which says what's on it). The hint box cuts a long board,
so only the nearest AEGISM_HINT_MAX_CONTACTS contacts are listed.

Reads the same server-side variables the engagement pipeline runs on,
so it only has data where that pipeline runs: singleplayer, Eden
Preview, or the host of a hosted game (not a client of a dedicated
server -- a Site's status terminal, aegism_network_fnc_terminalOpen,
works there).
```

## aegism_fnc_emconText

`addons/main/functions/fn_emconText.sqf`

```text
A radar vehicle's emission state for the debug overlays and the status
board, from what aegism_system_fnc_emconUpdate records on it ("AEGISM_
emcon") and whether its radar really is emitting (isVehicleRadarOn):

    EMITTING (amber) - lit by AEGIS-M: always on, cued, guiding missiles,
        holding after its last contact, or an intermittent search burst
    SILENT (grey) - silent until cued, or between intermittent bursts
    SHUT DOWN (red) - an anti-radiation missile is inbound on it
    AI: EMITTING / AI: SILENT - Radar Emission "AI decides": AEGIS-M
        leaves it to the AI, and this is what the AI chose

The detail says why ("cued: ...", "fire control: ...", "silent in 6s").
If the radar hasn't followed what AEGIS-M set within 2 s, the detail
says so.
```

## aegism_fnc_hasTrack

`addons/main/functions/fn_hasTrack.sqf`

```text
Whether a pooled contact is held by a sensor that tracks it: anything
but passive radar alone. Passive radar only hears an emitter's radar,
which gives a bearing but no range. A contact that only passive radar
has heard in the last 3 s (the pools' own contact expiry, aegism_detect_
fnc_pruneStaleContacts) cues the Site's radars (Radar Emission, aegism_
system_fnc_emconUpdate), but no weapon is assigned to it until a radar,
IR or visual sensor holds it.

A contact with no sensor kinds recorded, or none in the last 3 s, counts
as tracked.
```

## aegism_fnc_perfLog

`addons/main/functions/fn_perfLog.sqf`

```text
Writes one PERF line to the RPT summarising what AEGIS-M did on this
machine since the last one (the counters in AEGISM_perfCounts, see
perf.hpp), then resets them. Registered on the server every
AEGISM_PERF_INTERVAL seconds (main XEH_postInit) while the CBA setting
"RPT Performance Summary" is on. Silent when nothing happened, so an
idle mission logs nothing.

Columns (per interval):
    coord - Site coordinator runs, total and worst single run (ms);
        the total by part -- reviewing the claims it has, listing
        weapons and timing contacts with the layered-reserve plan,
        assigning; then, apart from the runs, the time spent in the
        frames between them working out launcher shots ahead, how many
        such frames, and how many looks at a munition the runs put off
        for that
    ticks - engagement loop ticks that had work to do
    aim - full CIWS/launcher aim solves / CIWS per-frame steers
    rounds - CIWS rounds tracked, per-frame checks near the target,
        frames skipped while still in flight, total ms in the round
        manager
    canEngage - engageability checks (coordinator + standalone)
    select - standalone full target re-evaluations
    fired - Fired events seen / threats among them / ignored as landing
        clear of every Site
    tracker - munition tracker checks, total ms
    sensors - vehicles' sensor reads (aegism_detect_fnc_confidenceLoop):
        munitions seen across them (aegism_detect_fnc_munitionSeen), the
        line-of-sight rays traced for that, total ms
    plan - reserve plan cache hits / rebuilds / intercept solves it ran
        (aegism_intercept_fnc_assignEngagements' _fnPlanShot)
    openFire - CIWS open-fire range recalculations (aegism_intercept_
        fnc_openFireRange; at most one a second per gun and target type)
    fps - the server's frames over the whole interval, timed every
        frame (main XEH_postInit): average fps, the worst frame (ms),
        and how many frames took longer than PERF_SLOW_FRAME_MS (below
        20 fps)
    clock - how far the mission clock (CBA_missionTime, which AEGIS-M
        runs on) and the game's own (time) each moved in the interval,
        and the real time it took. With the game fast-forwarded the
        first two outrun the third; if the game's falls behind the
        mission clock's, the engine isn't keeping the pace it's set and
        everything predicted on the mission clock comes late. (The one
        place AEGIS-M reads time: to set the two side by side.)
```

## aegism_fnc_pollSyncedObjects

`addons/main/functions/fn_pollSyncedObjects.sqf`

```text
Generic live-resync helper for AEGIS-M's push-model modules
(EngagementSettings, Crew, Network): a placed module's own init
function runs exactly once, at its own activation, and pushes its data
to whatever is synced to it AT THAT MOMENT -- a sync line drawn or
erased afterward (e.g. a Zeus operator re-syncing an EngagementSettings
module to an additional System mid-mission) does not re-trigger that
init function, since nothing new is being activated. Nothing in vanilla
Arma raises an event for a sync-graph change either, so the only way to
detect one is to poll synchronizedObjects, which always reflects the
CURRENT live graph regardless of when a link was drawn.

Registers a low-frequency, server-only per-frame handler (mirroring
every other AEGIS-M loop's isServer gating, see aegism_system_fnc_
moduleInit) that diffs _logic's synchronizedObjects against last poll's
set: _applyFn runs once for each newly-synced object, _clearFn once for
each newly-unsynced one. Both are called with explicit arguments rather
than relying on closure capture of the caller's private variables --
correct here, since the code runs from a later, separate PFH tick after
the calling script has already returned, by which point any of its
privates are gone; only what's threaded through _data (or bound into
_applyFn/_clearFn's own call arguments) survives to reach them.

The initial "last poll set" is seeded from synchronizedObjects _logic
AT REGISTRATION TIME (i.e. whatever's already synced when the caller's
own one-time init runs), not an empty array -- a caller (e.g. aegism_
network_fnc_moduleInit) that already applies its data to every
initially-synced unit directly, before ever calling this function, would
otherwise have _applyFn redundantly re-run against every one of them on
this poll's first tick. Harmless for an idempotent _applyFn (repeating a
setVariable/pushBackUnique changes nothing), but this is a generic
helper other callers may use with a non-idempotent _applyFn, so it's
seeded correctly rather than relying on every future caller happening to
write one.

If _logic itself is deleted (e.g. a Zeus operator deletes a Network mid-
mission), _onDeletedFn is called once and the handler removes itself.
```

## aegism_fnc_scaledRange

`addons/main/functions/fn_scaledRange.sqf`

```text
Applies the active AEGIS-M range scale setting (Arma Scale / Real World
Scale / Custom Multiplier) to a real-world-sourced base range value.
Every range-consuming module (System, EngagementSettings, detection loop)
must resolve its ranges through this function rather than reading its
configured base value directly, so the scale setting stays a single
global multiplier applied in one place.

Reads the settings' own global variables (CBA keeps every setting's
value in the missionNamespace variable of the same name) rather than
CBA_settings_fnc_get: this runs inside every envelope check.
```

## aegism_fnc_sensorTags

`addons/main/functions/fn_sensorTags.sqf`

```text
Short tags for the sensor kinds that saw a contact recently, for the
debug overlays: a pool entry's "sources" (aegism_detect_fnc_addContact
-- sensor kind -> when it last saw it), keeping those within the pools'
own contact expiry (3 s, aegism_detect_fnc_pruneStaleContacts).

    activeradar RDR, passiveradar PAS, ir IR, visual VIS, datalink DL;
    any other kind the engine reports, upper case.
```

## aegism_fnc_setWeaponAiSuppressed

`addons/main/functions/fn_setWeaponAiSuppressed.sqf`

```text
Enables or disables a specific turret's own crewman's independent AI
targeting/engagement (disableAI "TARGET"/"AUTOTARGET"/"FIREWEAPON"), so that turret's
weapon only ever fires when AEGIS-M's own aegism_intercept_fnc_fireWeapon
commands it via BIS_fnc_fire -- a real fire-control gate, not just AEGIS-M
picking targets in parallel with a crew that can ALSO independently
decide to shoot on its own. Without this, a launcher/CIWS turret's crew
can engage a target the moment they spot it themselves, completely
outside AEGIS-M's own assignment/ammo/reaction-time/cooldown/LOS/
reliability gates -- which is indistinguishable, from the outside, from
AEGIS-M "not preventing" a shot it never actually decided to take.

"AUTOTARGET" stops independent target ACQUISITION (the AI won't scan
for/acquire a new target on its own); "TARGET" stops independent
ENGAGEMENT/reaction to an already-known target. "FIREWEAPON" stops the
unit firing its weapon at all: with only the first two off, a launcher
gunner given an aircraft for AEGIS-M's shot (aegism_intercept_fnc_
gunnerLock, so the aircraft gets its missile warning) went on to fire
missiles of its own every couple of seconds, some 3.5 s later
(UNCOMMANDED-FIRE) -- even taken off the target again and told to hold
fire. All three are disabled together since the goal is to prevent ANY
self-initiated fire. BIS_fnc_fire and lockCameraTo (AEGIS-M's own
aim/fire commands) are separate scripted command paths.

Scoped to ONE turret's crewman (via turretUnit), not the whole vehicle
-- a Tigris/ZSU-style vehicle's coax MG or a multi-turret vehicle's other
stations are untouched; only the specific turret(s) AEGIS-M discovered
as a launcher/CIWS weapon should ever be suppressed.

disableAI's disabled state is tied to the UNIT object, not the turret/
vehicle context (confirmed against BIKI) -- it follows that crewman if
they change seats or eject, and is NOT automatically cleared by vehicle
destruction. It's restored only when a vehicle is unsynced from a Site
and isn't a System in its own right (aegism_network_fnc_moduleInit); a
destroyed System's crew stays suppressed.
```

## aegism_fnc_siteSettingsSource

`addons/main/functions/fn_siteSettingsSource.sqf`

```text
The Site whose settings apply to a Site's vehicles: the Site itself --
or, while it's linked with others (aegism_network_fnc_linkSites) and one
of them is ticked "Shared Site Coordinator", that one. Its doctrine,
crew and alarm settings then take precedence over every other Site of
the group (each vehicle's own overrides still apply on top).
```

## aegism_fnc_statusBoard

`addons/main/functions/fn_statusBoard.sqf`

```text
The AEGIS-M status board, as structured text:

    - one Site in detail: every member vehicle with its roles ([R]adar
      [I]R [V]isual sensor, [L]auncher [C]IWS), a colour-coded status,
      its current target and ammo. A Site linked with others (aegism_
      network_fnc_linkSites) is shown with its whole group: which Site
      coordinates it and whose settings apply, what links them, and each
      Site's vehicles under its own heading (the coordinator first, the
      one asked about marked "this terminal" or "nearest"; a vehicle
      linking them shown once, LINK)
    - with _everything, other Sites one line each, a linked one with
      what it's linked with and who coordinates
    - with _everything: every other Site as a one-line summary,
      standalone (unsynced) Systems one line each, and the vehicles
      AEGIS-M found capable but hasn't activated (deferred until synced
      to a Site), with why -- e.g. a launcher with no sensor of its own
      placed without a Site
    - under each radar vehicle, its emission (Radar Emission, aegism_
      fnc_emconText): RDR EMITTING / SILENT / SHUT DOWN and why
    - last, the detailed Site's tracked contacts, the sensor kinds that
      saw each ([RDR IR], aegism_fnc_sensorTags; "cue only" for one only
      passive radar hears, which nothing engages) and the weapons on
      each (the longest section, so it's the one a hint box cuts)

Each engagement shows in its own state's colour (aegism_fnc_statusStyle
-- the state the engagement loop records on it every tick): blue QUEUED
behind another on its launcher, amber REACTING/SLEWING/LOCKING, orange
RELOADING, teal RANGE HOLD, red FIRING, gold IN FLIGHT, purple NO LOS /
NO SOLUTION, grey CREW FAILED / FIRE HELD / NO AMMO. A vehicle with
nothing assigned: green READY, yellow TRACKING (sensor with contacts),
grey NO AMMO, dark grey DESTROYED.

Shown by the Site Status Hint (aegism_fnc_debugHint: the Site nearest
the camera, and everything else) and by a Site's status terminal
(aegism_network_fnc_terminalRequest: that Site alone).

Reads the same server-side variables the engagement pipeline runs on,
so it only has data where that pipeline runs: singleplayer, Eden
Preview, or the server (a terminal's board is built there and sent to
the player using it).
```

## aegism_fnc_statusStyle

`addons/main/functions/fn_statusStyle.sqf`

```text
How the debug overlays (aegism_fnc_debugDraw, aegism_fnc_debugHint) show
one engagement's state -- the "status" aegism_intercept_fnc_
engagementLoop records on it every tick -- so each munition queued on a
launcher shows where it actually is, not one colour for the lot:

    queued - waiting its turn: the launcher is on another first (blue)
    assigned - just assigned, not worked yet (green)
    reacting - crew reaction time (amber)
    slewing - turret swinging onto it (amber)
    locking - on it, waiting for its gunner's lock on an aircraft (amber)
    reloading - shot interval / burst pause / lost fire cycle (orange)
    rangeHold - a gun tracking it, beyond its open-fire range (teal)
    cued - a gun on it before it's in reach, holding until it is (teal)
    firing - a gun's burst on it, or a missile just launched (red)
    inFlight - salvo away, missiles guiding (gold)
    losBlocked / noSolution - can't see it / can't reach it (purple)
    crewFailed / held / noAmmo - crew missed its cycle, fire held, empty
        (grey)
```

## aegism_fnc_zeusAttributeDialog

`addons/main/functions/fn_zeusAttributeDialog.sqf`

```text
Opens a Zeus dialog (Zeus Enhanced, zen_dialog_fnc_create) for one set of
AEGIS-M Eden attributes on one object -- the Site module's own settings,
or a vehicle's AEGIS-M overrides -- built straight from that attribute
config, so Zeus shows exactly what Eden does: every attribute's display
name, tooltip and choices, with the object's CURRENT values filled in
(every row forces its value: ZEN would otherwise show whatever was last
confirmed in a dialog of the same title, i.e. another Site's values).

    Combo - a list of its Values (a value set by the attribute's own
        expression as true/false shows as its "on"/"off" entry)
    Checkbox - a checkbox
    Edit - a text box (a number, or blank)

ZEN dialogs have no headings, so Eden's section headings (SubCategory)
go into each row's tooltip, and a name used in two sections ("Max Range
(m)" for launchers and for CIWS) is prefixed with its section.

On confirm the chosen values go, as [property, value] pairs, to
_applyFunction on every machine, and to anyone joining later (one JIP
entry per object and function, replaced by each edit): it runs each
attribute's own Eden expression, so Zeus and Eden set exactly the same
variables, and every machine's copy (what this dialog reads) stays
current.

Without Zeus Enhanced there's no dialog to open: a hint says so.
```

## aegism_fnc_siteName

`addons/main/functions/fn_siteName.sqf`

```text
A Site's name, the same in the RPT (LINK lines), the status board, the 3D
overlay and the terminals: its Eden variable name, else "Site N" by its
place among the Sites in "AEGISM_allPoolOwners" (the order they were set
up), with its map grid on request. Added 2026-10-07 when the user asked
for clearer debug of what is linked between Sites: until then the RPT
printed the logic object ("L AEGIS-M:2"), the board "Site N (grid ...)"
and the 3D overlay only a variable name, so the three couldn't be matched.

The list of Sites only exists where the engagement logic runs (the
server, a host, singleplayer); elsewhere a Site with no variable name is
just "Site". The terminals get their labels from the server.
```
