/* ----------------------------------------------------------------------------
Function: aegism_crew_fnc_moduleInit

Description:
    Entry point run when an AEGISM_Module_Crew is placed and synced in Eden
    or Zeus. Reads the module's personality attributes and stores the
    resulting data ("AEGISM_crew") on every synced object -- a crewed unit,
    one or more AEGISM_Module_System vehicles (for unmanned point-defense),
    or a single AEGISM_Module_Network object to apply the personality
    battery-wide (per the object -> network -> default resolution order in
    aegism_system_fnc_resolveCrew).

Parameters:
    _logic - the module logic object <OBJECT>
    _units - synced objects: a crew unit, AEGISM_Module_System vehicles,
        and/or an AEGISM_Module_Network object <ARRAY of OBJECT>
    _activated - module activation state (unused, modules run on init) <BOOLEAN>

Returns:
    Nothing

Examples:
    [_logic, _units, _activated] call aegism_crew_fnc_moduleInit;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_logic", "_units", "_activated"];

if (_units isEqualTo []) exitWith {
    diag_log text format ["[AEGIS-M] WARNING: AEGISM_Module_Crew %1 was placed with no synced object -- ignoring.", _logic];
};

private _crewData = createHashMapFromArray [
    ["skillTier", _logic getVariable ["skillTier", "regular"]],
    ["temperament", _logic getVariable ["temperament", "standard"]],
    ["costValueJudgment", _logic getVariable ["costValueJudgment", false]]
];

{
    _x setVariable ["AEGISM_crew", _crewData, false];
} forEach _units;

diag_log text format ["[AEGIS-M] Crew %1 applied to %2 synced object(s) -- skillTier=%3 temperament=%4", _logic, count _units, _crewData get "skillTier", _crewData get "temperament"];
