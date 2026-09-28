/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_canEngage

Description:
    Whether one weapon can usefully engage one target right now -- the one
    rule the Site coordinator (assign AND release, aegism_intercept_fnc_
    assignEngagements) and standalone target selection (aegism_intercept_
    fnc_selectTarget) share.

        launcher - the target is inside the missile's envelope NOW (lock
            range, doctrine limits: aegism_intercept_fnc_inEnvelope), and
            the missile can actually catch it (a feasible intercept from its
            real speed profile, aegism_intercept_fnc_computeLeadPoint).
        ciws - a feasible intercept exists, and the INTERCEPT point (where
            the rounds would meet the target) is inside the gun's envelope,
            including the minimum elevation of the barrel aimed there.

    Judging a gun at the intercept point is what stops it spending ammunition
    on a jet flying away from it: the jet may be 2000m away "inside" a 2500m
    gun, but the rounds would only catch it far beyond 2500m (or never), so
    it is released instead of claimed forever.

    Velocity-only intercept estimate (no acceleration sampling), so calling
    this has no side effects.

Parameters:
    _system - the System vehicle <OBJECT>
    _role - "launcher" or "ciws" <STRING>
    _weaponInfo - weaponInfo, see aegism_system_fnc_discoverCapabilities <ARRAY>
    _target - the target object <OBJECT>
    _settings - that vehicle's resolved engagement settings <HASHMAP>

Returns:
    [canEngage <BOOLEAN>, reason if not <STRING>, flight time to the
     intercept in seconds, if it can (0 if unknown) <NUMBER>]

Examples:
    [_cheetah, "ciws", _weaponInfo, _jet, _settings] call aegism_intercept_fnc_canEngage;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_system", "_role", "_weaponInfo", "_target", "_settings"];

private _origin = eyePos _system;
private _targetPos = getPosASL _target;
private _height = (ASLToAGL _targetPos) select 2;
private _currentDistance = _origin distance _targetPos;
private _isCiws = _role == "ciws";

private _fnEnvelopeReason = {
    params ["_distance", "_elevation"];
    format ["out of envelope (%1m, %2m AGL, %3 deg elevation)", round _distance, round _height, round (_elevation * 10) / 10]
};

if (!_isCiws) then {
    private _elevation = [_origin, _targetPos] call aegism_intercept_fnc_elevationAngle;
    if !([_settings, _weaponInfo, _currentDistance, _height, _role, _elevation] call aegism_intercept_fnc_inEnvelope) exitWith {
        [false, [_currentDistance, _elevation] call _fnEnvelopeReason]
    };
    ([_system, _origin, _target, _weaponInfo, _role, false] call aegism_intercept_fnc_computeLeadPoint) params ["", "_feasible", "_flightTime"];
    [_feasible, ["", format ["missile cannot catch it (%1m, receding)", round _currentDistance]] select !_feasible, _flightTime max 0]
} else {
    ([_system, _origin, _target, _weaponInfo, _role, false] call aegism_intercept_fnc_computeLeadPoint) params ["_aimPoint", "_feasible", "_flightTime", "_interceptDistance"];
    if (!_feasible) exitWith {
        [false, format ["no intercept solution (%1m, receding faster than the rounds close, or beyond reach)", round _currentDistance]]
    };
    private _elevation = [_origin, _aimPoint] call aegism_intercept_fnc_elevationAngle;
    if !([_settings, _weaponInfo, _interceptDistance, _height, _role, _elevation] call aegism_intercept_fnc_inEnvelope) exitWith {
        [false, [_interceptDistance, _elevation] call _fnEnvelopeReason]
    };
    [true, "", _flightTime max 0]
}
