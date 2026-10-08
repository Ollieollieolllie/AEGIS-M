/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_infiniteAmmo

Description:
    Gives a turret back what it has fired of one magazine class (the
    Infinite Ammo setting): its loaded magazine topped up, and a magazine
    for each one it has used up.
    Full notes: docs/functions/intercept.md

Parameters:
    _system - the vehicle <OBJECT>
    _turretPath - turret path <ARRAY>
    _magazineClass - CfgMagazines class <STRING>
    _weaponClass - optional, the weapon it's for: loaded with it if it has
        none loaded <STRING>

Returns:
    Nothing

Examples:
    [_spartan, [0], "magazine_Missile_rim116_x21", "weapon_rim116Launcher"] call aegism_intercept_fnc_infiniteAmmo;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_system", "_turretPath", "_magazineClass", ["_weaponClass", ""]];

if (isNull _system || {!alive _system} || {_magazineClass == ""} || {!(_system turretLocal _turretPath)}) exitWith {};

// A magazine for each one of this class the turret has used up since set-up
// (aegism_intercept_fnc_firedHandler keeps what it carried then).
private _fnMine = { (_x select 0) == _magazineClass && {(_x select 1) isEqualTo _turretPath} };
private _atStart = _fnMine count (_system getVariable ["AEGISM_magazinesAtStart", []]);
private _have = { (_x call _fnMine) && {(_x select 2) > 0} } count (magazinesAllTurrets _system);
for "_i" from 1 to (_atStart - _have) do { _system addMagazineTurret [_magazineClass, _turretPath]; };

// Its loaded magazine topped up while it still has a round: one that has
// run out is left to the weapon's own change of magazine, so that still
// takes its time (see notes).
private _full = getNumber (configFile >> "CfgMagazines" >> _magazineClass >> "count");
private _loaded = _system magazineTurretAmmo [_magazineClass, _turretPath];
if (_loaded > 0 && {_loaded < _full}) then { _system setMagazineTurretAmmo [_magazineClass, _full, _turretPath]; };
if (_loaded <= 0 && {_have == 0} && {_atStart > 0} && {_weaponClass != ""}) then { _system loadMagazine [_turretPath, _weaponClass, _magazineClass]; };
