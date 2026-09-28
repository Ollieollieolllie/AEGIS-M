/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_firedEventHandler

Description:
    CBA_fnc_addClassEventHandler "Fired" callback, registered globally
    (see XEH_preInit.sqf) rather than per-System: a single mission may fire
    many munitions per second, and per-System registration of the same
    class-EH repeatedly would multiply callbacks. Classifies the fired
    projectile and, if it's a real munition class (missile/rocket/bomb/
    artillery shell -- classifyTarget returns "" for anything else, e.g.
    plain bullets), spawns a per-munition tracker (aegism_detect_fnc_
    trackMunition) via CBA_fnc_addPerFrameHandler. The tracker itself is
    what actually pushes the contact into each nearby pool.

    Server-only (isServer): the tracker mutates AEGISM_pooledContacts,
    which only the server's engagement loop ever reads (see aegism_system_
    fnc_moduleInit) -- running this pipeline on clients too would waste
    CPU tracking munitions no local loop will ever act on.

Parameters:
    _unit - the firing unit or vehicle <OBJECT>
    _weapon - fired weapon classname <STRING>
    _muzzle - fired muzzle classname <STRING>
    _mode - fired weapon mode <STRING>
    _ammo - fired ammo classname <STRING>
    _magazine - fired magazine classname <STRING>
    _projectile - the spawned projectile object <OBJECT>

Returns:
    Nothing

Examples:
    (params of a CBA "Fired" class event handler) call aegism_detect_fnc_firedEventHandler;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_MUNITION_LOG_INTERVAL 10

params ["_unit", "", "", "", "_ammo", "", "_projectile"];

if (!isServer) exitWith {};
if (isNull _projectile) exitWith {};

// An AEGIS-M System's own interceptors are never friendly threats (the
// friendly-munition check would otherwise evaluate every outgoing SAM). They
// stay trackable by a HOSTILE side's radars (e.g. an opposing AEGIS-M
// battery), so they're only tagged, not skipped.
if (_unit in (missionNamespace getVariable ["AEGISM_allSystems", []])) then {
    _projectile setVariable ["AEGISM_fromSystem", true];
};

// Side captured now, while the shooter certainly exists: the tracker uses it
// for IFF -- a hostile side's munitions are tracked outright, a friendly or
// neutral one's only while predicted to hit the Site (doctrine
// engageFriendlyThreats). aegism_detect_fnc_watchProjectile also follows
// submunition handoffs (e.g. an MLRS rocket's carrier releasing the rocket).
private _shooterSide = side _unit;
private _class = [_projectile, _shooterSide] call aegism_detect_fnc_watchProjectile;
if (_class == "") exitWith {};

// One line per shooter per AEGISM_MUNITION_LOG_INTERVAL (a barrage would
// otherwise log every round), stating the IFF outcome. Not for AEGIS-M's own
// interceptors -- their FIRE lines already cover them.
if (!(_projectile getVariable ["AEGISM_fromSystem", false]) && {time > (_unit getVariable ["AEGISM_munitionLogAt", -1e9]) + AEGISM_MUNITION_LOG_INTERVAL}) then {
    _unit setVariable ["AEGISM_munitionLogAt", time];
    private _hostileRadars = {
        private _system = _x getVariable "AEGISM_system";
        !isNil "_system" && {_system getOrDefault ["hasRadar", false]} && {[side _x, _shooterSide] call aegism_detect_fnc_isHostile}
    } count (missionNamespace getVariable ["AEGISM_allPoolOwners", []]);
    diag_log text format ["[AEGIS-M] MUNITION: %1 (%2) fired %3 (%4) -- %5", _unit, _shooterSide, _ammo, _class,
        [format ["%1 AEGIS-M radar(s) hostile to %2 will track it when in range and line of sight.", _hostileRadars, _shooterSide],
         format ["no AEGIS-M radar is hostile to %1 (IFF: friendly) -- tracked and engaged only if predicted to hit a Site whose doctrine engages friendly threats (see FRIENDLY-THREAT).", _shooterSide]] select (_hostileRadars == 0)];
};
