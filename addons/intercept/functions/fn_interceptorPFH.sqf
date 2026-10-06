/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_interceptorPFH

Description:
    Per-frame proximity/direct-hit tracker for one AEGIS-M launcher missile
    (started by aegism_intercept_fnc_onSystemFired). Necessary because the
    engine has no projectile-vs-projectile collision at all: a missile
    passing straight through an incoming munition does nothing unless
    something scripted detonates both. (CIWS rounds are tracked together per
    gun by aegism_intercept_fnc_ciwsRounds.)

    Hit: against a MUNITION target, the missile's path coming within its
    own radius -- its blast (CfgAmmo indirectHitRange) or its proximity fuse
    (proximityExplosionDistance), whichever is larger -- of the target's
    body, its box (aegism_intercept_fnc_bodyPass); against an aircraft,
    within its blast of the aircraft's centre.

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
    detonate the missile first; this handler then sees it gone, and credits
    the kill if the stretch it was on that frame came within its radius of
    the munition's body.

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

    Speed: sampled every second after launch, and folded into the missile's
    learned speed curve however the flight ends (aegism_intercept_fnc_
    recordMissileSpeed, MISSILE-SPEED). An intercept also logs the length
    of the path it actually flew (summed frame by frame) against the
    straight line, for the log's check of the prediction. A missile whose
    seeker changed to another munition (above) isn't measured for its turn
    rate; its speeds still count.

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
private _hitRadius = if (_isMunitionTarget) then { _blastRadius max getNumber (_ammoCfg >> "proximityExplosionDistance") } else { _blastRadius };
if (_hitRadius <= 0 && {!_isMunitionTarget}) exitWith {};

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
        // Gone since the last frame. If the stretch it was on -- from where
        // it was, at the velocity it had, for this frame -- comes within its
        // own radius of a munition's body, it went off within reach of it:
        // the game's own proximity fuse, ahead of this one. That's a kill
        // (the blast used to reach the munition's sensor proxy; half the
        // RIM-162's kills came that way).
        private _miss = -1;
        private _at = _lastProjPos;
        if (_isMunitionTarget && {!isNull _target} && {alive _target} && {(_launchPos distance _lastProjPos) >= _armDistance}) then {
            private _targetPos = getPosWorldVisual _target;
            private _stretch = (_args select 18) vectorMultiply diag_deltaTime;
            private _passed = [_target, _lastProjPos vectorDiff _lastTargetPos, (_lastProjPos vectorAdd _stretch) vectorDiff _targetPos, _hitRadius] call aegism_intercept_fnc_bodyPass;
            if (_passed <= _hitRadius) then {
                _miss = _passed;
                // Where on that stretch: nearest the target.
                private _lengthSq = _stretch vectorDotProduct _stretch;
                if (_lengthSq > 0) then {
                    _at = _lastProjPos vectorAdd (_stretch vectorMultiply (0 max (1 min (((_targetPos vectorDiff _lastProjPos) vectorDotProduct _stretch) / _lengthSq))));
                };
            };
        };
        if (_isGuided && {_launch isNotEqualTo []}) then {
            private _flown = CBA_missionTime - (_launch param [2, CBA_missionTime]);
            if (_miss >= 0) then {
                [_ammoClass, _launch, _peakRate, _flown, _retargeted] call aegism_intercept_fnc_recordMissileTurn;
                [_launch param [3, ""], _launch param [4, ""], _flown, _pathFlown, _speeds, "", _launchPos distance _at] call aegism_intercept_fnc_recordMissileSpeed;
            } else {
                [_ammoClass, _launch, _peakRate, -1, _retargeted] call aegism_intercept_fnc_recordMissileTurn;
                [_launch param [3, ""], _launch param [4, ""], _flown, -1, _speeds,
                    "ended out of reach of its target (it missed, or its life ran out)"] call aegism_intercept_fnc_recordMissileSpeed;
            };
        };
        if (_miss >= 0) then {
            [_projectile, _target, true, _miss, _hitRadius, _at, _ammoClass] call aegism_intercept_fnc_interceptHit;
        };
    };

    // Lost: its target gone before it got there, or its seeker on something
    // else. Another incoming munition in its launcher's Site picture is
    // followed instead; anything else, it self-destructs (aegism_intercept_
    // fnc_interceptorLost).
    private _why = "";
    if (isNull _target || {!alive _target}) then { _why = format ["its target %1 is gone before it got there", _args select 14]; };
    if (_isGuided) then {
        private _homing = missileTarget _projectile;
        if (!isNull _homing && {_homing != _target}) then {
            private _launcher = (getShotParents _projectile) param [0, objNull];
            private _site = _launcher getVariable ["AEGISM_network", objNull];
            private _pool = ([_site, _launcher] select (isNull _site)) getVariable ["AEGISM_pooledContacts", createHashMap];
            if (alive _homing && {(_homing getVariable ["AEGISM_contactKey", ""]) in _pool}) then {
                _target = _homing;
                _args set [1, _homing];
                _args set [8, getPosWorldVisual _homing];
                _args set [9, _projectile distance _homing];
                _args set [14, str _homing];
                // Its turns are no longer all toward the one intercept: not
                // measured for its turn rate (MISSILE-TURN).
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
            [_launch param [3, ""], _launch param [4, ""], CBA_missionTime - (_launch param [2, CBA_missionTime]), -1, _speeds,
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
    // Relative to the target's model origin: a munition's body is its box
    // there (aegism_intercept_fnc_bodyPass), an aircraft its centre.
    private _targetPos = getPosWorldVisual _target;
    private _rel0 = _lastProjPos vectorDiff _lastTargetPos;
    private _rel1 = _projPos vectorDiff _targetPos;
    private _minDistance = if (_isMunitionTarget) then {
        [_target, _rel0, _rel1, _hitRadius] call aegism_intercept_fnc_bodyPass
    } else {
        private _seg = _rel1 vectorDiff _rel0;
        private _segLenSqr = _seg vectorDotProduct _seg;
        vectorMagnitude (if (_segLenSqr <= 0.0001) then {
            _rel1
        } else {
            _rel0 vectorAdd (_seg vectorMultiply (0 max (1 min (-(_rel0 vectorDotProduct _seg) / _segLenSqr))))
        })
    };
    private _separation = vectorMagnitude _rel1;

    if (_minDistance <= _hitRadius && {(_launchPos distance _projPos) >= _armDistance}) exitWith {
        [_pfhHandle] call CBA_fnc_removePerFrameHandler;
        if (_isGuided && {_launch isNotEqualTo []}) then {
            private _flown = CBA_missionTime - (_launch param [2, CBA_missionTime]);
            [_ammoClass, _launch, _peakRate, _flown, _args select 15] call aegism_intercept_fnc_recordMissileTurn;
            [_launch param [3, ""], _launch param [4, ""], _flown, _pathFlown, _speeds, "", _launchPos distance _projPos] call aegism_intercept_fnc_recordMissileSpeed;
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
    // Its velocity, for the stretch it was on if it's gone next frame.
    _args set [18, velocity _projectile];
}, 0, [_projectile, _target, _hitRadius, _armDistance, _isGuided, _launchPos, _isMunitionTarget, _launchPos, getPosWorldVisual _target, _launchPos distance (getPosWorldVisual _target), false,
    typeOf _projectile, _launch, [vectorDirVisual _projectile, CBA_missionTime, 0, 0, 0], str _target, false, [], 0, velocity _projectile]] call CBA_fnc_addPerFrameHandler;
