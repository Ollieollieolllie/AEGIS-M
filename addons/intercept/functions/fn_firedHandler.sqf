/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_firedHandler

Description:
    Makes sure a System vehicle has AEGIS-M's persistent "Fired" event
    handler, adding it again if something removed it (EH-RESTORED).
    Full notes: docs/functions/intercept.md

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
