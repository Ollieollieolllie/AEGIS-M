/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_turretPoints

Description:
    World positions of a turret's muzzle (where rounds/missiles leave) and
    of its aiming camera (what lockCameraTo points), from the turret's own
    config memory points (resolved once per vehicle type, aegism_intercept_
    fnc_turretConfig).

        muzzle - gunBeg for a gun, missileBeg for a launcher (falling back
            to the other if one is missing)
        camera - uavCameraGunnerPos for an unmanned turret, otherwise
            memoryPointGunnerOptics

    Why both: lockCameraTo points the CAMERA at the aim point, and the
    barrel runs parallel to it but offset (often by about a metre), so every
    round passed the target by that offset -- CIWS rounds landing about a
    metre low at all ranges. Solving the lead from the muzzle and shifting
    the camera's lock point by (camera - muzzle) makes the barrel line itself
    pass through the aim point.

    Missing memory points fall back to the turret crewman's eye position
    (or the vehicle's position if the turret is empty).

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
