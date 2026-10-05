/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_turningRadar

Description:
    A vehicle's turning radar: an active radar that turns with a turret,
    narrower than all round, on a turret no AEGIS-M weapon uses (the vanilla
    radar truck's 120 degrees) -- the one AEGIS-M points (aegism_system_fnc_
    radarSchedule) and hands the relay scan to (aegism_system_fnc_
    radarRelay).

Parameters:
    _vehicle - the vehicle <OBJECT>

Returns:
    Its sensors entry (aegism_system_fnc_discoverCapabilities), or [] if it
    has none <ARRAY>

Examples:
    [_radarTruck] call aegism_system_fnc_turningRadar;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_vehicle"];

private _system = _vehicle getVariable ["AEGISM_system", createHashMap];
private _weaponTurrets = ((_system getOrDefault ["launcherWeapons", []]) + (_system getOrDefault ["ciwsWeapons", []])) apply { _x select 0 };
((_system getOrDefault ["sensors", []]) select {
    (_x select 0) == "radar" && {(_x select 3) isNotEqualTo []} && {(_x select 2) < 360} && {!((_x select 3) in _weaponTurrets)}
}) param [0, []]
