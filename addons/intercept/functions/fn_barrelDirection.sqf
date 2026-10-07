/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_barrelDirection

Description:
    World-space unit vector a System weapon's barrel (or missile rail)
    currently points along.
    Full notes: docs/functions/intercept.md

Parameters:
    _system - the vehicle <OBJECT>
    _turretPath - the weapon's turret path <ARRAY>
    _weaponClass - CfgWeapons class <STRING>

Returns:
    Unit direction vector, world space; [0,0,0] if it can't be determined <ARRAY>

Examples:
    [_cram, [1], "pook_SAM_M2HB"] call aegism_intercept_fnc_barrelDirection;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_system", "_turretPath", "_weaponClass"];

private _direction = _system weaponDirection _weaponClass;
if (_direction isNotEqualTo [0, 0, 0]) exitWith { _direction };

{
    _x params ["_beg", "_end"];
    private _axis = (_system selectionPosition [_beg, "Memory"]) vectorDiff (_system selectionPosition [_end, "Memory"]);
    if (_axis isNotEqualTo [0, 0, 0]) exitWith {
        _direction = vectorNormalized (_system vectorModelToWorldVisual _axis);
    };
} forEach (([_system, _turretPath] call aegism_intercept_fnc_turretConfig) select 5);

_direction
