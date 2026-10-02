/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_trackMunition

Description:
    Starts tracking a freshly-fired, already-classified munition, and gives
    it a sensor proxy so the game's own sensors can see it.

    Gives the munition its own contact key ("AEGISM_contactKey" = "m<n>", see
    aegism_fnc_contactKey) and adds it to the list the single munition
    tracker works through (aegism_detect_fnc_munitionTracker: every tracked
    munition checked every AEGISM_TRACK_INTERVAL s, spread over frames by
    fire time). What a check does (seen by a sensor, IFF, whether it
    threatens a Site): aegism_detect_fnc_munitionCheck.

    The proxy: a fired projectile can't be a sensor target itself (CfgAmmo
    has no radar/IR/visual target properties), so an invisible vehicle of
    its threat class's proxy type ("AEGISM_MunitionProxy_<class>", detection
    config.cpp) flies with it, attached a few metres behind it -- created
    AEGISM_PROXY_DELAY s after launch, clear of the launching vehicle
    (aegism_detect_fnc_proxyCreate), moved every frame instead for an ammo
    class that doesn't carry an attached object -- and is deleted with it
    (aegism_detect_fnc_munitionTracker). Every vehicle's sensors then see
    it, or don't, by their own rules; the detection loop (aegism_detect_
    fnc_confidenceLoop) reads which munitions each vehicle sees.

    Local to the server: no network traffic for something that moves every
    frame, but only sensors simulated on the server see it -- a vehicle
    whose crew is simulated elsewhere (a headless client, a player gunner)
    doesn't. No proxy for an AEGIS-M System's own interceptor unless some
    AEGIS-M vehicle is hostile to the side that fired it: nobody else would
    track it, and every sensor around would carry it as a contact.

Parameters:
    _projectile - the fired munition object <OBJECT>
    _class - pre-classified target class, from aegism_detect_fnc_
        classifyTarget <STRING>
    _shooterSide - side of the unit/vehicle that fired it <SIDE>

Returns:
    Nothing

Examples:
    [_projectile, "missile", east] call aegism_detect_fnc_trackMunition;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\proxy.hpp"

params ["_projectile", "_class", ["_shooterSide", sideUnknown]];

private _sequence = (missionNamespace getVariable ["AEGISM_munitionSeq", 0]) + 1;
missionNamespace setVariable ["AEGISM_munitionSeq", _sequence];
private _key = "m" + str _sequence;
_projectile setVariable ["AEGISM_contactKey", _key];

private _tracked = missionNamespace getVariable "AEGISM_trackedMunitions";
if (isNil "_tracked") then {
    _tracked = [];
    missionNamespace setVariable ["AEGISM_trackedMunitions", _tracked];
};

private _watched = !(_projectile getVariable ["AEGISM_fromSystem", false]) || {
    ((missionNamespace getVariable ["AEGISM_allPoolOwners", []]) findIf {
        !isNil { _x getVariable "AEGISM_system" } && {[side _x, _shooterSide] call aegism_detect_fnc_isHostile}
    }) != -1
};

// [projectile, class, shooter side, key, pools it's in, next check at,
// sensor proxy (objNull until it's made, or if none), flags (HashMap)].
// Flags "follow": its proxy is moved every frame; "attachCheckAt": when to
// check its proxy came along when attached.
private _entry = [_projectile, _class, _shooterSide, _key, [], time, objNull, createHashMap];
_tracked pushBack _entry;

if (_watched) then {
    [aegism_detect_fnc_proxyCreate, [_entry], AEGISM_PROXY_DELAY] call CBA_fnc_waitAndExecute;
};

if !(missionNamespace getVariable ["AEGISM_munitionTrackerRunning", false]) then {
    missionNamespace setVariable ["AEGISM_munitionTrackerRunning", true];
    [{
        params ["", "_pfhHandle"];
        if !([] call aegism_detect_fnc_munitionTracker) then {
            [_pfhHandle] call CBA_fnc_removePerFrameHandler;
            missionNamespace setVariable ["AEGISM_munitionTrackerRunning", false];
        };
    }, 0, []] call CBA_fnc_addPerFrameHandler;
};
