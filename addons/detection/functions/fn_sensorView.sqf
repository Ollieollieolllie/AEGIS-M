/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_sensorView

Description:
    What one vehicle's sensors can see of a munition right now: worked out
    once per sensor read (aegism_detect_fnc_confidenceLoop), then every
    tracked munition is judged against it (aegism_detect_fnc_munitionSeen).

    The game's sensors can't target a projectile at all (CfgAmmo has no
    radar/IR/visual target properties), so AEGIS-M judges munitions itself,
    by the rules the engine's sensors work to and from the same config (BI's
    Sensors config reference; aegism_system_fnc_discoverCapabilities reads
    it). Each munition used to carry an invisible vehicle for the game's
    sensors to find instead, which they weren't built for: radars reported
    nothing for ~2.5 s after coming on, the vehicle didn't always stay with
    its munition, showed no speed while attached (so low munitions vanished
    in ground clutter), and could be shot. For each sensor that finds
    things in the air -- radar, IR, visual:
        on - a radar only while the vehicle's radar emits (isVehicleRadarOn:
            Radar Emission, aegism_system_fnc_emconUpdate); none through fog
            thicker than its maxFogSeeThrough
        where it looks - along the hull, or where its turret points
            (aegism_detect_fnc_sensorAxis), tilted down by its aimDown; its
            horizontal and vertical arcs either side of that
        how far - against the sky its AirTarget range, against the ground
            its GroundTarget range: the smallest of maxRange, the object
            view distance x objectDistanceLimitCoef and the view distance x
            viewDistanceLimitCoef (where those are set), never less than
            minRange; scaled by its nightRangeCoef toward night (sunOrMoon:
            1 by day, 0 at night) and by the munition's signature
            (AEGISM_MUNITION_SIGNATURE, sensing.hpp)
        ground clutter and limits - passed on for each munition: its
            groundNoiseDistanceCoef / maxGroundNoiseDistance and
            min/maxSpeedThreshold, min/maxTrackableSpeed and min/max
            TrackableATL
    On a dedicated server the view distances are the server's.

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
