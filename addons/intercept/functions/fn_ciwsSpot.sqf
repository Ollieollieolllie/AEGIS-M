/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_ciwsSpot

Description:
    Closed-loop spotting for a CIWS gun, the way a real Phalanx corrects its
    own aim: a sample of its rounds is measured as they pass the PREDICTED
    target -- the track the aim was solved against when the round was fired
    (aegism_intercept_fnc_ciwsRounds) -- and what each round says the gun
    NEEDED is folded into a correction the gun's aim carries (aegism_
    intercept_fnc_aimWeapon).

    Measured against the prediction, a miss is the gun's own error only:
    turret lag, the flight-time estimate, drop, zeroing. The target's
    evasion -- where it went that the prediction didn't foresee -- is kept
    out of it (it's reported separately, as how far the target strayed from
    its predicted track). Measured against the real target, a jinking
    helicopter's escape looked like a gun error and was fed back into the
    aim.

    The miss is split on two axes square to the gun's line of sight and to
    each other:
        ahead - along the predicted target's crossing motion (+ ahead of it,
            - behind). A lead error of dt seconds misses by crossing speed x
            dt, so the round's needed lead correction is (its correction at
            firing) - ahead / crossing speed. Only measurable when the target
            crossed further than its own size during the round's flight (one
            coming straight down the barrel needs no lead).
        high - the part of "up" square to that crossing motion (+ high).
            Needed elevation correction = (its correction at firing) - high /
            range; aegism_intercept_fnc_aimWeapon applies it on the same
            axis. A target whose crossing motion is itself up/down leaves no
            separate "high" to measure (its weight goes to 0): any error on
            that axis is the lead's.

    Estimate: a weighted mean of each round's needed correction, one per
    TARGET CLASS (a lead learned on falling shells isn't a helicopter's),
    reset when the gun changes ammunition. Each round is weighted by how
    precisely it measures: a round's own scatter is the gun's dispersion
    (an angle), so a lead sample's uncertainty grows with range / crossing
    speed (weight (crossing speed / range)^2), and "high" only exists in
    proportion to how much of the vertical its axis carries (weight: the
    square of that). Older rounds fade by AEGISM_SPOT_DECAY per new round
    (about the last few hundred count), so the correction follows a change
    -- the vehicle moving, a different engagement geometry -- instead of
    being outvoted by the whole mission's history. It used to be recomputed
    from each burst alone: a few rounds, often close in where a metre of
    miss is many milliradians, swung it from +1.4 to -12.3 mrad between
    bursts.

    Turret state (aegism_intercept_fnc_turretState):
        estimate - target class -> [round class, lead weight, weighted lead
            s, elevation weight, weighted elevation rad]
        corrections - target class -> [lead s, elevation rad]
        spotStats - burstId -> [rounds, sum ahead m, sum high m, sum target
            deviation m, deviation samples], for aegism_intercept_fnc_
            ciwsBurst's SPOTTING line
        scatter - target class -> [round class, rounds, sum of squared
            angular miss square to the line of sight, sum of squared target
            deviation m, sum of squared flight time s] (fading like the
            estimate) -- the gun's measured accuracy, for aegism_intercept_
            fnc_openFireRange

Parameters:
    _spot - [system, turretPath, burstId, correction at firing [lead s,
        elevation rad], predicted track, round class, target class] <ARRAY>
    _miss - round position minus predicted target position at closest
        approach, m <ARRAY>
    _ghostPos - predicted target position then, ASL <ARRAY>
    _ghostVelocity - predicted target velocity then <ARRAY>
    _flightTime - seconds the round had flown <NUMBER>
    _targetRadius - the target's own half-size, m <NUMBER>
    _deviation - how far the real target was from its predicted position,
        m, -1 if unknown <NUMBER>

Returns:
    Nothing

Examples:
    [_spot, [4.2, -1.1, 0.3], _ghostPos, _ghostVelocity, 1.8, 7.5, 3.1] call aegism_intercept_fnc_ciwsSpot;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_SPOT_KEEP_BURSTS 4
#define AEGISM_SPOT_DECAY 0.997

params ["_spot", "_miss", "_ghostPos", "_ghostVelocity", "_flightTime", "_targetRadius", "_deviation"];
_spot params ["_system", "_turretPath", "_burstId", "_correctionAtFire", "", "_roundClass", ["_targetClass", ""]];
_correctionAtFire params ["_leadAtFire", "_elevationAtFire"];

if (isNull _system) exitWith {};

private _gunPos = eyePos _system;
private _range = _gunPos distance _ghostPos;
if (_range <= 0) exitWith {};

private _ts = [_system, _turretPath] call aegism_intercept_fnc_turretState;

