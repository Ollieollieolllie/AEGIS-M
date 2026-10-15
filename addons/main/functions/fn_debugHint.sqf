/* ----------------------------------------------------------------------------
Function: aegism_fnc_debugHint

Description:
    Live status board in the hint box, refreshed once a second while the CBA
    setting Site Status Hint is on. On a client, the server builds it and
    sends it (aegism_fnc_debugRequest).
    Full notes: docs/functions/main.md

Parameters:
    None

Returns:
    Nothing

Examples:
    [] call aegism_fnc_debugHint;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

// On a client: said to be waiting while nothing has come from the server in
// this long, s.
#define AEGISM_HINT_WAIT 3

if !("aegism_main_debugHint" call CBA_settings_fnc_get) exitWith {
    if (missionNamespace getVariable ["AEGISM_debugHintShown", false]) then {
        missionNamespace setVariable ["AEGISM_debugHintShown", false];
        hintSilent "";
    };
};
missionNamespace setVariable ["AEGISM_debugHintShown", true];

if (isServer) exitWith {
    hintSilent parseText ([positionCameraToWorld [0, 0, 0]] call aegism_fnc_debugBoard);
};

// A client: shown as it comes (aegism_fnc_debugReceive).
if (CBA_missionTime - (missionNamespace getVariable ["AEGISM_debugHintAt", -1e9]) > AEGISM_HINT_WAIT) then {
    hintSilent parseText "<t size='1.2' font='PuristaBold' color='#4FC3F7'>AEGIS-M</t><br/><t size='0.85' color='#90A4AE'>Asking the server for its status board...</t>";
};
