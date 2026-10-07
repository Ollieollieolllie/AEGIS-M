/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_firedEventHandler

Description:
    CBA_fnc_addClassEventHandler "Fired" callback, registered once on the
    server for every unit and vehicle (see XEH_preInit.sqf).
    Full notes: docs/functions/detection.md

Parameters:
    _unit - the firing unit or vehicle <OBJECT>
    _weapon - fired weapon classname <STRING>
    _muzzle - fired muzzle classname <STRING>
    _mode - fired weapon mode <STRING>
    _ammo - fired ammo classname <STRING>
    _magazine - fired magazine classname <STRING>
    _projectile - the spawned projectile <OBJECT>

Returns:
    Nothing

Examples:
    (params of a CBA "Fired" class event handler) call aegism_detect_fnc_firedEventHandler;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\perf.hpp"
#include "..\..\main\rpt.hpp"

#define AEGISM_MUNITION_LOG_INTERVAL 10

params ["_unit", "", "", "", "_ammo", "", "_projectile"];

PERF_INC(PERF_FIRED_EH);

([_ammo] call aegism_detect_fnc_ammoThreatInfo) params ["_class", "_isCarrier"];
if (_class == "" && {!_isCarrier}) exitWith {};
if (isNull _projectile) exitWith {};
if ((missionNamespace getVariable ["AEGISM_allPoolOwners", []]) isEqualTo []) exitWith {};

PERF_INC(PERF_FIRED_THREATS);

private _fromSystem = !isNil { _unit getVariable "AEGISM_system" };
if (_fromSystem) then { _projectile setVariable ["AEGISM_fromSystem", true]; };

// Side captured now, while the shooter certainly exists: the tracker uses it
// for IFF -- a hostile side's munitions are tracked outright, a friendly or
// neutral one's only while predicted to hit the Site (doctrine
// engageFriendlyThreats). aegism_detect_fnc_watchProjectile also follows
// submunition handoffs (e.g. an MLRS rocket's carrier releasing the rocket).
private _shooterSide = side _unit;
[_projectile, _shooterSide, _class, _isCarrier] call aegism_detect_fnc_watchProjectile;
if (_class == "") exitWith {};

// One line per shooter per AEGISM_MUNITION_LOG_INTERVAL (a barrage would
// otherwise log every round), stating the IFF outcome. Not for AEGIS-M's own
// interceptors -- their FIRE lines already cover them.
if (!_fromSystem && {CBA_missionTime > (_unit getVariable ["AEGISM_munitionLogAt", -1e9]) + AEGISM_MUNITION_LOG_INTERVAL}) then {
    _unit setVariable ["AEGISM_munitionLogAt", CBA_missionTime];
    private _hostileWatchers = {
        !isNil { _x getVariable "AEGISM_system" } && {[side _x, _shooterSide] call aegism_detect_fnc_isHostile}
    } count (missionNamespace getVariable ["AEGISM_allPoolOwners", []]);
    if (AEGISM_RPT_VERBOSE) then {
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " MUNITION: %1 (%2) fired %3 (%4) -- %5", _unit, _shooterSide, _ammo, _class,
            [format ["%1 AEGIS-M sensor vehicle(s) hostile to %2 will track it once their sensors see it.", _hostileWatchers, _shooterSide],
             format ["no AEGIS-M sensor vehicle is hostile to %1 (IFF: friendly) -- tracked and engaged only if predicted to hit a Site whose doctrine engages friendly threats (see FRIENDLY-THREAT).", _shooterSide]] select (_hostileWatchers == 0)];
    };
};
