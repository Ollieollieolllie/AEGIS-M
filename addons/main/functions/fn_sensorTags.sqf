/* ----------------------------------------------------------------------------
Function: aegism_fnc_sensorTags

Description:
    Short tags for the sensor kinds that saw a contact recently, for the
    debug overlays: a pool entry's "sources" (aegism_detect_fnc_addContact
    -- sensor kind -> when it last saw it), keeping those within the pools'
    own contact expiry (3 s, aegism_detect_fnc_pruneStaleContacts).

        activeradar RDR, passiveradar PAS, ir IR, visual VIS, datalink DL;
        any other kind the engine reports, upper case.

Parameters:
    _sources - sensor kind -> time last seen <HASHMAP>

Returns:
    e.g. "RDR IR", or "" if none <STRING>

Examples:
    [_entry getOrDefault ["sources", createHashMap]] call aegism_fnc_sensorTags;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_SOURCE_WINDOW 3

params ["_sources"];

private _names = createHashMapFromArray [["activeradar", "RDR"], ["passiveradar", "PAS"], ["ir", "IR"], ["visual", "VIS"], ["datalink", "DL"]];
private _tags = [];
{
    if (CBA_missionTime - _y <= AEGISM_SOURCE_WINDOW) then { _tags pushBackUnique (_names getOrDefault [_x, toUpper _x]); };
} forEach _sources;
_tags sort true;
_tags joinString " "
