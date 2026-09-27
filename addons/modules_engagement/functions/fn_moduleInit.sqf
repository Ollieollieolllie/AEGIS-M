/* ----------------------------------------------------------------------------
Function: aegism_engagement_fnc_moduleInit

Description:
    Entry point run when an AEGISM_Module_EngagementSettings is placed and
    synced in Eden or Zeus. Reads the module's doctrine attributes and
    stores the resulting data ("AEGISM_engagement") on every synced object
    -- one or more AEGISM_Module_System vehicles for a per-site override, or
    a single AEGISM_Module_Network object to apply the doctrine battery-wide
    (per the object -> network -> default resolution order in
    aegism_system_fnc_resolveEngagementSettings).

Parameters:
    _logic - the module logic object <OBJECT>
    _units - synced objects: AEGISM_Module_System vehicles and/or an
        AEGISM_Module_Network object <ARRAY of OBJECT>
    _activated - module activation state (unused, modules run on init) <BOOLEAN>

Returns:
    Nothing

Examples:
    [_logic, _units, _activated] call aegism_engagement_fnc_moduleInit;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_logic", "_units", "_activated"];

if (_units isEqualTo []) exitWith {
    diag_log text format ["[AEGIS-M] WARNING: AEGISM_Module_EngagementSettings %1 was placed with no synced object -- ignoring.", _logic];
};

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

{
    _x setVariable ["AEGISM_engagement", _engagementData, false];
} forEach _units;

diag_log text format ["[AEGIS-M] EngagementSettings %1 applied to %2 synced object(s) -- allowlist=%3", _logic, count _units, _allowlist];
