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

Parameters:
    _vehicle - the vehicle to set up as an AEGIS-M System <OBJECT>

Returns:
    Nothing

Examples:
    [_tigris] call aegism_system_fnc_moduleInit;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\rpt.hpp"

// Seconds between sensor reads while any munition is in flight (once a
// second otherwise).
#define AEGISM_SENSOR_READ_FAST 0.25

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
private _hasSensor = _capabilities get "hasSensor";
private _hasAnyCapability = (_capabilities get "hasRadar") || _hasSensor || _hasWeapons;
// For the log: "radar 16000m 120deg on turret [0], passive 16000m 360deg".
private _sensorText = ((_capabilities get "sensors") apply {
    _x params ["_type", "_range", "_arc", "_aim"];
    format ["%1 %2m %3deg%4", _type, round _range, round _arc, ["", format [" on turret %1", _aim]] select (_aim isNotEqualTo [])]
}) joinString ", ";
if (_sensorText == "") then { _sensorText = "none"; };
if (!_hasAnyCapability) exitWith {
    _vehicle setVariable ["AEGISM_systemInitialized", true, false];
    if (AEGISM_RPT_VERBOSE) then {
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " DISCOVERY: %1 (%2) has no AEGIS-M-qualifying capability -- no radar, IR or visual sensor, no air-capable missile, no high-ROF air-capable gun.", _vehicle, typeOf _vehicle];
    };
};

// Adoption policy: a vehicle synced to a Site is always adopted (the
// mission designer chose it) -- including one whose only capability is a
// sensor, which then feeds the Site what it sees. An UNSYNCED vehicle is
// only adopted as a standalone System if standalone air defence is enabled
// AND it is a self-contained AA platform -- a sensor of its own (radar, IR
// or visual) plus its own AA weapons (a Cheetah/Tigris-style SPAAG, or a
// Spartan with its launcher-mounted IR). Anything else is deferred, not
// rejected: aegism_network_fnc_moduleInit re-runs this function when the
// vehicle is later synced to a Site.
private _synced = !isNull (_vehicle getVariable ["AEGISM_network", objNull]);
private _standaloneEligible = ("aegism_main_standaloneAdoption" call CBA_settings_fnc_get) && _hasSensor && _hasWeapons;
if (!_synced && !_standaloneEligible) exitWith {
    if !(_vehicle getVariable ["AEGISM_systemDeferred", false]) then {
        _vehicle setVariable ["AEGISM_systemDeferred", true, false];
        // Nothing but an IR/visual sensor -- most tanks and IFVs: only of
        // use synced to a Site, so deferred without a word (every armoured
        // vehicle in a mission would otherwise show up as NOT ACTIVE).
        if (!_hasWeapons && {!(_capabilities get "hasRadar")}) exitWith {};
        // Why, and what to do about it -- the debug overlays show it on the
        // vehicle (AEGISM_deferredSystems), so one placed on its own doesn't
        // just sit there silently.
        private _reason = switch (true) do {
            case !_hasSensor: { "no sensor of its own -- sync it to a Site with a radar" };
            case !_hasWeapons: { "radar only -- sync it to a Site to feed its weapons" };
            default { "Standalone Air Defence is off (CBA setting) -- sync it to a Site" };
        };
        _vehicle setVariable ["AEGISM_deferReason", _reason, false];
        private _deferred = missionNamespace getVariable ["AEGISM_deferredSystems", []];
        _deferred pushBackUnique _vehicle;
        missionNamespace setVariable ["AEGISM_deferredSystems", _deferred, false];
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " DISCOVERY: %1 (%2) has AEGIS-M capability (sensors: %3; launchers=%4 ciws=%5) but isn't active: %6. Deferred until synced.", _vehicle, typeOf _vehicle, _sensorText, count (_capabilities get "launcherWeapons"), count (_capabilities get "ciwsWeapons"), _reason];
    };
};

_vehicle setVariable ["AEGISM_systemInitialized", true, false];
_vehicle setVariable ["AEGISM_systemDeferred", false, false];
private _deferred = missionNamespace getVariable ["AEGISM_deferredSystems", []];
if (_vehicle in _deferred) then { missionNamespace setVariable ["AEGISM_deferredSystems", _deferred - [_vehicle], false]; };
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

