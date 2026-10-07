/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_canEngage

Description:
    Whether one weapon can usefully engage one target right now: the one
    rule the Site coordinator and standalone target selection share.
    Full notes: docs/functions/intercept.md

Parameters:
    _system - the System vehicle <OBJECT>
    _role - "launcher" or "ciws" <STRING>
    _weaponInfo - weaponInfo, see aegism_system_fnc_discoverCapabilities <ARRAY>
    _target - the target object <OBJECT>
    _settings - that vehicle's resolved engagement settings <HASHMAP>
    _reaction - optional, gun only: seconds before its crew can fire, from
        now (a new assignment's crew reaction). Default 0 <NUMBER>

Returns:
    [canEngage <BOOLEAN>, reason if not <STRING>, flight time to the
     intercept in seconds, if it can (0 if unknown) <NUMBER>, and for a gun
     that can: distance to the intercept, m <NUMBER>, the cue time it was
     judged at if it's only cued (not in reach yet), s, else 0 <NUMBER>, its
     firing window, s (1e10 for a target that won't come down) <NUMBER>, and
     why that window is short ("" if it isn't) <STRING>]

Examples:
    [_cheetah, "ciws", _weaponInfo, _jet, _settings] call aegism_intercept_fnc_canEngage;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\perf.hpp"

#define AEGISM_GRAVITY 9.80665

params ["_system", "_role", "_weaponInfo", "_target", "_settings", ["_reaction", 0]];

PERF_INC(PERF_CAN_ENGAGE);

private _origin = eyePos _system;
private _targetPos = getPosASL _target;
private _currentDistance = _origin distance _targetPos;
private _isCiws = _role == "ciws";

private _fnEnvelopeReason = {
    params ["_distance", "_height", "_elevation"];
    format ["out of envelope (%1m, %2m AGL, %3 deg elevation)", round _distance, round _height, round (_elevation * 10) / 10]
};

if (!_isCiws) then {
    ([_settings, _weaponInfo, _role] call aegism_intercept_fnc_envelopeBounds) params ["_minRange", "_maxRange", "_minAltitude", "_maxAltitude"];
    // Too far to meet inside its reach at all (see notes), before solving
    // anything: the coordinator checks every free contact against every
    // launcher, most of them far out of reach.
    private _span = if (_maxRange > 0) then { [_weaponInfo, _maxRange] call aegism_intercept_fnc_missileFlightTime } else { -1 };
    if (_span >= 0 && {_currentDistance > _maxRange + (vectorMagnitude velocity _target) * _span + 0.5 * AEGISM_GRAVITY * _span * _span}) exitWith {
        [false, format ["beyond reach (%1m)", round _currentDistance]]
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
    // An unguided round falls: projected on gravity, as the reserve plan
    // projects it (aegism_intercept_fnc_planShot). On its velocity alone a
    // rocket coming down from 5 km was met, on paper, about 450 m further
    // out than it really was, and a free RAM launcher wasn't given it until
    // about 3.5 s after it could have fired for the edge of its reach
    // (2026-10-06: first kills at 4.5 km of 5).
    private _ballistic = _targetClass in ["artilleryShell", "rocket", "bomb"];
    ([_system, _weaponInfo, _target, _muzzle, true, true, false, 0, _ballistic, _timeToImpact] call aegism_intercept_fnc_launchSolution)
        params ["_launchable", "_reason", "", "", "_flightTime", "_slewTime", "", "", "", "_interceptPoint", "_interceptDistance"];
    if (!_launchable) exitWith { [false, _reason] };
    // Where the missile meets it has to be inside the envelope (aegism_
    // intercept_fnc_inEnvelope's rule) -- not where it is now: launched at an
    // incoming munition still beyond its reach, it meets it inside.
    private _interceptHeight = (ASLToAGL _interceptPoint) select 2;
    if (_interceptDistance < _minRange || {_interceptDistance > _maxRange} || {_interceptHeight < _minAltitude} || {_maxAltitude > 0 && {_interceptHeight > _maxAltitude}}) exitWith {
        [false, [_interceptDistance, _interceptHeight, [_origin, _interceptPoint] call aegism_intercept_fnc_elevationAngle] call _fnEnvelopeReason]
    };
    if (_timeToImpact < 1e9 && {_slewTime + (_flightTime max 0) >= _timeToImpact}) exitWith {
        [false, format ["can't get a missile onto it in time (turret swing %1s + missile flight %2s vs impact in %3s)", round (_slewTime * 10) / 10, round (_flightTime * 10) / 10, round (_timeToImpact * 10) / 10]]
    };
    [true, "", _flightTime max 0]
} else {
    private _targetClass = [_target] call aegism_detect_fnc_classifyTarget;
    private _corrections = ([_system, _weaponInfo select 0] call aegism_intercept_fnc_turretState) get "corrections";
    private _leadCorrection = if (isNil "_corrections") then { 0 } else { (_corrections getOrDefault [_targetClass, [0, 0]]) select 0 };
    ([_weaponInfo select 1, _weaponInfo select 2] call aegism_intercept_fnc_weaponKinematics) params ["", "_v0", "_k", "", "", "", "", "_lifetime"];
    private _ballistic = _targetClass in ["artilleryShell", "rocket", "bomb"];
    _origin = ([_system, _weaponInfo select 0, _role] call aegism_intercept_fnc_turretPoints) select 0;
    // Worked out once, and only for a target that gets as far as the timing
    // check.
    private _timeToImpact = -1;

    // The gun against the target for a burst opened _delay s from now (the
    // target projected to then, aegism_intercept_fnc_computeLeadPoint).
    private _fnSolve = {
        params ["_delay"];
        // Too far to reach at all (see notes). The longest a round can fly
        // and still meet it inside the gun's reach is its flight time TO that
        // reach (or its lifetime, if shorter) -- not its lifetime alone: the
        // Cheetah's 35mm round lives 30s, so that bound ruled out almost
        // nothing, and the coordinator solved every rocket in the sky against
        // the gun every run. Plus the spotting lead correction, which projects
        // the target further, and the wait until the burst.
        private _reach = _weaponInfo param [5, 0];
        if (_reach > 0 && {_v0 > 0}) then {
            private _flightToReach = if (_k > 0) then { ((exp ((_k * _reach) min 30)) - 1) / (_k * _v0) } else { _reach / _v0 };
            if (_lifetime > 0) then { _flightToReach = _flightToReach min _lifetime; };
            private _span = _flightToReach + abs _leadCorrection + _delay;
            if (_currentDistance > _reach + (vectorMagnitude velocity _target) * _span + 0.5 * AEGISM_GRAVITY * _span * _span) exitWith {
                _reach = -1;
            };
        };
        if (_reach < 0) exitWith {
            [false, format ["beyond reach (%1m)", round _currentDistance]]
        };

        // An unguided round's path is projected on gravity (exact: artillery
        // has no drag), as the gun's own aim sees it. Solved exactly as the
        // gun's own aim does (aegism_intercept_fnc_aimWeapon): from the
        // muzzle, with its spotting lead correction for this target class.
        // Solved from the eye position without it, a target at the edge of
        // reach could pass here while the aim found no solution -- and a gun
        // held on it, NO-SOLUTION, for 23s.
        ([_system, _origin, _target, _weaponInfo, _role, false, _delay, _ballistic, _leadCorrection] call aegism_intercept_fnc_computeLeadPoint) params ["_aimPoint", "_feasible", "_flightTime", "_interceptDistance", "", "_interceptPoint"];
        if (!_feasible) exitWith {
            [false, format ["no intercept solution (%1m, receding faster than the rounds close, or beyond reach)", round _currentDistance]]
        };
        // The target's height where the rounds meet it -- not where it is
        // now: a shell diving through a minimum height is below it by the
        // time it's hit.
        private _interceptHeight = (ASLToAGL _interceptPoint) select 2;
        private _elevation = [_origin, _aimPoint] call aegism_intercept_fnc_elevationAngle;
        if !([_settings, _weaponInfo, _interceptDistance, _interceptHeight, _role, _elevation] call aegism_intercept_fnc_inEnvelope) exitWith {
            [false, [_interceptDistance, _interceptHeight, _elevation] call _fnEnvelopeReason]
        };
        // A gun can't hit what its turret can't point at: past its elevation
        // or traverse limit the barrel stops short and never comes on target.
        ([_system, _weaponInfo select 0, _origin vectorFromTo _aimPoint] call aegism_intercept_fnc_turretCanPoint) params ["_canPoint", "_aimElevation", "_minElevation", "_maxElevation", "", "_aimTurn", "_minTurn", "_maxTurn"];
        if (!_canPoint) exitWith {
            [false, format ["beyond the turret's limits (aim %1 deg elevation, %2 deg traverse; turret %3 to %4 deg elevation, %5 to %6 deg traverse)", round _aimElevation, round _aimTurn, _minElevation, _maxElevation, _minTurn, _maxTurn]]
        };
        // It has to get there in time: swing the barrel onto the intercept
        // (aegism_intercept_fnc_turretSlewTime, the turret's own rates) --
        // done while it waits, for a burst opened later -- and fly the rounds
        // out, before the target comes down. A gun handed one it can't make
        // holds fire on it (LAST-DITCH-HOLD) while others it could still kill
        // come down unengaged.
        if (_timeToImpact < 0) then { _timeToImpact = [_target, _targetClass, [getPosASL _system]] call aegism_intercept_fnc_timeToImpact; };
        private _slewTime = [_system, _weaponInfo select 0, _weaponInfo select 1, _origin vectorFromTo _aimPoint] call aegism_intercept_fnc_turretSlewTime;
        // It opens fire once its crew has reacted, its barrel is round and
        // the burst's time has come, whichever is last.
        private _openAt = (_slewTime max _delay) max _reaction;
        if (_timeToImpact < 1e9 && {_openAt + (_flightTime max 0) >= _timeToImpact}) exitWith {
            [false, format ["can't get on it in time (%1 %2s + round flight %3s vs impact in %4s)", ["barrel swing", "crew reaction"] select (_reaction > (_slewTime max _delay)),
                round (_openAt * 10) / 10, round (_flightTime * 10) / 10, round (_timeToImpact * 10) / 10]]
        };
        // Its firing window (see notes): from then until the last burst
        // whose rounds still arrive before impact.
        private _window = if (_timeToImpact < 1e9) then { _timeToImpact - _openAt - (_flightTime max 0) } else { 1e10 };
        private _short = "";
        if (_window < 1e9) then {
            private _minWindow = _settings getOrDefault ["ciwsMinWindow", 3];
            if (_window < _minWindow) exitWith {
                _short = format ["only %1s to fire at it before impact, under its %2s Minimum Firing Window", round (_window * 10) / 10, _minWindow];
            };
            // And it can still follow it at the end of that window: a rocket
            // coming down steeply goes past a turret's elevation limit (the
            // Cheetah's 80 degrees) in its last seconds, and the gun was
            // handed ones it then held fire on or dropped.
            ([_system, _origin, _target, _weaponInfo, _role, false, _openAt + _minWindow, _ballistic, _leadCorrection] call aegism_intercept_fnc_computeLeadPoint) params ["_endAim", "_endFeasible"];
            if (!_endFeasible || {!(([_system, _weaponInfo select 0, _origin vectorFromTo _endAim] call aegism_intercept_fnc_turretCanPoint) select 0)}) then {
                _short = format ["it goes beyond the turret's limits or reach within its %1s Minimum Firing Window", _minWindow];
            };
        };
        [true, "", _flightTime max 0, _interceptDistance, 0, _window, _short]
    };

    private _now = [0] call _fnSolve;
    // Not in reach yet: cued if it will be within the gun's cue time (CIWS
    // setting "Cue Before In Range"), so its crew has reacted and its barrel
    // is on it by then.
    private _cueAhead = _settings getOrDefault ["ciwsCueAhead", 5];
    if ((_now select 0) || {_cueAhead <= 0}) exitWith { _now };
    private _cued = [_cueAhead] call _fnSolve;
    if (_cued select 0) exitWith { _cued set [4, _cueAhead]; _cued };
    _now
}
