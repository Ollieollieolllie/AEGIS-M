/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_detonate

Description:
    Sets off a projectile where it is (triggerAmmo), here and on every other
    machine: each one flies its own copy of a shell or a rocket.
    Full notes: docs/functions/detection.md

Parameters:
    _projectile - the projectile <OBJECT>
    _dropPayload - also delete what it releases as it goes off (a carrier
        round's warhead) <BOOLEAN, default false>

Returns:
    Nothing

Examples:
    [_missile] call aegism_detect_fnc_detonate;
    [_mlrsRocket, true] call aegism_detect_fnc_detonate;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_projectile", ["_dropPayload", false]];

if (isNull _projectile || {!alive _projectile}) exitWith {};

private _ammo = typeOf _projectile;

// The other machines' copies, of the munitions they keep a list of
// (aegism_detect_fnc_projectileCopy): sent while it still has a position
// and a velocity to find them by.
if (isMultiplayer) then {
    ([_ammo] call aegism_detect_fnc_ammoThreatInfo) params ["_class", "_isCarrier"];
    if (_class != "" || {_isCarrier}) then {
        [_projectile, _ammo, (getShotParents _projectile) param [0, objNull], getPosASL _projectile, velocity _projectile, CBA_missionTime, _dropPayload]
            remoteExecCall ["aegism_detect_fnc_detonateCopy", -2];
    };
};

if (_dropPayload) then {
    _projectile addEventHandler ["SubmunitionCreated", {
        params ["", "_submunitionProjectile"];
        deleteVehicle _submunitionProjectile;
    }];
};
triggerAmmo _projectile;
