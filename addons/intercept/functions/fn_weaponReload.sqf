/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_weaponReload
Description:
    Whether a turret's weapon can fire right now, from the engine's own
    reload state (weaponState [vehicle, turret, weapon], Arma 3 2.06+):
        magazineReloadPhase - 1 -> 0 while it loads its next magazine, 0
            once loaded; the time left is that times the weapon's CfgWeapons
            magazineReloadTime
        roundReloadPhase - while it readies the next round (-1 with no
            magazine); the time left is that times its fire mode's
            reloadTime (aegism_intercept_fnc_fireModeStats)

    A launcher that has just fired the last missile of a magazine already
    shows the next magazine's full count while it's still loading it, and a
    fire command then fires nothing: POOK's 9K331 fired six times into its
    reload, each taken for a missed shot, and its targets got through
    (2026-10-06). POOK's launchers reload for minutes (the S-125's
    magazineReloadTime is 900 s).

Parameters:
    _system - the vehicle <OBJECT>
    _turretPath - turret path <ARRAY>
    _weaponClass - CfgWeapons class <STRING>

Returns:
    [ready <BOOLEAN>, seconds until it is (0 if it is, or if its config
     gives no reload time) <NUMBER>, loading a magazine <BOOLEAN>,
     [roundReloadPhase, magazineReloadPhase] as reported <ARRAY>] <ARRAY>

Examples:
    [_tor, [0], "pook_9K331_TLAR"] call aegism_intercept_fnc_weaponReload;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_system", "_turretPath", "_weaponClass"];

(weaponState [_system, _turretPath, _weaponClass]) params ["", "", "", "", "", ["_roundPhase", 0], ["_magazinePhase", 0]];

private _loading = _magazinePhase > 0;
private _wait = 0;
if (_loading) then {
    _wait = _magazinePhase * getNumber (configFile >> "CfgWeapons" >> _weaponClass >> "magazineReloadTime");
};
if (_roundPhase > 0) then {
    _wait = _wait max (_roundPhase * (([_system, _turretPath, _weaponClass] call aegism_intercept_fnc_fireModeStats) select 2));
};

[!_loading && {_roundPhase == 0}, _wait max 0, _loading, [_roundPhase, _magazinePhase]]
