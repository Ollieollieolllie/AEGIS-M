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

    Each kill is noted for a moment ("AEGISM_recentKills": when, where, its
    blast radius): the blast of a munition AEGIS-M destroyed is credited to
    whoever FIRED it, and the sensor proxies it takes out with it still
    count (aegism_detect_fnc_proxyCreate), where the incoming side's own
    blasts otherwise don't.

Parameters:
    _munition - the munition <OBJECT>

Returns:
    Nothing

Examples:
    [_shell] call aegism_detect_fnc_destroyMunition;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\proxy.hpp"

params ["_munition"];

if (isNull _munition || {!alive _munition}) exitWith {};

// Noted for its blast (see header): the last AEGISM_KILL_NOTE s of kills.
private _kills = (missionNamespace getVariable ["AEGISM_recentKills", []]) select { CBA_missionTime - (_x select 0) <= AEGISM_KILL_NOTE };
_kills pushBack [CBA_missionTime, getPosASL _munition, getNumber (configOf _munition >> "indirectHitRange")];
missionNamespace setVariable ["AEGISM_recentKills", _kills];

if ((toLower getText (configOf _munition >> "simulation")) == "shotsubmunitions") then {
    _munition setVariable ["AEGISM_intercepted", true];
    _munition addEventHandler ["SubmunitionCreated", {
        params ["", "_submunitionProjectile"];
        deleteVehicle _submunitionProjectile;
    }];
};
triggerAmmo _munition;
