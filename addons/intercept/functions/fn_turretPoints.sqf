/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_turretPoints

Description:
    World positions of a turret's muzzle and of its aiming camera, from the
    turret's config memory points.
    Full notes: docs/functions/intercept.md

Parameters:
    _system - the vehicle <OBJECT>
    _turretPath - turret path <ARRAY>
    _role - "ciws" (gun) or "launcher" (missiles) <STRING>

Returns:
    [muzzle ASL <ARRAY>, camera ASL <ARRAY>]

Examples:
    [_cram, [0], "ciws"] call aegism_intercept_fnc_turretPoints;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_system", "_turretPath", "_role"];

([_system, _turretPath] call aegism_intercept_fnc_turretConfig) params ["_muzzleGun", "_muzzleLauncher", "_cameraPoint"];
private _muzzlePoint = [_muzzleGun, _muzzleLauncher] select (_role == "launcher");

private _fnFallback = {
    private _gunner = _system turretUnit _turretPath;
    if (isNull _gunner) then { getPosASLVisual _system } else { eyePos _gunner }
};

[
    if (_muzzlePoint != "") then { _system modelToWorldVisualWorld (_system selectionPosition [_muzzlePoint, "Memory"]) } else { call _fnFallback },
    if (_cameraPoint != "") then { _system modelToWorldVisualWorld (_system selectionPosition [_cameraPoint, "Memory"]) } else { call _fnFallback }
]
