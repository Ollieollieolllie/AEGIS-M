/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_sensorAxis

Description:
    World-space direction one of a vehicle's sensors is looking along right
    now (its arcs are measured from it). A hull-fixed sensor looks along the
    hull. A turret-mounted one (its animDirection is a turret's gun or body,
    aegism_system_fnc_discoverCapabilities) looks where that turret points:
    the turret's barrel direction (aegism_intercept_fnc_barrelDirection --
    weaponDirection of the turret's first weapon, then its barrel memory
    points; the vanilla radar's turret carries "FakeWeapon" for this). So a
    radar AEGIS-M turns (aegism_system_fnc_radarSchedule) sees where it has
    actually got to, not where it was told to go.

    If the turret's direction can't be read, the hull's is used, and that's
    logged once per vehicle type and turret (SENSOR-AIM).

Parameters:
    _vehicle - the vehicle <OBJECT>
    _aim - the sensor's turret path, or [] for the hull <ARRAY>

Returns:
    Unit direction vector, world space <ARRAY>

Examples:
    [_spartan, [0]] call aegism_detect_fnc_sensorAxis;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_vehicle", "_aim"];

if (_aim isEqualTo []) exitWith { vectorDir _vehicle };

// A turret with a weapon: barrelDirection tries its weaponDirection, then
// its barrel memory points. One without: the memory points alone
// (weaponDirection of "" names no weapon).
private _weapon = (_vehicle weaponsTurret _aim) param [0, ""];
private _direction = [0, 0, 0];
if (_weapon != "") then {
    _direction = [_vehicle, _aim, _weapon] call aegism_intercept_fnc_barrelDirection;
} else {
    {
        _x params ["_beg", "_end"];
        private _axis = (_vehicle selectionPosition [_beg, "Memory"]) vectorDiff (_vehicle selectionPosition [_end, "Memory"]);
        if (_axis isNotEqualTo [0, 0, 0]) exitWith { _direction = vectorNormalized (_vehicle vectorModelToWorldVisual _axis); };
    } forEach (([_vehicle, _aim] call aegism_intercept_fnc_turretConfig) select 5);
};
if (_direction isNotEqualTo [0, 0, 0]) exitWith { _direction };

private _logged = missionNamespace getVariable "AEGISM_sensorAimLogged";
if (isNil "_logged") then {
    _logged = createHashMap;
    missionNamespace setVariable ["AEGISM_sensorAimLogged", _logged];
};
private _key = [typeOf _vehicle, _aim];
if !(_key in _logged) then {
    _logged set [_key, true];
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " SENSOR-AIM: can't read where %1's turret %2 points (no weapon direction, no barrel memory points) -- its sensors' arcs are measured from the hull instead.", typeOf _vehicle, _aim];
};
vectorDir _vehicle
