/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_turretPoints

Description:
    World positions of a turret's muzzle (where rounds/missiles leave) and
    of its aiming camera (what lockCameraTo points), from the turret's own
    config memory points.

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
    (or the vehicle's position if the turret is empty), which is what was
    used before.

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

private _gunner = _system turretUnit _turretPath;
private _fallback = if (isNull _gunner) then { getPosASLVisual _system } else { eyePos _gunner };
private _turretCfg = [_system, _turretPath] call CBA_fnc_getTurret;

// World (ASL) position of the first named memory point that exists.
private _fnPoint = {
    params ["_keys"];
    private _result = [];
    {
        private _name = getText (_turretCfg >> _x);
        if (_result isEqualTo [] && {_name != ""}) then {
            private _modelPos = _system selectionPosition [_name, "Memory"];
            if (_modelPos isNotEqualTo [0, 0, 0]) then { _result = _system modelToWorldVisualWorld _modelPos; };
        };
    } forEach _keys;
    _result
};

private _muzzle = [[["gunBeg", "missileBeg"], ["missileBeg", "gunBeg"]] select (_role == "launcher")] call _fnPoint;
private _camera = [[["memoryPointGunnerOptics"], ["uavCameraGunnerPos", "memoryPointGunnerOptics"]] select (unitIsUAV _system)] call _fnPoint;

[[_muzzle, _fallback] select (_muzzle isEqualTo []), [_camera, _fallback] select (_camera isEqualTo [])]
