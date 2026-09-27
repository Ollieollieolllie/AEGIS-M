/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_moduleInit

Description:
    Entry point run when an AEGISM_Module_System is placed and synced in
    Eden or Zeus. Reads the module's role checkboxes and role-specific
    attributes, stores the resulting System data on the synced vehicle
    ("AEGISM_system"), then resolves and caches that vehicle's contact
    source, Engagement Settings, and Crew per the link validation rules in
    the AEGIS-M architecture plan (section 1), caching them as
    "AEGISM_resolvedContactSource" / "AEGISM_resolvedEngagementSettings" /
    "AEGISM_resolvedCrew". If the resolved contact source includes its own
    Radar role, also initializes "AEGISM_pooledContacts" (HashMap, see
    aegism_detect_fnc_addContact) so the detection loop has somewhere to
    store this System's own sensor contacts. Runs once at mission init;
    link resolution is not re-run automatically if modules are synced/
    unsynced later at runtime.

    Role bitmask stored in AEGISM_system's "roleMask" key: Radar = 1,
    Launcher = 2, CIWS = 4 (any combination).

Parameters:
    _logic - the module logic object <OBJECT>
    _units - synced units, expects exactly one: the target vehicle <ARRAY of OBJECT>
    _activated - module activation state (unused, modules run on init) <BOOLEAN>

Returns:
    Nothing

Examples:
    [_logic, _units, _activated] call aegism_system_fnc_moduleInit;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_logic", "_units", "_activated"];

if (_units isEqualTo []) exitWith {
    diag_log text format ["[AEGIS-M] WARNING: AEGISM_Module_System %1 was placed with no synced vehicle -- ignoring.", _logic];
};

private _vehicle = _units select 0;

private _roleMask = 0;
if (_logic getVariable ["roleRadar", false]) then { _roleMask = _roleMask + 1; };
if (_logic getVariable ["roleLauncher", false]) then { _roleMask = _roleMask + 2; };
if (_logic getVariable ["roleCiws", false]) then { _roleMask = _roleMask + 4; };

private _systemData = createHashMapFromArray [
    ["roleMask", _roleMask],
    ["radarDetectionRange", _logic getVariable ["radarDetectionRange", 4000]],
    ["radarArc", _logic getVariable ["radarArc", 360]],
    ["passiveOpticalRange", _logic getVariable ["passiveOpticalRange", 2000]],
    ["missileCount", _logic getVariable ["missileCount", 4]],
    ["reloadTime", _logic getVariable ["reloadTime", 30]],
    ["guidanceSpeed", _logic getVariable ["guidanceSpeed", 800]],
    ["guidanceN", _logic getVariable ["guidanceN", 4]],
    ["ciwsGuidanceSpeed", _logic getVariable ["ciwsGuidanceSpeed", 1100]],
    ["ciwsGuidanceN", _logic getVariable ["ciwsGuidanceN", 5]]
];

_vehicle setVariable ["AEGISM_system", _systemData, false];

private _contactSource = [_vehicle] call aegism_system_fnc_resolveContactSource;
private _engagementSettings = [_vehicle] call aegism_system_fnc_resolveEngagementSettings;
private _crew = [_vehicle] call aegism_system_fnc_resolveCrew;

_vehicle setVariable ["AEGISM_resolvedContactSource", _contactSource, false];
_vehicle setVariable ["AEGISM_resolvedEngagementSettings", _engagementSettings, false];
_vehicle setVariable ["AEGISM_resolvedCrew", _crew, false];

if ("ownRadar" in _contactSource) then {
    _vehicle setVariable ["AEGISM_pooledContacts", createHashMap, false];
    private _allOwners = missionNamespace getVariable ["AEGISM_allPoolOwners", []];
    _allOwners pushBackUnique _vehicle;
    missionNamespace setVariable ["AEGISM_allPoolOwners", _allOwners];

    [{
        params ["_args", "_pfhHandle"];
        _args params ["_vehicle"];
        if (isNull _vehicle) exitWith {
            [_pfhHandle] call CBA_fnc_removePerFrameHandler;
        };
        [_vehicle] call aegism_detect_fnc_confidenceLoop;
    }, 1, [_vehicle]] call CBA_fnc_addPerFrameHandler;
};

diag_log text format ["[AEGIS-M] System initialized on %1 -- roleMask=%2 contactSource=%3", _vehicle, _roleMask, _contactSource];
