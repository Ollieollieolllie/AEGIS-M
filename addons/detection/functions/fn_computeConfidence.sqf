/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_computeConfidence

Description:
    Computes a 0-1 passive detection confidence score for a platform
    contact (aircraft/helicopter/drone) against a System's sensor, per the
    AEGIS-M architecture plan (section 2) hybrid detection model: a custom
    LOS/distance/optics estimate blended with the crew unit's native
    knowsAbout value, plus an additional radar-emission term when the
    System's Radar role is actively emitting.

    This is a pure scoring function -- it does not read or write any
    contact pool; callers (the confidence loop) decide what to do with the
    returned score.

Parameters:
    _system - the System vehicle doing the sensing <OBJECT>
    _target - the candidate platform <OBJECT>
    _crewUnit - the unit whose native knowsAbout value contributes to the
        score (objNull if unmanned -- that term is skipped) <OBJECT>
    _radarActive - whether the System's radar is currently emitting <BOOLEAN>

Returns:
    Detection confidence, 0-1 <NUMBER>

Examples:
    [_radarTruck, _incomingJet, _gunner, false] call aegism_detect_fnc_computeConfidence;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_system", "_target", "_crewUnit", "_radarActive"];

if (isNull _target || {!alive _target}) exitWith { 0 };

private _systemData = _system getVariable ["AEGISM_system", createHashMap];
private _opticalRange = [_systemData getOrDefault ["passiveOpticalRange", 2000]] call aegism_fnc_scaledRange;
private _radarRange = [_systemData getOrDefault ["radarDetectionRange", 4000]] call aegism_fnc_scaledRange;

private _eyePos = AGLToASL (eyePos _system);
private _targetPos = getPosASL _target;
private _dist = _eyePos distance _targetPos;

// LOS component: 0 if blocked, 1 if fully clear
private _losClear = (lineIntersectsSurfaces [_eyePos, _targetPos, _system, _target, true, 1]) isEqualTo [];
private _losComponent = parseNumber _losClear;

// Distance/size component: linear falloff vs. optical range, weighted by
// an approximate target size factor (bounding box diagonal) since larger
// aircraft are spotted farther away than small drones at the same range.
private _boundingBox = boundingBoxReal _target;
_boundingBox params ["_bbMin", "_bbMax"];
private _sizeFactor = (vectorMagnitude (_bbMax vectorDiff _bbMin)) / 15; // ~15m as a "typical" reference size
private _effectiveOpticalRange = _opticalRange * (0.5 + (_sizeFactor min 1.5));
private _distanceComponent = 1 - ((_dist / _effectiveOpticalRange) min 1);

// Native perception contribution
private _knowsAboutComponent = 0;
if (!isNull _crewUnit) then {
    _knowsAboutComponent = ((_crewUnit knowsAbout _target) / 4) min 1;
};

// Passive score: LOS gates the whole thing (no LOS, no passive detection),
// then blend distance/size with native perception.
private _passiveScore = _losComponent * ((_distanceComponent * 0.7) + (_knowsAboutComponent * 0.3));

// Radar contribution: only relevant within radar range while emitting,
// converges much faster than passive (radar "sees" reliably once in range).
private _radarScore = 0;
if (_radarActive && {_dist <= _radarRange}) then {
    _radarScore = 1 - ((_dist / _radarRange) min 1) * 0.3; // stays high (0.7-1.0) across the whole radar envelope
};

(_passiveScore max _radarScore) min 1
