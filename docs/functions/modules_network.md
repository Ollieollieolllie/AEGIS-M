# modules_network: function notes

What each function does and why, in full: the descriptions that used to sit in each
function's header, moved out of the code on 2026-10-07. Each header keeps a short
description with its parameters, return value and examples. Change a function's
behaviour and its notes here change with it. This folder is not packed into the mod.

## aegism_network_fnc_alarmPlayer

`addons/modules_network/functions/fn_alarmPlayer.sqf`

```text
Plays the Sites' alarms on this machine: every machine with a player
runs it every frame (this addon's XEH_postInit). The server only decides
each Site's alarm and publishes it ("AEGISM_alarmNow", aegism_network_
fnc_siteAlarm); this plays it for this machine alone (playSound3D,
local) at each of the Site's speakers:
    - one cycle of the sound at a time, the next as soon as the last has
      ended (after the sound's own CfgSFX delay, none for AEGIS-M's
      tones). Every cycle is a new sound, so none is ever left stuck: a
      looping engine sound source (what the server used to create)
      wasn't heard again after the camera had been away -- Zeus, a
      spectator, a teleport -- and sometimes not from its start;
    - only while the camera, wherever it is (the player, Zeus, a
      spectator), is within the sound's reach of the speaker, and from
      the moment it comes within it;
    - a one-shot (the All Clear) once, when it's published, from the
      speakers in reach then.
A new state stops the old sound at once.

The sound is read from the class's own config, as the engine plays a
sound source: CfgVehicles <class> >> sound, and that CfgSFX class's
sounds[] (each [file, volume, pitch, reach, probability, min, mid, max
delay], one picked by probability for each cycle). A file named without
its extension, as CfgSFX allows (playSound3D needs it), is found as .wss,
.ogg or .wav. Resolved once per class ("AEGISM_cacheAlarmSound"); a class
with nothing playable is logged once (ALARM-SOUND).

Heard to its reach: the game fades a sound played this way out by about
600 m at volume 1 whatever distance it's given (the user, 2026-10-07:
"audio still not audible past 600m Max", with longer Alarm Ranges set;
AEGISM_ALARM_CARRY). So each cycle is played not at the speaker but from
a point on the line from the camera to it, as far off as

    distance to the speaker x 600 / the sound's reach

-- at the edge of its reach it sounds as it does at the edge of that
carry, and nearer in proportion, from the speaker's direction. A 400 m
alarm is played from further off than its speaker, a 5 km one from much
nearer. playSound3D's own distance is left at 0 (no cut-off): whether the
camera is within reach is checked here. The point is fixed for the cycle
(1.4 to 6.6 s for AEGIS-M's tones) and worked out again for the next, so a
fast-moving listener hears it drift a little within a cycle. Not yet
heard in game.
```

## aegism_network_fnc_drawThreatRings

`addons/modules_network/functions/fn_drawThreatRings.sqf`

```text
Draws a Site's threat rings on the map (its "Threat Rings" setting): a
ring for each weapon and sensor of every member System, at the reach
AEGIS-M itself works to:
    launcher (red) - its engagement range: the missile's own reach, or
        the Site's or vehicle's Max Range where that's shorter (aegism_
        intercept_fnc_envelopeBounds, the limit every engagement is
        checked against)
    CIWS (orange) - the gun's own reach, or CIWS Max Range where that's
        shorter. It opens fire inside that, once a burst is likely
        enough to hit (aegism_intercept_fnc_openFireRange).
    sensor (blue) - its config reach against an aircraft (aegism_system_
        fnc_discoverCapabilities), capped at the view distance where its
        config caps it (IR, visual). One fixed to the hull with less than
        360 degrees is drawn as its sector, the way the vehicle faces
        now; one that turns with a turret as a full ring.
    protected area (green) - the Site's Protected Area Radius round its
        module (the area a hostile munition landing in, or guided at
        anything inside, is a threat to: aegism_detect_fnc_
        munitionThreat), "Protected area: 750 m".
A vehicle's sensors with the same reach and arc share a ring (a radar
and its passive receiver), as do its launchers of one weapon. Each ring
is a line with a labelled dot on its edge: a sector's in the middle of
its arc, a full ring's at north-east -- or, if another label is already
there (a radar's and a launcher's ring the same size round the same
place), the next clear diagonal (AEGISM_RING_LABEL_BEARINGS).

A Site linked with others (aegism_network_fnc_linkSites) is drawn with
its whole group, as one set, by the group's lead -- so the same weapons
and sensors on different Sites merge (below), and a vehicle linking them
is drawn once. With a Shared Site Coordinator its Threat Rings setting
decides for the whole group; otherwise each Site's own decides whether
its vehicles are in it.

Full rings of one kind with similar reaches on vehicles close together
are drawn as one, whatever the weapon or vehicle: every pair's reaches
within AEGISM_RING_MERGE_FRACTION of each other, and the vehicles within
that fraction of the larger reach of each other (1.6 km for a 16 km
Patriot). The ring is centred on their middle and reaches as far as the
furthest-reaching of them (each one's reach plus its distance from the
middle), so it covers every ring it replaces; its label lists every
system on it ("4x MIM-145 Defender: MIM-145 16.0 km | Mk49 Spartan:
RIM-116 15.5 km"). A sector is always drawn on its own.

They're made the way cTab makes a player's markers: "_USER_DEFINED"
names, in the side channel, created by one of the Site's crew -- so
they're in that side's channel, and players can delete them like their
own. Each is built locally and sent once (its last property set with the
global command, which broadcasts the whole marker).

Drawn once -- on the Site's first coordinator tick, when its links are
known (aegism_network_fnc_moduleInit) -- they don't follow the vehicles,
or go when one is destroyed. Logged (THREAT-RINGS). Their names are kept
on the group's lead ("AEGISM_threatRings"): drawing again replaces every
ring the group's Sites had, so a Zeus edit of the setting (aegism_
network_fnc_zeusApplySite) redraws the group, or just deletes them if
none of it draws rings any more.

Server only.
```

