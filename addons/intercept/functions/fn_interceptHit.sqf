/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_interceptHit

Description:
    Detonates an interceptor that has reached its target (triggerAmmo: real
    splash), and a MUNITION target with it (aegism_detect_fnc_
    destroyMunition) -- the engine has no projectile-vs-projectile
    collision, so an incoming round has no hitpoints for the splash to act
    on. An aircraft target is left to real splash damage.

Parameters:
    _projectile - the interceptor <OBJECT>
    _target - its target <OBJECT>
    _isMunitionTarget - the target is a munition <BOOLEAN>
    _minDistance - closest approach, m (for the log) <NUMBER>
    _hitRadius - the hit radius it was inside, m (for the log) <NUMBER>

Returns:
    Nothing

Examples:
    [_round, _shell, true, 0.8, 1.2] call aegism_intercept_fnc_interceptHit;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_projectile", "_target", "_isMunitionTarget", "_minDistance", "_hitRadius"];

// The munition first: the interceptor's blast then finds it already gone,
// not shooting its sensor proxy down too (PROXY-HIT).
if (_isMunitionTarget) then { [_target] call aegism_detect_fnc_destroyMunition; };
triggerAmmo _projectile;
diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " INTERCEPT: %1 hit %2 (closest %3m, hit radius %4m).", typeOf _projectile, _target, _minDistance, _hitRadius];
