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

Parameters:
    _vehicle - the vehicle <OBJECT>
    _turretPath - turret path <ARRAY>

Returns:
    [muzzleGun, muzzleLauncher, camera, minElev, maxElev, barrelPairs] <ARRAY>

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

_cached = [
    ["gunBeg", "missileBeg"] call _fnFirst,
    ["missileBeg", "gunBeg"] call _fnFirst,
    ([["memoryPointGunnerOptics"], ["uavCameraGunnerPos", "memoryPointGunnerOptics"]] select (unitIsUAV _vehicle)) call _fnFirst,
    getNumber (_turretCfg >> "minElev"),
    getNumber (_turretCfg >> "maxElev"),
    _barrelPairs
];
_cache set [_key, _cached];
_cached