## aegism_network_fnc_edenCoordinator

`addons/modules_network/functions/fn_edenCoordinator.sqf`

```text
Eden: keeps "Shared Site Coordinator" to one Site per group of connected
Sites -- Site modules synced to each other, synced to the same vehicle,
or with a vehicle of one synced to a vehicle of the other (directly or
through a crewman), chained: the links aegism_network_fnc_linkSites
makes at runtime. Run on every Eden
attribute change and every new connection (Cfg3DEN EventHandlers, this
addon's config).

The Site just ticked wins: each Site's last-seen value is remembered for
the editing session ("AEGISM_edenCoordinatorSeen"), so a Site ticked
since the last run keeps it and the others in its group are unticked
(set3DENAttribute -- undoable like any edit). Where a new connection
joins two groups that each had one, the first Site keeps it.

The same rule is applied in Zeus (aegism_network_fnc_zeusApplySite); a
group that still ends up with two (a link made in Zeus) is led by the
first set up (aegism_network_fnc_linkSites).
```

## aegism_network_fnc_isTerminal

`addons/modules_network/functions/fn_isTerminal.sqf`

```text
Whether an object synced to a Site is one of its status terminals
(aegism_network_fnc_terminalAction) rather than an alarm speaker: a
laptop -- any object whose class name has "laptop" in it (vanilla's
Land_Laptop_F, Land_Laptop_unfolded_F, Land_Laptop_device_F,
Land_Laptop_02_unfolded_F...). Or whatever a terminal laptop has been put
down into since ("AEGISM_terminalItem", aegism_network_fnc_terminalTrack):
the holder a dropped one lies in has no "laptop" in its class.
```

## aegism_network_fnc_linkSites

`addons/modules_network/functions/fn_linkSites.sqf`

```text
Links Sites into one, and splits them again once every link between
them is gone. Two Sites are linked by any of these, as many as there are:
    shared - a live AEGIS-M System synced to both (e.g. a radar both
        connect to)
    pair - a live System of one synced to a live System of the other
        (a vehicle-to-vehicle sync line; to a crewman counts as to his
        vehicle) -- held while both are alive
    modules - the two Site modules synced to each other
Links chain: A linked to B and B to C make one group of three. Losing one
of several links keeps the group (logged, LINK-CHANGE); losing the last
splits it (UNLINK).

A linked group works as one Site:
    - one contact pool and one assignment ledger: every Site in it holds
      the same "AEGISM_pooledContacts" and "AEGISM_claims" HashMaps, so
      each Site's sensors feed the group and each Site's vehicles see
      the group's assignments
    - one coordinator, its lead: the Site ticked "Shared Site
      Coordinator", or, if none is, the first of them set up. It assigns
      every target across all the group's vehicles ("AEGISM_
      groupMembers", aegism_intercept_fnc_assignEngagements), so two of
      its weapons are never put on one target unless that's the plan (a
      CIWS alongside a launcher). The other Sites' coordinators stand by.
      Its Target Priority orders the group's targets.
    - settings: with a Shared Site Coordinator, its settings apply to
      every vehicle of the group (aegism_fnc_siteSettingsSource); without
      one, each vehicle keeps its own Site's. Every vehicle of a group
      that changes is re-resolved at once.
    - it protects all its vehicles: a munition threatening any of them
      is a threat to the group (aegism_detect_fnc_munitionThreat), and
      its Sites' alarms sound together (incoming, going live).
More than one Site of a group ticked as coordinator (Eden and Zeus untick
the others, so only a link made later can do that): the first set up
leads, logged (LINK).

When the group splits, each part gets its own copy of the contacts and
keeps its own vehicles' assignments (a missile already in flight is
still followed), and its own settings again. Logged: LINK, LINK-CHANGE,
UNLINK.

Run from every Site's coordinator tick (server, every 0.5 s); works out
every Site's group once a frame. Each Site logic carries:
    AEGISM_linkLead - its group's lead (itself while not linked)
    AEGISM_linkSites - its group's Sites ([itself])
    AEGISM_groupMembers - every vehicle of its group (its own members)
    AEGISM_links - every link holding its group together: [type, a, b]
        -- ["shared", vehicle, objNull], ["pair", vehicle, vehicle] (one
        on each Site), ["modules", Site, Site]

Link records (2026-10-07): each link is [kind, a, b, the one Site, the
other] -- "shared" (a: a vehicle of both), "pair" (a of the one synced to
b of the other), "modules" (a, b: the two Site modules). The two Sites
were added so every debug view can say which Sites a link joins: a
vehicle synced to three Sites used to read "X (synced to both)" three
times over. Kept on every Site of the group as "AEGISM_links"; the status
board, the 3D overlay and the LINK / LINK-CHANGE / UNLINK lines read them
(names from aegism_fnc_siteName).
```

