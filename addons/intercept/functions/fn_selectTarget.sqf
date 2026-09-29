/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_selectTarget

Description:
    Target selection for a STANDALONE System (no Site synced -- a networked
    System gets its assignment from aegism_intercept_fnc_assignEngagements
    instead). Filters the System's own pooled contacts to those on the
    doctrine allowlist that at least one of its ready weapons can engage
    (aegism_intercept_fnc_canEngage), picks the best per the doctrine's
    targetPriority rule, and returns the nearest-envelope weapon for it.

    Previously the chosen target was matched against the doctrine envelope
    only and fired at with whichever weapon happened to be first, even if
    that weapon couldn't reach it.

    A gun keeps its current target while it can still engage it and its own
    aim has a solution -- as a Site's claim does -- instead of re-picking
    every tick: under Soonest
    Impact the shells of one salvo trade places constantly, and a standalone
    Praetorian swung 40-127 degrees between six of them in 12s without
    firing. (Launchers still re-pick: they're free for the next target as
    soon as their missiles are away.)

Parameters:
    _weaponPos - ASL position ranges are measured from <ARRAY>
    _candidates - [object, class] pairs from the System's own pool <ARRAY>
    _engagementSettings - resolved doctrine <HASHMAP>
    _weapons - this role's weaponInfos that currently have ammo <ARRAY>
    _role - "launcher" or "ciws" <STRING>
    _system - the System vehicle <OBJECT>
    _current - optional, the target it's engaging now <OBJECT>

Returns:
    [target <OBJECT>, weaponInfo <ARRAY>], or [objNull, []] if nothing is
    engageable

Examples:
    [_weaponPos, _candidates, _settings, _readyWeapons, "ciws", _cheetah] call aegism_intercept_fnc_selectTarget;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_weaponPos", "_candidates", "_engagementSettings", "_weapons", "_role", "_system", ["_current", objNull]];

private _allowlist = _engagementSettings getOrDefault ["targetClassAllowlist", []];
private _priority = _engagementSettings getOrDefault ["targetPriority", "soonestImpact"];

// [object, class, weaponInfo] for every candidate some ready weapon reaches.
private _engageable = [];
{
    _x params ["_object", "_class"];
    if (!isNull _object && {alive _object} && {_class in _allowlist}) then {
        private _idx = _weapons findIf { ([_system, _role, _x, _object, _engagementSettings] call aegism_intercept_fnc_canEngage) select 0 };
        if (_idx != -1) then {
            _engageable pushBack [_object, _class, _weapons select _idx];
        };
    };
} forEach _candidates;

if (_engageable isEqualTo []) exitWith { [objNull, []] };

// ...unless the gun's own latest aim at it found no solution.
private _aimRecord = _system getVariable ["AEGISM_aim_ciws", []];
private _currentUnsolved = (_aimRecord param [3, objNull]) == _current && {!(_aimRecord param [4, true])};
if (_role == "ciws" && {!isNull _current} && {!_currentUnsolved}) then {
    private _currentIndex = _engageable findIf { (_x select 0) == _current };
    if (_currentIndex != -1) exitWith { _engageable = [_engageable select _currentIndex]; };
};

// Higher score = more preferred. SQF's selectMax only works on numbers, so
// scores are a parallel array.
private _scores = switch (_priority) do {
    case "fastestClosing": {
        _engageable apply {
            _x params ["_object"];
            private _los = (getPosASL _object) vectorFromTo _weaponPos;
            (velocity _object) vectorDotProduct _los
        };
    };
    case "highestValue": {
        _engageable apply {
            _x params ["_object", "_class"];
            ([_class] call aegism_intercept_fnc_threatValue) * 1e6 - (_weaponPos distance (getPosASL _object))
        };
    };
    case "nearest": {
        _engageable apply { -(_weaponPos distance (getPosASL (_x select 0))) };
    };
    default {
        // Soonest Impact: the one that reaches this vehicle first.
        _engageable apply {
            _x params ["_object", "_class"];
            -([_object, _class, [getPosASL _system]] call aegism_intercept_fnc_timeToImpact)
        };
    };
};

private _best = _engageable select (_scores find (selectMax _scores));
[_best select 0, _best select 2]
