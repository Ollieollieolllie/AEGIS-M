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
        Against a platform target a round with no blast radius isn't
        tracked at all: the engine's own collision already handles it.

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

Returns:
    Nothing

Examples:
    [_missile, _incomingRocket] call aegism_intercept_fnc_interceptorPFH;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_projectile", "_target"];

if (isNull _projectile || {isNull _target}) exitWith {};

private _ammoCfg = configOf _projectile;
private _blastRadius = [typeOf _projectile] call aegism_intercept_fnc_munitionSize;
private _isMunitionTarget = ([_target] call aegism_detect_fnc_classifyTarget) in ["missile", "rocket", "bomb", "artilleryShell"];
private _hitRadius = if (_isMunitionTarget) then { _blastRadius max ([_target] call aegism_intercept_fnc_targetHitRadius) } else { _blastRadius };
if (_hitRadius <= 0) exitWith {};

private _armDistance = getNumber (_ammoCfg >> "fuseDistance");
private _isGuided = (toLower getText (_ammoCfg >> "simulation")) == "shotmissile";
private _launchPos = getPosASLVisual _projectile;

[{
    params ["_args", "_pfhHandle"];
    _args params ["_projectile", "_target", "_hitRadius", "_armDistance", "_isGuided", "_launchPos", "_isMunitionTarget", "_lastProjPos", "_lastTargetPos", "_lastSeparation", "_hasClosed"];

    if (isNull _projectile || {!alive _projectile} || {isNull _target} || {!alive _target}) exitWith {
        [_pfhHandle] call CBA_fnc_removePerFrameHandler;
    };

    private _projPos = getPosASLVisual _projectile;
    private _targetPos = getPosASLVisual _target;

    // Closest approach of the relative-position segment to the origin.
    private _rel0 = _lastProjPos vectorDiff _lastTargetPos;
    private _rel1 = _projPos vectorDiff _targetPos;
    private _seg = _rel1 vectorDiff _rel0;
    private _segLenSqr = _seg vectorDotProduct _seg;
    private _minDistance = if (_segLenSqr <= 0.0001) then {
        vectorMagnitude _rel1
    } else {
        private _t = 0 max (1 min (-(_rel0 vectorDotProduct _seg) / _segLenSqr));
        vectorMagnitude (_rel0 vectorAdd (_seg vectorMultiply _t))
    };

    private _separation = vectorMagnitude _rel1;
    private _armed = (_launchPos distance _projPos) >= _armDistance;

    if (_armed && {_minDistance <= _hitRadius}) exitWith {
        [_pfhHandle] call CBA_fnc_removePerFrameHandler;
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
    };

    if (_separation < _lastSeparation) then { _hasClosed = true; };
    if (!_isGuided && {_hasClosed} && {_separation > _lastSeparation}) exitWith {
        [_pfhHandle] call CBA_fnc_removePerFrameHandler;
    };

    _args set [7, _projPos];
    _args set [8, _targetPos];
    _args set [9, _separation];
    _args set [10, _hasClosed];
}, 0, [_projectile, _target, _hitRadius, _armDistance, _isGuided, _launchPos, _isMunitionTarget, _launchPos, getPosASLVisual _target, _launchPos distance (getPosASLVisual _target), false]] call CBA_fnc_addPerFrameHandler;
