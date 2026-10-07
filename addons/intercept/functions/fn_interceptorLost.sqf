/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_interceptorLost
Description:
    Self-destructs an AEGIS-M launcher missile that no longer has the target
    it was fired at.
    Full notes: docs/functions/intercept.md

Parameters:
    _projectile - the missile <OBJECT>
    _target - what it was fired at <OBJECT>
    _why - why it's lost, for the log <STRING>

Returns:
    Nothing

Examples:
    [_missile, _rocket, "its target is gone"] call aegism_intercept_fnc_interceptorLost;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_projectile", "_target", "_why"];

if (isNull _projectile || {!alive _projectile}) exitWith {};

private _launcher = (getShotParents _projectile) param [0, objNull];
diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " INTERCEPTOR-LOST: %1 from %2 -- %3; self-destructed so its seeker can't take anything else.",
    typeOf _projectile, _launcher, _why];
private _at = getPosASL _projectile;
private _ammo = typeOf _projectile;
triggerAmmo _projectile;
[_at, getNumber (configFile >> "CfgAmmo" >> _ammo >> "indirectHitRange"), format ["%1 (self-destructing)", _ammo]] call aegism_detect_fnc_blastMunitions;
