/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_gunnerLock

Description:
    Keeps a launcher turret's gunner locked on the aircraft it's assigned --
    as a real crew locks on before launch -- or lets go of it.
    Full notes: docs/functions/intercept.md

Parameters:
    _system - the launcher vehicle <OBJECT>
    _turretPath - the launcher's turret path <ARRAY>
    _target - its target, or objNull to let go <OBJECT>
    _weaponClass - the launcher's weapon, for its lock time <STRING, default "">

Returns:
    Seconds until the lock is complete; 0 when locked, or nothing to lock <NUMBER>

Examples:
    [_samSite, [0], _helicopter, "weapon_mim145Launcher"] call aegism_intercept_fnc_gunnerLock;
    [_samSite, [0], objNull] call aegism_intercept_fnc_gunnerLock;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\rpt.hpp"

params ["_system", "_turretPath", "_target", ["_weaponClass", ""]];

private _ts = [_system, _turretPath] call aegism_intercept_fnc_turretState;
private _gunner = _system turretUnit _turretPath;

private _wanted = _target;
if (!isNull _wanted && {([_wanted] call aegism_detect_fnc_classifyTarget) in ["missile", "rocket", "bomb", "artilleryShell"]}) then { _wanted = objNull; };

if (isNull _wanted) exitWith {
    if (!isNull (_ts getOrDefault ["lockTarget", objNull])) then {
        _ts set ["lockTarget", objNull];
        if (!isNull _gunner) then {
            _gunner doTarget objNull;
            _gunner disableAI "TARGET";
        };
    };
    0
};
if (isNull _gunner) exitWith { 0 };

if ((_ts getOrDefault ["lockTarget", objNull]) isNotEqualTo _wanted) then {
    _ts set ["lockTarget", _wanted];
    _ts set ["lockSince", CBA_missionTime];
    _gunner enableAI "TARGET";
    _gunner reveal [_wanted, 4];
    _gunner doTarget _wanted;
    if (AEGISM_RPT_VERBOSE) then {
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " LOCK-ON: %1 turret %2 -- gunner %3 locking %4 (%5), %6m; %7 s to lock.", _system, _turretPath, _gunner, _wanted, typeOf _wanted, round (_system distance _wanted),
            getNumber (configFile >> "CfgWeapons" >> _weaponClass >> "weaponLockDelay")];
    };
};

((_ts get "lockSince") + getNumber (configFile >> "CfgWeapons" >> _weaponClass >> "weaponLockDelay") - CBA_missionTime) max 0
