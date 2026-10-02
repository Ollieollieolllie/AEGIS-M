/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_proxyFollow

Description:
    Puts a munition's sensor proxy (aegism_detect_fnc_proxyCreate) where
    the munition is, flying at its velocity -- the way the published
    Intercept Munitions mod moves its own projectile proxies (setPosASL +
    setVelocity). Places a new proxy before it's attached, and moves every
    frame (aegism_detect_fnc_munitionTracker) a proxy its munition didn't
    carry when attached (aegism_detect_fnc_proxyCheckAttach: the MLRS
    carrier stage R_230mm_HE left it at the launcher). A proxy moved this
    way also reports the munition's real speed to the sensors; an attached
    one reports none of its own.

    The proxy sits AEGISM_PROXY_TRAIL m behind the munition along its
    flight, so the munition is always flying away from it and can never
    strike its geometry.

Parameters:
    _proxy - the proxy <OBJECT>
    _projectile - its munition <OBJECT>

Returns:
    Nothing

Examples:
    [_proxy, _projectile] call aegism_detect_fnc_proxyFollow;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\proxy.hpp"

params ["_proxy", "_projectile"];

private _velocity = velocity _projectile;
private _position = getPosASL _projectile;
if ((vectorMagnitude _velocity) > 1) then {
    _position = _position vectorDiff ((vectorNormalized _velocity) vectorMultiply AEGISM_PROXY_TRAIL);
};
_proxy setPosASL _position;
_proxy setVelocity _velocity;