## aegism_network_fnc_moduleInit

`addons/modules_network/functions/fn_moduleInit.sqf`

```text
Entry point run when an AEGISM_Module_Site is placed and synced in Eden
or Zeus. This is the one AEGIS-M module a mission designer places: sync
it to every radar, launcher, SHORAD, and CIWS vehicle that makes up a
site to link them into a battery. There is nothing to set on the
vehicles themselves -- each one's Radar/Launcher/CIWS role is discovered
automatically from its own real sensors and loaded ammo (aegism_system_
fnc_discoverCapabilities), not declared via any Attribute -- this module
only carries the doctrine (engagement envelope, target priority, salvo
policy, target-class allowlist, CIWS-last-resort) and personality (skill
tier, temperament, cost/value judgment) that apply battery-wide, per the
object -> network -> default resolution order in aegism_system_fnc_
resolveEngagementSettings / resolveCrew.

Writes "AEGISM_network" (pointing at this Site's logic object),
"AEGISM_engagement", and "AEGISM_crew" onto every synced vehicle (and
onto the Site logic itself), and initializes this Site's own pooled-
contact list ("AEGISM_pooledContacts", populated by radar-capable member
Systems' own native sensors, see aegism_detect_fnc_confidenceLoop),
engagement-assignment ledger ("AEGISM_claims", HashMap of contact key
-> array of per-role assignment records, written once per tick by
aegism_intercept_fnc_assignEngagements -- see that function's own doc
comment for the record shape and scoring -- and read/executed by every
member System's own aegism_intercept_fnc_engagementLoop so two Systems
in the same battery are coordinated rather than independently converging
on the same contact), and member registry ("AEGISM_networkMembers").
Registers itself on the global "AEGISM_allPoolOwners" list
(missionNamespace) so the detection loop's trackers can find it without
a per-tick module-logic scan.

Also suppresses independent AI targeting/engagement (aegism_fnc_
setWeaponAiSuppressed) on EVERY turret of every synced vehicle, applied
to the whole vehicle rather than any specific weapon -- deliberately
broader/blunter than aegism_system_fnc_moduleInit's own precise per-
discovered-weapon suppression, since a vehicle synced here is declared
by the mission designer to be part of this Site and should never open
fire on its own initiative even if aegism_system_fnc_discoverCapabilities
never actually recognizes it (a bug there, or simply syncing before its
own scan pass reaches it, should never mean "fires uncontrolled" rather
than "doesn't fire until AEGIS-M is ready"). The tradeoff: this also
suppresses turrets AEGIS-M will never use (e.g. a mixed-role vehicle's
own coax MG) -- accepted, since syncing a vehicle here is an explicit
choice to hand it to AEGIS-M. Restored on unsync ONLY if the vehicle
isn't also independently recognized as a System in its own right (that
recognition owns its own, narrower suppression and shouldn't be undone
by a Site-level unsync).

Also registers a server-only 0.5s call into aegism_intercept_fnc_
assignEngagements for this Site (below), which publishes each member's
assignments for its own 0.1s engagement loop.

Its threat rings ("Threat Rings on Map") are drawn on its first
coordinator tick, once its links are known -- a linked group's as one set
(aegism_network_fnc_drawThreatRings).

A vehicle synced to it AND to another Site links the two into one
(aegism_network_fnc_linkSites): one coordinator, one contact pool, one
set of assignments, until that vehicle is destroyed.

Each laptop synced to it (aegism_network_fnc_isTerminal) becomes its
status terminal: an action that opens its live status board, on every
machine (aegism_network_fnc_terminalAction).

A vehicle's own Radar/Launcher/CIWS setup (aegism_system_fnc_moduleInit)
is intentionally NOT triggered from here -- it's driven independently by
aegism_fnc_scanForRoles's periodic discovery sweep (addons/main), so a
qualifying vehicle works standalone (with default doctrine/personality
per aegism_system_fnc_defaultEngagementSettings/defaultCrew) whether or
not it's ever synced to a Site at all. This module's only job is
linking already-functional Systems into a battery under shared
doctrine/personality, not bringing them to life in the first place.

Registers a live-resync poll (aegism_fnc_pollSyncedObjects) so a vehicle
synced or unsynced from this Site AFTER this one-time init has already
run still takes effect: "AEGISM_network"/"AEGISM_engagement"/"AEGISM_
crew"/"AEGISM_networkMembers" all stay current with the live sync
graph, and each affected vehicle's own periodic re-resolution poll
(aegism_system_fnc_moduleInit) picks up the change from there. The same
poll's deletion hook prunes this Site from "AEGISM_allPoolOwners" if it
is ever deleted mid-mission (e.g. by a Zeus operator) -- otherwise a
member System's aegism_detect_fnc_confidenceLoop would keep pushing
detections into a dead logic object's pool for the rest of the mission,
and every still-synced vehicle would silently lose battery contacts/
deconfliction with no diagnostic.
```

## aegism_network_fnc_readSiteSettings

`addons/modules_network/functions/fn_readSiteSettings.sqf`

```text
The doctrine and personality a Site hands its members, read from the
Site logic's own attribute variables (set by its Eden attributes, or in
Zeus by aegism_network_fnc_zeusApplySite).
```

## aegism_network_fnc_scanForUninitSites

`addons/modules_network/functions/fn_scanForUninitSites.sqf`

