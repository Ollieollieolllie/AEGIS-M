/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_canEngage

Description:
    Whether one weapon can usefully engage one target right now -- the one
    rule the Site coordinator (assign AND release, aegism_intercept_fnc_
    assignEngagements) and standalone target selection (aegism_intercept_
    fnc_selectTarget) share.

        launcher - the target is inside the missile's envelope NOW (lock
            range, doctrine limits: aegism_intercept_fnc_inEnvelope), and a
            missile can be put onto it (aegism_intercept_fnc_launchSolution):
            it can catch it on its real speed profile, launched along the
            closest direction the turret can reach -- straight, or off-bore
            within the missile's post-launch cone and turn (a vertical
            launch cell, a turret at its limit). Against an incoming
            munition, the turret's swing plus the missile's flight must
            beat its impact -- or, only when that's too late, a launch now,
            before the turret is round.
        ciws - a feasible intercept exists, and the INTERCEPT point (where
            the rounds would meet the target) is inside the gun's envelope
            -- its range, the target's height THERE, and the minimum
            elevation of the barrel aimed there -- within the turret's own
            elevation limits, and reachable in time: the barrel's swing onto
            it (aegism_intercept_fnc_turretSlewTime) plus the rounds' flight
            before the target comes down.

    Judging a gun at the intercept point is what stops it spending ammunition
    on a jet flying away from it: the jet may be 2000m away "inside" a 2500m
    gun, but the rounds would only catch it far beyond 2500m (or never), so
    it is released instead of claimed forever.

    A gun first rules out, without solving anything, a target too far to
    reach at all: the intercept has to be within the gun's range, and the
    target can't cover more than speed x t + g t^2 / 2 in the round's flight
    time t to that range (or its lifetime, CfgAmmo timeToLive, if shorter).
    The coordinator checks every free contact against every gun, most of
    them far out of reach.

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
    // How a missile gets onto it (aegism_intercept_fnc_launchSolution):
    // straight, after the turret swings to the closest direction it can
    // reach; or off-bore -- a vertical launch cell, a turret at its limit --
    // only if the missile can still be guided onto it after launch, and turn
    // in time. The Spartan's RAM turret stops at 40 degrees and was given
    // rockets on a high arc above that: it sat on each one SLEWING until the
    // 15s never-fired timeout while its queue waited behind it.
    // Against an incoming munition it has to get there in time: the
    // turret's swing plus the missile's flight, before it comes down --
    // or, when swinging first is too late, firing now and letting the
    // missile turn (the last resort, see launchSolution).
    private _targetClass = [_target] call aegism_detect_fnc_classifyTarget;
    private _timeToImpact = if (_targetClass in ["missile", "rocket", "bomb", "artilleryShell"]) then {
        [_target, _targetClass, [getPosASL _system]] call aegism_intercept_fnc_timeToImpact
    } else { 1e10 };
    private _muzzle = ([_system, _weaponInfo select 0, _role] call aegism_intercept_fnc_turretPoints) select 0;
    ([_system, _weaponInfo, _target, _muzzle, true, true, false, 0, false, _timeToImpact] call aegism_intercept_fnc_launchSolution)
        params ["_launchable", "_reason", "", "", "_flightTime", "_slewTime"];
    if (!_launchable) exitWith { [false, _reason] };
    if (_timeToImpact < 1e9 && {_slewTime + (_flightTime max 0) >= _timeToImpact}) exitWith {
        [false, format ["can't get a missile onto it in time (turret swing %1s + missile flight %2s vs impact in %3s)", round (_slewTime * 10) / 10, round (_flightTime * 10) / 10, round (_timeToImpact * 10) / 10]]
    };
    [true, "", _flightTime max 0]
} else {
    private _targetClass = [_target] call aegism_detect_fnc_classifyTarget;
    private _corrections = ([_system, _weaponInfo select 0] call aegism_intercept_fnc_turretState) get "corrections";
    private _leadCorrection = if (isNil "_corrections") then { 0 } else { (_corrections getOrDefault [_targetClass, [0, 0]]) select 0 };

    // Too far to reach at all (see header). The longest a round can fly and
    // still meet it inside the gun's reach is its flight time TO that reach
    // (or its lifetime, if shorter) -- not its lifetime alone: the Cheetah's
    // 35mm round lives 30s, so that bound ruled out almost nothing, and the
    // coordinator solved every rocket in the sky against the gun every run.
    ([_weaponInfo select 1, _weaponInfo select 2] call aegism_intercept_fnc_weaponKinematics) params ["", "_v0", "_k", "", "", "", "", "_lifetime"];
    private _reach = _weaponInfo param [5, 0];
    if (_reach > 0 && {_v0 > 0}) then {
        private _flightToReach = if (_k > 0) then { ((exp ((_k * _reach) min 30)) - 1) / (_k * _v0) } else { _reach / _v0 };
        if (_lifetime > 0) then { _flightToReach = _flightToReach min _lifetime; };
        // Plus the spotting lead correction, which projects the target further.
        _flightToReach = _flightToReach + abs _leadCorrection;
        if (_currentDistance > _reach + (vectorMagnitude velocity _target) * _flightToReach + 0.5 * AEGISM_GRAVITY * _flightToReach * _flightToReach) exitWith {
            _reach = -1;
        };
    };
    if (_reach < 0) exitWith {
        [false, format ["beyond reach (%1m)", round _currentDistance]]
    };

    // An unguided round's path is projected on gravity (exact: artillery has
    // no drag), as the gun's own aim sees it. Solved exactly as the gun's own
    // aim does (aegism_intercept_fnc_aimWeapon): from the muzzle, with its
    // spotting lead correction for this target class. Solved from the eye
    // position without it, a target at the edge of reach could pass here
    // while the aim found no solution -- and a gun held on it, NO-SOLUTION,
    // for 23s.
    private _ballistic = _targetClass in ["artilleryShell", "rocket", "bomb"];
    _origin = ([_system, _weaponInfo select 0, _role] call aegism_intercept_fnc_turretPoints) select 0;
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
    // A gun can't hit what its turret can't point at: past its elevation or
    // traverse limit the barrel stops short and never comes on target.
    ([_system, _weaponInfo select 0, _origin vectorFromTo _aimPoint] call aegism_intercept_fnc_turretCanPoint) params ["_canPoint", "_aimElevation", "_minElevation", "_maxElevation", "", "_aimTurn", "_minTurn", "_maxTurn"];
    if (!_canPoint) exitWith {
        [false, format ["beyond the turret's limits (aim %1 deg elevation, %2 deg traverse; turret %3 to %4 deg elevation, %5 to %6 deg traverse)", round _aimElevation, round _aimTurn, _minElevation, _maxElevation, _minTurn, _maxTurn]]
    };
    // It has to get there in time: swing the barrel onto the intercept
    // (aegism_intercept_fnc_turretSlewTime, the turret's own rates) and fly
    // the rounds out, before the target comes down. A gun handed one it
    // can't make holds fire on it (LAST-DITCH-HOLD) while others it could
    // still kill come down unengaged.
    private _timeToImpact = [_target, _targetClass, [getPosASL _system]] call aegism_intercept_fnc_timeToImpact;
    private _slewTime = [_system, _weaponInfo select 0, _weaponInfo select 1, _origin vectorFromTo _aimPoint] call aegism_intercept_fnc_turretSlewTime;
    if (_timeToImpact < 1e9 && {_slewTime + (_flightTime max 0) >= _timeToImpact}) exitWith {
        [false, format ["can't get on it in time (barrel swing %1s + round flight %2s vs impact in %3s)", round (_slewTime * 10) / 10, round (_flightTime * 10) / 10, round (_timeToImpact * 10) / 10]]
    };
    [true, "", _flightTime max 0, _interceptDistance]
}
