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
    engagement-assignment ledger ("AEGISM_claims", HashMap of contact netId
    -> array of per-role assignment records, written once per tick by
    aegism_intercept_fnc_assignEngagements -- see that function's own doc
    comment for the record shape and scoring -- and read/executed by every
    member System's own aegism_intercept_fnc_engagementLoop so two Systems
    in the same battery are coordinated rather than independently converging
    on the same contact), and member registry ("AEGISM_networkMembers").
    Registers itself on the global "AEGISM_allPoolOwners" list
    (missionNamespace) so the detection loop's trackers can find it without
    a per-tick module-logic scan.

    Also registers a server-only per-tick call into aegism_intercept_fnc_
    assignEngagements for this Site (below), at the same cadence as
    engagementLoop so a member System's own tick always sees a fresh
    assignment.

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

params ["_logic", "_units", "_activated"];

// isGlobal = 1 (below) guarantees this runs on every machine, but a module
// logic object can't cross the network as an object reference -- each
// machine gets its netId string instead. Without this normalization every
// getVariable/setVariable call on _logic below silently throws a type
// error and the whole doctrine/personality block never applies, leaving
// every synced vehicle running its own uncoordinated default settings.
if (_logic isEqualType "") then { _logic = objectFromNetId _logic; };
if (isNull _logic) exitWith {};

private _allowlist = [];
if (_logic getVariable ["allowMissile", true]) then { _allowlist pushBack "missile"; };
if (_logic getVariable ["allowRocket", true]) then { _allowlist pushBack "rocket"; };
if (_logic getVariable ["allowBomb", true]) then { _allowlist pushBack "bomb"; };
if (_logic getVariable ["allowArtilleryShell", true]) then { _allowlist pushBack "artilleryShell"; };
if (_logic getVariable ["allowFixedWing", true]) then { _allowlist pushBack "fixedWing"; };
if (_logic getVariable ["allowHelicopter", true]) then { _allowlist pushBack "helicopter"; };
if (_logic getVariable ["allowDrone", true]) then { _allowlist pushBack "drone"; };

private _engagementData = createHashMapFromArray [
    ["minRange", _logic getVariable ["minRange", 500]],
    ["maxRange", _logic getVariable ["maxRange", 8000]],
    ["minAltitude", _logic getVariable ["minAltitude", 0]],
    ["maxAltitude", _logic getVariable ["maxAltitude", 6000]],
    ["targetPriority", _logic getVariable ["targetPriority", "nearest"]],
    ["salvoSize", _logic getVariable ["salvoSize", 1]],
    ["minShotInterval", _logic getVariable ["minShotInterval", 4]],
    ["targetClassAllowlist", _allowlist],
    ["ciwsLastResort", _logic getVariable ["ciwsLastResort", false]]
];

private _crewData = createHashMapFromArray [
    ["skillTier", _logic getVariable ["skillTier", "regular"]],
    ["temperament", _logic getVariable ["temperament", "standard"]],
    ["costValueJudgment", _logic getVariable ["costValueJudgment", false]]
];

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
} forEach _units;

[
    _logic,
    {
        params ["_object", "_data"];
        private _siteLogic = _data get "logic";
        _object setVariable ["AEGISM_network", _siteLogic, false];
        _object setVariable ["AEGISM_engagement", _data get "engagementData", false];
        _object setVariable ["AEGISM_crew", _data get "crewData", false];
        private _members = _siteLogic getVariable ["AEGISM_networkMembers", []];
        _members pushBackUnique _object;
        _siteLogic setVariable ["AEGISM_networkMembers", _members, false];
    },
    {
        params ["_object", "_data"];
        private _siteLogic = _data get "logic";
        _object setVariable ["AEGISM_network", nil, false];
        _object setVariable ["AEGISM_engagement", nil, false];
        _object setVariable ["AEGISM_crew", nil, false];
        private _members = _siteLogic getVariable ["AEGISM_networkMembers", []];
        _siteLogic setVariable ["AEGISM_networkMembers", _members - [_object], false];
    },
    createHashMapFromArray [["logic", _logic], ["engagementData", _engagementData], ["crewData", _crewData]],
    5,
    {
        params ["_logic", "_logicNetId"];
        private _allOwners = missionNamespace getVariable ["AEGISM_allPoolOwners", []];
        missionNamespace setVariable ["AEGISM_allPoolOwners", _allOwners - [_logic]];
        diag_log text format ["[AEGIS-M] WARNING: Site (netId %1) was deleted -- pruned from AEGISM_allPoolOwners. Any vehicle still referencing it will lose battery contacts/deconfliction.", _logicNetId];
    }
] call aegism_fnc_pollSyncedObjects;

// Server-only, same reasoning as aegism_system_fnc_moduleInit's own
// detection/engagement loops: this mutates AEGISM_claims (shared, Site-
// wide state), so registering it on every client would have each one
// independently compute and stomp on the same assignments. Runs at the
// same 0.5s cadence as aegism_intercept_fnc_engagementLoop so a member
// System's own tick always sees a fresh assignment rather than one already
// a full interval stale.
if (isServer) then {
    [{
        params ["_args", "_pfhHandle"];
        _args params ["_logic"];
        if (isNull _logic) exitWith {
            [_pfhHandle] call CBA_fnc_removePerFrameHandler;
        };
        [_logic] call aegism_intercept_fnc_assignEngagements;
    }, 0.5, [_logic]] call CBA_fnc_addPerFrameHandler;
};

diag_log text format ["[AEGIS-M] Site %1 established with %2 member vehicle(s) -- allowlist=%3", _logic, count _units, _allowlist];
