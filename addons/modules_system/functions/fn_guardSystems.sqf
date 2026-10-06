/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_guardSystems

Description:
    Keeps what AEGIS-M has set on its vehicles set, against other mods'
    scripts and the game itself. Every machine, every couple of seconds
    (this addon's XEH_postInit, with the discovery scan):

    The crew's own targeting and firing on every AEGIS-M weapon turret (off
    since AEGIS-M took it, aegism_fnc_setWeaponAiSuppressed): a gunner here
    -- where it's simulated -- with AUTOTARGET or FIREWEAPON back on is set
    off again. Another mod's AI script can turn them on (enableAI), and a
    crewman new to the seat (a replacement, a Zeus swap) never had them
    off: either way the crew would pick its own targets and fire them,
    outside AEGIS-M (UNCOMMANDED-FIRE). "TARGET" is left alone: AEGIS-M
    turns it on itself while a gunner holds a lock (aegism_intercept_fnc_
    gunnerLock). Logged once per gunner (AI-RESTORED). A player gunner is
    never touched.

    On the server, each armed vehicle's Fired handler (aegism_intercept_fnc_
    firedHandler): there from its first look, before AEGIS-M has fired it, so
    a shot it fires by itself is seen (UNCOMMANDED-FIRE); and AEGIS-M's
    mission-wide catch for munitions nothing reported fired (aegism_detect_
    fnc_projectileCreated). Either is re-added if something removed it
    (logged, EH-RESTORED).

    The list is the vehicles this machine set up ("AEGISM_guardedSystems",
    aegism_system_fnc_moduleInit); gone ones are dropped.

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
