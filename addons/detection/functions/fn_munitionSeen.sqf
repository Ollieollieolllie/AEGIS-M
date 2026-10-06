/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_munitionSeen

Description:
    Which of a vehicle's sensors see one tracked munition right now, against
    the vehicle's sensor view for this read (aegism_detect_fnc_sensorView).
    A sensor sees it if all of these hold, cheapest first:
        - it's within the sensor's reach, and its speed and height above the
          terrain are within what the sensor can track at all;
        - it's inside the sensor's horizontal and vertical arcs, measured
          from where the sensor looks;
        - against the sky (seen from below: it's above the sensor) it's
          within the sensor's AirTarget range. Seen from above, the line
          from the sensor through it is carried on to the ground or the sea
          behind it: with ground there it has to be within the GroundTarget
          range, and clear of ground clutter -- farther from that ground
          than groundNoiseDistanceCoef x the sensor-to-ground distance (at
          most maxGroundNoiseDistance), unless it's fast: at or above
          maxSpeedThreshold it always shows, and between the two thresholds
          the clutter shrinks in proportion. (Munitions fly at hundreds of
          m/s; the vanilla radar's thresholds are 21 and 28 m/s.) Ground
          behind a munition that's above the sensor (a mountainside) isn't
          looked for;
        - the vehicle has a line of sight to it: no terrain between them, and
          nothing else in the first AEGISM_LOS_OBJECT_REACH m (the line
          command's own limit). One ray per vehicle, not per sensor, and a
          clear one isn't traced again for AEGISM_LOS_REUSE s (sensing.hpp).
    A munition is hot for its whole flight (its motor, the air it pushes
    through), so IR sees it as radar does.

Parameters:
    _view - the vehicle's sensor view (aegism_detect_fnc_sensorView) <ARRAY>
    _entry - the tracked munition's entry (aegism_detect_fnc_trackMunition) <ARRAY>

Returns:
    The sensor kinds that see it ("activeradar", "ir", "visual"); [] if none <ARRAY>

Examples:
    private _seenBy = [_view, _entry] call aegism_detect_fnc_munitionSeen;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\sensing.hpp"
#include "..\..\main\perf.hpp"

params ["_view", "_entry"];
_view params ["_vehicle", "_eye", "_sensors", "_maxReach"];
_entry params ["_projectile", "", "", "", "", "", "_losSeen"];

if (_sensors isEqualTo [] || {isNull _projectile}) exitWith { [] };

private _pos = getPosASL _projectile;
private _rel = _pos vectorDiff _eye;
private _distance = vectorMagnitude _rel;
if (_distance > _maxReach || {_distance <= 0}) exitWith { [] };

private _speed = vectorMagnitude velocity _projectile;
private _height = (ASLToATL _pos) select 2;
private _bearing = (_rel select 0) atan2 (_rel select 1);
private _elevation = asin ((((_rel select 2) / _distance) max -1) min 1);

// The ground (or sea) behind it along the line from the sensor, for one seen
// from above: its distance from the sensor, -1 if there's none within the
// vehicle's reach. Worked out once, and only if a sensor gets that far.
private _behind = -2;
private _fnBehind = {
    if (_behind > -2) exitWith { _behind };
    _behind = -1;
    private _dir = _rel vectorMultiply (1 / _distance);
    private _hit = terrainIntersectAtASL [_pos, _pos vectorAdd (_dir vectorMultiply _maxReach)];
    if (_hit isNotEqualTo [0, 0, 0]) then { _behind = _distance + (_pos distance _hit); };
    // The sea isn't terrain: where the line comes down to it.
    if ((_dir select 2) < 0 && {(_pos select 2) > 0}) then {
        private _toSea = _distance + (_pos select 2) / (-(_dir select 2));
        if (_toSea <= _distance + _maxReach && {_behind < 0 || {_toSea < _behind}}) then { _behind = _toSea; };
    };
    _behind
};

private _seenBy = [];
{
    _x params ["_kind", "_axisBearing", "_axisElevation", "_halfArc", "_halfVertical", "_rangeAir", "_rangeGround",
        "_noiseCoef", "_noiseMax", "_speedMin", "_speedMax", "_trackSpeed", "_trackHeight"];
    if (!(_kind in _seenBy)
        && {_distance <= (_rangeAir max _rangeGround)}
        && {_speed >= (_trackSpeed select 0)} && {_speed <= (_trackSpeed select 1)}
        && {_height >= (_trackHeight select 0)} && {_height <= (_trackHeight select 1)}
        && {_halfArc < 0 || {abs ((((_bearing - _axisBearing) + 540) mod 360) - 180) <= _halfArc}}
        && {_halfVertical < 0 || {abs (_elevation - _axisElevation) <= _halfVertical}}) then {
        private _range = _rangeAir;
        private _clear = true;
        if (_elevation < 0) then {
            private _ground = call _fnBehind;
            if (_ground >= 0) then {
                _range = _rangeGround;
                // Ground clutter, unless it's fast enough to show through.
                if (_noiseCoef >= 0 && {_speed < _speedMax}) then {
                    private _noise = _noiseCoef * _ground;
                    if (_noiseMax >= 0) then { _noise = _noise min _noiseMax; };
                    if (_speed > _speedMin) then { _noise = _noise * (_speedMax - _speed) / (_speedMax - _speedMin); };
                    _clear = (_ground - _distance) >= _noise;
                };
            };
        };
        if (_clear && {_distance <= _range}) then { _seenBy pushBack _kind; };
    };
} forEach _sensors;
if (_seenBy isEqualTo []) exitWith { [] };

// Line of sight, the vehicle's own.
private _losKey = netId _vehicle;
if (CBA_missionTime - (_losSeen getOrDefault [_losKey, -1e9]) > AEGISM_LOS_REUSE) then {
    PERF_INC(PERF_LOS_RAYS);
    private _blocked = (terrainIntersectASL [_eye, _pos]) || {
        private _to = if (_distance > AEGISM_LOS_OBJECT_REACH) then { _eye vectorAdd (_rel vectorMultiply (AEGISM_LOS_OBJECT_REACH / _distance)) } else { _pos };
        (lineIntersectsSurfaces [_eye, _to, _vehicle, _projectile, true, 1]) isNotEqualTo []
    };
    if (_blocked) then { _seenBy = []; } else { _losSeen set [_losKey, CBA_missionTime]; };
};
_seenBy