// Two axes square to the line of sight, and square to EACH OTHER: "ahead"
// along the target's crossing motion, and "high" along the part of up that
// isn't along that motion. (High used to be all of up: for a shell coming
// down in the gun's own vertical plane, whose crossing motion IS up/down,
// one miss was counted on both axes -- "3.7m behind and 3.7m low" -- and
// both corrections moved the aim for it, together overshooting.)
private _los = _gunPos vectorFromTo _ghostPos;
private _crossVelocity = _ghostVelocity vectorDiff (_los vectorMultiply (_ghostVelocity vectorDotProduct _los));
private _crossSpeed = vectorMagnitude _crossVelocity;
private _along = if (_crossSpeed > 0) then { _crossVelocity vectorMultiply (1 / _crossSpeed) } else { [0, 0, 0] };
private _ahead = _miss vectorDotProduct _along;
private _upSquare = [0, 0, 1] vectorDiff (_los vectorMultiply (_los select 2));
_upSquare = _upSquare vectorDiff (_along vectorMultiply (_upSquare vectorDotProduct _along));
// How much of the vertical this axis still carries: 1 looking level at a
// target crossing sideways, 0 looking straight up, or at one moving up/down.
private _cosElevation = vectorMagnitude _upSquare;
private _high = if (_cosElevation > 0.001) then { _miss vectorDotProduct (_upSquare vectorMultiply (1 / _cosElevation)) } else { 0 };

// --- This burst's stats (SPOTTING line) ---------------------------------------
private _allStats = _ts get "spotStats";
if (isNil "_allStats") then { _allStats = createHashMap; _ts set ["spotStats", _allStats]; };
private _burstStats = _allStats get _burstId;
if (isNil "_burstStats") then {
    _burstStats = [0, 0, 0, 0, 0];
    _allStats set [_burstId, _burstStats];
    // A new burst: drop the ones too old to be reported.
    { if (_x < _burstId - AEGISM_SPOT_KEEP_BURSTS) then { _allStats deleteAt _x; }; } forEach (keys _allStats);
};
_burstStats set [0, (_burstStats select 0) + 1];
_burstStats set [1, (_burstStats select 1) + _ahead];
_burstStats set [2, (_burstStats select 2) + _high];
if (_deviation >= 0) then {
    _burstStats set [3, (_burstStats select 3) + _deviation];
    _burstStats set [4, (_burstStats select 4) + 1];
};

// --- The gun's correction for this target class ------------------------------
private _estimates = _ts get "estimate";
if (isNil "_estimates") then { _estimates = createHashMap; _ts set ["estimate", _estimates]; };
private _estimate = _estimates getOrDefault [_targetClass, []];
if ((_estimate param [0, ""]) != _roundClass) then { _estimate = [_roundClass, 0, 0, 0, 0]; };
_estimate params ["", "_leadWeight", "_weightedLead", "_elevationWeight", "_weightedElevation"];

_leadWeight = _leadWeight * AEGISM_SPOT_DECAY;
_weightedLead = _weightedLead * AEGISM_SPOT_DECAY;
_elevationWeight = _elevationWeight * AEGISM_SPOT_DECAY;
_weightedElevation = _weightedElevation * AEGISM_SPOT_DECAY;

if (_crossSpeed * _flightTime > _targetRadius) then {
    private _weight = (_crossSpeed / _range) ^ 2;
    _leadWeight = _leadWeight + _weight;
    _weightedLead = _weightedLead + _weight * (_leadAtFire - _ahead / _crossSpeed);
};
if (_cosElevation > 0.001) then {
    private _weight = _cosElevation ^ 2;
    _elevationWeight = _elevationWeight + _weight;
    _weightedElevation = _weightedElevation + _weight * (_elevationAtFire - _high / _range);
};
_estimates set [_targetClass, [_roundClass, _leadWeight, _weightedLead, _elevationWeight, _weightedElevation]];

private _corrections = _ts get "corrections";
if (isNil "_corrections") then { _corrections = createHashMap; _ts set ["corrections", _corrections]; };
_corrections set [_targetClass, [
    if (_leadWeight > 0) then { _weightedLead / _leadWeight } else { 0 },
    if (_elevationWeight > 0) then { _weightedElevation / _elevationWeight } else { 0 }
]];

// --- The gun's measured accuracy (aegism_intercept_fnc_openFireRange) --------
// Its rounds' angular miss square to the line of sight, as fired (with the
// correction they carried), and how far the real target strayed from the
// predicted track against the round's flight time.
private _perpendicular = _miss vectorDiff (_los vectorMultiply (_miss vectorDotProduct _los));
private _scatterAll = _ts get "scatter";
if (isNil "_scatterAll") then { _scatterAll = createHashMap; _ts set ["scatter", _scatterAll]; };
private _scatter = _scatterAll getOrDefault [_targetClass, []];
if ((_scatter param [0, ""]) != _roundClass) then { _scatter = [_roundClass, 0, 0, 0, 0]; };
_scatter params ["", "_scatterRounds", "_sumAngleSq", "_sumDeviationSq", "_sumFlightSq"];
_scatterRounds = _scatterRounds * AEGISM_SPOT_DECAY + 1;
_sumAngleSq = _sumAngleSq * AEGISM_SPOT_DECAY + (_perpendicular vectorDotProduct _perpendicular) / (_range * _range);
_sumDeviationSq = _sumDeviationSq * AEGISM_SPOT_DECAY;
_sumFlightSq = _sumFlightSq * AEGISM_SPOT_DECAY;
if (_deviation >= 0 && {_flightTime > 0}) then {
    _sumDeviationSq = _sumDeviationSq + _deviation * _deviation;
    _sumFlightSq = _sumFlightSq + _flightTime * _flightTime;
};
_scatterAll set [_targetClass, [_roundClass, _scatterRounds, _sumAngleSq, _sumDeviationSq, _sumFlightSq]];
