/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_confidenceLoop

Description:
    Interval-based (not true per-frame, for performance) scan run once per
    pool owner (System with real native radar/sensor capability, or
    Network) that reads the vehicle's OWN native sensor detections via
    getSensorTargets -- the engine's own radar/IR/visual/datalink
    simulation, already running against that vehicle's real CfgVehicles
    Turrets/Sensors config -- rather than AEGIS-M re-implementing its own
    LOS/distance/confidence estimate on top of it. Detection is binary here
    (the engine already decided detected-or-not using its own, more
    complete simulation); every allowlisted, non-friendly, non-destroyed
    sensor target is pooled at full confidence, and anything previously
    pooled that no longer appears in this tick's sensor targets (out of
    range, behind terrain, destroyed, radar switched off, ...) is removed.

    This single pipeline covers both platforms (aircraft/helicopters/
    drones) and munitions (missiles/rockets/shells in flight) uniformly --
    a fired projectile is a real object the same native sensor simulation
    detects, exactly how vanilla Arma's own CIWS-capable vehicles (e.g. the
    Praetorian) already auto-engage incoming rockets under the hood. There
    is no separate global "Fired" event handler pipeline anymore.

    A detected contact is added/removed on both the scanning System's own
    pool AND its Network's pool (if synced), so a Launcher/CIWS-only System
    with no radar of its own, relying purely on a Network's shared
    contacts, still sees everything a radar-equipped sibling detects.

Parameters:
    _poolOwner - the System vehicle (with real native radar/sensor
        capability) or Network logic to scan around <OBJECT>

Returns:
    Nothing (intended to be wrapped in a CBA_fnc_addPerFrameHandler by the
    caller, which supplies the recurring interval)

Examples:
    [_radarTruck] call aegism_detect_fnc_confidenceLoop;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_poolOwner"];

if (isNull _poolOwner) exitWith {};

private _system = _poolOwner getVariable "AEGISM_system";
if (isNil "_system") exitWith {}; // Network itself has no sensor -- its detections come from member Systems' own loops
if !(_system get "hasRadar") exitWith {};

private _engagementSettings = _poolOwner getVariable "AEGISM_resolvedEngagementSettings";
if (isNil "_engagementSettings") then { _engagementSettings = [_poolOwner] call aegism_system_fnc_resolveEngagementSettings; };
private _allowlist = _engagementSettings getOrDefault ["targetClassAllowlist", []];
private _network = _poolOwner getVariable ["AEGISM_network", objNull];

private _detectedKeys = [];

{
    _x params ["_target", "", "_relationship"];

    if (_relationship != "friendly" && {_relationship != "destroyed"} && {!isNull _target} && {alive _target}) then {
        private _class = [_target] call aegism_detect_fnc_classifyTarget;

        if (_class in _allowlist) then {
            [_poolOwner, _target, _class, 1] call aegism_detect_fnc_addContact;
            if (!isNull _network) then {
                [_network, _target, _class, 1] call aegism_detect_fnc_addContact;
            };
            _detectedKeys pushBack (str (netId _target));
        };
    };
} forEach (getSensorTargets _poolOwner);

// Anything still pooled from a previous tick but absent from this tick's
// sensor targets is no longer detected (out of range/arc, behind terrain,
// destroyed, radar off, ...) and gets dropped from both pools.
private _pool = _poolOwner getVariable ["AEGISM_pooledContacts", createHashMap];
{
    if !(_x in _detectedKeys) then {
        private _obj = (_pool get _x) get "object";
        [_poolOwner, _obj] call aegism_detect_fnc_removeContact;
        if (!isNull _network) then {
            [_network, _obj] call aegism_detect_fnc_removeContact;
        };
    };
} forEach (keys _pool);
