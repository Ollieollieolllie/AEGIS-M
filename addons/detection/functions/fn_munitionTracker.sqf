/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_munitionTracker

Description:
    One frame of the munition tracker: works through every tracked munition,
    checking each one that's due and then again AEGISM_TRACK_INTERVAL s
    later.
    Full notes: docs/functions/detection.md

Parameters:
    None

Returns:
    true while there's anything left to track (false stops the handler) <BOOLEAN>

Examples:
    [] call aegism_detect_fnc_munitionTracker;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\perf.hpp"

#define AEGISM_TRACK_INTERVAL 0.5

private _tracked = missionNamespace getVariable ["AEGISM_trackedMunitions", []];
if (_tracked isEqualTo []) exitWith { false };

private _started = diag_tickTime;
private _owners = missionNamespace getVariable ["AEGISM_allPoolOwners", []];

for "_i" from (count _tracked - 1) to 0 step -1 do {
    private _entry = _tracked select _i;
    private _projectile = _entry select 0;
    if (isNull _projectile || {!alive _projectile}) then {
        private _key = _entry select 3;
        { [_x, _key] call aegism_detect_fnc_removeContact; } forEach (_entry select 4);
        private _flags = _entry select 7;
        // Never in any Site's picture: why, from its path at the checks
        // (aegism_detect_fnc_munitionCheck) -- nobody's sensors saw it, or
        // they did and it was judged no threat; how near and how low it came.
        private _path = _flags getOrDefault ["path", []];
        if (_path isNotEqualTo [] && {(_entry select 4) isEqualTo []}) then {
            _path params ["_nearest", "_nearestVehicle", "_lowest", "_topSpeed", "_seenKinds", ["_elevation", 0]];
            diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " UNSEEN: %1 (%2, %3) gone %4s after it was fired, never in a Site's picture -- %5. At its checks: nearest AEGIS-M sensor vehicle %6m (%7, %10 deg up from it), lowest %8m above ground, top speed %9 m/s.",
                _flags getOrDefault ["ammo", "?"], _entry select 1, _key, (CBA_missionTime - (_flags getOrDefault ["firedAt", CBA_missionTime])) toFixed 1,
                ["no AEGIS-M sensor ever saw it", format ["seen by %1, but judged no threat", _seenKinds joinString ", "]] select (_seenKinds isNotEqualTo []),
                round _nearest, _nearestVehicle, round _lowest, round _topSpeed, round _elevation];
        };
        // An anti-radiation missile: how it ended, from its last check
        // (aegism_detect_fnc_munitionCheck) -- what it was homing on, and
        // where it was then relative to the nearest AEGIS-M radar.
        private _arm = _flags getOrDefault ["arm", []];
        if (_arm isNotEqualTo []) then {
            _arm params ["_ammo", "_lastPos", "_homing", "_seen"];
            private _radars = (missionNamespace getVariable ["AEGISM_allSystems", []]) select {
                !isNull _x && {(_x getVariable ["AEGISM_system", createHashMap]) getOrDefault ["hasRadar", false]}
            };
            private _nearest = objNull;
            if (_lastPos isNotEqualTo [] && {_radars isNotEqualTo []}) then {
                _nearest = ([_radars, [], { _x distance _lastPos }, "ASCEND"] call BIS_fnc_sortBy) select 0;
            };
            diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " ARM-END: %1 (%2) gone %3s after it was fired -- at its last check it was homing on %4; %5; %6.",
                _ammo, _key, (CBA_missionTime - (_flags getOrDefault ["firedAt", CBA_missionTime])) toFixed 1,
                if (isNull _homing) then { "nothing" } else {
                    format ["%1 (%2, radar %3)", _homing, ["destroyed", "alive"] select (alive _homing), ["off", "on"] select (isVehicleRadarOn _homing)]
                },
                if (isNull _nearest) then { "no AEGIS-M radar to measure from" } else {
                    format ["the nearest AEGIS-M radar, %1 (%2, radar %3), was %4m from it", _nearest, ["destroyed", "alive"] select (alive _nearest), ["off", "on"] select (isVehicleRadarOn _nearest), round (_nearest distance _lastPos)]
                },
                ["no AEGIS-M sensor ever saw it, so no radar shut down for it", "an AEGIS-M sensor saw it"] select _seen];
        };
        _tracked deleteAt _i;
    } else {
        if (CBA_missionTime >= (_entry select 5)) then {
            _entry set [5, CBA_missionTime + AEGISM_TRACK_INTERVAL];
            PERF_INC(PERF_TRACKER_CHECKS);
            [_entry, _owners] call aegism_detect_fnc_munitionCheck;
        };
    };
};

PERF_ADD(PERF_TRACKER_MS,(diag_tickTime - _started) * 1000);
true
