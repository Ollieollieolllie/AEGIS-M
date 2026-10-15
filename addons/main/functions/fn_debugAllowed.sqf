/* ----------------------------------------------------------------------------
Function: aegism_fnc_debugAllowed

Description:
    Whether the server sends its debug views to a machine: the CBA setting
    Debug Views for Clients (Nobody, Admins and Zeus, Everyone). Server only.
    Full notes: docs/functions/main.md

Parameters:
    _owner - the machine's owner ID (remoteExecutedOwner) <NUMBER>

Returns:
    [allowed, why not (structured-text-safe; "" if allowed)] <ARRAY>

Examples:
    ([remoteExecutedOwner] call aegism_fnc_debugAllowed) params ["_allowed", "_why"];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_owner"];

// This machine: its own views read the pipeline directly.
if (!isMultiplayer || {_owner in [0, clientOwner]}) exitWith { [true, ""] };

switch (missionNamespace getVariable ["aegism_main_debugClients", 1]) do {
    case 2: { [true, ""] };
    case 1: {
        private _zeus = (allCurators findIf {
            private _unit = getAssignedCuratorUnit _x;
            !isNull _unit && {owner _unit == _owner}
        }) != -1;
        if ((admin _owner) > 0 || {_zeus}) then { [true, ""] } else {
            [false, "The server sends the AEGIS-M debug views only to a logged-in admin or a Zeus (CBA setting AEGIS-M > Debug > Debug Views for Clients)."]
        }
    };
    default { [false, "The server doesn't send the AEGIS-M debug views to anyone (CBA setting AEGIS-M > Debug > Debug Views for Clients)."] };
}
