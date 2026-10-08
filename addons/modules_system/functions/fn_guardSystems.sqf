/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_guardSystems

Description:
    Keeps what AEGIS-M has set on its vehicles set, against other mods'
    scripts and the game itself.
    Full notes: docs/functions/modules_system.md

Parameters:
    None

Returns:
    Nothing

Examples:
    [] call aegism_system_fnc_guardSystems;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

private _guarded = missionNamespace getVariable ["AEGISM_guardedSystems", []];
private _gone = [];
{
    private _vehicle = _x;
    private _system = _vehicle getVariable "AEGISM_system";
    if (isNull _vehicle || {!alive _vehicle} || {isNil "_system"}) then {
        _gone pushBack _vehicle;
    } else {
        {
            private _gunner = _vehicle turretUnit (_x select 0);
            if (!isNull _gunner && {alive _gunner} && {local _gunner} && {!isPlayer _gunner}) then {
                private _on = ["AUTOTARGET", "FIREWEAPON"] select { _gunner checkAIFeature _x };
                if (_on isNotEqualTo []) then {
                    { _gunner disableAI _x; } forEach _on;
                    if !(_gunner getVariable ["AEGISM_aiRestoredLogged", false]) then {
                        _gunner setVariable ["AEGISM_aiRestoredLogged", true];
                        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " AI-RESTORED: %1 turret %2 -- its gunner %3 had its own %4 on (another mod's script, or a crewman new to the seat); off again, so it can't pick or fire on targets of its own (logged once per gunner).",
                            _vehicle, _x select 0, _gunner, _on joinString " and "];
                    };
                };
            };
        } forEach ((_system getOrDefault ["launcherWeapons", []]) + (_system getOrDefault ["ciwsWeapons", []]));
        if (isServer && {((_system getOrDefault ["launcherWeapons", []]) + (_system getOrDefault ["ciwsWeapons", []])) isNotEqualTo []}) then {
            [_vehicle] call aegism_intercept_fnc_firedHandler;
            // Infinite Ammo: every weapon it has is kept at what it carried,
            // fired or not -- so switching it on mid-mission refills the lot
            // (aegism_intercept_fnc_infiniteAmmo). Not a gun in the middle of
            // a burst, whose rounds are being counted (aegism_intercept_fnc_
            // ciwsBurst): its next burst starts topped up.
            if ((_vehicle getVariable ["AEGISM_resolvedEngagementSettings", createHashMap]) getOrDefault ["infiniteAmmo", false]) then {
                {
                    _x params ["_turretPath", "_weaponClass", "_magazineClass"];
                    private _burstEnds = ((([_vehicle, _turretPath] call aegism_intercept_fnc_turretState) getOrDefault ["burst", [-1]]) select 0);
                    if (CBA_missionTime >= _burstEnds) then {
                        [_vehicle, _turretPath, _magazineClass, _weaponClass] call aegism_intercept_fnc_infiniteAmmo;
                    };
                } forEach ((_system getOrDefault ["launcherWeapons", []]) + (_system getOrDefault ["ciwsWeapons", []]));
            };
        };
    };
} forEach _guarded;
if (_gone isNotEqualTo []) then {
    missionNamespace setVariable ["AEGISM_guardedSystems", _guarded - _gone];
};

if (isServer) then {
    private _id = missionNamespace getVariable ["AEGISM_projectileCreatedEH", -1];
    if (_id >= 0 && {!((getEventHandlerInfo ["ProjectileCreated", _id]) param [0, false])}) then {
        missionNamespace setVariable ["AEGISM_projectileCreatedEH", addMissionEventHandler ["ProjectileCreated", {
            _this call aegism_detect_fnc_projectileCreated;
        }]];
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " EH-RESTORED: AEGIS-M's ProjectileCreated mission event handler was removed (another mod's removeAllMissionEventHandlers?) -- added again."];
    };
};