// Every recognized System, sensor or not -- distinct from AEGISM_allPoolOwners
// below, which only ever gains a vehicle with a sensor of its own
// ("ownSensor": that list exists purely so the detection loops know which
// vehicles have a pool worth scanning). Read by the debug overlays (aegism_fnc_debugDraw,
// aegism_fnc_debugHint), which drop dead entries as they go.
private _allSystems = missionNamespace getVariable ["AEGISM_allSystems", []];
_allSystems pushBackUnique _vehicle;
missionNamespace setVariable ["AEGISM_allSystems", _allSystems, false];

private _overrides = [_vehicle] call aegism_system_fnc_resolveSettings;
if (_overrides isNotEqualTo []) then {
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " OVERRIDES: %1 uses its own vehicle settings instead of its Site's: %2", _vehicle, _overrides joinString ", "];
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

if ("ownSensor" in _contactSource) then {
    _vehicle setVariable ["AEGISM_pooledContacts", createHashMap, false];
    // The highest any AEGIS-M sensor loses a target in ground clutter: a
    // munition proxy below it is moved with its munition, showing its speed
    // (aegism_detect_fnc_munitionTracker).
    missionNamespace setVariable ["AEGISM_clutterHeight", (missionNamespace getVariable ["AEGISM_clutterHeight", -1]) max (_capabilities getOrDefault ["clutterHeight", -1])];

    private _allOwners = missionNamespace getVariable ["AEGISM_allPoolOwners", []];
    _allOwners pushBackUnique _vehicle;
    missionNamespace setVariable ["AEGISM_allPoolOwners", _allOwners];

    // Its radar's emission once a second (Radar Emission), and what its
    // sensors see: once a second, but every AEGISM_SENSOR_READ_FAST s while
    // any munition is in flight -- a munition is a few seconds from impact by
    // the time it's seen, and reading once a second added up to a second
    // before AEGIS-M knew what the game's sensors already showed.
    [{
        params ["_args", "_pfhHandle"];
        _args params ["_vehicle", "_lastTime", "_emconAt", "_readAt"];
        if (isNull _vehicle || {!alive _vehicle}) exitWith {
            private _allOwners = missionNamespace getVariable ["AEGISM_allPoolOwners", []];
            missionNamespace setVariable ["AEGISM_allPoolOwners", _allOwners - [_vehicle]];
            [_pfhHandle] call CBA_fnc_removePerFrameHandler;
        };
        // Paused (game time not moving): nothing to detect.
        if (CBA_missionTime == _lastTime) exitWith {};
        _args set [1, CBA_missionTime];
        if (CBA_missionTime >= _emconAt + 1) then {
            _args set [2, CBA_missionTime];
            [_vehicle] call aegism_system_fnc_emconUpdate;
        };
        private _interval = [1, AEGISM_SENSOR_READ_FAST] select ((missionNamespace getVariable ["AEGISM_trackedMunitions", []]) isNotEqualTo []);
        if (CBA_missionTime >= _readAt + _interval) then {
            _args set [3, CBA_missionTime];
            [_vehicle] call aegism_detect_fnc_confidenceLoop;
        };
    }, AEGISM_SENSOR_READ_FAST, [_vehicle, -1, -1e9, -1e9]] call CBA_fnc_addPerFrameHandler;
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
        if (CBA_missionTime == _lastTime) exitWith {};
        _args set [2, CBA_missionTime];
        [_vehicle, _role] call aegism_intercept_fnc_engagementLoop;
    }, 0.1, [_vehicle, _x, -1]] call CBA_fnc_addPerFrameHandler;
} forEach _activeWeaponRoles;

diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " System initialized on %1 (%2) -- sensors: %3; launcherWeapons=%4 ciwsWeapons=%5 contactSource=%6", _vehicle, typeOf _vehicle, _sensorText, count (_capabilities get "launcherWeapons"), count (_capabilities get "ciwsWeapons"), _contactSource];