```text
One tick of a periodic fallback scan (registered in XEH_postInit.sqf)
that manually runs aegism_network_fnc_moduleInit on any placed
AEGISM_Module_Site object whose own module activation never fired --
working around an observed Eden Preview limitation where a Module_F-
derived module's own "function"/isTriggerActivated=0 auto-run does not
reliably invoke in Preview mode, even though the exact same setup runs
correctly once the mission is exported and launched as a real scenario.

Finds every placed Site with `entities` (indexed by type) -- it used to
be allMissionObjects every 2s on every machine, which walks every object
in the mission. The first pass checks the two agree and logs which one
this scan uses; if `entities` ever misses a Site that allMissionObjects
finds, the scan keeps using allMissionObjects.

A Site is considered already initialized if it has "AEGISM_network
Members" set (written by aegism_network_fnc_moduleInit itself), so a Site
whose real activation DID fire is left alone. Synced units are recovered
via synchronizedObjects -- the same sync-line data the module's own
activation would have passed.

Runs on every machine, matching the module's own isGlobal=1 activation
-- aegism_network_fnc_moduleInit gates its own loop registrations to the
server.
```

## aegism_network_fnc_siteAlarm

`addons/modules_network/functions/fn_siteAlarm.sqf`

```text
A Site's alarm, one of three states, updated with the Site's
coordinator (every 0.5s, server only):
    incoming - a munition threatening the Site was seen within the last
        AEGISM_INCOMING_HOLD s ("AEGISM_incomingAt", written by aegism_
        detect_fnc_munitionCheck)
    warning - the Site has a weapon assigned to a target (going live:
        before its first shot), or fired within the last "alarmHold" s
        ("AEGISM_lastShotAt", written by aegism_intercept_fnc_
        onSystemFired)
    off - neither
Incoming replaces warning; a state whose tone is "off" falls through to
the next. Going quiet (to off from either) plays the All Clear tone once,
if the Site has one.

Each state's tone is a sound source class (this addon's CfgVehicles
AEGISM_Alarm_*, heard to the Site's Alarm Range -- or the Site's custom
class, at its own range), played at every speaker -- each non-vehicle
object synced to the Site, or the Site logic itself if there is none.
(A laptop synced to the Site is its status terminal, aegism_network_fnc_
isTerminal, not a speaker.)

The server only decides the state: a change is published on the Site
("AEGISM_alarmNow", JIP-safe), and every player's machine plays it for
itself (aegism_network_fnc_alarmPlayer). A looping sound source created
here and left to the engine wasn't heard after the camera had been away
(Zeus, spectator, a teleport), and sometimes not from its start. The
network still only carries a change of state, never the repeats.
Nothing happens between changes but a few variable reads.

Logged as ALARM on each change.
```

## aegism_network_fnc_terminalAction

`addons/modules_network/functions/fn_terminalAction.sqf`

```text
Makes an object a terminal, on this machine: the action "AEGIS-M: Site
Terminal" (within 3 m), which opens its screen (aegism_network_fnc_
terminalOpen). An objNull anchor takes the action away.

A terminal is a laptop (any object whose class name has "laptop" in it,
aegism_network_fnc_isTerminal -- they're not alarm speakers) synced to a
Site or to a single AEGIS-M vehicle. The server sends this to every
machine, and to anyone joining later (one JIP entry per terminal, gone
with it): for one synced to a Site, from the Site's own setup (aegism_
network_fnc_moduleInit) and its live-resync poll; for one synced only to
a vehicle, from the server's scan (aegism_network_fnc_terminalScan).

The anchor is the Site or vehicle the action was made for. It only backs
up what the terminal itself lists as synced when the server works out
what it reaches (aegism_network_fnc_terminalScope).

One with Fixed in Place ("AEGISM_terminalFixed") also has its inventory
locked here (lockInventory, each machine's own), and unlocked if that's
switched off again.
```

## aegism_network_fnc_terminalLink

`addons/modules_network/functions/fn_terminalLink.sqf`

```text
Server: connects a laptop to a Site or vehicle, or takes that connection
away, and sends every machine its action (aegism_network_fnc_terminal
Action, one JIP entry per laptop). What used to be read from the sync
alone is now also kept on the laptop, public ("AEGISM_terminalLink", the
Sites and vehicles), so that it can go with the laptop when it's carried
off -- an inventory item taken from the ground leaves no object behind to
be synced to anything. Also records which inventory item the laptop is
("AEGISM_terminalItem": the first thing in its cargo; "" for a prop,
which can't be picked up), lists one that is an item among the laptops
the server follows ("AEGISM_terminalBodies", aegism_network_fnc_terminal
Track), and logs each laptop once as it becomes a terminal (TERMINAL).

Called where the action used to be sent from: a Site's setup and its
live-resync poll (aegism_network_fnc_moduleInit), the scan for laptops
synced to a single vehicle (aegism_network_fnc_terminalScan), a laptop put
down again (aegism_network_fnc_terminalTrack), and a Zeus edit of one
(with no anchor: published again as it is).
```

## aegism_network_fnc_terminalData

`addons/modules_network/functions/fn_terminalData.sqf`

```text
What a terminal may do and what it's connected to -- its access, manual
interception, surface strike and the Sites and vehicles of its connection
-- for either kind of terminal: a laptop on the ground (its own
variables), or a unit carrying one (the first record in its "AEGISM_
terminalCarried" whose item it still has on it; none for a dead unit).
Everything on the server that used to read a laptop's variables goes
through this (aegism_network_fnc_terminalScope, terminalApply,
terminalOrder, terminalPicture).
```

