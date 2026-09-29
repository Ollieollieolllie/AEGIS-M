/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_openFireRange

Description:
    The farthest a gun opens fire from: the longest distance at which its
    own config hit probability is still at least _chance. Every CfgWeapons
    fire mode authors that curve (the engine's AI uses it): minRangeProbab
    at minRange, midRangeProbab at midRange, maxRangeProbab at maxRange,
    straight lines between, nothing outside. At each distance the best mode
    counts.

    e.g. the Phalanx (weapon_Cannon_Phalanx): "far" is 0.8 at 1500m falling
    to 0.1 at 3000m, so 50% is reached out to 2143m -- where its full 3000m
    reach used to have it throwing a handful of rounds per burst at shells
    it had no chance of hitting.

    Cached per weapon and chance ("AEGISM_cacheOpenFire"), and logged once
    (OPEN-FIRE-RANGE). _chance <= 0, or a weapon whose curve never reaches
    it: no limit (its full config reach).

Parameters:
    _weaponClass - CfgWeapons class <STRING>
    _chance - hit probability, 0-1 <NUMBER>

Returns:
    Metres; 1e10 for no limit <NUMBER>

Examples:
    ["weapon_Cannon_Phalanx", 0.5] call aegism_intercept_fnc_openFireRange;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_weaponClass", "_chance"];

if (_chance <= 0) exitWith { 1e10 };

private _cache = missionNamespace getVariable "AEGISM_cacheOpenFire";
if (isNil "_cache") then {
    _cache = createHashMap;
    missionNamespace setVariable ["AEGISM_cacheOpenFire", _cache];
};
private _key = _weaponClass + "|" + str _chance;
private _cached = _cache get _key;
if (!isNil "_cached") exitWith { _cached };

private _weaponCfg = configFile >> "CfgWeapons" >> _weaponClass;
private _modes = [];
{
    private _modeCfg = if (_x == "this") then { _weaponCfg } else { _weaponCfg >> _x };
    if (isClass _modeCfg) then { _modes pushBack _modeCfg; };
} forEach (getArray (_weaponCfg >> "modes"));
if (_modes isEqualTo []) then { _modes = [_weaponCfg]; };

private _reach = 0;
private _best = -1;
{
    private _modeCfg = _x;
    private _points = [];
    {
        _x params ["_rangeKey", "_probabilityKey"];
        _points pushBack [getNumber (_modeCfg >> _rangeKey), getNumber (_modeCfg >> _probabilityKey)];
    } forEach [["minRange", "minRangeProbab"], ["midRange", "midRangeProbab"], ["maxRange", "maxRangeProbab"]];
    _reach = _reach max ((_points select 2) select 0);

    // The farthest distance on each segment where the line is >= _chance.
    for "_i" from 0 to 1 do {
        (_points select _i) params ["_near", "_nearProbability"];
        (_points select (_i + 1)) params ["_far", "_farProbability"];
        if (_farProbability >= _chance) then {
            _best = _best max _far;
        } else {
            if (_nearProbability >= _chance) then {
                _best = _best max (linearConversion [_nearProbability, _farProbability, _chance, _near, _far, true]);
            };
        };
    };
} forEach _modes;

_cached = [1e10, _best] select (_best > 0);
_cache set [_key, _cached];

diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " OPEN-FIRE-RANGE: %1 opens fire inside %2 -- %3 (full reach %4m).",
    _weaponClass,
    [format ["%1m", round _best], "its full reach"] select (_best <= 0),
    [format ["its own config hit probability (fire modes' min/mid/maxRangeProbab) is at least %1 percent there", round (_chance * 100)],
     format ["its config hit probability never reaches %1 percent, so no limit", round (_chance * 100)]] select (_best <= 0),
    round _reach];

_cached
