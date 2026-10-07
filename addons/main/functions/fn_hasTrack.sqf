/* ----------------------------------------------------------------------------
Function: aegism_fnc_hasTrack

Description:
    Whether a pooled contact is held by a sensor that tracks it: anything
    but passive radar alone.
    Full notes: docs/functions/main.md

Parameters:
    _entry - a pool entry (aegism_detect_fnc_addContact) <HASHMAP>

Returns:
    <BOOLEAN>

Examples:
    [_entry] call aegism_fnc_hasTrack;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_SOURCE_WINDOW 3

params ["_entry"];

private _recent = false;
private _tracked = false;
{
    if (CBA_missionTime - _y <= AEGISM_SOURCE_WINDOW) then {
        _recent = true;
        if (_x != "passiveradar") then { _tracked = true; };
    };
} forEach (_entry getOrDefault ["sources", createHashMap]);

_tracked || {!_recent}
