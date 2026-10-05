/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_proxyCreate

Description:
    Creates a tracked munition's sensor proxy (see aegism_detect_fnc_
    trackMunition), AEGISM_PROXY_MIN_DELAY s after launch, attached at once.
    For an ammo type whose proxies are moved every frame (a free vehicle),
    not until its munition is clear of the shooter, up to AEGISM_PROXY_MAX_
    DELAY s after launch: until then it tries again every frame (proxy.hpp).
    Nothing if the munition is already gone.

    The proxy is its threat class's proxy type ("AEGISM_MunitionProxy_
    <class>", detection config.cpp), texture blanked (invisible), hot for
    IR -- its (silent) engine running, which an IR sensor needs to see it,
    and its thermal look set (setVehicleTIPars: engine, wheels, weapon) --
    and attached
    AEGISM_PROXY_TRAIL m behind the munition, in the munition's own model
    space: the engine carries it from then on, with no script each frame.
    attachTo doesn't carry it on every projectile, though -- the MLRS
    carrier stage R_230mm_HE left an attached proxy at the launcher -- so
    the tracker checks it once the munition is well away from where it was
    made (aegism_detect_fnc_proxyCheckAttach), and an ammo class that didn't
    carry it gets its proxies moved every frame instead (aegism_detect_fnc_
    proxyFollow) from then on, without trying to attach.

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

// A proxy moved every frame is a free, simulated vehicle: not until its
// munition is clear of whatever fired it (proxy.hpp), checked every frame.
private _follow = (typeOf _projectile) in (missionNamespace getVariable ["AEGISM_proxyFollowAmmo", createHashMap]);
private _wait = false;
if (_follow && {time < (_flags getOrDefault ["firedAt", time]) + AEGISM_PROXY_MAX_DELAY}) then {
    private _shooter = (getShotParents _projectile) param [0, objNull];
    private _proxyRadius = missionNamespace getVariable ["AEGISM_proxyRadius", -1];
    _wait = !isNull _shooter && {_proxyRadius < 0 || {(_projectile distance _shooter) <= ((boundingBoxReal _shooter) select 2) + AEGISM_PROXY_TRAIL + _proxyRadius}};
};
if (_wait) exitWith { [aegism_detect_fnc_proxyCreate, [_entry]] call CBA_fnc_execNextFrame; };

private _started = diag_tickTime;

private _proxy = (format ["AEGISM_MunitionProxy_%1", _class]) createVehicleLocal [0, 0, 0];
_proxy allowDamage false;
_proxy setObjectTexture [0, ""];
_proxy setVehicleTIPars [1, 1, 1];
// An IR sensor only sees a vehicle whose engine is running (as an IR missile
// can't lock one parked); the proxy's is silent (detection config.cpp).
_proxy engineOn true;
_proxy setVariable ["AEGISM_proxyKey", _key];
// Its tracked munition's entry, so the sensor read that first sees it can
// have it checked at once (aegism_detect_fnc_confidenceLoop).
_proxy setVariable ["AEGISM_proxyEntry", _entry];
// Its own size, for the clearance above.
if (isNil { missionNamespace getVariable "AEGISM_proxyRadius" }) then {
    missionNamespace setVariable ["AEGISM_proxyRadius", (boundingBoxReal _proxy) select 2];
};

if (_follow) then {
    [_proxy, _projectile] call aegism_detect_fnc_proxyFollow;
    _flags set ["follow", true];
} else {
    // Attached straight from where it's made, never free on the way.
    _proxy attachTo [_projectile, [0, -AEGISM_PROXY_TRAIL, 0]];
    _flags set ["attachCheckAt", time + AEGISM_PROXY_ATTACH_CHECK];
    _flags set ["attachFrom", getPosASL _projectile];
};
_entry set [6, _proxy];

PERF_ADD(PERF_TRACKER_MS,(diag_tickTime - _started) * 1000);
