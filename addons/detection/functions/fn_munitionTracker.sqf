/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_munitionTracker

Description:
    One frame of the munition tracker: works through every tracked munition
    ("AEGISM_trackedMunitions", aegism_detect_fnc_trackMunition), seeing its
    sensor proxy carried (checked once after it's attached, aegism_detect_
    fnc_proxyCheckAttach; moved every frame instead if it wasn't, aegism_
    detect_fnc_proxyFollow), and checking each one that's due (aegism_detect_fnc_munitionCheck) and then
    again AEGISM_TRACK_INTERVAL s later. Munitions come in at their own fire
    times, so a barrage's checks are spread over frames rather than all
    landing on one.

    A munition that's gone (impact, intercept, leaves simulation) is
    removed from every pool it was added to, by its own key -- it used to be
    looked up by netId after it was already deleted, which never matched --
    and its proxy is deleted.

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
        deleteVehicle (_entry select 6);
        _tracked deleteAt _i;
    } else {
        // Its sensor proxy: attached, the engine carries it; checked once
        // that it came along, and moved every frame if it didn't.
        private _proxy = _entry select 6;
        if (!isNull _proxy) then {
            private _flags = _entry select 7;
            if (_flags getOrDefault ["follow", false]) then {
                [_proxy, _projectile] call aegism_detect_fnc_proxyFollow;
            } else {
                private _checkAt = _flags getOrDefault ["attachCheckAt", -1];
                if (_checkAt >= 0 && {time >= _checkAt}) then {
                    _flags set ["attachCheckAt", -1];
                    [_entry] call aegism_detect_fnc_proxyCheckAttach;
                };
            };
        };
        if (time >= (_entry select 5)) then {
            _entry set [5, time + AEGISM_TRACK_INTERVAL];
            PERF_INC(PERF_TRACKER_CHECKS);
            [_entry, _owners] call aegism_detect_fnc_munitionCheck;
        };
    };
};

PERF_ADD(PERF_TRACKER_MS,(diag_tickTime - _started) * 1000);
true
