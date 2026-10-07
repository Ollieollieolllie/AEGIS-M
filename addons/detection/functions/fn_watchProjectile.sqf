/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_watchProjectile

Description:
    Starts tracking one fired projectile if it classifies as a threat
    (aegism_detect_fnc_trackMunition), and follows it through submunition
    handoffs.
    Full notes: docs/functions/detection.md

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
// Handled: the catch for munitions nothing reported fired (aegism_detect_
// fnc_projectileCreated) leaves it alone.
_projectile setVariable ["AEGISM_seen", true];

([typeOf _projectile] call aegism_detect_fnc_ammoThreatInfo) params ["_knownClass", "_knownCarrier", "_submunitions"];
if (_class == "" && {!_isCarrier}) then {
    _class = _knownClass;
    _isCarrier = _knownCarrier;
};

// A cluster's bomblets aren't followed (see notes) -- and aren't munitions
// nothing fired either.
if (_isCarrier && {_submunitions != 1}) then {
    _projectile addEventHandler ["SubmunitionCreated", {
        params ["", "_submunitionProjectile"];
        _submunitionProjectile setVariable ["AEGISM_seen", true];
    }];
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
