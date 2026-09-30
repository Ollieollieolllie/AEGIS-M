/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_turretConfig

Description:
    One turret's config, resolved once per vehicle type + turret path and
    cached ("AEGISM_cacheTurrets"). CBA_fnc_getTurret walks the turret tree
    in SQF, and turretPoints/turretCanPoint/barrelDirection each did that on
    every call -- every frame for a CIWS.

        muzzleGun / muzzleLauncher - the memory point rounds/missiles leave
            from: gunBeg then missileBeg for a gun, the reverse for a
            launcher -- the first that exists in the model ("" if neither)
        camera - the aiming camera lockCameraTo points: uavCameraGunnerPos
            (unmanned turret) or memoryPointGunnerOptics ("" if neither)
        minElev / maxElev - elevation limits, degrees
        barrelPairs - [beginning, end] memory point names of the barrel
            (gunBeg/gunEnd, missileBeg/missileEnd) that both exist
        traverseRate / elevateRate - how fast it turns, degrees per second:
            maxHorizontalRotSpeed / maxVerticalRotSpeed, in the config's own
            unit of 45 degrees per second (0 if not set). Logged once per
            vehicle type and turret (TURRET-RATE).
        minTurn / maxTurn - traverse limits, degrees from the vehicle's
            forward, POSITIVE TO THE LEFT: the Ghost Hawk's left door gun
            is minTurn 15, maxTurn 160, initTurn 90, its right one -160,
            -15, -90 (vanilla Heli_Transport_01 config). A span of 360 or
            more turns all the way round.
        mount - what the turret can do at all: "trainable" (traverses and
            elevates), "elevating" (fixed bearing), "traversing" (fixed
            elevation) or "fixed" (neither -- a vertical launch cell, a
            hull-fixed launcher). An axis moves if its limits span more
            than zero and its rate is set. A weapon on the driver's path
            ([-1]) reads the vehicle's own config, which has neither.

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
diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " TURRET-RATE: %1 turret %2 -- %3 mount: traverses %4 deg/s, elevates %5 deg/s (maxHorizontalRotSpeed %6, maxVerticalRotSpeed %7 x 45 deg/s), elevation %8 to %9 deg, traverse %10 to %11 deg (left positive).",
    typeOf _vehicle, _turretPath, _mount, round _traverseRate, round _elevateRate,
    getNumber (_turretCfg >> "maxHorizontalRotSpeed"), getNumber (_turretCfg >> "maxVerticalRotSpeed"), _minElevation, _maxElevation, _minTurn, _maxTurn];
_cached
