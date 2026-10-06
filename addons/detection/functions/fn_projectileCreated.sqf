/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_projectileCreated

Description:
    AEGIS-M's catch for munitions nothing reported fired: the server's
    "ProjectileCreated" mission event (Arma 3 2.18), which comes for every
    projectile however it was made. Munitions are otherwise found through
    each shooter's "Fired" event (aegism_detect_fnc_firedEventHandler),
    which misses two kinds:
        - a shell spawned by script (createVehicle: Zeus ordnance, a
          mission's artillery effects), which nobody fired;
        - one from a shooter whose Fired event handlers another mod removed
          (removeAllEventHandlers).
    A threat-class munition (aegism_detect_fnc_ammoThreatInfo; a bullet
    returns after that one cached lookup) is looked at the next frame: one
    the Fired path has handled by then is marked ("AEGISM_seen", aegism_
    detect_fnc_watchProjectile), and anything else is tracked here, from
    its shot parents -- a shell with none has no side (sideUnknown): never
    hostile by IFF, so it's engaged as a friendly round would be, only if
    it threatens a Site (doctrine: Engage Friendly Threats). Logged once
    per ammo type (MUNITION-UNREPORTED).

    The event handler is put back if something removes it (aegism_system_
    fnc_guardSystems).

Parameters:
    _projectile - the new projectile <OBJECT>

Returns:
    Nothing

Examples:
    addMissionEventHandler ["ProjectileCreated", { _this call aegism_detect_fnc_projectileCreated; }];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_projectile"];

if (isNull _projectile) exitWith {};
([typeOf _projectile] call aegism_detect_fnc_ammoThreatInfo) params ["_class", "_isCarrier"];
if (_class == "" && {!_isCarrier}) exitWith {};
if ((missionNamespace getVariable ["AEGISM_allPoolOwners", []]) isEqualTo []) exitWith {};

[{
    params ["_projectile"];
    if (isNull _projectile || {!alive _projectile} || {_projectile getVariable ["AEGISM_seen", false]}) exitWith {};
    (getShotParents _projectile) params [["_vehicle", objNull], ["_instigator", objNull]];
    private _shooter = [_vehicle, _instigator] select (isNull _vehicle);
    private _side = [side _shooter, sideUnknown] select (isNull _shooter);
    if (!isNull _shooter && {!isNil { _shooter getVariable "AEGISM_system" }}) then { _projectile setVariable ["AEGISM_fromSystem", true]; };
    private _logged = missionNamespace getVariable ["AEGISM_unreportedLogged", createHashMap];
    if !((typeOf _projectile) in _logged) then {
        _logged set [typeOf _projectile, true];
        missionNamespace setVariable ["AEGISM_unreportedLogged", _logged];
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " MUNITION-UNREPORTED: %1 appeared with no Fired event -- %2. Tracked anyway (logged once per ammo type).",
            typeOf _projectile,
            if (isNull _shooter) then { "nothing fired it (spawned by a script: Zeus ordnance, a mission's effects); no side, so engaged only if it threatens a Site" } else {
                format ["fired by %1 (%2, %3), whose Fired event handlers something removed", _shooter, typeOf _shooter, _side]
            }];
    };
    [_projectile, _side] call aegism_detect_fnc_watchProjectile;
}, [_projectile]] call CBA_fnc_execNextFrame;
