/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_watchProjectile

Description:
    Starts tracking one fired projectile if it classifies as a threat
    (aegism_detect_fnc_trackMunition), and follows it through submunition
    handoffs.

    A carrier (CfgAmmo simulation "shotSubmunitions") is deleted mid-flight
    and replaced by the projectile(s) it releases. The MLRS rocket
    R_230mm_HE, for example, becomes R_230mm_fly after triggerDistance =
    500m, which then flies the rest of the way. Without following that, the
    tracker saw the carrier vanish and dropped the contact for good. The
    handoff uses the projectile "SubmunitionCreated" event (as ACE's CLGP
    code does) and runs this same function on each released projectile, so
    multi-stage carriers work too. Only a carrier that releases ONE round
    (aegism_detect_fnc_ammoThreatInfo, from its config) is followed: a
    cluster carrier's dozens of bomblets (R_230mm_Cluster 50,
    Cluster_155mm_AMOS 35) can't be intercepted one by one, and each tracked
    round flies a sensor proxy. Released projectiles that don't classify are
    ignored the normal way anyway (Mo_cluster_AP has no artilleryLock).

Parameters:
    _projectile - the fired or released projectile <OBJECT>
    _shooterSide - side of whoever fired it, for IFF <SIDE>
    _class - optional, its threat class if already known <STRING>
    _isCarrier - optional, it's a carrier, if already known <BOOLEAN>

Returns:
    The projectile's threat class, or "" if it isn't one <STRING>

Examples:
    [_projectile, side _unit] call aegism_detect_fnc_watchProjectile;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_projectile", "_shooterSide", ["_class", ""], ["_isCarrier", false]];

if (isNull _projectile) exitWith { "" };

([typeOf _projectile] call aegism_detect_fnc_ammoThreatInfo) params ["_knownClass", "_knownCarrier", "_submunitions"];
if (_class == "" && {!_isCarrier}) then {
    _class = _knownClass;
    _isCarrier = _knownCarrier;
};

if (_isCarrier && {_submunitions == 1}) then {
    _projectile setVariable ["AEGISM_shooterSide", _shooterSide];
    _projectile addEventHandler ["SubmunitionCreated", {
        params ["_projectile", "_submunitionProjectile"];
        // Intercepted by AEGIS-M: its payload is deleted as it's released
        // (aegism_intercept_fnc_interceptHit), nothing to track.
        if (_projectile getVariable ["AEGISM_intercepted", false]) exitWith {};
        [_submunitionProjectile, _projectile getVariable ["AEGISM_shooterSide", sideUnknown]] call aegism_detect_fnc_watchProjectile;
    }];
};

if (_class != "") then {
    [_projectile, _class, _shooterSide] call aegism_detect_fnc_trackMunition;
};

_class
