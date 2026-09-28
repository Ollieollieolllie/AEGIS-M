/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_watchProjectile

Description:
    Starts tracking one fired projectile if it classifies as a threat
    (aegism_detect_fnc_classifyTarget -> aegism_detect_fnc_trackMunition),
    and follows it through submunition handoffs.

    A carrier (CfgAmmo simulation "shotSubmunitions") is deleted mid-flight
    and replaced by the projectile(s) it releases. The MLRS rocket
    R_230mm_HE, for example, becomes R_230mm_fly after triggerDistance =
    500m, which then flies the rest of the way. Without following that, the
    tracker saw the carrier vanish and dropped the contact for good. The
    handoff uses the projectile "SubmunitionCreated" event (as ACE's CLGP
    code does) and runs this same function on each released projectile, so
    multi-stage carriers work too. Released projectiles that don't classify
    are ignored the normal way -- e.g. cluster bomblets (Mo_cluster_AP, no
    artilleryLock).

Parameters:
    _projectile - the fired or released projectile <OBJECT>
    _shooterSide - side of whoever fired it, for IFF <SIDE>

Returns:
    The projectile's threat class, or "" if it isn't one <STRING>

Examples:
    [_projectile, side _unit] call aegism_detect_fnc_watchProjectile;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_projectile", "_shooterSide"];

if (isNull _projectile) exitWith { "" };

if ((toLower getText (configOf _projectile >> "simulation")) == "shotsubmunitions") then {
    _projectile setVariable ["AEGISM_shooterSide", _shooterSide];
    _projectile addEventHandler ["SubmunitionCreated", {
        params ["_projectile", "_submunitionProjectile"];
        [_submunitionProjectile, _projectile getVariable ["AEGISM_shooterSide", sideUnknown]] call aegism_detect_fnc_watchProjectile;
    }];
};

private _class = [_projectile] call aegism_detect_fnc_classifyTarget;
if (_class != "") then {
    [_projectile, _class, _shooterSide] call aegism_detect_fnc_trackMunition;
};

_class
