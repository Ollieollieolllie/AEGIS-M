/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_firedEventHandler

Description:
    CBA_fnc_addClassEventHandler "Fired" callback, registered once on the
    server for every unit and vehicle (see XEH_preInit.sqf). Hands every
    threat-class munition (missile/rocket/bomb/artillery shell) or carrier
    to aegism_detect_fnc_watchProjectile, which starts tracking it.

    This runs for every round fired in the mission, so the first thing it
    does is the cached ammo lookup (aegism_detect_fnc_ammoThreatInfo): a
    bullet returns after that one lookup. It also returns straight away in
    a mission with no AEGIS-M radar or Site at all.

    An AEGIS-M System's own interceptors are tagged "AEGISM_fromSystem"
    (never friendly threats; a HOSTILE side's radars still track them).

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
if (!_fromSystem && {time > (_unit getVariable ["AEGISM_munitionLogAt", -1e9]) + AEGISM_MUNITION_LOG_INTERVAL}) then {
    _unit setVariable ["AEGISM_munitionLogAt", time];
    private _hostileRadars = {
        private _system = _x getVariable "AEGISM_system";
        !isNil "_system" && {(_system getOrDefault ["munitionSensors", []]) isNotEqualTo []} && {[side _x, _shooterSide] call aegism_detect_fnc_isHostile}
    } count (missionNamespace getVariable ["AEGISM_allPoolOwners", []]);
    diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " MUNITION: %1 (%2) fired %3 (%4) -- %5", _unit, _shooterSide, _ammo, _class,
        [format ["%1 AEGIS-M radar/IR vehicle(s) hostile to %2 will track it when in range and line of sight.", _hostileRadars, _shooterSide],
         format ["no AEGIS-M radar/IR vehicle is hostile to %1 (IFF: friendly) -- tracked and engaged only if predicted to hit a Site whose doctrine engages friendly threats (see FRIENDLY-THREAT).", _shooterSide]] select (_hostileRadars == 0)];
};
