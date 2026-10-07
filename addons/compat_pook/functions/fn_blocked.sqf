/* ----------------------------------------------------------------------------
Function: (every POOK function this addon switches off)

Description:
    Does nothing, in place of one of POOK's scripts that would aim, fire or
    fuse a vehicle's weapons itself (this addon's config.cpp points POOK's
    own CfgFunctions entries at this file).
    Full notes: docs/functions/compat_pook.md

Parameters:
    Whatever POOK's event handler passes (ignored)

Returns:
    Nothing

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

// The functions library names each function to itself as it's compiled.
private _name = if (isNil "_fnc_scriptName") then { "a POOK script" } else { _fnc_scriptName };
private _logged = missionNamespace getVariable ["AEGISM_compatPookLogged", createHashMap];
if !(_name in _logged) then {
    _logged set [_name, true];
    missionNamespace setVariable ["AEGISM_compatPookLogged", _logged];
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " COMPAT: POOK's %1 is switched off while AEGIS-M's POOK compatibility is loaded -- it works vehicles' weapons itself (logged once).", _name];
};
