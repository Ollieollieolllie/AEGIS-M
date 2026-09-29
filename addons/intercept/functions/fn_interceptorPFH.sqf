/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_interceptorPFH

Description:
    Per-frame proximity/direct-hit tracker for one AEGIS-M launcher missile
    (started by aegism_intercept_fnc_onSystemFired). Necessary because the
    engine has no projectile-vs-projectile collision at all: a missile
    passing straight through an incoming munition does nothing unless
    something scripted detonates both. (CIWS rounds are tracked together per
    gun by aegism_intercept_fnc_ciwsRounds.)

    Hit radius: the missile's own blast radius (CfgAmmo indirectHitRange),
    widened for a MUNITION target to that target's own physical half-size
    (aegism_intercept_fnc_targetHitRadius).

    Arming: no detonation until the missile has flown its own CfgAmmo
    fuseDistance from where it was fired (e.g. 100m for the MIM-145 SAM).

    Closest approach is computed on RELATIVE motion between frames (both
    the missile and the target move), not against the target's current
    position only -- at a 1500 m/s closing speed that difference is ~25m
    per frame.

    A guided missile is tracked for its whole flight: it routinely opens
    distance during boost or a turn and closes again. An unguided one stops
    being tracked once it has closed and started opening.

    On a hit: aegism_intercept_fnc_interceptHit. The engine's own proximity
    fuse (CfgAmmo proximityExplosionDistance, set on most vanilla SAMs) may
    detonate the missile first; this handler then simply sees it gone.

Parameters:
    _projectile - the missile <OBJECT>
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

    if (_minDistance <= _hitRadius && {(_launchPos distance _projPos) >= _armDistance}) exitWith {
        [_pfhHandle] call CBA_fnc_removePerFrameHandler;
        [_projectile, _target, _isMunitionTarget, _minDistance, _hitRadius] call aegism_intercept_fnc_interceptHit;
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
