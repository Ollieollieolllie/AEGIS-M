/* ----------------------------------------------------------------------------
Function: aegism_fnc_pollSyncedObjects

Description:
    Generic live-resync helper for AEGIS-M's push-model modules
    (EngagementSettings, Crew, Network): a placed module's own init
    function runs exactly once, at its own activation, and pushes its data
    to whatever is synced to it AT THAT MOMENT -- a sync line drawn or
    erased afterward (e.g. a Zeus operator re-syncing an EngagementSettings
    module to an additional System mid-mission) does not re-trigger that
    init function, since nothing new is being activated. Nothing in vanilla
    Arma raises an event for a sync-graph change either, so the only way to
    detect one is to poll synchronizedObjects, which always reflects the
    CURRENT live graph regardless of when a link was drawn.

    Registers a low-frequency, server-only per-frame handler (mirroring
    every other AEGIS-M loop's isServer gating, see aegism_system_fnc_
    moduleInit) that diffs _logic's synchronizedObjects against last poll's
    set: _applyFn runs once for each newly-synced object, _clearFn once for
    each newly-unsynced one. Both are called with explicit arguments rather
    than relying on closure capture of the caller's private variables --
    correct here, since the code runs from a later, separate PFH tick after
    the calling script has already returned, by which point any of its
    privates are gone; only what's threaded through _data (or bound into
    _applyFn/_clearFn's own call arguments) survives to reach them.

    If _logic itself is deleted (e.g. a Zeus operator deletes a Network mid-
    mission), _onDeletedFn is called once and the handler removes itself.

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
}, _interval, [_logic, _applyFn, _clearFn, _data, _onDeletedFn, _logicNetId, []]] call CBA_fnc_addPerFrameHandler;
