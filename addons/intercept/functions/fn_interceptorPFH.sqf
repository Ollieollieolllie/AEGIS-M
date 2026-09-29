/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_interceptorPFH

Description:
    Per-frame proximity/direct-hit tracker for one AEGIS-M interceptor round
    (started by aegism_intercept_fnc_onSystemFired). Necessary because the
    engine has no projectile-vs-projectile collision at all: a missile or
    shell passing straight through an incoming munition does nothing unless
    something scripted detonates both.

    Hit radius:
        the round's own blast radius (CfgAmmo indirectHitRange, via
        aegism_intercept_fnc_munitionSize), widened for a MUNITION target to
        that target's own physical half-size (aegism_intercept_fnc_
        targetHitRadius) -- so a kinetic CIWS round (blast radius ~0) that
        passes through an incoming missile's body counts as a direct hit.
        A gun round against a platform target (aircraft) is never fuzed:
        the engine's own collision already handles it.

    Spotting (CIWS rounds, _spot given): every round is also measured
    against the track the target was PREDICTED to fly when the round was
    fired (_spot's track, from aegism_intercept_fnc_aimWeapon), and its
    closest pass to that predicted target is reported to aegism_intercept_
    fnc_ciwsSpot. Measuring against the prediction rather than the target
    itself keeps the gun's own errors (turret lag, flight time, drop) apart
    from the target's evasion, which no fire control can foresee -- measured
    against the real target, a helicopter's jink looked like a gun error and
    was fed back into the aim. A round that ends before it passes the
    predicted target (it hit the aircraft, or detonated) has its pass
    extrapolated from its last motion relative to it. Gun rounds against
    aircraft are tracked for this alone.

    Arming: no detonation until the round has flown its own CfgAmmo
    fuseDistance from where it was fired (the engine's own arming distance
    -- e.g. 100m for the MIM-145 SAM), so it can't fuze on a target right
    at the launcher.

    Closest approach is computed on RELATIVE motion between frames (both
    the round and the target move), not against the target's current
    position only -- at a 1500 m/s closing speed that difference is ~25m
    per frame.

    Guided rounds (simulation shotMissile) are tracked for their whole
    flight: a missile routinely opens distance during boost or a turn and
    closes again, and the old "distance increased once -> give up" rule
    stopped tracking before most missiles ever got close. Unguided rounds
    stop being tracked once they've closed and then started opening, since
    they can't come back.

    On a hit: the round is detonated in place (triggerAmmo, real splash);
    a munition target is detonated too (it has no hitpoints for the splash
    to act on). A platform target is left to real splash damage.

    A CARRIER target (CfgAmmo simulation "shotSubmunitions") is triggered
    the same way, but everything it releases is deleted the moment it's
    created (its "SubmunitionCreated" event). Triggering a carrier doesn't
    destroy it -- it makes it release its payload on the spot: every MLRS
    R_230mm_HE "kill" used to hand the Site a live R_230mm_fly warhead
    (1250m danger radius) to shoot at again, so each rocket cost two
    interceptors. A cluster carrier would have scattered its bomblets over
    the Site. The carrier is flagged "AEGISM_intercepted" first so
    aegism_detect_fnc_watchProjectile doesn't start tracking the payload.

    The engine's own proximity fuse (CfgAmmo proximityExplosionDistance, set
    on most vanilla SAMs) may detonate the missile first; this handler then
    simply sees the projectile gone and removes itself.

Parameters:
    _projectile - the interceptor round <OBJECT>
    _target - the target it was fired at <OBJECT>
    _spot - optional, CIWS rounds: [system, turretPath, burstId, aim
        correction at firing, predicted track [time, position, velocity,
        acceleration], round class] for aegism_intercept_fnc_ciwsSpot <ARRAY>

Returns:
    Nothing

Examples:
    [_missile, _incomingRocket] call aegism_intercept_fnc_interceptorPFH;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_projectile", "_target", ["_spot", []]];

if (isNull _projectile || {isNull _target}) exitWith {};

