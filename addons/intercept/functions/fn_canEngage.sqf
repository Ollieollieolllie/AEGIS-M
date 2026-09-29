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
            the rounds would meet the target) is inside the gun's envelope
            -- its range, the target's height THERE, and the minimum
            elevation of the barrel aimed there -- and within the turret's
            own elevation limits (aegism_intercept_fnc_turretCanPoint).

    Judging a gun at the intercept point is what stops it spending ammunition
    on a jet flying away from it: the jet may be 2000m away "inside" a 2500m
    gun, but the rounds would only catch it far beyond 2500m (or never), so
    it is released instead of claimed forever.

    A gun first rules out, without solving anything, a target too far to
    reach at all: the intercept has to be within the gun's range, and the
    target can't cover more than speed x t + g t^2 / 2 in the round's
    lifetime t (CfgAmmo timeToLive). The coordinator checks every free
    contact against every gun, most of them far out of reach.

    No acceleration sampling, so calling this has no side effects: the
    intercept is estimated from velocity -- plus gravity for a gun against
    an unguided round, whose path that is.

Parameters:
    _system - the System vehicle <OBJECT>
    _role - "launcher" or "ciws" <STRING>
    _weaponInfo - weaponInfo, see aegism_system_fnc_discoverCapabilities <ARRAY>
    _target - the target object <OBJECT>
    _settings - that vehicle's resolved engagement settings <HASHMAP>

Returns:
    [canEngage <BOOLEAN>, reason if not <STRING>, flight time to the
     intercept in seconds, if it can (0 if unknown) <NUMBER>, and for a gun
     that can: distance to the intercept, m <NUMBER>]

Examples:
    [_cheetah, "ciws", _weaponInfo, _jet, _settings] call aegism_intercept_fnc_canEngage;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\perf.hpp"

#define AEGISM_GRAVITY 9.80665

params ["_system", "_role", "_weaponInfo", "_target", "_settings"];

PERF_INC(PERF_CAN_ENGAGE);

private _origin = eyePos _system;
private _targetPos = getPosASL _target;
private _height = (ASLToAGL _targetPos) select 2;
private _currentDistance = _origin distance _targetPos;
private _isCiws = _role == "ciws";

private _fnEnvelopeReason = {
    params ["_distance", "_height", "_elevation"];
    format ["out of envelope (%1m, %2m AGL, %3 deg elevation)", round _distance, round _height, round (_elevation * 10) / 10]
};

if (!_isCiws) then {
    private _elevation = [_origin, _targetPos] call aegism_intercept_fnc_elevationAngle;
    if !([_settings, _weaponInfo, _currentDistance, _height, _role, _elevation] call aegism_intercept_fnc_inEnvelope) exitWith {
        [false, [_currentDistance, _height, _elevation] call _fnEnvelopeReason]
    };
    ([_system, _origin, _target, _weaponInfo, _role, false] call aegism_intercept_fnc_computeLeadPoint) params ["", "_feasible", "_flightTime"];
    [_feasible, ["", format ["missile cannot catch it (%1m, receding)", round _currentDistance]] select !_feasible, _flightTime max 0]
} else {
    // Too far to reach at all (see header).
    private _lifetime = ([_weaponInfo select 1, _weaponInfo select 2] call aegism_intercept_fnc_weaponKinematics) select 7;
    private _reach = _weaponInfo param [5, 0];
    if (_reach > 0 && {_lifetime > 0} && {_currentDistance > _reach + (vectorMagnitude velocity _target) * _lifetime + 0.5 * AEGISM_GRAVITY * _lifetime * _lifetime}) exitWith {
        [false, format ["beyond reach (%1m)", round _currentDistance]]
    };

    // An unguided round's path is projected on gravity (exact: artillery has
    // no drag), as the gun's own aim sees it. Solved exactly as the gun's own
    // aim does (aegism_intercept_fnc_aimWeapon): from the muzzle, with its
    // spotting lead correction for this target class. Solved from the eye
    // position without it, a target at the edge of reach could pass here
    // while the aim found no solution -- and a gun held on it, NO-SOLUTION,
    // for 23s.
    private _targetClass = [_target] call aegism_detect_fnc_classifyTarget;
    private _ballistic = _targetClass in ["artilleryShell", "rocket", "bomb"];
    _origin = ([_system, _weaponInfo select 0, _role] call aegism_intercept_fnc_turretPoints) select 0;
    private _corrections = ([_system, _weaponInfo select 0] call aegism_intercept_fnc_turretState) get "corrections";
    private _leadCorrection = if (isNil "_corrections") then { 0 } else { (_corrections getOrDefault [_targetClass, [0, 0]]) select 0 };
    ([_system, _origin, _target, _weaponInfo, _role, false, 0, _ballistic, _leadCorrection] call aegism_intercept_fnc_computeLeadPoint) params ["_aimPoint", "_feasible", "_flightTime", "_interceptDistance", "", "_interceptPoint"];
    if (!_feasible) exitWith {
        [false, format ["no intercept solution (%1m, receding faster than the rounds close, or beyond reach)", round _currentDistance]]
    };
    // The target's height where the rounds meet it -- not where it is now:
    // a shell diving through a minimum height is below it by the time it's
    // hit.
    private _interceptHeight = (ASLToAGL _interceptPoint) select 2;
    private _elevation = [_origin, _aimPoint] call aegism_intercept_fnc_elevationAngle;
    if !([_settings, _weaponInfo, _interceptDistance, _interceptHeight, _role, _elevation] call aegism_intercept_fnc_inEnvelope) exitWith {
        [false, [_interceptDistance, _interceptHeight, _elevation] call _fnEnvelopeReason]
    };
    // A gun can't hit what its turret can't point at: past its elevation
    // limit the barrel stops short and never comes on target.
    ([_system, _weaponInfo select 0, _origin vectorFromTo _aimPoint] call aegism_intercept_fnc_turretCanPoint) params ["_canPoint", "_aimElevation", "_minElevation", "_maxElevation"];
    if (!_canPoint) exitWith {
        [false, format ["beyond the turret's elevation limits (aim %1 deg, turret %2 to %3 deg)", round _aimElevation, _minElevation, _maxElevation]]
    };
    [true, "", _flightTime max 0, _interceptDistance]
}