## aegism_network_fnc_terminalTrack

`addons/modules_network/functions/fn_terminalTrack.sqf`

```text
Server, once a second (this addon's XEH_postInit): a terminal laptop's
connection follows the item. The user (2026-10-07): "get the laptop to
keep its connection, such that it could be picked up and stolen, taken
else where, dropped then used, perhaps having it in your inventory
allows you to scroll wheel to use it".

A record -- [item class, connected to, access, manual interception,
surface strike, fixed in place] -- belongs to whatever holds the laptop:
    - a laptop on the ground: its own variables, as ever. The server
      keeps a copy with where it lies ("AEGISM_terminalBodies", from
      aegism_network_fnc_terminalLink, read again each pass), because
      the game removes an emptied holder and nothing could be read then;
    - a unit carrying it: "AEGISM_terminalCarried" on the unit (public).
      A player carrying one has "AEGIS-M: Site Terminal (carried)" on
      the action menu (CBA_fnc_addPlayerAction, so in vehicles and after
      a respawn too), and to the server the unit is the terminal:
      nobody else can use it, and it's always "at" it;
    - a crate, a vehicle, a body: the same variable on that. It keeps
      its connection there and is a terminal again once taken out.

Each pass counts, it doesn't listen:
    1. a laptop on the ground whose holder is gone or no longer has the
       item in it has left where it lay;
    2. a unit or crate with fewer of the item than records has let the
       last one it took up go;
    3. each connection so freed goes to the nearest thing within 10 m
       (AEGISM_TERMINAL_REACH) of where it was that has one more of the
       item than it's known to hold: a unit first, alive or dead; else a
       holder on the ground, which becomes a terminal again there with
       its action on every machine; else a crate or vehicle. None found
       for 10 s (AEGISM_TERMINAL_LOOSE_FOR, mine), it's dropped and
       logged.
A laptop moved between a unit's own uniform, vest and pack changes none
of these counts. A laptop that isn't a terminal, carried beside one that
is, can't be told apart from it.

Fixed in Place: the laptop's inventory is locked on every machine
(aegism_network_fnc_terminalAction). Should one be taken anyway, it's
taken off the unit and put back as it was -- same class, place and
facing -- and the player is told.

Why counting: the first version listened for each unit's Take and Put
(CBA class events) and read the laptop's variables from the container the
event named. In its first test (19:36 RPT 2026-10-07, 68 s) nothing came
of a pick-up and nothing was logged -- the server was never told -- and
the log couldn't say which step had failed. This needs no event, no
reading of a holder that is about to go, and says what it does: TERMINAL
for a laptop made a terminal, taken up, put down, kept in something, put
back, or lost.

First run (19:53 RPT 2026-10-07, 22 s): the laptop was logged as a
terminal at the start, and its leaving the ground was seen about 7 s in;
then nobody was found with it and its connection was dropped after the
10 s. The game's own laptop item (Laptop_Unfolded, from the Old Man
content) is a magazine in config (CfgMagazines, OM_Magazine), though its
holder lists it under TransportItems: on a unit it's among "magazines",
and only "items" was counted. A unit's count is now both, and a fixed
one is taken off its taker with removeMagazine.

Not yet seen working in game: a pick-up found on its taker, the carried
action, a drop becoming a terminal again, whether lockInventory stops
the Take of a single item on the ground, and whether the action shows on
the holder a dropped laptop lies in.
```

## aegism_network_fnc_terminalOpen

`addons/modules_network/functions/fn_terminalOpen.sqf`

```text
Opens a terminal's screen on this machine (built 2026-10-07, replacing
the status-only screen; untested in game at the time of writing).

Layout: a title bar with the terminal's access (STATUS ONLY / FULL
CONTROL); on the left a list of what it reaches -- each Site, its
vehicles indented under it; on the right two tabs for the one picked:
    Status - its live status board (aegism_fnc_statusBoard), scrolling,
        asked of the server once a second while the tab is shown
        (aegism_network_fnc_terminalRequest)
    Settings - only on a Full Control terminal: its settings form
        (aegism_network_fnc_terminalSelect), with Apply (aegism_network_
        fnc_terminalSend) and Revert, and a line for the server's answer.

The screen is an RscDisplayEmpty with controls made by script; their ids
and colours are in terminal.hpp. Its state is one HashMap in uiNamespace
("AEGISM_terminalState"): terminal, anchor, access, nodes (what it
reaches, from the server), node (the index picked), tab, rows (the
form's rows), formControls, formFor (what the form was built for).

What it reaches and its access come from the server (aegism_network_fnc_
terminalScope -> aegism_network_fnc_terminalFill), asked once a second
until answered: the Sites' link and member lists only exist there.
```

## aegism_network_fnc_terminalRequest

`addons/modules_network/functions/fn_terminalRequest.sqf`

```text
Server side of a terminal's Status tab: builds the status board
(aegism_fnc_statusBoard) of a Site -- that Site alone, every contact it
tracks -- or, for a vehicle, of its Site, and sends it back to the
machine that asked (aegism_network_fnc_terminalShow). Run once a second
per open terminal screen showing Status.

A vehicle with no Site gets the whole board (every Site, standalone
vehicles): there is no board for one vehicle. That shows more than the
terminal reaches; only its control is limited to the vehicle.
```

