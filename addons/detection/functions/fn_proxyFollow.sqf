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

    The proxy sits AEGISM_PROXY_OFFSET m above the munition, square to its
    flight: off its path, so neither the munition nor the next round of its
    salvo can strike its geometry.

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
// Up, less its part along the flight; flying straight up or down, sideways.
private _up = [0, 0, 1];
if ((vectorMagnitude _velocity) > 1) then {
    private _along = vectorNormalized _velocity;
    _up = _up vectorDiff (_along vectorMultiply (_along select 2));
    if ((vectorMagnitude _up) < 0.1) then { _up = [1, 0, 0]; };
};
_proxy setPosASL ((getPosASL _projectile) vectorAdd ((vectorNormalized _up) vectorMultiply AEGISM_PROXY_OFFSET));
_proxy setVelocity _velocity;
