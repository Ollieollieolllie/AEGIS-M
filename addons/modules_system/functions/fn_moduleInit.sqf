/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_moduleInit

Description:
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
        - with its own radar: its own pool ("AEGISM_pooledContacts") and a
          1-second detection loop (aegism_detect_fnc_confidenceLoop).
        - one 0.1-second engagement loop per weapon role (aegism_intercept_
          fnc_engagementLoop).
    Registering the loops on every machine would make every client detect
    the same contact and fire its own redundant shot.

    Capability discovery only ever happens once -- a vehicle's turrets and
    sensors are fixed for its lifetime; ammo is re-checked at fire time.

Parameters:
    _vehicle - the vehicle to set up as an AEGIS-M System <OBJECT>

Returns:
    Nothing

Examples:
    [_tigris] call aegism_system_fnc_moduleInit;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_vehicle"];

if (isNull _vehicle) exitWith {};
if (_vehicle getVariable ["AEGISM_systemInitialized", false]) exitWith {};

// Aircraft and infantry are never AEGIS-M Systems -- they are what air
// defence shoots AT. Without this, an attack helicopter's radar + AA
// missiles + minigun made it a "System" and AEGIS-M suppressed its gunner.
if (_vehicle isKindOf "Air" || {_vehicle isKindOf "CAManBase"} || {!(_vehicle isKindOf "AllVehicles")}) exitWith {
    _vehicle setVariable ["AEGISM_systemInitialized", true, false];
};

private _capabilities = [_vehicle] call aegism_system_fnc_discoverCapabilities;
private _hasWeapons = (_capabilities get "launcherWeapons") isNotEqualTo [] || {(_capabilities get "ciwsWeapons") isNotEqualTo []};
private _hasAnyCapability = (_capabilities get "hasRadar") || _hasWeapons;
if (!_hasAnyCapability) exitWith {
    _vehicle setVariable ["AEGISM_systemInitialized", true, false];
    diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " DISCOVERY: %1 (%2) has no AEGIS-M-qualifying capability -- no radar sensor, no air-capable missile, no high-ROF air-capable gun.", _vehicle, typeOf _vehicle];
};

// Adoption policy: a vehicle synced to a Site is always adopted (the
// mission designer chose it). An UNSYNCED vehicle is only adopted as a
// standalone System if standalone air defence is enabled AND it is a
// self-contained AA platform -- its own radar plus its own AA weapons
// (a Cheetah/Tigris-style SPAAG). Anything else is deferred, not rejected:
// aegism_network_fnc_moduleInit re-runs this function when the vehicle is
// later synced to a Site.
private _synced = !isNull (_vehicle getVariable ["AEGISM_network", objNull]);
private _standaloneEligible = ("aegism_main_standaloneAdoption" call CBA_settings_fnc_get) && {_capabilities get "hasRadar"} && _hasWeapons;
if (!_synced && !_standaloneEligible) exitWith {
    if !(_vehicle getVariable ["AEGISM_systemDeferred", false]) then {
        _vehicle setVariable ["AEGISM_systemDeferred", true, false];
        diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " DISCOVERY: %1 (%2) has AEGIS-M capability (radar=%3 launchers=%4 ciws=%5) but is not synced to a Site and is not a self-contained AA platform (or standalone adoption is disabled) -- deferred until synced.", _vehicle, typeOf _vehicle, _capabilities get "hasRadar", count (_capabilities get "launcherWeapons"), count (_capabilities get "ciwsWeapons")];
    };
};

_vehicle setVariable ["AEGISM_systemInitialized", true, false];
_vehicle setVariable ["AEGISM_systemDeferred", false, false];
_vehicle setVariable ["AEGISM_system", _capabilities, false];

// Suppress the crew's own independent targeting/engagement on every
// discovered launcher/CIWS turret (see aegism_fnc_setWeaponAiSuppressed's
// own doc comment for why) -- on every machine, since disableAI affects
// local AI simulation and needs to apply wherever this vehicle's crew is
// actually simulated (a headless client, a player's AI group), not just the
// server.
private _weaponTurretPaths = ((_capabilities get "launcherWeapons") + (_capabilities get "ciwsWeapons")) apply { _x select 0 };
if (_weaponTurretPaths isNotEqualTo []) then {
    [_vehicle, _weaponTurretPaths, true] call aegism_fnc_setWeaponAiSuppressed;
};