## aegism_network_fnc_terminalShow

`addons/modules_network/functions/fn_terminalShow.sqf`

```text
Shows what the server sent on this machine's open terminal screen: a
status board (aegism_network_fnc_terminalRequest), sized to its text so
the screen scrolls, and/or a line about the last Apply (aegism_network_
fnc_terminalApply) at the foot. Does nothing once the screen is closed.
```

## aegism_network_fnc_zeusApplySite

`addons/modules_network/functions/fn_zeusApplySite.sqf`

```text
Applies a Site's settings as edited in Zeus (aegism_fnc_
zeusAttributeDialog), on every machine: each attribute's own Eden
expression runs (aegism_fnc_applyAttributeValues), so the Site logic
gets the same variables its Eden attributes would set.

On the server the Site's doctrine and personality are then rebuilt
(aegism_network_fnc_readSiteSettings), handed to every member vehicle,
and each member System -- and, for a Site linked with others, every
vehicle of its group -- re-resolved at once rather than at its next
5-second poll. Ticking "Shared Site Coordinator" unticks it on every
other Site linked, synced or sharing a vehicle with this one. Logged as
SITE-SETTINGS.
```

## aegism_network_fnc_zeusEdit

`addons/modules_network/functions/fn_zeusEdit.sqf`

```text
Opens the right AEGIS-M settings dialog in Zeus for an entity:
    a Site module - the Site's own settings (every Site attribute)
    an air-defence vehicle, or one of its crew - that vehicle's AEGIS-M
        overrides (the same "AEGIS-M: Vehicle Overrides" as in Eden)
An air-defence vehicle is one AEGIS-M has adopted as a System, or found
capable and deferred until it is synced to a Site.

With _open false it only answers whether the entity can be edited (for
Zeus Enhanced menu and button conditions).

Also: a terminal (a laptop, aegism_network_fnc_isTerminal) -- a one-row
dialog for its Terminal Access ("AEGISM_terminalAccess", set on every
machine).
```

## aegism_network_fnc_zeusInit

`addons/modules_network/functions/fn_zeusInit.sqf`

```text
Zeus access to AEGIS-M's settings (aegism_network_fnc_zeusEdit). Run on
every machine with an interface, from this addon's XEH_postInit.

    Site module - double-click it, or place one: its settings dialog
        opens (Zeus Enhanced's own object window is turned off for
        Sites, see aegism_network_fnc_moduleInit)
    Vehicle - the "AEGIS-M" button in its Zeus Enhanced attributes
        window opens its overrides
    Either - right-click it: "AEGIS-M Settings" in the context menu
    Module "AEGIS-M > Edit Air Defence" - place it on a Site or an
        air-defence vehicle (or within 50 m of a Site)

The dialogs themselves come from Zeus Enhanced (ZEN). Without it only
the double-click/placement hooks exist, and they hint that ZEN is
needed.
```

## aegism_network_fnc_terminalScan

`addons/modules_network/functions/fn_terminalScan.sqf`

```text
One pass of the server's scan (every 5 s, this addon's XEH_postInit) for
terminals synced to a single AEGIS-M vehicle instead of a Site: each
gets its action on every machine (aegism_network_fnc_terminalAction),
and loses it once the sync is gone. A terminal synced to a Site as well
is left to that Site.

A scan, because a vehicle has no setup of its own that looks at what's
synced to it the way a Site's does, and a sync made later (Zeus, script)
raises no event. It walks `vehicles` and only looks at what's synced to
an AEGIS-M one.
```

## aegism_network_fnc_terminalScope

`addons/modules_network/functions/fn_terminalScope.sqf`

```text
What a terminal reaches, worked out on the server, where the Sites' link
and member lists are ("AEGISM_linkSites", "AEGISM_linkLead",
"AEGISM_networkMembers" aren't sent to clients):

    synced to a vehicle - that vehicle (one AEGIS-M has adopted, or found
        capable and deferred)
    synced to a Site - that Site and its live vehicles
    synced to the Shared Site Coordinator of linked Sites (ticked, and
        leading its group) - every linked Site and their vehicles

Returned as nodes in the order the screen lists them: [object, label,
"site" or "vehicle"]. A Site's label is its variable name, or "Site at
<grid>"; a vehicle's is its display name and its group/unit id.

With _reply it also sends the nodes and the terminal's access
("AEGISM_terminalAccess": "status" or "control", set by its Eden
attribute or in Zeus, default "status") to the machine that asked
(aegism_network_fnc_terminalFill). Without, it's the reach check of
aegism_network_fnc_terminalApply.
```

## aegism_network_fnc_terminalFill

`addons/modules_network/functions/fn_terminalFill.sqf`

```text
Fills this machine's open terminal screen with what the terminal reaches
and its access, as the server worked them out (aegism_network_fnc_
terminalScope): the list on the left (Sites in the accent colour, their
vehicles indented), the access badge, whether there's a Settings tab;
then picks the first.

The screen asks again every fifth second, and an answer that differs
lists the reach again, keeping what was picked if it's still within it
(else the first). Seen in the first test (2026-10-07): a terminal synced
to the coordinating Site handed the Shared Site Coordinator's place to
another Site, kept showing that Site, and its next Apply to it was
refused as out of reach.
```

## aegism_network_fnc_terminalSelect

