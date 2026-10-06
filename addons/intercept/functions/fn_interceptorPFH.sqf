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

    Lost target: a guided missile whose target is gone before it gets there
    (another weapon killed it first), or whose seeker has turned to
    something else, follows another incoming munition its launcher's Site
    is tracking if that's what its seeker took -- otherwise it
    self-destructs (aegism_intercept_fnc_interceptorLost). Left free, its
    seeker took the next thing it found, which shot down an aircraft the
    Site wasn't allowed to engage.

    Turn rate: a guided missile's body direction is followed every frame,
    and its rotation summed over AEGISM_TURN_WINDOW s windows -- the fastest
    window is the flight's fastest SUSTAINED turn (a window that long
    averages out frame-to-frame jitter and a last-instant jink). The body
    direction, not the velocity: gravity bends a slow missile's path just
    off the rail without it steering at all. At the end of the flight it's
    folded into the missile's turn rate (aegism_intercept_fnc_
    recordMissileTurn, MISSILE-TURN) -- what an off-bore launch is planned
    with (aegism_intercept_fnc_launchSolution).

    Speed: a flight that ends in its intercept is scored against its flight
    simulated from config (aegism_intercept_fnc_recordMissileSpeed,
    MISSILE-SPEED): its time, and the length of the path it actually flew
    (summed frame by frame) -- not the straight line from where it was
    launched, which left out the turn after an off-bore launch: the lead
    solver models that turn itself, and the RIM-116's factor counted it a
    second time (predictions ~9% long once it applied, 2026-10-06). A
    missile whose seeker changed to another munition (above) isn't
    measured for either. Its speed is sampled every second after launch, for
    the log's check of the simulation -- logged however the flight ends.

Parameters:
    _projectile - the missile <OBJECT>
    _target - the target it was fired at <OBJECT>
    _launch - optional, its launch plan [off-bore deg, predicted flight s,
        fired at, weapon class, magazine class] (aegism_intercept_fnc_
        fireWeapon) <ARRAY>

Returns:
    Nothing

Examples:
    [_missile, _incomingRocket] call aegism_intercept_fnc_interceptorPFH;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

// Turn-rate measurement window, seconds (see header).
#define AEGISM_TURN_WINDOW 0.5

