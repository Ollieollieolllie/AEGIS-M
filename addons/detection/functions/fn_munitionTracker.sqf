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
    and its proxy is deleted. One that never came into any Site's picture is
    logged (UNSEEN): whether any sensor saw it, how near and how low it came,
    and how its proxy kept with it. An anti-radiation missile's end is logged
    (ARM-END): what it was homing on at its last check, how far it then was
    from the nearest AEGIS-M radar and whether that radar was emitting, and
    whether any AEGIS-M sensor saw it.

Parameters:
    None

Returns:
    true while there's anything left to track (false stops the handler) <BOOLEAN>

Examples:
    [] call aegism_detect_fnc_munitionTracker;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\proxy.hpp"
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
        private _flags = _entry select 7;
        // Never in any Site's picture: why, from its path at the checks
        // (aegism_detect_fnc_munitionCheck) -- nobody's sensors saw it, or
        // they did and it was judged no threat; how near and how low it came,
        // and whether its proxy kept with it and what speed it showed.
        private _path = _flags getOrDefault ["path", []];
        if (_path isNotEqualTo [] && {(_entry select 4) isEqualTo []}) then {
            _path params ["_nearest", "_nearestVehicle", "_lowest", "_topSpeed", "_proxyOffset", "_proxySpeed", "_seenKinds", ["_elevation", 0]];
            diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " UNSEEN: %1 (%2, %3) gone %4s after it was fired, never in a Site's picture -- %5. At its checks: nearest AEGIS-M sensor vehicle %6m (%7, %11 deg up from it), lowest %8m above ground, top speed %9 m/s; its proxy %10.",
                _flags getOrDefault ["ammo", "?"], _entry select 1, _key, (time - (_flags getOrDefault ["firedAt", time])) toFixed 1,
                ["no AEGIS-M sensor ever saw it", format ["seen by %1, but judged no threat", _seenKinds joinString ", "]] select (_seenKinds isNotEqualTo []),
                round _nearest, _nearestVehicle, round _lowest, round _topSpeed,
                if (_proxyOffset <= 0) then { "never made (gone too soon)" } else {
                    format ["%1, at most %2m from it, showing up to %3 m/s", ["attached", "moved every frame"] select (_flags getOrDefault ["follow", false]), round _proxyOffset, round _proxySpeed]
                },
                round _elevation];
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
            diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " ARM-END: %1 (%2) gone %3s after it was fired -- at its last check it was homing on %4; %5; %6.",
                _ammo, _key, (time - (_flags getOrDefault ["firedAt", time])) toFixed 1,
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
        // Its sensor proxy: attached, the engine carries it; checked once
        // that it came along, and moved every frame if it didn't.
        private _proxy = _entry select 6;
        if (!isNull _proxy) then {
            private _flags = _entry select 7;
            if (_flags getOrDefault ["follow", false]) then {
                [_proxy, _projectile] call aegism_detect_fnc_proxyFollow;
            } else {
                // Once the munition is well away from where the proxy was
                // made, so one left behind is unmistakably off (proxy.hpp).
                private _checkAt = _flags getOrDefault ["attachCheckAt", -1];
                if (_checkAt >= 0 && {time >= _checkAt}
                    && {((getPosASL _projectile) distance (_flags getOrDefault ["attachFrom", getPosASL _projectile])) > 2 * AEGISM_PROXY_ATTACH_TOLERANCE
                        || {time >= _checkAt + AEGISM_PROXY_ATTACH_TIMEOUT}}) then {
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
