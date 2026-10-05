/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_proxyCheckAttach

Description:
    Whether a munition carried its attached sensor proxy (aegism_detect_
    fnc_proxyCreate): checked once by aegism_detect_fnc_munitionTracker, at
    least AEGISM_PROXY_ATTACH_CHECK s after attaching and once the munition
    is over twice AEGISM_PROXY_ATTACH_TOLERANCE from where the proxy was made
    (or AEGISM_PROXY_ATTACH_TIMEOUT s later). An attached proxy sits
    AEGISM_PROXY_OFFSET m from its munition; one more than
    AEGISM_PROXY_ATTACH_TOLERANCE m off was left behind (attachTo doesn't
    carry it on every projectile -- the MLRS carrier stage R_230mm_HE
    didn't), so it's detached and moved every frame instead (aegism_detect_
    fnc_proxyFollow), and so is every later proxy of that ammo class
    ("AEGISM_proxyFollowAmmo"). Each ammo class's outcome is logged once
    (PROXY-ATTACH).

Parameters:
    _entry - the tracked munition's entry (aegism_detect_fnc_trackMunition) <ARRAY>

Returns:
    Nothing

Examples:
    [_entry] call aegism_detect_fnc_proxyCheckAttach;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\proxy.hpp"
#include "..\..\main\rpt.hpp"

params ["_entry"];
_entry params ["_projectile", "", "", "", "", "", "_proxy", "_flags"];

private _ammo = typeOf _projectile;
private _offset = _proxy distance _projectile;
private _carried = _offset <= AEGISM_PROXY_ATTACH_TOLERANCE;

if (!_carried) then {
    detach _proxy;
    _flags set ["follow", true];
    private _followAmmo = missionNamespace getVariable "AEGISM_proxyFollowAmmo";
    if (isNil "_followAmmo") then {
        _followAmmo = createHashMap;
        missionNamespace setVariable ["AEGISM_proxyFollowAmmo", _followAmmo];
    };
    _followAmmo set [_ammo, true];
    [_proxy, _projectile] call aegism_detect_fnc_proxyFollow;
};

private _logged = missionNamespace getVariable "AEGISM_proxyAttachLogged";
if (isNil "_logged") then {
    _logged = createHashMap;
    missionNamespace setVariable ["AEGISM_proxyAttachLogged", _logged];
};
if !(_ammo in _logged) then {
    _logged set [_ammo, true];
    if (AEGISM_RPT_VERBOSE) then {
        diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " PROXY-ATTACH: %1 %2 (proxy %3m from it, munition at %4 m/s).", _ammo,
            ["didn't carry its attached sensor proxy -- its proxies are moved every frame instead", "carries its attached sensor proxy"] select _carried,
            round _offset, round (vectorMagnitude velocity _projectile)];
    };
};
