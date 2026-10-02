/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_proxyCreate

Description:
    Creates a tracked munition's sensor proxy (see aegism_detect_fnc_
    trackMunition), AEGISM_PROXY_DELAY s after launch -- created at the
    muzzle, its geometry is inside the launching vehicle. Nothing if the
    munition is already gone.

    The proxy is its threat class's proxy type ("AEGISM_MunitionProxy_
    <class>", detection config.cpp), texture blanked (invisible), hot for
    IR (setVehicleTIPars: engine, wheels, weapon), and attached
    AEGISM_PROXY_TRAIL m behind the munition, in the munition's own model
    space: the engine carries it from then on, with no script each frame.
    attachTo doesn't carry it on every projectile, though -- the MLRS
    carrier stage R_230mm_HE left an attached proxy at the launcher -- so
    the tracker checks AEGISM_PROXY_ATTACH_CHECK s later (aegism_detect_fnc_
    proxyCheckAttach), and an ammo class that didn't carry it gets its
    proxies moved every frame instead (aegism_detect_fnc_proxyFollow) from
    then on, without trying to attach.

Parameters:
    _entry - the tracked munition's entry (aegism_detect_fnc_trackMunition) <ARRAY>

Returns:
    Nothing

Examples:
    [_entry] call aegism_detect_fnc_proxyCreate;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\proxy.hpp"
#include "..\..\main\perf.hpp"

params ["_entry"];
_entry params ["_projectile", "_class", "", "_key", "", "", "", "_flags"];

if (isNull _projectile || {!alive _projectile}) exitWith {};
private _started = diag_tickTime;

private _proxy = (format ["AEGISM_MunitionProxy_%1", _class]) createVehicleLocal [0, 0, 0];
_proxy allowDamage false;
_proxy setObjectTexture [0, ""];
_proxy setVehicleTIPars [1, 1, 1];
_proxy setVariable ["AEGISM_proxyKey", _key];
[_proxy, _projectile] call aegism_detect_fnc_proxyFollow;

if ((typeOf _projectile) in (missionNamespace getVariable ["AEGISM_proxyFollowAmmo", createHashMap])) then {
    _flags set ["follow", true];
} else {
    _proxy attachTo [_projectile, [0, -AEGISM_PROXY_TRAIL, 0]];
    _flags set ["attachCheckAt", time + AEGISM_PROXY_ATTACH_CHECK];
};
_entry set [6, _proxy];

PERF_ADD(PERF_TRACKER_MS,(diag_tickTime - _started) * 1000);
