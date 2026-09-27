/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_moduleInit

Description:
    Entry point run when an AEGISM_Module_Site is placed and synced in Eden
    or Zeus. This is the one AEGIS-M module a mission designer places: sync
    it to every radar, launcher, SHORAD, and CIWS vehicle that makes up a
    site to link them into a battery. Each vehicle declares its own role
    (Radar/Launcher/CIWS) and role-specific tuning directly on its own
    Attributes panel (see AllVehicles in addons/main/config.cpp) rather than
    via a separate module -- this module only carries the doctrine
    (engagement envelope, target priority, salvo policy, target-class
    allowlist) and personality (skill tier, temperament, cost/value
    judgment) that apply battery-wide, per the object -> network -> default
    resolution order in aegism_system_fnc_resolveEngagementSettings /
    resolveCrew.

    Writes "AEGISM_network" (pointing at this Site's logic object),
    "AEGISM_engagement", and "AEGISM_crew" onto every synced vehicle, and
    initializes this Site's own pooled-contact list ("AEGISM_
    pooledContacts", populated by radar-capable member Systems' own native
    sensors, see aegism_detect_fnc_confidenceLoop), target-deconfliction ledger
    ("AEGISM_claims", HashMap of contact netId -> [claiming System object,
    claim timestamp], read/renewed by aegism_intercept_fnc_selectTarget /
    engagementLoop so two Systems in the same battery don't both spend
    interceptors on the same single contact), and member registry
    ("AEGISM_networkMembers"). Registers itself on the global "AEGISM_
    allPoolOwners" list (missionNamespace) so the detection loop's trackers
    can find it without a per-tick module-logic scan.

    A vehicle's own Radar/Launcher/CIWS setup (aegism_system_fnc_moduleInit)
    is intentionally NOT triggered from here -- it's driven independently by
    aegism_fnc_scanForRoles's periodic discovery sweep (addons/main), so a
    role-flagged vehicle works standalone (with default doctrine/personality
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
    ["targetClassAllowlist", _allowlist]
];

private _crewData = createHashMapFromArray [
    ["skillTier", _logic getVariable ["skillTier", "regular"]],
    ["temperament", _logic getVariable ["temperament", "standard"]],
    ["costValueJudgment", _logic getVariable ["costValueJudgment", false]]
];

_logic setVariable ["AEGISM_pooledContacts", createHashMap, false];
_logic setVariable ["AEGISM_claims", createHashMap, false];
_logic setVariable ["AEGISM_networkMembers", _units, false];

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

diag_log text format ["[AEGIS-M] Site %1 established with %2 member vehicle(s) -- allowlist=%3", _logic, count _units, _allowlist];