`addons/modules_network/functions/fn_terminalSelect.sqf`

```text
Shows one node on this machine's open terminal screen, on the Status or
the Settings tab.

Status: asks the server for its board at once (and the screen's own
loop asks again every second).

Settings (Full Control only): builds the form, once per node (again on
Revert): one row per attribute of the same config Eden and the Zeus
dialog use (aegism_fnc_zeusAttributeDialog) -- a Site's own Attributes,
or Cfg3DEN's AEGISM_VehicleOverrides for a vehicle -- under Eden's
SubCategory headings, each with its tooltip and the target's current
value as this machine has it (the variables each attribute's expression
sets, kept current on every machine by the apply functions):
    Combo - RscCombo of its Values (a value stored as true/false shows
        as its on/off entry)
    Checkbox - RscCheckBox
    Edit - RscEdit (a number, or blank)
The rows are kept in the screen's state for aegism_network_fnc_
terminalSend.
```

## aegism_network_fnc_terminalSend

`addons/modules_network/functions/fn_terminalSend.sqf`

```text
Apply on this machine's open terminal screen: reads the settings form's
rows into [property, value] pairs, as the Zeus dialog does (a combo's
value as its config has it; a number typed into a box as a number where
Eden gives one), and sends them with the terminal and the target to the
server (aegism_network_fnc_terminalApply). Every row is sent, changed or
not: each attribute's own expression runs, as on a Zeus confirm.
```

## aegism_network_fnc_terminalApply

`addons/modules_network/functions/fn_terminalApply.sqf`

```text
Server side of a control terminal's Apply. Refuses (and says why, on the
screen and as TERMINAL in the RPT) unless:
    - the terminal's access is "control"
    - the player is within AEGISM_TERMINAL_REACH m of it (terminal.hpp;
      10 m is my figure)
    - the target is within what the terminal reaches now (aegism_
      network_fnc_terminalScope)

Then applies the pairs on every machine through the same functions and
the same JIP entry as a Zeus edit (aegism_network_fnc_zeusApplySite for
a Site, aegism_system_fnc_zeusApplyOverrides for a vehicle): only an
attribute's own config expression ever runs, with the sent value as
_value, so a client can't have anything else executed.
```

## aegism_network_fnc_terminalPicture

`addons/modules_network/functions/fn_terminalPicture.sqf`

```text
The Interception page's data, built on the server once a second while a
terminal shows it (2026-10-07). Needs the terminal's own attribute
"AEGISM_terminalEngage" (Manual Interception), which is separate from
"AEGISM_terminalAccess".

The picture and the orders belong to the Site that coordinates
("AEGISM_linkLead"): its pool and claims are the group's.

Tracks: every live contact of that pool ("threat"; "ordered" if it's
there for an order alone, the entry's "manualOnly"), with what's on it
from the claims, and its time to impact from the entry's cached "tti".
Then what the group's vehicles' sensors see besides
("AEGISM_otherTracks", written by aegism_detect_fnc_confidenceLoop on
every read, used while no older than AEGISM_TERMINAL_TRACK_FRESH, 2 s, my
figure): "hostile" (a class the Site doesn't engage), "friendly",
"neutral". A munition is identified by its contact key, never sent as an
object: a projectile isn't a network object a client could resolve.
Positions and velocities are sent and the client moves a track on by its
velocity between answers.

Weapons: those of the Site picked (its own members), of every vehicle
of the group when the Site picked is its Shared Site Coordinator (lead,
ticked, more than one Site linked -- the test aegism_network_fnc_
terminalScope uses for a terminal's reach; the user's first test showed
only the coordinator's own launchers, 2026-10-07), or of the one vehicle
picked. With a track picked, each is asked
aegism_intercept_fnc_canEngage for it -- the same test the order itself
has to pass.

Reply: [node, error, automation on, Site name, tracks, weapons, orders,
last lines], to aegism_network_fnc_terminalIntercept on the machine that
asked.
```

## aegism_network_fnc_terminalOrder

`addons/modules_network/functions/fn_terminalOrder.sqf`

```text
Takes the Interception page's orders on the server (2026-10-07). Refused
(MANUAL ... refused in the RPT, and a line on the screen): terminal or
node gone, no "AEGISM_terminalEngage", player further than
AEGISM_TERMINAL_REACH, node outside the terminal's reach
(aegism_network_fnc_terminalScope), or a vehicle in no Site.

"engage" [key, vehicle, turret, weapon]: the vehicle has to be one of the
node's, the weapon one of its "launcherWeapons"/"ciwsWeapons", with a round
left and a shot at the track now (canEngage). The order is a HashMap
(target, key, name, system, weaponInfo, role, by, at, placed) pushed on the
coordinating Site's "AEGISM_manualOrders"; the coordinator places it as a
claim on its next run ("AEGISM_assignNow" makes that the next frame). See
aegism_intercept_fnc_assignEngagements.

"cease" [key or ""]: ends the orders of the node's vehicles (on that
track, or all). A claim nothing was fired for, or a gun's, is taken out of
the claims here; one with a missile in flight keeps it and fires no more
("salvo" = fired).

"automation" [on]: sets "AEGISM_automation" on the node and on everything
under it -- the coordinator's switch on every linked Site and every vehicle
of the group, a Site's on itself and its vehicles, a vehicle's on itself.
The coordinator leaves the weapons of a vehicle whose own flag or whose
Site's is off out of everything it decides itself. (First version set the
node's flag alone: with the coordinator switched off, the Patriots of the
Sites linked to it were still assigned on their own, 13:01 RPT
2026-10-07.)

Lines for the page go on the coordinating Site's "AEGISM_manualLog" (the
last 8), which the coordinator writes to as well.
```

