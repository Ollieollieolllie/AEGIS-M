/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_debugCheckCiws

Description:
    On-demand capability check for a specific vehicle, run from the debug
    console: answers "why isn't this vehicle's gun/launcher being used" by
    running the real aegism_system_fnc_discoverCapabilities and printing
    every qualifying weapon with its real envelope (and burst time for
    CIWS), every loaded magazine with its ammo class and airLock (the
    air-capability gate), and the vehicle's adoption state (synced to a
    Site / deferred / standalone setting). Also shows the cached
    AEGISM_system, in case the loadout changed since discovery.

Parameters:
    _vehicle - the vehicle to check <OBJECT>

Returns:
    Nothing

Examples:
    [cursorObject] call aegism_system_fnc_debugCheckCiws;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_vehicle"];

if (isNull _vehicle) exitWith {
    hint "[AEGIS-M] DEBUG CIWS CHECK: no vehicle given (pass cursorObject or a specific object).";
};

private _lines = [format ["=== AEGIS-M CIWS Check: %1 (%2) ===", _vehicle, typeOf _vehicle]];

private _cachedSystem = _vehicle getVariable "AEGISM_system";
if (isNil "_cachedSystem") then {
    _lines pushBack "Cached AEGISM_system: none -- this vehicle has never been recognized as an AEGIS-M System at all.";
} else {
    _lines pushBack format ["Cached AEGISM_system: hasRadar=%1 launcherWeapons=%2 ciwsWeapons=%3 (from whenever this vehicle was last scanned -- may be stale if the loadout changed since)", _cachedSystem get "hasRadar", count (_cachedSystem get "launcherWeapons"), count (_cachedSystem get "ciwsWeapons")];
};

// Runs the REAL discovery rather than re-implementing it, so this report
// can never drift from what discovery actually decides (an earlier copy of
// the CIWS rate-of-fire logic here did drift). Per-weapon rejection reasons
// are also written to the RPT by discovery itself ("[AEGIS-M] DISCOVERY:").
private _fresh = [_vehicle] call aegism_system_fnc_discoverCapabilities;
_lines pushBack format ["Fresh discovery (right now): hasRadar=%1 (range %2m, arc %3)", _fresh get "hasRadar", round (_fresh get "radarRange"), _fresh get "radarArc"];
{
    _x params ["_turretPath", "_weaponClass", "_magClass", "_size", "_minRange", "_maxRange"];
    _lines pushBack format ["  LAUNCHER turret %1: %2 (%3) -- envelope %4-%5m, warhead radius %6m", _turretPath, _weaponClass, _magClass, round _minRange, round _maxRange, _size];
} forEach (_fresh get "launcherWeapons");
{
    _x params ["_turretPath", "_weaponClass", "_magClass", "", "_minRange", "_maxRange", "_burstTime"];
    _lines pushBack format ["  CIWS turret %1: %2 (%3) -- envelope %4-%5m, burst %6s", _turretPath, _weaponClass, _magClass, round _minRange, round _maxRange, round (_burstTime * 100) / 100];
} forEach (_fresh get "ciwsWeapons");

_lines pushBack "Loaded magazines:";
{
    _x params ["_magClass", "_turretPath"];
    private _ammoClassName = getText (configFile >> "CfgMagazines" >> _magClass >> "ammo");
    _lines pushBack format ["  turret %1: %2 -> ammo %3 (class '%4', airLock %5)", _turretPath, _magClass, _ammoClassName, [_ammoClassName] call aegism_detect_fnc_classifyAmmoClass, getNumber (configFile >> "CfgAmmo" >> _ammoClassName >> "airLock")];
} forEach (magazinesAllTurrets _vehicle);

_lines pushBack format ["Adoption: synced=%1 deferred=%2 standaloneAdoption=%3", !isNull (_vehicle getVariable ["AEGISM_network", objNull]), _vehicle getVariable ["AEGISM_systemDeferred", false], "aegism_main_standaloneAdoption" call CBA_settings_fnc_get];

private _fullMsg = _lines joinString "\n";
hint _fullMsg;
diag_log text _fullMsg;