// Everything below is the engagement pipeline: server only. A client has no
// use for it (the pools, claims and loops only exist on the server; the
// debug overlays only show data where the server runs), and used to carry
// a cleanup handler per System for nothing.
if (!isServer) exitWith {};

// Every recognized System, radar or not -- distinct from AEGISM_allPoolOwners
// below, which only ever gains a vehicle with real "ownRadar" capability
// (that list exists purely so the detection loop knows which vehicles have
// a pool worth scanning). Read by the debug overlays (aegism_fnc_debugDraw,
// aegism_fnc_debugHint), which drop dead entries as they go.
private _allSystems = missionNamespace getVariable ["AEGISM_allSystems", []];
_allSystems pushBackUnique _vehicle;
missionNamespace setVariable ["AEGISM_allSystems", _allSystems, false];

private _overrides = [_vehicle] call aegism_system_fnc_resolveSettings;
if (_overrides isNotEqualTo []) then {
    diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " OVERRIDES: %1 uses its own vehicle settings instead of its Site's: %2", _vehicle, _overrides joinString ", "];
};
private _contactSource = _vehicle getVariable "AEGISM_resolvedContactSource";

[{
    params ["_args", "_pfhHandle"];
    _args params ["_vehicle"];
    if (isNull _vehicle || {!alive _vehicle}) exitWith {
        [_pfhHandle] call CBA_fnc_removePerFrameHandler;
    };
    [_vehicle] call aegism_system_fnc_resolveSettings;
}, 5, [_vehicle]] call CBA_fnc_addPerFrameHandler;

if ("ownRadar" in _contactSource) then {
    _vehicle setVariable ["AEGISM_pooledContacts", createHashMap, false];

    private _allOwners = missionNamespace getVariable ["AEGISM_allPoolOwners", []];
    _allOwners pushBackUnique _vehicle;
    missionNamespace setVariable ["AEGISM_allPoolOwners", _allOwners];

    [{
        params ["_args", "_pfhHandle"];
        _args params ["_vehicle", "_lastTime"];
        if (isNull _vehicle || {!alive _vehicle}) exitWith {
            private _allOwners = missionNamespace getVariable ["AEGISM_allPoolOwners", []];
            missionNamespace setVariable ["AEGISM_allPoolOwners", _allOwners - [_vehicle]];
            [_pfhHandle] call CBA_fnc_removePerFrameHandler;
        };
        // Paused (game time not moving): nothing to detect.
        if (time == _lastTime) exitWith {};
        _args set [1, time];
        [_vehicle] call aegism_detect_fnc_confidenceLoop;
    }, 1, [_vehicle, -1]] call CBA_fnc_addPerFrameHandler;
};

// Every weapon ticks at 0.1s: its turret has to keep re-aiming at a moving
// lead point. A tick with nothing assigned (or nothing in a standalone
// System's pool) returns before doing any real work.
private _activeWeaponRoles = [];
if ((_capabilities get "launcherWeapons") isNotEqualTo []) then { _activeWeaponRoles pushBack "launcher"; };
if ((_capabilities get "ciwsWeapons") isNotEqualTo []) then { _activeWeaponRoles pushBack "ciws"; };
{
    [{
        params ["_args", "_pfhHandle"];
        _args params ["_vehicle", "_role", "_lastTime"];
        if (isNull _vehicle || {!alive _vehicle}) exitWith {
            [_pfhHandle] call CBA_fnc_removePerFrameHandler;
        };
        // Paused (game time not moving): nothing to do.
        if (time == _lastTime) exitWith {};
        _args set [2, time];
        [_vehicle, _role] call aegism_intercept_fnc_engagementLoop;
    }, 0.1, [_vehicle, _x, -1]] call CBA_fnc_addPerFrameHandler;
} forEach _activeWeaponRoles;

diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " System initialized on %1 -- hasRadar=%2 launcherWeapons=%3 ciwsWeapons=%4 contactSource=%5", _vehicle, _capabilities get "hasRadar", count (_capabilities get "launcherWeapons"), count (_capabilities get "ciwsWeapons"), _contactSource];