## aegism_network_fnc_terminalIntercept

`addons/modules_network/functions/fn_terminalIntercept.sqf`

```text
Client side of the Interception page: takes the server's picture, keeps it
in the screen's state ("picture", "pictureAt") for the map, and fills the
track and weapon lists again. The lists are rebuilt every second, so what's
picked is kept by contact key ("trackKey") and by weapon id ("weaponId":
netId|turret|weapon) and put back; "filling" tells the lists' own
LBSelChanged events that this isn't a pick.

An answer for another node than the one shown, or arriving after the tab
was left, is dropped.
```

## aegism_network_fnc_terminalCommand

`addons/modules_network/functions/fn_terminalCommand.sqf`

```text
Everything the Interception page does on the client: "request" (ask for
the picture; the screen's once-a-second handler and every pick call it),
"track" / "weapon" (a pick in a list), "mapClick" (the track nearest the
click within AEGISM_TERMINAL_PICK_RADIUS of the screen, my figure), and
the three orders, sent to aegism_network_fnc_terminalOrder.
```

## aegism_network_fnc_terminalMapDraw

`addons/modules_network/functions/fn_terminalMapDraw.sqf`

```text
The Draw handler of the Interception page's map. From the picture in the
screen's state: each weapon vehicle (mil_box), the reach of the weapon
picked (drawEllipse, metres), each track at its position moved on by its
velocity for the time since the answer, a 5 s leader, a line from every
weapon on it, a ring on the one picked. Munitions are only named when
picked or under 15 s from impact, or a salvo is unreadable.

The map is an RscMapControl made with ctrlCreate on the screen itself (a
map can't sit in a controls group). It's kept at zero size as well as
hidden while another tab shows. The user's first test (2026-10-07): the
map shows and the page works.

Centring is not done here: aegism_network_fnc_terminalMapCentre.
```

## aegism_network_fnc_terminalMapCentre

`addons/modules_network/functions/fn_terminalMapCentre.sqf`

```text
Centres the Interception page's map (2026-10-07, third try). A per-frame
handler, started by aegism_network_fnc_terminalSelect when it sets
"mapCentre" in the screen's state ([point, width of ground m, moves, last
aim, frames to wait, first result]); it removes itself when the request is
done or the screen closed.

History, both from the user's tests: (1) ctrlMapAnimAdd in terminalSelect,
with the map still at zero size: "opens not centered on the site". (2) The
same from the map's Draw handler, with one check after it: "still not
centered". Why isn't known -- no error in the RPT, and the zoom then was a
guess (24000 / worldSize = 0.78 on Altis, which is nearly the whole
island).

So nothing is assumed now. Each move: wait 3 frames, wait for
ctrlMapAnimDone, ask the map what its middle row really shows
(ctrlMapScreenToWorld at the control's left, middle and right), then move
again with the scale that would show the width asked for (shown width is
in proportion to ctrlMapScale) and aimed off by as much as the last move
landed off. Up to 6 moves; done when the width is within 5 % and the
middle within 1 % of the width (my figures).

One RPT line per centring, TERMINAL-MAP: centred or NOT, moves, width
shown against asked, how far off, the scale, what the first move left, the
control's rectangle. If the user reports it off again, that line says
which of the game's answers was wrong.
```

## Interception page, second round (2026-10-07)

```text
From the user: "Multiple launchers of the same TYPE in close proximity
should just list as one", "see the missile in flight ... if thats not too
performance heavy", "need a radar control option as well".

Rows of launchers (aegism_network_fnc_terminalIntercept): the server still
sends one entry a weapon; the client makes a row of entries with the same
[vehicle type, role, turret, weapon, magazine] whose vehicles are within
AEGISM_TERMINAL_BATTERY_RADIUS (150 m, my figure) of one already in the
row. Greedy, in the order sent: a line of launchers each 150 m from the
next can come out as two rows. The screen's state keeps "rows" ([id,
vehicles, turret, weapon, reaches, one has a shot]), "rings" (for the map)
and "labelled" (one vehicle a row gets its name on the map). The settings
form's own rows moved to "formRows".

"engage" takes a vehicle or a list (aegism_network_fnc_terminalOrder): of
those with a shot, sorted by [already on this track, claims it's working
that aren't in flight, fewer rounds], the first takes the order.

Missiles in flight: the picture's 9th element, [position, velocity, on an
order] for every live interceptor of every claim. The map moves each on
by its velocity since the answer and draws a 1 s tail. While there are
any, the screen asks for the picture twice a second instead of once (its
handler now ticks every 0.5 s; board and reach requests keep their old
pace). Cost on the server per answer: one pass over the pool and the
claims, plus one canEngage a weapon listed when a track is picked.

Radars: the picture's 10th element, [vehicle, emitting, order, state,
why] (aegism_fnc_emconText). "radar" [vehicles or [], "on"/"off"/""] sets
"AEGISM_radarOrder" on each and runs aegism_system_fnc_emconUpdate at
once. Emission only: where a turning radar looks is still its own
(aegism_system_fnc_radarSchedule).
```
