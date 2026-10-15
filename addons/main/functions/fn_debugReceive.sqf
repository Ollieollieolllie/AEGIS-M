/* ----------------------------------------------------------------------------
Function: aegism_fnc_debugReceive

Description:
    A client's end of the debug views: what the server sends it (aegism_fnc_
    debugRequest, aegism_fnc_debugPublish).
    Full notes: docs/functions/main.md

Parameters:
    _kind - "hint" (the status board), "draw" (the 3D overlay's model), or
        "denied" (why the server sends neither) <STRING>
    _data - the board's structured text, the model, or why <ANY>

Returns:
    Nothing

Examples:
    ["hint", _board] remoteExecCall ["aegism_fnc_debugReceive", _owner];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_kind", "_data"];

// Only the server's.
if (isMultiplayer && {remoteExecutedOwner != 2}) exitWith {};

switch (_kind) do {
    case "hint": {
        if ("aegism_main_debugHint" call CBA_settings_fnc_get) then {
            missionNamespace setVariable ["AEGISM_debugHintAt", CBA_missionTime];
            missionNamespace setVariable ["AEGISM_debugHintShown", true];
            hintSilent parseText _data;
        };
    };
    case "draw": {
        missionNamespace setVariable ["AEGISM_debugModel", _data];
    };
    case "denied": {
        missionNamespace setVariable ["AEGISM_debugModel", []];
        if ("aegism_main_debugHint" call CBA_settings_fnc_get) then {
            missionNamespace setVariable ["AEGISM_debugHintAt", CBA_missionTime];
            missionNamespace setVariable ["AEGISM_debugHintShown", true];
            hintSilent parseText format ["<t size='1.2' font='PuristaBold' color='#4FC3F7'>AEGIS-M</t><br/><t size='0.85' color='#FFA726'>%1</t>", _data];
        };
        if !(missionNamespace getVariable ["AEGISM_debugDeniedSaid", false]) then {
            missionNamespace setVariable ["AEGISM_debugDeniedSaid", true];
            systemChat ("AEGIS-M: " + _data);
        };
    };
};
