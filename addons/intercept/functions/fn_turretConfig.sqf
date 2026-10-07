/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_turretConfig

Description:
    One turret's config, resolved once per vehicle type + turret path and
    cached ("AEGISM_cacheTurrets").
    Full notes: docs/functions/intercept.md

Parameters:
    _vehicle - the vehicle <OBJECT>
    _turretPath - turret path <ARRAY>

Returns:
    [muzzleGun, muzzleLauncher, camera, minElev, maxElev, barrelPairs,
     traverseRate, elevateRate, minTurn, maxTurn, mount] <ARRAY>

Examples:
    [_praetorian, [0]] call aegism_intercept_fnc_turretConfig;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\rpt.hpp"

params ["_vehicle", "_turretPath"];

private _cache = missionNamespace getVariable "AEGISM_cacheTurrets";
if (isNil "_cache") then {
    _cache = createHashMap;
    missionNamespace setVariable ["AEGISM_cacheTurrets", _cache];
};
private _key = [typeOf _vehicle, _turretPath];
private _cached = _cache get _key;
if (!isNil "_cached") exitWith { _cached };

private _turretCfg = [_vehicle, _turretPath] call CBA_fnc_getTurret;

// A memory point exists if the model has it (selectionPosition returns
// [0,0,0] for a missing one).
private _fnExists = { _this != "" && {(_vehicle selectionPosition [_this, "Memory"]) isNotEqualTo [0, 0, 0]} };
private _fnFirst = {
    private _found = "";
    {
        private _name = getText (_turretCfg >> _x);
        if (_found == "" && {_name call _fnExists}) then { _found = _name; };
    } forEach _this;
    _found
};

private _barrelPairs = [];
{
    _x params ["_begKey", "_endKey"];
    private _beg = getText (_turretCfg >> _begKey);
    private _end = getText (_turretCfg >> _endKey);
    if (_beg != "" && {_end != ""}) then { _barrelPairs pushBack [_beg, _end]; };
} forEach [["gunBeg", "gunEnd"], ["missileBeg", "missileEnd"]];

private _minElevation = getNumber (_turretCfg >> "minElev");
private _maxElevation = getNumber (_turretCfg >> "maxElev");
private _minTurn = getNumber (_turretCfg >> "minTurn");
private _maxTurn = getNumber (_turretCfg >> "maxTurn");
private _traverseRate = 45 * getNumber (_turretCfg >> "maxHorizontalRotSpeed");
private _elevateRate = 45 * getNumber (_turretCfg >> "maxVerticalRotSpeed");
private _traverses = _maxTurn > _minTurn && {_traverseRate > 0};
private _elevates = _maxElevation > _minElevation && {_elevateRate > 0};
private _mount = switch (true) do {
    case (_traverses && _elevates): { "trainable" };
    case (_elevates): { "elevating" };
    case (_traverses): { "traversing" };
    default { "fixed" };
};

_cached = [
    ["gunBeg", "missileBeg"] call _fnFirst,
    ["missileBeg", "gunBeg"] call _fnFirst,
    ([["memoryPointGunnerOptics"], ["uavCameraGunnerPos", "memoryPointGunnerOptics"]] select (unitIsUAV _vehicle)) call _fnFirst,
    _minElevation,
    _maxElevation,
    _barrelPairs,
    _traverseRate,
    _elevateRate,
    _minTurn,
    _maxTurn,
    _mount
];
_cache set [_key, _cached];
if (AEGISM_RPT_VERBOSE) then {
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " TURRET-RATE: %1 turret %2 -- %3 mount: traverses %4 deg/s, elevates %5 deg/s (maxHorizontalRotSpeed %6, maxVerticalRotSpeed %7 x 45 deg/s), elevation %8 to %9 deg, traverse %10 to %11 deg (left positive).",
        typeOf _vehicle, _turretPath, _mount, round _traverseRate, round _elevateRate,
        getNumber (_turretCfg >> "maxHorizontalRotSpeed"), getNumber (_turretCfg >> "maxVerticalRotSpeed"), _minElevation, _maxElevation, _minTurn, _maxTurn];
};
_cached
