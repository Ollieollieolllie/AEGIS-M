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

    Aim point:
        ciws - where the unguided round meets the target, raised for drop
            (aegism_intercept_fnc_computeLeadPoint)
        launcher - the closest direction the turret can reach to where the
            missile (from its real speed profile) meets the target
            (aegism_intercept_fnc_launchSolution): the intercept itself, so
            it doesn't leave the rail and turn hard, or the turret's limit
    When there is no feasible intercept (the target is receding faster than
    the round can close, or the meeting point is beyond the weapon's reach)
    the turret tracks the target itself and the weapon is not aligned.

    Alignment:
        ciws - aegism_intercept_fnc_ciwsGate: the intercept inside the gun's
            open-fire range (aegism_intercept_fnc_openFireRange: where one
            burst still hits with doctrine ciwsOpenFireChance, from the gun's
            measured accuracy, the round's flight and reach, and the hit
            radius), and the barrel's error at the intercept
            within the target's own half-size (aegism_intercept_fnc_
            targetHitRadius) plus the gun's own spread there (the current
            fire mode's CfgWeapons dispersion), with the last-ditch rule.
            An unguided munition's path is projected on gravity alone --
            exact for artillery (no drag), and the same projection aegism_
            intercept_fnc_canEngage judges reach with.
        launcher - by the way to launch that kills soonest (aegism_
            intercept_fnc_launchSolution):
            "now" / "fixed" - at once, along the barrel as it points (a
                vertical launch cell; a turret still swinging round, only
                when waiting for it would be too late to intercept)
            "onBore" / "slew" - barrel within AEGISM_AIM_ON_TARGET degrees
                of the launch direction, OR the turret has stopped closing
                on it (the angle hasn't shrunk for AEGISM_AIM_SETTLE_TICKS
                checks in a row: trailing a fast-moving lead point), with
                the barrel's own angle off the intercept still inside the
                missile's post-launch cone (aegism_intercept_fnc_
                missileAgility)
            An off-bore launch also needs its first leg clear -- to where
            the missile's turn ends, or (its turn not known yet) its own
            arming distance (CfgAmmo fuseDistance) straight along the
            barrel -- traced at most every AEGISM_LAUNCH_PATH_REUSE s
            (LAUNCH-PATH-BLOCKED). The plan is kept as the turret's
            "launchPlan" for the FIRE log.
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
     feasible <BOOLEAN>, inRange <BOOLEAN> -- a gun's intercept is inside its
     open-fire range (always true for a launcher)]

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
// An off-bore launch's first leg is re-traced at most this often.
#define AEGISM_LAUNCH_PATH_REUSE 0.5

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

// --- Launcher (see header) ---
if (!_isCiws) exitWith {
    // An incoming munition's impact: firing before the turret is round is
    // only for one it would otherwise miss.
    private _launcherTargetClass = [_target] call aegism_detect_fnc_classifyTarget;
    private _timeToImpact = if (_launcherTargetClass in ["missile", "rocket", "bomb", "artilleryShell"]) then {
        [_target, _launcherTargetClass, [getPosASL _system]] call aegism_intercept_fnc_timeToImpact
    } else { 1e10 };
    ([_system, _weaponInfo, _target, _origin, true, true, true, 0, false, _timeToImpact] call aegism_intercept_fnc_launchSolution)
        params ["_feasible", "_reason", "_way", "_launchDir", "_tof", "_slewTime", "", "_turnTime", "_calibrated", "", "_interceptDistance", "_turnEnd", "_leadDir", "_cone", "_reachDir"];
    // The turret keeps swinging to the closest direction it can reach
    // whichever way wins now: "now" is decided again every tick, and waiting
    // out the crew's reaction must not freeze it where it is.
    private _aimPoint = if (_feasible) then { _origin vectorAdd (_reachDir vectorMultiply (_interceptDistance max 1)) } else { getPosASLVisual _target };
    if (time - (_ts getOrDefault ["ciwsAimAt", -1e9]) > AEGISM_CIWS_AIM_OWNERSHIP) then {
        if ((_system turretLocal _turretPath) || {time - (_ts getOrDefault ["lockAt", -1e9]) >= AEGISM_REMOTE_LOCK_INTERVAL}) then {
            [_system, _turretPath, _aimPoint vectorAdd _cameraOffset] call aegism_intercept_fnc_lockTurret;
            _ts set ["lockAt", time];
        };
    };

    private _barrel = [_system, _turretPath, _weaponClass] call aegism_intercept_fnc_barrelDirection;
    private _angle = acos (((_barrel vectorCos (_origin vectorFromTo _aimPoint)) min 1) max -1);
    (_ts getOrDefault ["trend", [1e9, objNull, 0]]) params ["_lastAngle", "_lastTarget", "_notClosing"];
    _notClosing = if (_lastTarget == _target && {_angle >= _lastAngle}) then { _notClosing + 1 } else { 0 };
    _ts set ["trend", [_angle, _target, _notClosing]];

    // The barrel's own angle off the intercept: what the missile will
    // actually have to turn through.
    private _barrelOffBore = if (_leadDir isEqualTo []) then { 180 } else { acos (((_barrel vectorCos _leadDir) min 1) max -1) };
    private _aligned = _feasible && {
        (_way in ["now", "fixed"]) || {_angle <= AEGISM_AIM_ON_TARGET} || {_notClosing >= AEGISM_AIM_SETTLE_TICKS && {_barrelOffBore <= _cone}}
    };

    // Off-bore: the first leg of its flight has to be clear (see header).
    if (_aligned && {_barrelOffBore > AEGISM_AIM_ON_TARGET}) then {
        (_ts getOrDefault ["launchPath", [-1e9, objNull, true]]) params ["_checkedAt", "_checkedTarget", "_clear"];
        if (time - _checkedAt > AEGISM_LAUNCH_PATH_REUSE || {_checkedTarget != _target}) then {
            private _legEnd = if (_calibrated && {_turnTime > 0}) then { _turnEnd } else {
                _origin vectorAdd (_barrel vectorMultiply ((([_weaponClass, _magazineClass] call aegism_intercept_fnc_weaponKinematics) select 9) max 1))
            };
            _clear = (lineIntersectsSurfaces [_origin, _legEnd, _system, _target, true, 1]) isEqualTo [];
            _ts set ["launchPath", [time, _target, _clear]];
            if (!_clear) then {
                diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " LAUNCH-PATH-BLOCKED: %1 turret %2 on %3 -- an off-bore launch (%4 deg off) would fly into something within %5m; holding.",
                    _system, _turretPath, _target, round _barrelOffBore, round (_origin distance _legEnd)];
            };
        };
        if (!_clear) then { _aligned = false; };
    };

    _ts set ["aim_launcher", [_angle, AEGISM_AIM_ON_TARGET, time, _target, _feasible, _aligned, _aimPoint]];
    _ts set ["launchPlan", [_target, _way, _barrelOffBore, _turnTime, _tof, _calibrated, _reason, _slewTime]];
    [_aligned, _angle, AEGISM_AIM_ON_TARGET, _aimPoint, _feasible, true]
};

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

