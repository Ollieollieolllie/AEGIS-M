/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_interceptHit

Description:
    Detonates an interceptor that has reached its target (triggerAmmo: real
    splash), and a MUNITION target with it -- the engine has no projectile-
    vs-projectile collision, so an incoming round has no hitpoints for the
    splash to act on. An aircraft target is left to real splash damage.

    A CARRIER target (CfgAmmo simulation "shotSubmunitions") is triggered
    the same way, but everything it releases is deleted the moment it's
    created (its "SubmunitionCreated" event). Triggering a carrier doesn't
    destroy it -- it makes it release its payload on the spot: every MLRS
    R_230mm_HE "kill" used to hand the Site a live R_230mm_fly warhead
    (1250m danger radius) to shoot at again. The carrier is flagged
    "AEGISM_intercepted" first so aegism_detect_fnc_watchProjectile doesn't
    start tracking the payload.

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

triggerAmmo _projectile;
if (_isMunitionTarget) then {
    if ((toLower getText (configOf _target >> "simulation")) == "shotsubmunitions") then {
        _target setVariable ["AEGISM_intercepted", true];
        _target addEventHandler ["SubmunitionCreated", {
            params ["", "_submunitionProjectile"];
            deleteVehicle _submunitionProjectile;
        }];
    };
    triggerAmmo _target;
};
diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " INTERCEPT: %1 hit %2 (closest %3m, hit radius %4m).", typeOf _projectile, _target, _minDistance, _hitRadius];
