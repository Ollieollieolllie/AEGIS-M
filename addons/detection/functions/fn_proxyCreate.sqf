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
    AEGISM_PROXY_OFFSET m above the munition, in the munition's own model
    space: the engine carries it from then on, with no script each frame.
    attachTo doesn't carry it on every projectile, though -- the MLRS
    carrier stage R_230mm_HE left an attached proxy at the launcher -- so
    the tracker checks it once the munition is well away from where it was
    made (aegism_detect_fnc_proxyCheckAttach), and an ammo class that didn't
    carry it gets its proxies moved every frame instead (aegism_detect_fnc_
    proxyFollow) from then on, without trying to attach.

    A weapon that would destroy the proxy destroys its munition instead
    (PROXY-HIT): the proxy is what a gunner's radar shows and locks.

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
if (_follow && {CBA_missionTime < (_flags getOrDefault ["firedAt", CBA_missionTime]) + AEGISM_PROXY_MAX_DELAY}) then {
    private _shooter = (getShotParents _projectile) param [0, objNull];
    private _proxyRadius = missionNamespace getVariable ["AEGISM_proxyRadius", -1];
    _wait = !isNull _shooter && {_proxyRadius < 0 || {(_projectile distance _shooter) <= ((boundingBoxReal _shooter) select 2) + AEGISM_PROXY_OFFSET + _proxyRadius}};
};
if (_wait) exitWith { [aegism_detect_fnc_proxyCreate, [_entry]] call CBA_fnc_execNextFrame; };

private _started = diag_tickTime;

private _proxy = (format ["AEGISM_MunitionProxy_%1", _class]) createVehicleLocal [0, 0, 0];
// Shot down, its munition dies (aegism_detect_fnc_destroyMunition): the
// proxy is what sensors see and lock, so a weapon fired at the munition --
// a gunner locking it on radar -- hits the proxy, never the munition (no
// projectile hits a projectile). Weapon damage only, from anyone, added up
// until it would destroy the proxy -- a rocket of a salvo detonating can
// take out the ones flying beside it -- but not a collision (a proxy moved
// every frame can graze the ground). The proxy itself is never damaged: it
// goes with its munition (aegism_detect_fnc_munitionTracker). PROXY-HIT.
_proxy addEventHandler ["HandleDamage", {
    params ["_proxy", "", "_damage", "_source", "_ammo", "_hitIndex", "_instigator"];
    private _entry = _proxy getVariable ["AEGISM_proxyEntry", [objNull]];
    private _attacker = [_instigator, _source] select (isNull _instigator);
    if (_ammo != "" && {_hitIndex == -1} && {_damage > 0}) then {
        private _total = (_proxy getVariable ["AEGISM_proxyDamage", 0]) + _damage;
        _proxy setVariable ["AEGISM_proxyDamage", _total];
        private _munition = _entry select 0;
        if (_total >= 1 && {!isNull _munition} && {alive _munition}) then {
            diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " PROXY-HIT: %1 (%2) destroyed -- its sensor proxy was shot down by %3 (%4, %5).",
                typeOf _munition, _proxy getVariable ["AEGISM_proxyKey", "?"], _attacker, typeOf _attacker, _ammo];
            [_munition] call aegism_detect_fnc_destroyMunition;
        };
    };
    0
}];
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
    _proxy attachTo [_projectile, [0, 0, AEGISM_PROXY_OFFSET]];
    _flags set ["attachCheckAt", CBA_missionTime + AEGISM_PROXY_ATTACH_CHECK];
    _flags set ["attachFrom", getPosASL _projectile];
};
_entry set [6, _proxy];

PERF_ADD(PERF_TRACKER_MS,(diag_tickTime - _started) * 1000);
