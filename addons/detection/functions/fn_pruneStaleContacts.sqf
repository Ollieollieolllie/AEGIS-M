/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_pruneStaleContacts

Description:
    Removes contacts from a pool (System or Site) whose object is gone/dead
    or that no sensor has refreshed for AEGISM_CONTACT_STALE_TIME seconds.
    Full notes: docs/functions/detection.md

Parameters:
    _poolOwner - the System vehicle or Site logic holding the pool <OBJECT>

Returns:
    Nothing

Examples:
    [_site] call aegism_detect_fnc_pruneStaleContacts;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_CONTACT_STALE_TIME 3

params ["_poolOwner"];

private _pool = _poolOwner getVariable "AEGISM_pooledContacts";
if (isNil "_pool") exitWith {};

{
    private _entry = _pool get _x;
    private _object = _entry get "object";
    if (isNull _object || {!alive _object} || {CBA_missionTime - (_entry getOrDefault ["lastSeen", 0]) > AEGISM_CONTACT_STALE_TIME}) then {
        _pool deleteAt _x;
    };
} forEach (keys _pool);
