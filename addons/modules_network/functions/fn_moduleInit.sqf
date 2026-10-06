/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_moduleInit

Description:
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

Parameters:
    _logic - the module logic object (this Site) <OBJECT>
    _units - synced vehicles <ARRAY of OBJECT>
    _activated - module activation state (unused, modules run on init) <BOOLEAN>

Returns:
    Nothing

Examples:
    [_logic, _units, _activated] call aegism_network_fnc_moduleInit;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\coordinator.hpp"

params ["_logic", "_units", "_activated"];

// isGlobal = 1 (below) guarantees this runs on every machine, but a module
// logic object can't cross the network as an object reference -- each
// machine gets its netId string instead. Without this normalization every
// getVariable/setVariable call on _logic below silently throws a type
// error and the whole doctrine/personality block never applies, leaving
// every synced vehicle running its own uncoordinated default settings.
if (_logic isEqualType "") then { _logic = objectFromNetId _logic; };
if (isNull _logic) exitWith {};

// A sync line drawn to a crewed vehicle can land on a crew member rather
// than the vehicle itself -- normalize every synced object to its vehicle,
// drop infantry/logics, and de-duplicate (a vehicle with several synced
// crew would otherwise appear once per crewman).
_units = (_units apply { vehicle _x }) select { _x isKindOf "AllVehicles" && {!(_x isKindOf "CAManBase")} };
_units = _units arrayIntersect _units;

([_logic] call aegism_network_fnc_readSiteSettings) params ["_engagementData", "_crewData"];
private _allowlist = _engagementData get "targetClassAllowlist";

// In Zeus, double-clicking the Site opens AEGIS-M's own settings dialog
// (aegism_network_fnc_zeusInit), not Zeus Enhanced's generic object window.
_logic setVariable ["zen_attributes_disabled", true];

_logic setVariable ["AEGISM_pooledContacts", createHashMap, false];
_logic setVariable ["AEGISM_claims", createHashMap, false];
_logic setVariable ["AEGISM_networkMembers", _units, false];
// Also kept directly on the Site logic itself (not just on member units,
// below) -- aegism_intercept_fnc_assignEngagements coordinates from the
// Site's own perspective and needs its doctrine/personality without
// having to borrow a copy from whichever member happens to be first.
_logic setVariable ["AEGISM_engagement", _engagementData, false];
_logic setVariable ["AEGISM_crew", _crewData, false];

private _allOwners = missionNamespace getVariable ["AEGISM_allPoolOwners", []];
_allOwners pushBackUnique _logic;
missionNamespace setVariable ["AEGISM_allPoolOwners", _allOwners];

{
    _x setVariable ["AEGISM_network", _logic, false];
    _x setVariable ["AEGISM_engagement", _engagementData, false];
    _x setVariable ["AEGISM_crew", _crewData, false];
    // Blanket-suppress every turret's independent AI targeting the MOMENT
    // a vehicle is synced, regardless of whether aegism_system_fnc_
    // discoverCapabilities ever actually recognizes it as a launcher/CIWS
    // System -- deliberately broader/blunter than aegism_system_fnc_
    // moduleInit's own precise per-weapon suppression (which only touches
    // turrets it discovered as a real launcher/CIWS): a vehicle synced here
    // is DECLARED to be part of this Site by the mission designer, so it
    // should never independently open fire on its own initiative even if
    // discovery fails or hasn't run yet (a bug there, or simply syncing a
    // vehicle before its own scan pass reaches it, should never mean
    // "fires uncontrolled" -- see aegism_fnc_setWeaponAiSuppressed's own
    // doc comment for what this actually disables). This does suppress
    // turrets that AEGIS-M will never end up using (e.g. a mixed-role
    // vehicle's coax MG) -- an accepted tradeoff for a synced vehicle,
    // since the mission designer chose to sync it as an AEGIS-M asset.
    [_x, allTurrets _x, true] call aegism_fnc_setWeaponAiSuppressed;
} forEach _units;

// Re-run discovery now that AEGISM_network is set: a synced vehicle that
// isn't a standalone-eligible AA platform (e.g. a radar-less SAM launcher)
// was deferred by its first scan pass, and would otherwise never become a
// System. No-op if already initialized. Vehicles with a sensor of their own
// first, so a launcher's contact-source check already sees its sensor
// siblings.
private _sensorsFirst = [_units, [], { [1, 0] select (([_x, true] call aegism_system_fnc_discoverCapabilities) get "hasSensor") }, "ASCEND"] call BIS_fnc_sortBy;
{ [_x] call aegism_system_fnc_moduleInit; } forEach _sensorsFirst;

