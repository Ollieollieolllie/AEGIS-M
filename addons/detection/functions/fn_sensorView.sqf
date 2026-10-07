/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_sensorView

Description:
    What one vehicle's sensors can see of a munition right now: worked out
    once per sensor read (aegism_detect_fnc_confidenceLoop), then every
    tracked munition is judged against it (aegism_detect_fnc_munitionSeen).
    Full notes: docs/functions/detection.md

Parameters:
    _vehicle - the sensor vehicle <OBJECT>
    _system - its capabilities (aegism_system_fnc_discoverCapabilities) <HASHMAP>

Returns:
    [vehicle, its eye position ASL, sensors, the farthest any of them
    reaches m], each sensor [kind ("activeradar" / "ir" / "visual"), bearing
    it looks along, its elevation, half its horizontal arc (-1 all round),
    half its vertical arc (-1 all round), range against the sky, range
    against the ground, noiseCoef, noiseMax, speedMin, speedMax, [min, max]
    trackable speed, [min, max] trackable height] <ARRAY>

Examples:
    private _view = [_radarTruck, _radarTruck getVariable "AEGISM_system"] call aegism_detect_fnc_sensorView;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\sensing.hpp"

params ["_vehicle", "_system"];

private _radarOn = isVehicleRadarOn _vehicle;
private _fog = fog;
private _viewDistance = viewDistance;
private _objectDistance = getObjectViewDistance select 0;
private _light = sunOrMoon;

// One of a sensor's ranges ([minRange, maxRange, objectDistanceLimitCoef,
// viewDistanceLimitCoef]), as it stands now, against a munition.
private _fnRange = {
    params ["_ranges", "_night"];
    _ranges params ["_min", "_max", "_objectCoef", "_viewCoef"];
    private _range = _max;
    if (_objectCoef >= 0) then { _range = _range min (_objectDistance * _objectCoef); };
    if (_viewCoef >= 0) then { _range = _range min (_viewDistance * _viewCoef); };
    if (_min > 0) then { _range = _range max _min; };
    (_range max 0) * (_night + (1 - _night) * _light) * AEGISM_MUNITION_SIGNATURE
};

private _sensors = [];
private _maxReach = 0;
{
    _x params ["_type", "_range", "_arc", "_aim", "", "_maxFog", "", ["_verticalArc", 360], ["_aimDown", 0], "", ["_detail", createHashMap]];
    if (_type in ["radar", "ir", "visual"] && {_type != "radar" || {_radarOn}} && {_maxFog < 0 || {_fog <= _maxFog}}) then {
        private _axis = [_vehicle, _aim] call aegism_detect_fnc_sensorAxis;
        private _night = _detail getOrDefault ["night", 1];
        private _air = [_detail getOrDefault ["air", [-1, _range, -1, -1]], _night] call _fnRange;
        private _ground = [_detail getOrDefault ["ground", [-1, _range, -1, -1]], _night] call _fnRange;
        _maxReach = _maxReach max _air max _ground;
        _sensors pushBack [
            ["activeradar", _type] select (_type != "radar"),
            (_axis select 0) atan2 (_axis select 1),
            (asin (((_axis select 2) max -1) min 1)) - _aimDown,
            [_arc / 2, -1] select (_arc >= 360),
            [_verticalArc / 2, -1] select (_verticalArc >= 360),
            _air, _ground,
            _detail getOrDefault ["noiseCoef", -1], _detail getOrDefault ["noiseMax", -1],
            _detail getOrDefault ["speedMin", 0], _detail getOrDefault ["speedMax", 1000],
            _detail getOrDefault ["trackSpeed", [-1e10, 1e10]], _detail getOrDefault ["trackHeight", [-1e10, 1e10]]
        ];
    };
} forEach (_system getOrDefault ["sensors", []]);

[_vehicle, eyePos _vehicle, _sensors, _maxReach]