// The elevation correction goes square to the line of sight, upward -- but
// only the part of "up" square to the target's own crossing motion: along
// that motion is the lead correction's job (aegism_intercept_fnc_ciwsSpot
// measures them on the same two axes). A shell coming down in the gun's own
// vertical plane crosses along "up", so both used to act on the same axis.
if (_elevationCorrection != 0) then {
    private _los = _origin vectorFromTo _aimPoint;
    private _up = [0, 0, 1] vectorDiff (_los vectorMultiply (_los select 2));
    private _targetVelocity = (_track select 1) vectorAdd ((_track select 2) vectorMultiply (_tof max 0));
    private _cross = _targetVelocity vectorDiff (_los vectorMultiply (_targetVelocity vectorDotProduct _los));
    private _crossSpeed = vectorMagnitude _cross;
    if (_crossSpeed > 0) then {
        private _along = _cross vectorMultiply (1 / _crossSpeed);
        _up = _up vectorDiff (_along vectorMultiply (_up vectorDotProduct _along));
    };
    if ((vectorMagnitude _up) > 0.001) then {
        _aimPoint = _aimPoint vectorAdd ((vectorNormalized _up) vectorMultiply (_elevationCorrection * _interceptDistance));
    };
};

// The gun owns its turret while it aims (see header).
_ts set ["ciwsAimAt", time];
if ((_system turretLocal _turretPath) || {time - (_ts getOrDefault ["lockAt", -1e9]) >= AEGISM_REMOTE_LOCK_INTERVAL}) then {
    [_system, _turretPath, _aimPoint vectorAdd _cameraOffset] call aegism_intercept_fnc_lockTurret;
    _ts set ["lockAt", time];
};

private _barrel = [_system, _turretPath, _weaponClass] call aegism_intercept_fnc_barrelDirection;
// Clamped: float error can push vectorCos fractionally past 1, and acos of
// that is undefined.
private _angle = acos (((_barrel vectorCos (_origin vectorFromTo _aimPoint)) min 1) max -1);

private _targetRadius = [_target] call aegism_intercept_fnc_targetHitRadius;
private _tolerance = AEGISM_AIM_ON_TARGET;
if (_interceptDistance > 0) then {
    private _dispersion = ([_system, _turretPath, _weaponClass] call aegism_intercept_fnc_fireModeStats) select 1;
    _tolerance = deg (_dispersion + _targetRadius / _interceptDistance);
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
// Where this gun opens fire on this target (aegism_intercept_fnc_
// openFireRange): one burst's chance of a hit from its measured
// accuracy, the round's flight and the hit radius -- a munition's is the
// round's blast radius or its own size, as the fuse uses.
private _settings = _system getVariable "AEGISM_resolvedEngagementSettings";
if (isNil "_settings") then { _settings = [_system] call aegism_system_fnc_resolveEngagementSettings; };
private _hitRadius = if (_targetClass in ["missile", "rocket", "bomb", "artilleryShell"]) then {
    _targetRadius max (([_weaponClass, _magazineClass] call aegism_intercept_fnc_weaponKinematics) select 11)
} else { _targetRadius };
([_system, _turretPath, _weaponInfo, _targetClass, _hitRadius, _settings] call aegism_intercept_fnc_openFireRange) params ["_openFireRange", "_minRange"];

_ts set ["solve", [time, _aimPoint, _aimVelocity, _cameraOffset, _origin, _tolerance, _feasible, _interceptDistance, _target, _targetClass, _openFireRange, _minRange]];

private _aligned = [_system, _ts, _target, _targetClass, _angle, _tolerance, _feasible, _aimPoint, _interceptDistance, _openFireRange, _minRange] call aegism_intercept_fnc_ciwsGate;
[_aligned, _angle, _tolerance, _aimPoint, _feasible, _interceptDistance <= _openFireRange && {_interceptDistance >= _minRange}]
