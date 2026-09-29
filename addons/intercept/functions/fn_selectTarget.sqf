/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_selectTarget

Description:
    Target selection for one turret of a STANDALONE System (no Site synced
    -- a networked System gets its assignment from aegism_intercept_fnc_
    assignEngagements instead). Filters the candidates to those on the
    doctrine allowlist that at least one of the turret's ready weapons can
    engage (aegism_intercept_fnc_canEngage), picks the best per the
    doctrine's targetPriority rule, and returns the weapon for it.

    A gun keeps its current target while it can still engage it, its own
    aim has a solution, and that aim is inside its open-fire range (aegism_
    intercept_fnc_openFireRange) -- as a Site's claim does -- instead of
    re-picking every tick: under Soonest Impact the shells of one salvo
    trade places constantly, and a standalone Praetorian swung 40-127
    degrees between six of them in 12s without firing. That check comes
    FIRST and alone: only if the current target has to go are the other
    candidates evaluated (each one is a full intercept solve). Launchers
    always re-pick (the engagement loop reuses a launcher's pick for a
    moment and excludes targets its missiles are already flying at).

    A gun prefers targets it could open fire on now (intercept inside its
    open-fire range) over any it could only track, then the priority rule
    decides -- so it doesn't sit holding fire on a far shell while a nearer
    one passes through its reach.

Parameters:
    _weaponPos - ASL position ranges are measured from <ARRAY>
    _candidates - [object, class] pairs from the System's own pool <ARRAY>
    _engagementSettings - resolved doctrine <HASHMAP>
    _weapons - this turret's weaponInfos in this role that have ammo <ARRAY>
    _role - "launcher" or "ciws" <STRING>
    _system - the System vehicle <OBJECT>
    _current - optional, the target it's engaging now <OBJECT>
    _turretPath - optional, the turret (its aim record) <ARRAY>

Returns:
    [target <OBJECT>, weaponInfo <ARRAY>], or [objNull, []] if nothing is
    engageable

Examples:
    [_weaponPos, _candidates, _settings, _readyWeapons, "ciws", _cheetah, _shell, [0]] call aegism_intercept_fnc_selectTarget;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\perf.hpp"

params ["_weaponPos", "_candidates", "_engagementSettings", "_weapons", "_role", "_system", ["_current", objNull], ["_turretPath", []]];

private _allowlist = _engagementSettings getOrDefault ["targetClassAllowlist", []];
private _priority = _engagementSettings getOrDefault ["targetPriority", "soonestImpact"];

// --- A gun on a target keeps it while it can (see header) ---------------------
private _kept = [];
if (_role == "ciws" && {!isNull _current} && {alive _current} && {(_candidates findIf { (_x select 0) == _current }) != -1}) then {
    // ...unless the gun's own latest aim at it found no solution, or has it
    // beyond its open-fire range.
    private _aim = if (_turretPath isEqualTo []) then { [] } else { ([_system, _turretPath] call aegism_intercept_fnc_turretState) getOrDefault ["aim_ciws", []] };
    private _unsolved = (_aim param [3, objNull]) == _current && {!(_aim param [4, true]) || {!(_aim param [7, true])}};
    if (!_unsolved && {([_current] call aegism_detect_fnc_classifyTarget) in _allowlist}) then {
        private _index = _weapons findIf { ([_system, _role, _x, _current, _engagementSettings] call aegism_intercept_fnc_canEngage) select 0 };
        if (_index != -1) then { _kept = [_current, _weapons select _index]; };
    };
};
if (_kept isNotEqualTo []) exitWith { _kept };

PERF_INC(PERF_SELECT_FULL);

// [object, class, weaponInfo, in open-fire range] for every candidate some
// ready weapon reaches.
private _engageable = [];
{
    _x params ["_object", "_class"];
    if (!isNull _object && {alive _object} && {_class in _allowlist}) then {
        private _inRange = false;
        private _idx = _weapons findIf {
            private _weaponInfo = _x;
            private _engage = [_system, _role, _weaponInfo, _object, _engagementSettings] call aegism_intercept_fnc_canEngage;
            if (_engage select 0) then {
                _inRange = _role != "ciws" || {
                    // As the gun's own aim judges it (aegism_intercept_fnc_aimWeapon).
                    private _hitRadius = [_object] call aegism_intercept_fnc_targetHitRadius;
                    if (_class in ["missile", "rocket", "bomb", "artilleryShell"]) then {
                        _hitRadius = _hitRadius max (([_weaponInfo select 1, _weaponInfo select 2] call aegism_intercept_fnc_weaponKinematics) select 11);
                    };
                    ([_system, _weaponInfo select 0, _weaponInfo, _class, _hitRadius, _engagementSettings] call aegism_intercept_fnc_openFireRange) params ["_openFireRange", "_minRange"];
                    private _interceptDistance = _engage param [3, 0];
                    _interceptDistance <= _openFireRange && {_interceptDistance >= _minRange}
                };
            };
            _engage select 0
        };
        if (_idx != -1) then {
            _engageable pushBack [_object, _class, _weapons select _idx, _inRange];
        };
    };
} forEach _candidates;

if (_engageable isEqualTo []) exitWith { [objNull, []] };

// Targets it could open fire on now come first.
private _inRangeOnly = _engageable select { _x select 3 };
if (_inRangeOnly isNotEqualTo []) then { _engageable = _inRangeOnly; };

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
