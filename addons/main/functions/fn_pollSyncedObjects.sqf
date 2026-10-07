/* ----------------------------------------------------------------------------
Function: aegism_fnc_pollSyncedObjects

Description:
    Live-resync helper for AEGIS-M's modules: watches a placed module's
    synced objects, so one synced or unsynced after its init is handled.
    Full notes: docs/functions/main.md

Parameters:
    _logic - the module logic object to poll synchronizedObjects on <OBJECT>
    _applyFn - code called as [_object, _data] for each object newly
        present in synchronizedObjects <CODE>
    _clearFn - code called as [_object, _data] for each object newly absent
        from synchronizedObjects <CODE>
    _data - arbitrary value passed through to _applyFn/_clearFn each time
        (an object/HashMap reference stays valid indefinitely; use this
        rather than a closure-captured private) <ANY>
    _interval - seconds between polls <NUMBER>
    _onDeletedFn - code called as [_logic, _logicNetId] once if _logic
        becomes null, or {} for no cleanup action -- _logicNetId is
        captured as a string before _logic could go null, since a null
        object reference no longer formats to anything identifying (e.g.
        for a diag_log message naming which instance was deleted) <CODE>

Returns:
    Nothing

Examples:
    [_logic, {params ["_o","_d"]; _o setVariable ["AEGISM_engagement", _d, false];}, {params ["_o","_d"]; _o setVariable ["AEGISM_engagement", nil, false];}, _engagementData, 5, {}] call aegism_fnc_pollSyncedObjects;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_logic", "_applyFn", "_clearFn", "_data", "_interval", "_onDeletedFn"];

if (!isServer) exitWith {};
if (isNull _logic) exitWith {};

private _logicNetId = str (netId _logic);

[{
    params ["_args", "_pfhHandle"];
    _args params ["_logic", "_applyFn", "_clearFn", "_data", "_onDeletedFn", "_logicNetId", "_prevUnits"];

    if (isNull _logic) exitWith {
        [_logic, _logicNetId] call _onDeletedFn;
        [_pfhHandle] call CBA_fnc_removePerFrameHandler;
    };

    private _currentUnits = synchronizedObjects _logic;

    { if !(_x in _prevUnits) then { [_x, _data] call _applyFn; } } forEach _currentUnits;
    { if !(_x in _currentUnits) then { [_x, _data] call _clearFn; } } forEach _prevUnits;

    _args set [6, _currentUnits];
}, _interval, [_logic, _applyFn, _clearFn, _data, _onDeletedFn, _logicNetId, synchronizedObjects _logic]] call CBA_fnc_addPerFrameHandler;
