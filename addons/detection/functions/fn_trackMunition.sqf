/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_trackMunition

Description:
    Attaches a per-frame tracker to a freshly-fired, already-classified
    munition. Each tick, the tracker locates every AEGIS-M pool owner
    (System with its own Radar role, or Network) within that pool owner's
    scaled radar detection range and pushes/refreshes the munition as a
    full-confidence contact via aegism_detect_fnc_addContact (rejected
    silently if not on that pool owner's allowlist). Removes itself and
    calls aegism_detect_fnc_removeContact on every pool it added to once
    the munition is destroyed, lands, or leaves simulation.

    Pool owners are looked up via the global "AEGISM_allPoolOwners" list
    maintained by aegism_system_fnc_moduleInit / aegism_network_fnc_
    moduleInit (see XEH_preInit.sqf registration) rather than an
    every-tick nearestObjects scan for module logics.

Parameters:
    _projectile - the fired munition object <OBJECT>
    _class - pre-classified target class, from aegism_detect_fnc_
        classifyTarget <STRING>

Returns:
    Nothing

Examples:
    [_projectile, "missile"] call aegism_detect_fnc_trackMunition;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_projectile", "_class"];

private _addedTo = [];

private _handle = [{
    params ["_args", "_pfhHandle"];
    _args params ["_projectile", "_class", "_addedTo"];

    if (isNull _projectile || {!alive _projectile}) exitWith {
        {
            [_x, _projectile] call aegism_detect_fnc_removeContact;
        } forEach _addedTo;
        [_pfhHandle] call CBA_fnc_removePerFrameHandler;
    };

    private _pos = getPosASL _projectile;
    {
        private _poolOwner = _x;
        private _system = _poolOwner getVariable "AEGISM_system";
        private _range = if (isNil "_system") then {
            8000
        } else {
            [_system getOrDefault ["radarDetectionRange", 4000]] call aegism_fnc_scaledRange
        };

        if ((_poolOwner distance2D _projectile) <= _range) then {
            private _added = [_poolOwner, _projectile, _class, 1] call aegism_detect_fnc_addContact;
            if (_added && {!(_poolOwner in _addedTo)}) then {
                _addedTo pushBack _poolOwner;
            };
        };
    } forEach (missionNamespace getVariable ["AEGISM_allPoolOwners", []]);
}, 0.5, [_projectile, _class, _addedTo]] call CBA_fnc_addPerFrameHandler;