// Its threat rings: drawn on its first coordinator tick (below), once it's
// known whether it's linked with other Sites -- a linked group's are drawn
// as one set (aegism_network_fnc_drawThreatRings).
_logic setVariable ["AEGISM_ringsPending", true, false];
// What they were drawn under: a Zeus edit that changes it redraws them
// (aegism_network_fnc_zeusApplySite).
_logic setVariable ["AEGISM_ringsApplied", [_logic getVariable ["threatRings", false], _logic getVariable ["sharedCoordinator", false], _logic getVariable ["protectRadius", 750]], false];

// Its status terminals: the laptops synced to it, on every machine and for
// anyone joining later. One synced or unsynced later is the poll's (below).
if (isServer) then {
    {
        if ([_x] call aegism_network_fnc_isTerminal) then { [_x, _logic] remoteExec ["aegism_network_fnc_terminalAction", 0, _x]; };
    } forEach (synchronizedObjects _logic);
};

[
    _logic,
    {
        params ["_object", "_data"];
        _object = vehicle _object;
        if ([_object] call aegism_network_fnc_isTerminal) exitWith {
            [_object, _data get "logic"] remoteExec ["aegism_network_fnc_terminalAction", 0, _object];
        };
        if (!(_object isKindOf "AllVehicles") || {_object isKindOf "CAManBase"}) exitWith {};
        private _siteLogic = _data get "logic";
        _object setVariable ["AEGISM_network", _siteLogic, false];
        // The Site's CURRENT settings -- a Zeus edit (aegism_network_fnc_
        // zeusApplySite) replaces them after this init.
        _object setVariable ["AEGISM_engagement", _siteLogic getVariable "AEGISM_engagement", false];
        _object setVariable ["AEGISM_crew", _siteLogic getVariable "AEGISM_crew", false];
        // remoteExecCall to EVERY machine (target 0) -- this callback runs
        // server-only (aegism_fnc_pollSyncedObjects), and disableAI is
        // local AI state, so it must reach wherever the crew is simulated.
        // Target 0, not -2: -2 ("all except server") executes NOWHERE in
        // singleplayer/Preview, so a Zeus-synced vehicle's AI was never
        // actually suppressed there.
        [_object, allTurrets _object, true] remoteExecCall ["aegism_fnc_setWeaponAiSuppressed", 0];
        private _members = _siteLogic getVariable ["AEGISM_networkMembers", []];
        _members pushBackUnique _object;
        _siteLogic setVariable ["AEGISM_networkMembers", _members, false];
        // Adopt it now if its first scan deferred it (see aegism_system_fnc_
        // moduleInit's adoption policy).
        [_object] call aegism_system_fnc_moduleInit;
    },
    {
        params ["_object", "_data"];
        _object = vehicle _object;
        if ([_object] call aegism_network_fnc_isTerminal) exitWith {
            [_object, objNull] remoteExec ["aegism_network_fnc_terminalAction", 0, _object];
        };
        if (!(_object isKindOf "AllVehicles") || {_object isKindOf "CAManBase"}) exitWith {};
        private _siteLogic = _data get "logic";
        private _members = _siteLogic getVariable ["AEGISM_networkMembers", []];
        _siteLogic setVariable ["AEGISM_networkMembers", _members - [_object], false];
        // Still synced to another Site (it linked the two, aegism_network_
        // fnc_linkSites): it stays under AEGIS-M, reporting to that one.
        private _owners = missionNamespace getVariable ["AEGISM_allPoolOwners", []];
        private _otherIndex = _owners findIf { !isNull _x && {_x != _siteLogic} && {_object in (_x getVariable ["AEGISM_networkMembers", []])} };
        if (_otherIndex != -1) exitWith {
            private _other = _owners select _otherIndex;
            if ((_object getVariable ["AEGISM_network", objNull]) == _siteLogic) then {
                _object setVariable ["AEGISM_network", _other, false];
                _object setVariable ["AEGISM_engagement", _other getVariable "AEGISM_engagement", false];
                _object setVariable ["AEGISM_crew", _other getVariable "AEGISM_crew", false];
            };
        };
        _object setVariable ["AEGISM_network", nil, false];
        _object setVariable ["AEGISM_engagement", nil, false];
        _object setVariable ["AEGISM_crew", nil, false];
        _object setVariable ["AEGISM_assigned", nil, false];
        // Restore full native AI only if this vehicle isn't ALSO a
        // recognized System in its own right (aegism_system_fnc_moduleInit
        // applies its own, narrower suppression independently of the Site
        // sync -- unsyncing from a Site shouldn't re-enable firing on a
        // vehicle that's still a standalone AEGIS-M launcher/CIWS).
        //
        // Deliberately re-checked via aegism_system_fnc_discoverCapabilities
        // directly here, NOT via the "AEGISM_system" variable -- that
        // variable is written local-only (setVariable's global flag is
        // false) by whichever machine's own discovery scan happens to reach
        // this vehicle first, per that function's own doc comment. This
        // poll only ever runs on the server (aegism_fnc_pollSyncedObjects
        // is isServer-gated), so on a dedicated MP server the server's own
        // copy of "AEGISM_system" can be nil even though a CLIENT already
        // recognized this vehicle as a System -- checking that variable
        // here would then wrongly restore full native AI on a vehicle
        // that's still meant to be under AEGIS-M's control. Capability
        // discovery is a pure config/loadout read with no dependency on
        // which machine asks, so it gives the same answer everywhere.
        private _capabilities = [_object] call aegism_system_fnc_discoverCapabilities;
        private _stillASystem = (_capabilities get "hasRadar") || {(_capabilities get "launcherWeapons") isNotEqualTo []} || {(_capabilities get "ciwsWeapons") isNotEqualTo []};
        if (!_stillASystem) then {
            // remoteExecCall for the same reason as the apply callback
            // above -- this restore must reach every machine's own local
            // AI simulation, not just the server's.
            [_object, allTurrets _object, false] remoteExecCall ["aegism_fnc_setWeaponAiSuppressed", 0];
        };
    },
    createHashMapFromArray [["logic", _logic]],
    5,
    {
        params ["_logic", "_logicNetId"];
        private _allOwners = missionNamespace getVariable ["AEGISM_allPoolOwners", []];
        missionNamespace setVariable ["AEGISM_allPoolOwners", _allOwners - [_logic]];
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " WARNING: Site (netId %1) was deleted -- pruned from AEGISM_allPoolOwners. Any vehicle still referencing it will lose battery contacts/deconfliction.", _logicNetId];
    }
] call aegism_fnc_pollSyncedObjects;

