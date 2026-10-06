/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_firedHandler

Description:
    Makes sure a System vehicle has AEGIS-M's persistent "Fired" event
    handler (aegism_intercept_fnc_onSystemFired), here on the server where
    its weapons are fired from: added if it has none, and again if something
    removed it -- another mod's removeAllEventHandlers "Fired" would
    otherwise leave every missile it fires with no target given and no fuse
    (EH-RESTORED).

    Called as soon as the vehicle is a System and every couple of seconds
    after (aegism_system_fnc_guardSystems), and before every fire command
    (aegism_intercept_fnc_fireWeapon). It used to be added only by the first
    fire command to get past its crew's reliability roll, so a launcher that
    hadn't fired yet had none, and a missile it launched by itself went
    unseen: POOK's S-400 was one missile down before its first AEGIS-M shot,
    with nothing logged (2026-10-06).

Parameters:
    _system - the System vehicle <OBJECT>

Returns:
    Nothing

Examples:
    [_patriot] call aegism_intercept_fnc_firedHandler;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_system"];

private _firedEh = _system getVariable ["AEGISM_firedEh", -1];
if (_firedEh >= 0 && {(_system getEventHandlerInfo ["Fired", _firedEh]) param [0, false]}) exitWith {};

if (_firedEh >= 0) then {
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " EH-RESTORED: %1 (%2) lost AEGIS-M's Fired event handler (another mod's removeAllEventHandlers?) -- added again.", _system, typeOf _system];
};
_system setVariable ["AEGISM_firedEh", _system addEventHandler ["Fired", {
    params ["_vehicle", "_weapon", "", "", "", "", "_projectile", "_gunner"];
    [_vehicle, _weapon, _projectile, _gunner] call aegism_intercept_fnc_onSystemFired;
}], false];
