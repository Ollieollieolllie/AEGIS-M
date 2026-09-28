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

    This is the platform half of AEGIS-M's hybrid detection model --
    aircraft/helicopters/drones are real CfgVehicles objects with genuine
    radarTargetSize/irTargetSize/visualTargetSize properties, so
    getSensorTargets detects them correctly. It does NOT cover munitions:
    a fired CfgAmmo projectile has none of those target-size properties
    (confirmed against vanilla CfgAmmo, which never defines them either),
    so it is never itself a valid getSensorTargets result regardless of
    range/LOS/radar state. Munitions
    are detected by a separate, dedicated pipeline instead (aegism_detect_
    fnc_trackMunition, driven by a global "Fired" event handler) -- see
    that function's doc comment for why this has to be a hybrid rather than
    getSensorTargets covering both uniformly.

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
        } else {
            // Change-only per [poolOwner, target] pair (a HashMap on the
            // pool owner itself, cleared when the contact eventually leaves
            // sensor range entirely) -- a real sensor detection that never
            // makes it into the pool at all is otherwise completely
            // invisible: nothing else ever logs "saw something, didn't pool
            // it", so a class that SHOULD be allowlisted (e.g. fixedWing,
            // on by default) silently classifying as something else, or
            // the allowlist itself being wrong, would look identical to
            // "never detected at all" with no way to tell them apart from
            // the RPT alone. Logged once per contact rather than every
            // tick it's rejected, since a lingering non-allowlisted
            // contact (e.g. a friendly plane briefly misread as hostile by
            // getSensorTargets) would otherwise spam the RPT for as long
            // as it stays in sensor range.
            private _rejectKey = str (netId _target);
            private _rejectLog = _poolOwner getVariable ["AEGISM_lastDetectReject", createHashMap];
            if (!(_rejectKey in _rejectLog)) then {
                _rejectLog set [_rejectKey, true];
                _poolOwner setVariable ["AEGISM_lastDetectReject", _rejectLog, false];
                diag_log text format ["[AEGIS-M] DETECT-REJECT: %1 sees %2 (%3, relationship=%4, classified=%5) but that class is not in this pool's allowlist %6.", _poolOwner, _target, typeOf _target, _relationship, _class, _allowlist];
            };
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