// Server-only, same reasoning as aegism_system_fnc_moduleInit's own
// detection/engagement loops: this mutates AEGISM_claims (shared, Site-
// wide state), so registering it on every client would have each one
// independently compute and stomp on the same assignments. Every 0.5s;
// member engagement loops tick at 0.1s and work the published assignments
// in between. The Site's alarm (aegism_network_fnc_siteAlarm) follows the
// assignments it has just made; its sound stops with the Site.
if (isServer) then {
    // Every frame, but only working every AEGISM_COORDINATOR_INTERVAL s --
    // or at once when a munition close to impact has just come into the
    // picture ("AEGISM_assignNow", aegism_detect_fnc_munitionCheck): waiting
    // for the next turn cost up to half a second of the seconds it has left.
    // Between turns, the launcher shots of the munitions whose look its
    // last run put off are worked out ("AEGISM_assignMore", aegism_
    // intercept_fnc_planAhead).
    [{
        params ["_args", "_pfhHandle"];
        _args params ["_logic", "_alarm", "_lastTime", "_seenAt"];
        // Gone: each player's machine stops its alarm by itself (aegism_
        // network_fnc_alarmPlayer).
        if (isNull _logic) exitWith {
            [_pfhHandle] call CBA_fnc_removePerFrameHandler;
        };
        // Paused (game time not moving since the last frame): nothing has
        // changed. A paused game used to keep the coordinator running twice
        // a second.
        if (CBA_missionTime == _seenAt) exitWith {};
        _args set [3, CBA_missionTime];
        if (CBA_missionTime < _lastTime + AEGISM_COORDINATOR_INTERVAL && {!(_logic getVariable ["AEGISM_assignNow", false])}) exitWith {
            if ((_logic getVariable ["AEGISM_assignMore", false]) && {(_logic getVariable ["AEGISM_linkLead", _logic]) == _logic}) then {
                [_logic] call aegism_intercept_fnc_planAhead;
            };
        };
        _logic setVariable ["AEGISM_assignNow", false, false];
        _args set [2, CBA_missionTime];
        // Linked to another Site through a shared vehicle: the group's lead
        // coordinates the whole group (aegism_network_fnc_linkSites).
        [] call aegism_network_fnc_linkSites;
        // Its first tick: its threat rings, with its whole linked group's.
        if (_logic getVariable ["AEGISM_ringsPending", false]) then {
            { _x setVariable ["AEGISM_ringsPending", false, false]; } forEach (_logic getVariable ["AEGISM_linkSites", [_logic]]);
            [_logic] call aegism_network_fnc_drawThreatRings;
        };
        if ((_logic getVariable ["AEGISM_linkLead", _logic]) == _logic) then {
            [_logic] call aegism_intercept_fnc_assignEngagements;
        };
        [_logic, _alarm] call aegism_network_fnc_siteAlarm;
    }, 0, [_logic, ["", "", 0], -1, -1]] call CBA_fnc_addPerFrameHandler;
};

diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " Site %1 established with %2 member vehicle(s) -- allowlist=%3", _logic, count _units, _allowlist];