private _ammoCfg = configOf _projectile;
private _blastRadius = [typeOf _projectile] call aegism_intercept_fnc_munitionSize;
private _isMunitionTarget = ([_target] call aegism_detect_fnc_classifyTarget) in ["missile", "rocket", "bomb", "artilleryShell"];
private _targetRadius = [_target] call aegism_intercept_fnc_targetHitRadius;
private _hitRadius = if (_isMunitionTarget) then { _blastRadius max _targetRadius } else { _blastRadius };
// Proximity fuse: a missile against anything, a gun round only against a
// munition (against an aircraft the engine's own collision decides).
private _fuzed = _hitRadius > 0 && {_spot isEqualTo [] || {_isMunitionTarget}};
private _spotting = _spot isNotEqualTo [];
if (!_fuzed && {!_spotting}) exitWith {};

private _armDistance = getNumber (_ammoCfg >> "fuseDistance");
private _isGuided = (toLower getText (_ammoCfg >> "simulation")) == "shotmissile";
private _launchPos = getPosASLVisual _projectile;

// Round relative to the predicted target at launch (spotting only).
private _ghostRel = [0, 0, 0];
if (_spotting) then {
    (_spot select 4) params ["_trackTime", "_trackPos", "_trackVelocity", "_trackAcceleration"];
    private _dt = time - _trackTime;
    _ghostRel = _launchPos vectorDiff (_trackPos vectorAdd (_trackVelocity vectorMultiply _dt) vectorAdd (_trackAcceleration vectorMultiply (0.5 * _dt * _dt)));
};

