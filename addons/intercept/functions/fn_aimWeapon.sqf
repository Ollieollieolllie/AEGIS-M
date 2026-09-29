/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_aimWeapon

Description:
    Full aim solve for one System weapon: slews its turret toward the
    intercept point (lockCameraTo on that turret, see aegism_intercept_fnc_
    lockTurret) and reports whether the barrel is aligned closely enough to
    fire. Each lock stamps the turret's "lockAt" (aegism_intercept_fnc_
    turretState); aegism_intercept_fnc_engagementLoop hands the turret back
    to its crew once that goes stale.

    Launchers are solved here every engagement tick from the moment a target
    is assigned (including the crew reaction window). A CIWS gun is solved
    here by its per-frame tracker (aegism_intercept_fnc_ciwsTrack) every
    AEGISM_CIWS_SOLVE_INTERVAL s and steered in between from the "solve" this
    stores.

    Aim point (aegism_intercept_fnc_computeLeadPoint) for both roles:
        ciws - where the unguided round meets the target, raised for drop
        launcher - where the missile (from its real speed profile) meets
            the target, so it doesn't leave the rail and turn hard
    When there is no feasible intercept (the target is receding faster than
    the round can close, or the meeting point is beyond the weapon's reach)
    the turret tracks the target itself and the weapon is not aligned.

    Alignment:
        ciws - aegism_intercept_fnc_ciwsGate: the barrel's error at the
            intercept within the target's own half-size (aegism_intercept_
            fnc_targetHitRadius) plus the gun's own spread there (the current
            fire mode's CfgWeapons dispersion), with the last-ditch rule.
            An unguided munition's path is projected on gravity alone --
            exact for artillery (no drag), and the same projection aegism_
            intercept_fnc_canEngage judges reach with.
        launcher - barrel within AEGISM_AIM_ON_TARGET degrees, OR the turret
            has stopped closing on the aim point (the angle hasn't shrunk for
            AEGISM_AIM_SETTLE_TICKS checks in a row: it's at its elevation
            limit, or trailing a fast-moving lead point) -- either way only
            inside the missile's own lock cone (CfgAmmo missileLockCone, no
            limit if the ammo doesn't set one), so it never fires at
            something its seeker can't take.
    Barrel direction: aegism_intercept_fnc_barrelDirection.

    CIWS aim carries the gun's own spotting correction for this target class
    (turret state "corrections", [lead time s, elevation rad], aegism_
    intercept_fnc_ciwsSpot). The prediction each solve uses is recorded as
    the turret's "track" [time, position, velocity, acceleration] (and its
    flight time, "trackTof") for aegism_intercept_fnc_onSystemFired to hand
    each round.

    Shared turrets: a vehicle whose launcher and gun sit on the same turret
    (e.g. the Cheetah) would have both engagement loops issuing competing
    aim orders. The CIWS loop owns the turret while it is actively aiming; a
    launcher on the same turret skips its own lock for AEGISM_CIWS_AIM_
    OWNERSHIP seconds and only checks alignment.

    Records [angle, tolerance, time, target, feasible, aligned, aimPoint] as
    the turret's "aim_<role>" -- per turret, so two guns on one vehicle each
    gate their own bursts (one record per role used to be shared by every
    turret: a second gun read the first's alignment and never fired).

Parameters:
    _system - the firing System vehicle <OBJECT>
    _target - the target object <OBJECT>
    _weaponInfo - weaponInfo, see aegism_system_fnc_discoverCapabilities <ARRAY>
    _role - "launcher" or "ciws" <STRING>

Returns:
    [aligned <BOOLEAN>, angle <NUMBER>, tolerance <NUMBER>, aimPoint <ARRAY, ASL>,
     feasible <BOOLEAN>]

Examples:
    [_cheetah, _heli, _weaponInfo, "ciws"] call aegism_intercept_fnc_aimWeapon;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\perf.hpp"

#define AEGISM_AIM_ON_TARGET 2
#define AEGISM_AIM_SETTLE_TICKS 2
#define AEGISM_CIWS_AIM_OWNERSHIP 0.5
// Two solves further apart than this don't give the aim point a velocity to
// steer with (the target changed, or the gun was idle).
#define AEGISM_AIM_VELOCITY_MAX_GAP 0.5
// A turret that isn't local gets its lock sent over the network: at most
// this often.
#define AEGISM_REMOTE_LOCK_INTERVAL 0.1

params ["_system", "_target", "_weaponInfo", "_role"];
_weaponInfo params ["_turretPath", "_weaponClass", "_magazineClass"];

PERF_INC(PERF_AIM_SOLVES);

private _isCiws = _role == "ciws";
private _ts = [_system, _turretPath] call aegism_intercept_fnc_turretState;

// The intercept is solved from the MUZZLE, and the camera lockCameraTo
// points is aimed at the aim point shifted by (camera - muzzle), so the
// parallel barrel line passes through the aim point itself (see
// aegism_intercept_fnc_turretPoints: this offset put CIWS rounds about a
// metre low).
([_system, _turretPath, _role] call aegism_intercept_fnc_turretPoints) params ["_origin", "_camera"];
private _cameraOffset = _camera vectorDiff _origin;

private _targetClass = [_target] call aegism_detect_fnc_classifyTarget;

// CIWS spotting correction for this target class (aegism_intercept_fnc_
// ciwsSpot): lead time added to the target's projection, and an elevation
// angle applied square to the line of sight.
private _corrections = _ts get "corrections";
private _correction = if (_isCiws && {!isNil "_corrections"}) then { _corrections getOrDefault [_targetClass, [0, 0]] } else { [0, 0] };
_correction params ["_leadCorrection", "_elevationCorrection"];

private _ballistic = _isCiws && {_targetClass in ["artilleryShell", "rocket", "bomb"]};
([_system, _origin, _target, _weaponInfo, _role, !_ballistic, 0, _ballistic, _leadCorrection] call aegism_intercept_fnc_computeLeadPoint) params ["_aimPoint", "_feasible", "_tof", "_interceptDistance", "_track"];
if (_isCiws) then {
    _ts set ["track", [time] + _track];
    _ts set ["trackTof", _tof];
};

if (_elevationCorrection != 0) then {
    private _los = _origin vectorFromTo _aimPoint;
    private _up = vectorNormalized ([0, 0, 1] vectorDiff (_los vectorMultiply (_los select 2)));
    _aimPoint = _aimPoint vectorAdd (_up vectorMultiply (_elevationCorrection * _interceptDistance));
};

if (_isCiws) then { _ts set ["ciwsAimAt", time]; };
if (_isCiws || {time - (_ts getOrDefault ["ciwsAimAt", -1e9]) > AEGISM_CIWS_AIM_OWNERSHIP}) then {
    if ((_system turretLocal _turretPath) || {time - (_ts getOrDefault ["lockAt", -1e9]) >= AEGISM_REMOTE_LOCK_INTERVAL}) then {
        [_system, _turretPath, _aimPoint vectorAdd _cameraOffset] call aegism_intercept_fnc_lockTurret;
        _ts set ["lockAt", time];
    };
};

private _barrel = [_system, _turretPath, _weaponClass] call aegism_intercept_fnc_barrelDirection;
// Clamped: float error can push vectorCos fractionally past 1, and acos of
// that is undefined.
private _angle = acos (((_barrel vectorCos (_origin vectorFromTo _aimPoint)) min 1) max -1);

if (_isCiws) exitWith {
    private _tolerance = AEGISM_AIM_ON_TARGET;
    if (_interceptDistance > 0) then {
        private _dispersion = ([_system, _turretPath, _weaponClass] call aegism_intercept_fnc_fireModeStats) select 1;
        _tolerance = deg (_dispersion + ([_target] call aegism_intercept_fnc_targetHitRadius) / _interceptDistance);
    };

    // The aim point's own velocity, from the previous solve on this target:
    // the per-frame tracker steers along it between solves.
    private _aimVelocity = [0, 0, 0];
    private _previous = _ts getOrDefault ["solve", []];
    if (_previous isNotEqualTo [] && {(_previous select 8) == _target}) then {
        private _dt = time - (_previous select 0);
        if (_dt > 0 && {_dt <= AEGISM_AIM_VELOCITY_MAX_GAP}) then {
            _aimVelocity = (_aimPoint vectorDiff (_previous select 1)) vectorMultiply (1 / _dt);
        };
        if (_dt == 0) then { _aimVelocity = _previous select 2; };
    };
    _ts set ["solve", [time, _aimPoint, _aimVelocity, _cameraOffset, _origin, _tolerance, _feasible, _interceptDistance, _target, _targetClass]];

    private _aligned = [_system, _ts, _target, _targetClass, _angle, _tolerance, _feasible, _aimPoint] call aegism_intercept_fnc_ciwsGate;
    [_aligned, _angle, _tolerance, _aimPoint, _feasible]
};

// --- Launcher ---
(_ts getOrDefault ["trend", [1e9, objNull, 0]]) params ["_lastAngle", "_lastTarget", "_notClosing"];
_notClosing = if (_lastTarget == _target && {_angle >= _lastAngle}) then { _notClosing + 1 } else { 0 };
_ts set ["trend", [_angle, _target, _notClosing]];

private _lockCone = ([_weaponClass, _magazineClass] call aegism_intercept_fnc_weaponKinematics) select 8;
private _aligned = _feasible && {_angle <= _lockCone} && {_angle <= AEGISM_AIM_ON_TARGET || {_notClosing >= AEGISM_AIM_SETTLE_TICKS}};

_ts set ["aim_launcher", [_angle, AEGISM_AIM_ON_TARGET, time, _target, _feasible, _aligned, _aimPoint]];

[_aligned, _angle, AEGISM_AIM_ON_TARGET, _aimPoint, _feasible]
