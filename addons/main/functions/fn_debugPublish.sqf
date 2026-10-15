/* ----------------------------------------------------------------------------
Function: aegism_fnc_debugPublish

Description:
    Sends the 3D debug overlay (aegism_fnc_debugModel) to every client that
    has asked for it in the last few seconds (aegism_fnc_debugRequest). Run
    on the server every half second; nothing is worked out while none has.
    Full notes: docs/functions/main.md

Parameters:
    None

Returns:
    Nothing

Examples:
    [{ [] call aegism_fnc_debugPublish; }, 0.5, []] call CBA_fnc_addPerFrameHandler;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

// A client not heard from in this long has switched it off, or left, s (it
// asks once a second).
#define AEGISM_SUBSCRIBER_TIMEOUT 3

private _subscribers = missionNamespace getVariable ["AEGISM_debugSubscribers", createHashMap];
if (count _subscribers == 0) exitWith {};

private _gone = [];
{ if (CBA_missionTime - _y > AEGISM_SUBSCRIBER_TIMEOUT || {CBA_missionTime < _y}) then { _gone pushBack _x; }; } forEach _subscribers;
{ _subscribers deleteAt _x; } forEach _gone;
if (count _subscribers == 0) exitWith {};

["draw", [] call aegism_fnc_debugModel] remoteExecCall ["aegism_fnc_debugReceive", keys _subscribers];