[{
    params ["_args", "_pfhHandle"];
    _args params ["_projectile", "_target", "_hitRadius", "_armDistance", "_isGuided", "_launchPos", "_isMunitionTarget", "_lastProjPos", "_lastTargetPos", "_lastSeparation", "_hasClosed",
        "_spot", "_targetRadius", "_launchTime", "_realDone", "_spotted", "_lastGhostRel", "_lastGhostSeparation", "_ghostClosed", "_lastGhostRelVelocity"];

    // The predicted target (spotting): [position, velocity] now.
    private _fnGhost = {
        (_spot select 4) params ["_trackTime", "_trackPos", "_trackVelocity", "_trackAcceleration"];
        private _dt = time - _trackTime;
        [
            _trackPos vectorAdd (_trackVelocity vectorMultiply _dt) vectorAdd (_trackAcceleration vectorMultiply (0.5 * _dt * _dt)),
            _trackVelocity vectorAdd (_trackAcceleration vectorMultiply _dt)
        ]
    };
    // Reports one pass of the predicted target, with how far the real target
    // strayed from it at that moment (its evasion; -1 if it's gone).
    private _fnSpot = {
        params ["_miss", "_ghostPos", "_ghostVelocity"];
        private _deviation = if (!isNull _target && {alive _target}) then { (getPosASLVisual _target) distance _ghostPos } else { -1 };
        [_spot, _miss, _ghostPos, _ghostVelocity, time - _launchTime, _targetRadius, _deviation] call aegism_intercept_fnc_ciwsSpot;
    };
    // The round ended before passing the predicted target: extrapolate its
    // pass from its last relative motion -- only if it was still closing.
    private _fnSpotExtrapolated = {
        params ["_rel", "_relVelocity"];
        private _closing = _rel vectorDotProduct _relVelocity;
        private _speedSqr = _relVelocity vectorDotProduct _relVelocity;
        if (_closing < 0 && {_speedSqr > 0}) then {
            (call _fnGhost) params ["_ghostPos", "_ghostVelocity"];
            [_rel vectorAdd (_relVelocity vectorMultiply (-_closing / _speedSqr)), _ghostPos, _ghostVelocity] call _fnSpot;
        };
    };

    if (isNull _projectile || {!alive _projectile}) exitWith {
        [_pfhHandle] call CBA_fnc_removePerFrameHandler;
        if (!_spotted) then { [_lastGhostRel, _lastGhostRelVelocity] call _fnSpotExtrapolated; };
    };

    private _projPos = getPosASLVisual _projectile;

    // --- Spotting: the round against the predicted target.
    if (!_spotted) then {
        (call _fnGhost) params ["_ghostPos", "_ghostVelocity"];
        private _rel1 = _projPos vectorDiff _ghostPos;
        private _seg = _rel1 vectorDiff _lastGhostRel;
        private _segLenSqr = _seg vectorDotProduct _seg;
        private _closest = if (_segLenSqr <= 0.0001) then {
            _rel1
        } else {
            _lastGhostRel vectorAdd (_seg vectorMultiply (0 max (1 min (-(_lastGhostRel vectorDotProduct _seg) / _segLenSqr))))
        };
        private _separation = vectorMagnitude _rel1;
        if (_separation < _lastGhostSeparation) then { _ghostClosed = true; };
        if (_ghostClosed && {_separation > _lastGhostSeparation}) then {
            [_closest, _ghostPos, _ghostVelocity] call _fnSpot;
            _spotted = true;
            _args set [15, true];
        } else {
            _args set [16, _rel1];
            _args set [17, _separation];
            _args set [18, _ghostClosed];
            _args set [19, _seg vectorMultiply (1 / (diag_deltaTime max 0.001))];
        };
    };

    // --- Proximity fuse against the real target.
    private _detonated = false;
    if (!_realDone) then {
        if (isNull _target || {!alive _target}) then {
            _realDone = true;
        } else {
            private _targetPos = getPosASLVisual _target;
            private _rel0 = _lastProjPos vectorDiff _lastTargetPos;
            private _rel1 = _projPos vectorDiff _targetPos;
            private _seg = _rel1 vectorDiff _rel0;
            private _segLenSqr = _seg vectorDotProduct _seg;
            private _minDistance = vectorMagnitude (if (_segLenSqr <= 0.0001) then {
                _rel1
            } else {
                _rel0 vectorAdd (_seg vectorMultiply (0 max (1 min (-(_rel0 vectorDotProduct _seg) / _segLenSqr))))
            });
            private _separation = vectorMagnitude _rel1;
            private _armed = (_launchPos distance _projPos) >= _armDistance;

            if (_armed && {_minDistance <= _hitRadius}) then {
                _detonated = true;
                triggerAmmo _projectile;
                if (_isMunitionTarget) then {
                    if ((toLower getText (configOf _target >> "simulation")) == "shotsubmunitions") then {
                        _target setVariable ["AEGISM_intercepted", true];
                        _target addEventHandler ["SubmunitionCreated", {
                            params ["", "_submunitionProjectile"];
                            deleteVehicle _submunitionProjectile;
                        }];
                    };
                    triggerAmmo _target;
                };
                diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " INTERCEPT: %1 hit %2 (closest %3m, hit radius %4m).", typeOf _projectile, _target, _minDistance, _hitRadius];
            } else {
                if (_separation < _lastSeparation) then { _hasClosed = true; };
                if (!_isGuided && {_hasClosed} && {_separation > _lastSeparation}) then { _realDone = true; };
                _args set [7, _projPos];
                _args set [8, _targetPos];
                _args set [9, _separation];
                _args set [10, _hasClosed];
            };
        };
        _args set [14, _realDone];
    };

    if (_detonated) exitWith {
        [_pfhHandle] call CBA_fnc_removePerFrameHandler;
        if (!_spotted) then { [_args select 16, _args select 19] call _fnSpotExtrapolated; };
    };
    if (_realDone && {_spotted}) exitWith {
        [_pfhHandle] call CBA_fnc_removePerFrameHandler;
    };
}, 0, [_projectile, _target, _hitRadius, _armDistance, _isGuided, _launchPos, _isMunitionTarget, _launchPos, getPosASLVisual _target, _launchPos distance (getPosASLVisual _target), false,
    _spot, _targetRadius, time, !_fuzed, !_spotting, _ghostRel, vectorMagnitude _ghostRel, false, [0, 0, 0]]] call CBA_fnc_addPerFrameHandler;
