/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_ciwsSpot

Description:
    Closed-loop spotting for a CIWS gun, the way a real Phalanx corrects its
    own aim: every round is measured as it passes the PREDICTED target -- the
    track the aim was solved against when the round was fired (aegism_
    intercept_fnc_interceptorPFH) -- and what each round says the gun NEEDED
    is folded into a correction the gun's aim carries (aegism_intercept_fnc_
    aimWeapon).

    Measured against the prediction, a miss is the gun's own error only:
    turret lag, the flight-time estimate, drop, zeroing. The target's
    evasion -- where it went that the prediction didn't foresee -- is kept
    out of it (it's reported separately, as how far the target strayed from
    its predicted track). Measured against the real target, a jinking
    helicopter's escape looked like a gun error and was fed back into the
    aim.

    The miss is split square to the gun's line of sight:
        ahead - along the predicted target's crossing motion (+ ahead of it,
            - behind). A lead error of dt seconds misses by crossing speed x
            dt, so the round's needed lead correction is (its correction at
            firing) - ahead / crossing speed. Only measurable when the target
            crossed further than its own size during the round's flight (one
            coming straight down the barrel needs no lead).
        high - square to the line of sight, upward (+ high). Needed elevation
            correction = (its correction at firing) - high / range.

    Estimate: a weighted mean of every round's needed correction since the
    gun last changed ammunition, each round weighted by how precisely it
    measures it. A round's own scatter is the gun's dispersion (an angle),
    so a lead sample's uncertainty grows with range / crossing speed (weight
    (crossing speed / range)^2), and "high" only exists in proportion to
    how far the line of sight is from vertical (weight cos^2 of its
    elevation). It used to be recomputed from each burst alone: a few
    rounds, often close in where a metre of miss is many milliradians,
    swung it from +1.4 to -12.3 mrad and back between bursts.

    State per gun turret:
        "AEGISM_ciwsEstimate_<turretPath>" [round class, lead weight,
            weighted lead s, elevation weight, weighted elevation rad]
        "AEGISM_ciwsCorrection_<turretPath>" [lead s, elevation rad]
        "AEGISM_ciwsSpotStats_<turretPath>" burstId -> [rounds, sum ahead m,
            sum high m, sum target deviation m, deviation samples], for
            aegism_intercept_fnc_ciwsBurst's SPOTTING line

Parameters:
    _spot - [system, turretPath, burstId, correction at firing [lead s,
        elevation rad], predicted track, round class] <ARRAY>
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

params ["_spot", "_miss", "_ghostPos", "_ghostVelocity", "_flightTime", "_targetRadius", "_deviation"];
_spot params ["_system", "_turretPath", "_burstId", "_correctionAtFire", "", "_roundClass"];
_correctionAtFire params ["_leadAtFire", "_elevationAtFire"];

if (isNull _system) exitWith {};

private _gunPos = eyePos _system;
private _range = _gunPos distance _ghostPos;
if (_range <= 0) exitWith {};

private _los = _gunPos vectorFromTo _ghostPos;
private _crossVelocity = _ghostVelocity vectorDiff (_los vectorMultiply (_ghostVelocity vectorDotProduct _los));
private _crossSpeed = vectorMagnitude _crossVelocity;
private _ahead = if (_crossSpeed > 0) then { _miss vectorDotProduct (_crossVelocity vectorMultiply (1 / _crossSpeed)) } else { 0 };
private _upSquare = [0, 0, 1] vectorDiff (_los vectorMultiply (_los select 2));
private _cosElevation = vectorMagnitude _upSquare;
private _high = if (_cosElevation > 0) then { _miss vectorDotProduct (_upSquare vectorMultiply (1 / _cosElevation)) } else { 0 };

// --- This burst's stats (SPOTTING line) ---------------------------------------
private _statsKey = format ["AEGISM_ciwsSpotStats_%1", _turretPath];
private _allStats = _system getVariable _statsKey;
if (isNil "_allStats") then { _allStats = createHashMap; _system setVariable [_statsKey, _allStats, false]; };
(_allStats getOrDefault [_burstId, [0, 0, 0, 0, 0]]) params ["_rounds", "_sumAhead", "_sumHigh", "_sumDeviation", "_deviations"];
if (_deviation >= 0) then { _sumDeviation = _sumDeviation + _deviation; _deviations = _deviations + 1; };
_allStats set [_burstId, [_rounds + 1, _sumAhead + _ahead, _sumHigh + _high, _sumDeviation, _deviations]];
{ if (_x < _burstId - AEGISM_SPOT_KEEP_BURSTS) then { _allStats deleteAt _x; }; } forEach (keys _allStats);

// --- The gun's correction: weighted mean over every round since the last ammo change.
private _estimateKey = format ["AEGISM_ciwsEstimate_%1", _turretPath];
private _estimate = _system getVariable [_estimateKey, []];
if ((_estimate param [0, ""]) != _roundClass) then { _estimate = [_roundClass, 0, 0, 0, 0]; };
_estimate params ["", "_leadWeight", "_weightedLead", "_elevationWeight", "_weightedElevation"];

if (_crossSpeed * _flightTime > _targetRadius) then {
    private _weight = (_crossSpeed / _range) ^ 2;
    _leadWeight = _leadWeight + _weight;
    _weightedLead = _weightedLead + _weight * (_leadAtFire - _ahead / _crossSpeed);
};
if (_cosElevation > 0) then {
    private _weight = _cosElevation ^ 2;
    _elevationWeight = _elevationWeight + _weight;
    _weightedElevation = _weightedElevation + _weight * (_elevationAtFire - _high / _range);
};
_system setVariable [_estimateKey, [_roundClass, _leadWeight, _weightedLead, _elevationWeight, _weightedElevation], false];

_system setVariable [format ["AEGISM_ciwsCorrection_%1", _turretPath], [
    if (_leadWeight > 0) then { _weightedLead / _leadWeight } else { 0 },
    if (_elevationWeight > 0) then { _weightedElevation / _elevationWeight } else { 0 }
], false];
