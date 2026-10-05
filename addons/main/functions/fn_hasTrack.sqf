/* ----------------------------------------------------------------------------
Function: aegism_fnc_hasTrack

Description:
    Whether a pooled contact is held by a sensor that tracks it: anything
    but passive radar alone. Passive radar only hears an emitter's radar,
    which gives a bearing but no range. A contact that only passive radar
    has heard in the last 3 s (the pools' own contact expiry, aegism_detect_
    fnc_pruneStaleContacts) cues the Site's radars (Radar Emission, aegism_
    system_fnc_emconUpdate), but no weapon is assigned to it until a radar,
    IR or visual sensor holds it.

    A contact with no sensor kinds recorded, or none in the last 3 s, counts
    as tracked.

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
