/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_destroyMunition

Description:
    Destroys an incoming munition where it is (triggerAmmo: it detonates in
    the air). The engine has no projectile-vs-projectile collision, so an
    incoming round has no hitpoints of its own for a hit to act on: an
    interceptor that reaches it (aegism_intercept_fnc_interceptHit) and a
    weapon that destroys its sensor proxy (aegism_detect_fnc_proxyCreate)
    both end it here.

    A CARRIER (CfgAmmo simulation "shotSubmunitions") is triggered the same
    way, but everything it releases is deleted the moment it's created (its
    "SubmunitionCreated" event). Triggering a carrier doesn't destroy it --
    it makes it release its payload on the spot: every MLRS R_230mm_HE
    "kill" used to hand the Site a live R_230mm_fly warhead (1250m danger
    radius) to shoot at again. The carrier is flagged "AEGISM_intercepted"
    first so aegism_detect_fnc_watchProjectile doesn't start tracking the
    payload.

Parameters:
    _munition - the munition <OBJECT>

Returns:
    Nothing

Examples:
    [_shell] call aegism_detect_fnc_destroyMunition;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_munition"];

if (isNull _munition || {!alive _munition}) exitWith {};

if ((toLower getText (configOf _munition >> "simulation")) == "shotsubmunitions") then {
    _munition setVariable ["AEGISM_intercepted", true];
    _munition addEventHandler ["SubmunitionCreated", {
        params ["", "_submunitionProjectile"];
        deleteVehicle _submunitionProjectile;
    }];
};
triggerAmmo _munition;
