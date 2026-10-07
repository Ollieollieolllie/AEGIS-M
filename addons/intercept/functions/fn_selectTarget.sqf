/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_selectTarget

Description:
    Target selection for one turret of a STANDALONE System (no Site synced
    -- a networked System gets its assignment from
    aegism_intercept_fnc_assignEngagements instead).
    Full notes: docs/functions/intercept.md

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
    [target <OBJECT>, weaponInfo <ARRAY>, cued -- a gun's target not in its
    reach yet, only within its cue time <BOOLEAN>], or [objNull, []] if
    nothing is engageable

Examples:
    [_weaponPos, _candidates, _settings, _readyWeapons, "ciws", _cheetah, _shell, [0]] call aegism_intercept_fnc_selectTarget;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\perf.hpp"

params ["_weaponPos", "_candidates", "_engagementSettings", "_weapons", "_role", "_system", ["_current", objNull], ["_turretPath", []]];

private _allowlist = _engagementSettings getOrDefault ["targetClassAllowlist", []];
private _priority = _engagementSettings getOrDefault ["targetPriority", "soonestImpact"];

// --- A gun on a target keeps it while it can (see notes) ---------------------
private _kept = [];
if (_role == "ciws" && {!isNull _current} && {alive _current} && {(_candidates findIf { (_x select 0) == _current }) != -1}) then {
    // ...unless the gun's own latest aim at it found no solution, or has it
    // beyond its open-fire range.
    private _aim = if (_turretPath isEqualTo []) then { [] } else { ([_system, _turretPath] call aegism_intercept_fnc_turretState) getOrDefault ["aim_ciws", []] };
    private _unsolved = (_aim param [3, objNull]) == _current && {!(_aim param [4, true]) || {!(_aim param [7, true])}};
    if (!_unsolved && {([_current] call aegism_detect_fnc_classifyTarget) in _allowlist}) then {
        private _index = _weapons findIf { ([_system, _role, _x, _current, _engagementSettings] call aegism_intercept_fnc_canEngage) select 0 };
        if (_index != -1) then { _kept = [_current, _weapons select _index, false]; };
    };
};
if (_kept isNotEqualTo []) exitWith { _kept };

PERF_INC(PERF_SELECT_FULL);

// [object, class, weaponInfo, in open-fire range, cued, full firing window]
// for every candidate
// some ready weapon reaches -- or, for a gun, will reach within its cue time
// (aegism_intercept_fnc_canEngage, "Cue Before In Range").
private _engageable = [];
{
    _x params ["_object", "_class"];
    if (!isNull _object && {alive _object} && {_class in _allowlist}) then {
        private _inRange = false;
        private _cued = false;
        private _full = true;
        private _idx = _weapons findIf {
            private _weaponInfo = _x;
            private _engage = [_system, _role, _weaponInfo, _object, _engagementSettings] call aegism_intercept_fnc_canEngage;
            _cued = (_engage param [4, 0]) > 0;
            _full = (_engage param [6, ""]) == "";
            if ((_engage select 0) && {!_cued}) then {
                _inRange = _role != "ciws" || {
                    // As the gun's own aim judges it (aegism_intercept_fnc_aimWeapon):
                    // a munition's body seen from the gun, plus the round's own radius.
                    private _hitRadius = if (_class in ["missile", "rocket", "bomb", "artilleryShell"]) then {
                        private _kinematics = [_weaponInfo select 1, _weaponInfo select 2] call aegism_intercept_fnc_weaponKinematics;
                        round ((([_object, (getPosASL _object) vectorDiff (getPosASL _system)] call aegism_intercept_fnc_targetHitRadius) + ((_kinematics select 11) max (_kinematics select 13))) * 10) / 10
                    } else { [_object] call aegism_intercept_fnc_targetHitRadius };
                    ([_system, _weaponInfo select 0, _weaponInfo, _class, _hitRadius, _engagementSettings] call aegism_intercept_fnc_openFireRange) params ["_openFireRange", "_minRange"];
                    private _interceptDistance = _engage param [3, 0];
                    _interceptDistance <= _openFireRange && {_interceptDistance >= _minRange}
                };
            };
            _engage select 0
        };
        if (_idx != -1) then {
            _engageable pushBack [_object, _class, _weapons select _idx, _inRange, _cued, _full];
        };
    };
} forEach _candidates;

if (_engageable isEqualTo []) exitWith { [objNull, []] };

// A gun: targets it has its full firing window on come first (aegism_
// intercept_fnc_canEngage, Minimum Firing Window). One it has less on is a
// last-ditch shot, taken only with nothing better.
private _fullOnly = _engageable select { _x select 5 };
if (_fullOnly isNotEqualTo []) then { _engageable = _fullOnly; };

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
[_best select 0, _best select 2, _best select 4]