params ["_projectile", "_target", ["_launch", []]];

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
    _args params ["_projectile", "_target", "_hitRadius", "_armDistance", "_isGuided", "_launchPos", "_isMunitionTarget", "_lastProjPos", "_lastTargetPos", "_lastSeparation", "_hasClosed",
        "_ammoClass", "_launch", "_turn", "", "_retargeted", "_speeds", "_pathFlown"];
    // Turn measurement (see header): [last direction, last time, window
    // angle, window time, fastest window deg/s].
    _turn params ["_lastDir", "_lastTime", "_windowAngle", "_windowTime", "_peakRate"];

    if (isNull _projectile || {!alive _projectile}) exitWith {
        [_pfhHandle] call CBA_fnc_removePerFrameHandler;
        if (_isGuided && {_launch isNotEqualTo []}) then {
            [_ammoClass, _launch, _peakRate, -1, _retargeted] call aegism_intercept_fnc_recordMissileTurn;
            [_launch param [3, ""], _launch param [4, ""], CBA_missionTime - (_launch param [2, CBA_missionTime]), -1, _retargeted, _speeds,
                "ended without AEGIS-M's fuse seeing its intercept (it missed, the game's own proximity fuse went off, or its life ran out)"] call aegism_intercept_fnc_recordMissileSpeed;
        };
    };

    // Lost: its target gone before it got there, or its seeker on something
    // else (a sensor proxy counts as its munition). Another incoming munition
    // in its launcher's Site picture is followed instead; anything else, it
    // self-destructs (aegism_intercept_fnc_interceptorLost).
    private _why = "";
    if (isNull _target || {!alive _target}) then { _why = format ["its target %1 is gone before it got there", _args select 14]; };
    if (_isGuided) then {
        private _homing = missileTarget _projectile;
        if (!isNull _homing && {_homing isKindOf "AEGISM_MunitionProxy"}) then { _homing = (_homing getVariable ["AEGISM_proxyEntry", [objNull]]) select 0; };
        if (!isNull _homing && {_homing != _target}) then {
            private _launcher = (getShotParents _projectile) param [0, objNull];
            private _site = _launcher getVariable ["AEGISM_network", objNull];
            private _pool = ([_site, _launcher] select (isNull _site)) getVariable ["AEGISM_pooledContacts", createHashMap];
            if (alive _homing && {(_homing getVariable ["AEGISM_contactKey", ""]) in _pool}) then {
                _target = _homing;
                _args set [1, _homing];
                _args set [8, getPosASLVisual _homing];
                _args set [9, _projectile distance _homing];
                _args set [14, str _homing];
                // Its turns and flight time are no longer all toward the one
                // intercept: not measured (MISSILE-TURN, MISSILE-SPEED).
                _args set [15, true];
                _why = "";
            } else {
                _why = format ["its seeker turned from %1 to %2 (%3)", _args select 14, _homing, typeOf _homing];
            };
        };
    };
    if (_why != "") exitWith {
        [_pfhHandle] call CBA_fnc_removePerFrameHandler;
        if (_isGuided && {_launch isNotEqualTo []}) then {
            [_ammoClass, _launch, _peakRate, -1, _args select 15] call aegism_intercept_fnc_recordMissileTurn;
            [_launch param [3, ""], _launch param [4, ""], CBA_missionTime - (_launch param [2, CBA_missionTime]), -1, _args select 15, _speeds,
                format ["self-destructed: %1", _why]] call aegism_intercept_fnc_recordMissileSpeed;
        };
        if (_isGuided) then { [_projectile, _target, _why] call aegism_intercept_fnc_interceptorLost; };
    };

    if (_isGuided) then {
        private _dir = vectorDirVisual _projectile;
        _windowAngle = _windowAngle + acos (((_dir vectorCos _lastDir) min 1) max -1);
        _windowTime = _windowTime + (CBA_missionTime - _lastTime);
        if (_windowTime >= AEGISM_TURN_WINDOW) then {
            _peakRate = _peakRate max (_windowAngle / _windowTime);
            _windowAngle = 0;
            _windowTime = 0;
        };
        _args set [13, [_dir, CBA_missionTime, _windowAngle, _windowTime, _peakRate]];
        // Its speed each whole second after launch (see header).
        if (_launch isNotEqualTo [] && {CBA_missionTime - (_launch param [2, CBA_missionTime]) >= (count _speeds) + 1}) then {
            _speeds pushBack (vectorMagnitude velocity _projectile);
        };
    };

    private _projPos = getPosASLVisual _projectile;
    _pathFlown = _pathFlown + (_projPos vectorDistance _lastProjPos);
    _args set [17, _pathFlown];
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
        if (_isGuided && {_launch isNotEqualTo []}) then {
            private _flown = CBA_missionTime - (_launch param [2, CBA_missionTime]);
            [_ammoClass, _launch, _peakRate, _flown, _args select 15] call aegism_intercept_fnc_recordMissileTurn;
            [_launch param [3, ""], _launch param [4, ""], _flown, _pathFlown, _args select 15, _speeds, "", _launchPos distance _projPos] call aegism_intercept_fnc_recordMissileSpeed;
        };
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
}, 0, [_projectile, _target, _hitRadius, _armDistance, _isGuided, _launchPos, _isMunitionTarget, _launchPos, getPosASLVisual _target, _launchPos distance (getPosASLVisual _target), false,
    typeOf _projectile, _launch, [vectorDirVisual _projectile, CBA_missionTime, 0, 0, 0], str _target, false, [], 0]] call CBA_fnc_addPerFrameHandler;
