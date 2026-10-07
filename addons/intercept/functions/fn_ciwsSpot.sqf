/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_ciwsSpot

Description:
    Closed-loop spotting for a CIWS gun: its rounds are measured as they
    pass the predicted target, and what they say the gun needed is folded
    into a correction its aim carries.
    Full notes: docs/functions/intercept.md

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

#include "..\calibration.hpp"

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

// The round's miss square to the line of sight, as it would have been with
// the correction [lead s, elevation rad] instead of the one it was fired with.
private _perpendicular = _miss vectorDiff (_los vectorMultiply (_miss vectorDotProduct _los));
private _crosses = _crossSpeed * _flightTime > _targetRadius;
private _fnMissWith = {
    params ["_lead", "_elevation"];
    private _shifted = _perpendicular;
    if (_crosses) then {
        _shifted = _shifted vectorAdd (_along vectorMultiply ((_lead - _leadAtFire) * _crossSpeed));
    };
    if (_cosElevation > 0.001) then {
        _shifted = _shifted vectorAdd ((_upSquare vectorMultiply (1 / _cosElevation)) vectorMultiply ((_elevation - _elevationAtFire) * _range));
    };
    _shifted
};
private _corrections = _ts get "corrections";
if (isNil "_corrections") then { _corrections = createHashMap; _ts set ["corrections", _corrections]; };

// --- Safeguards (calibration.hpp) ----------------------------------------------
// An outlier: missing where the gun aims now (its correction before this
// round) by more than AEGISM_SPOT_OUTLIER times the median of its recent
// rounds' misses -- or, missing by no more than the target's own size, never.
// Its miss is still added to the recent ones, so if misses that size become
// the norm the median follows and they count again.
private _residual = (vectorMagnitude ((_corrections getOrDefault [_targetClass, [0, 0]]) call _fnMissWith)) / _range;
private _scales = _ts get "spotScale";
if (isNil "_scales") then { _scales = createHashMap; _ts set ["spotScale", _scales]; };
private _scale = _scales getOrDefault [_targetClass, []];
if ((_scale param [0, ""]) != _roundClass) then { _scale = [_roundClass, []]; _scales set [_targetClass, _scale]; };
private _recent = _scale select 1;
private _outlier = false;
if (count _recent >= AEGISM_SPOT_SCALE_MIN) then {
    private _sorted = +_recent;
    _sorted sort true;
    _outlier = _residual > AEGISM_SPOT_OUTLIER * ((_sorted select floor (count _sorted / 2)) max (_targetRadius / _range));
};
_recent pushBack _residual;
if (count _recent > AEGISM_SPOT_SCALE_ROUNDS) then { _recent deleteAt 0; };
// How far the real target strayed: no further than it could accelerate away
// from its predicted track during the round's flight -- beyond, its track or
// position glitched.
if (_deviation > AEGISM_MAX_ACCEL(_targetClass) * _flightTime * _flightTime + _targetRadius) then { _deviation = -1; };

// --- This burst's stats (SPOTTING line) ---------------------------------------
// [rounds used, sum ahead m, sum high m, sum target deviation m, deviation
// samples, outliers left out]
private _allStats = _ts get "spotStats";
if (isNil "_allStats") then { _allStats = createHashMap; _ts set ["spotStats", _allStats]; };
private _burstStats = _allStats get _burstId;
if (isNil "_burstStats") then {
    _burstStats = [0, 0, 0, 0, 0, 0];
    _allStats set [_burstId, _burstStats];
    // A new burst: drop the ones too old to be reported.
    { if (_x < _burstId - AEGISM_SPOT_KEEP_BURSTS) then { _allStats deleteAt _x; }; } forEach (keys _allStats);
};
if (_outlier) exitWith { _burstStats set [5, (_burstStats param [5, 0]) + 1]; };
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

// What this round says the gun needs -- only believed inside AEGISM_SPOT_MAX_
// LEAD / ELEVATION, so the correction (their average) stays inside them too.
if (_crosses) then {
    private _neededLead = _leadAtFire - _ahead / _crossSpeed;
    if (abs _neededLead <= AEGISM_SPOT_MAX_LEAD) then {
        private _weight = (_crossSpeed / _range) ^ 2;
        _leadWeight = _leadWeight + _weight;
        _weightedLead = _weightedLead + _weight * _neededLead;
    };
};
if (_cosElevation > 0.001) then {
    private _neededElevation = _elevationAtFire - _high / _range;
    if (abs _neededElevation <= AEGISM_SPOT_MAX_ELEVATION) then {
        private _weight = _cosElevation ^ 2;
        _elevationWeight = _elevationWeight + _weight;
        _weightedElevation = _weightedElevation + _weight * _neededElevation;
    };
};
_estimates set [_targetClass, [_roundClass, _leadWeight, _weightedLead, _elevationWeight, _weightedElevation]];

_corrections set [_targetClass, [
    if (_leadWeight > 0) then { _weightedLead / _leadWeight } else { 0 },
    if (_elevationWeight > 0) then { _weightedElevation / _elevationWeight } else { 0 }
]];

// --- The gun's measured accuracy (aegism_intercept_fnc_openFireRange) --------
// Its rounds' angular miss square to the line of sight, as it would have
// been with the correction the gun carries NOW (this round included) -- its
// scatter about where it now aims -- and how far the real target strayed
// from the predicted track against the round's flight time. Taken as fired,
// a lead error the correction then took out counted as scatter: one burst at
// a fast missile, 71m behind it, put the Cheetah's measured scatter at 37-47
// mrad (config 4.5) and its open-fire range at 400-500m, for every missile
// after it.
_perpendicular = (_corrections get _targetClass) call _fnMissWith;
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
