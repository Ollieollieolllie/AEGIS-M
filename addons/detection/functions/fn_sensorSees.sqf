/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_sensorSees

Description:
    Whether one of a vehicle's sensors (aegism_system_fnc_
    discoverCapabilities "munitionSensors") covers a munition at a
    position -- everything but line of sight, which the caller traces once
    per vehicle (aegism_detect_fnc_munitionCheck). All from the sensor's own
    config:
        reach - its AirTarget maxRange, capped at the view distance times
            its viewDistanceLimitCoef where that's set (vanilla IR: 1 -- the
            engine applies the same cap to aircraft, and on a dedicated
            server it's the server's view distance)
        arc - its angleRangeHorizontal, either side of where it looks
            (aegism_detect_fnc_sensorAxis: the hull, or its turret)
        fog - not at or beyond its maxFogSeeThrough (vanilla IR 0.995),
            against the current fog
    An IR sensor sees a munition for its whole flight, the same as an
    active radar: a rocket or missile is hot from its motor, a shell from
    firing, and all of them from the air they push through -- against the
    cold sky. Vanilla IR has no ground clutter (it inherits
    groundNoiseDistanceCoef -1 from SensorTemplatePassiveRadar; only the
    active radar template sets one), so one seen against the ground isn't
    treated differently. Vertical coverage isn't checked, as before.

Parameters:
    _vehicle - the sensor's vehicle <OBJECT>
    _sensor - one sensor entry [type, range, arc, aim, viewDistanceCoef,
        maxFog, component] <ARRAY>
    _position - the munition's position, ASL <ARRAY>

Returns:
    The sensor covers it <BOOLEAN>

Examples:
    [_spartan, _irSensor, getPosASL _rocket] call aegism_detect_fnc_sensorSees;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_vehicle", "_sensor", "_position"];
_sensor params ["", "_range", "_arc", "_aim", "_viewDistanceCoef", "_maxFog"];

if (_maxFog > 0 && {fog >= _maxFog}) exitWith { false };

private _reach = _range;
if (_viewDistanceCoef > 0) then { _reach = _reach min (viewDistance * _viewDistanceCoef); };
if ((_vehicle distance2D _position) > _reach) exitWith { false };

if (_arc >= 360) exitWith { true };
private _axis = [_vehicle, _aim] call aegism_detect_fnc_sensorAxis;
private _toTarget = _position vectorDiff (getPosASL _vehicle);
// Bearing difference folded into -180..180 (the difference is within
// -360..360, so +540 keeps the modulo's operand positive).
private _offAxis = abs ((((((_toTarget select 0) atan2 (_toTarget select 1)) - ((_axis select 0) atan2 (_axis select 1))) + 540) % 360) - 180);
_offAxis <= _arc / 2
