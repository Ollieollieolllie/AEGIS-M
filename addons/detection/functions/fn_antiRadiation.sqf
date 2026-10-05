/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_antiRadiation

Description:
    Whether an ammo type is an anti-radiation missile, and its seeker: one
    whose own sensors (CfgAmmo "Components >> SensorsManagerComponent >>
    Components") include a passive radar -- componentType
    PassiveRadarSensorComponent, which homes on a radar while it emits. The
    vanilla HARM and Kh-58 (ammo_Missile_AntiRadiationBase) carry one: 60
    degrees wide, 16 km. Cached per ammo type ("AEGISM_cacheAntiRadiation").

Parameters:
    _ammo - CfgAmmo class <STRING>

Returns:
    [seeker horizontal arc degrees, seeker reach metres] -- the largest
    maxRange of its target-type classes -- or [] if it isn't one <ARRAY>

Examples:
    ["ammo_Missile_HARM"] call aegism_detect_fnc_antiRadiation;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_ammo"];

private _cache = missionNamespace getVariable "AEGISM_cacheAntiRadiation";
if (isNil "_cache") then {
    _cache = createHashMap;
    missionNamespace setVariable ["AEGISM_cacheAntiRadiation", _cache];
};
private _cached = _cache get _ammo;
if (!isNil "_cached") exitWith { _cached };

private _seeker = [];
{
    if ((toLower getText (_x >> "componentType")) == "passiveradarsensorcomponent") exitWith {
        private _reach = 0;
        { _reach = _reach max (getNumber (_x >> "maxRange")); } forEach (configProperties [_x, "isClass _x", true]);
        _seeker = [[360, getNumber (_x >> "angleRangeHorizontal")] select (isNumber (_x >> "angleRangeHorizontal")), _reach];
    };
} forEach (configProperties [configFile >> "CfgAmmo" >> _ammo >> "Components" >> "SensorsManagerComponent" >> "Components", "isClass _x", true]);

_cache set [_ammo, _seeker];
_seeker
