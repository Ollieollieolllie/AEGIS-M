/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_confidenceLoop

Description:
    Interval-based (not true per-frame, for performance) scan run once per
    System with a sensor of its own that finds aircraft -- an active radar,
    an IR or a visual sensor (aegism_system_fnc_discoverCapabilities
    "hasSensor": the Spartan's launcher-mounted IR counts) -- that reads
    the vehicle's OWN native sensor detections via getSensorTargets -- the
    engine's own radar/IR/visual/passive/datalink simulation, already
    running against that vehicle's real CfgVehicles sensor config -- rather
    than AEGIS-M re-implementing its own LOS/distance/confidence estimate
    on top of it. Detection is binary here (the engine already decided
    detected-or-not using its own, more complete simulation); every
    allowlisted, genuinely hostile (IFF, see aegism_detect_fnc_isHostile),
    non-destroyed sensor target is pooled at full confidence, with the
    sensor kinds the engine says saw it (getSensorTargets' 4th element,
    e.g. "activeradar", "ir"). What the game's datalink passes on from
    other vehicles ("datalink") only counts with the CBA setting Use
    Datalink Contacts on: off (the default), a target only datalink reports
    is skipped, aircraft and munitions alike. A target the game lists with
    no sensor on it at all (lost, or only known of) is skipped too. A contact new to this
    vehicle's pool is logged once (DETECT) with them. A contact only
    passive radar hears is pooled, but only cues the Site's radars (aegism_
    fnc_hasTrack). Contacts no longer refreshed by any
    sensor expire (aegism_detect_fnc_pruneStaleContacts) rather than being
    deleted the instant one sensor loses them.

    Munitions are judged here too, on the same read, but by AEGIS-M: a
    fired projectile is never a getSensorTargets result (CfgAmmo has no
    radar/IR/visual target properties), so every tracked munition (aegism_
    detect_fnc_trackMunition) is checked against this vehicle's sensors
    from their own config (aegism_detect_fnc_sensorView, aegism_detect_fnc_
    munitionSeen). One that's seen isn't a contact here: it's recorded as
    seen by this vehicle, with the sensor kinds ("AEGISM_seenMunitions":
    [read at, munition key -> sensor kinds]), and the munition tracker
    (aegism_detect_fnc_munitionCheck) takes it from there -- IFF, whether it
    threatens a Site, which pools it goes in. (The game's datalink carries
    no munitions: Use Datalink Contacts is about aircraft.)

    A detected contact is added/removed on both the scanning System's own
    pool AND its Network's pool (if synced), so a Launcher/CIWS-only System
    with no sensor of its own, relying purely on a Network's shared
    contacts, still sees everything a sensor-equipped sibling detects.

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

#include "..\..\main\perf.hpp"
#include "..\..\main\rpt.hpp"

params ["_poolOwner"];

if (isNull _poolOwner) exitWith {};
private _started = diag_tickTime;

private _system = _poolOwner getVariable "AEGISM_system";
if (isNil "_system") exitWith {}; // Network itself has no sensor -- its detections come from member Systems' own loops
if !(_system getOrDefault ["hasSensor", false]) exitWith {};
private _ownPool = _poolOwner getVariable ["AEGISM_pooledContacts", createHashMap];

private _engagementSettings = _poolOwner getVariable "AEGISM_resolvedEngagementSettings";
if (isNil "_engagementSettings") then { _engagementSettings = [_poolOwner] call aegism_system_fnc_resolveEngagementSettings; };
private _allowlist = _engagementSettings getOrDefault ["targetClassAllowlist", []];
private _network = _poolOwner getVariable ["AEGISM_network", objNull];

private _ownSide = side _poolOwner;
// DETECT-REJECT, logged once per contact while it stays in sensor range:
// this tick's rejects replace the last tick's, so one that leaves and comes
// back is logged again, and the list never outgrows what the radar sees.
private _lastRejects = _poolOwner getVariable ["AEGISM_lastDetectReject", createHashMap];
private _rejects = createHashMap;
// Munition key -> sensor kinds, for every munition seen this tick.
private _seenMunitions = createHashMap;
// The game's datalink passes on what OTHER vehicles see -- any friendly
// vehicle with datalink in the mission, not only AEGIS-M's (a Site shares
// its own members' contacts itself). Used only with the CBA setting Use
// Datalink Contacts on; otherwise "datalink" is dropped from what saw a
// target, and a target only datalink reports is skipped.
private _useDatalink = "aegism_main_useDatalink" call CBA_settings_fnc_get;

// When its radar last came on (SIGHTED, below).
private _radarOn = isVehicleRadarOn _poolOwner;
if (_radarOn && {!(_poolOwner getVariable ["AEGISM_radarWasOn", false])}) then { _poolOwner setVariable ["AEGISM_radarOnAt", CBA_missionTime]; };
_poolOwner setVariable ["AEGISM_radarWasOn", _radarOn];
// SIGHTED (RPT Detail Verbose): the first time this vehicle's sensors see
// each munition -- how long after it was fired, how long its radar had been
// on, and where its beam was pointing -- to tell a radar that was silent or
// looking elsewhere from the game's own target acquisition.
private _sighted = _poolOwner getVariable "AEGISM_munitionsSighted";
if (isNil "_sighted") then { _sighted = createHashMap; _poolOwner setVariable ["AEGISM_munitionsSighted", _sighted, false]; };
private _fnSighted = {
    params ["_munitionKey", "_entry", "_sources"];
    _sighted set [_munitionKey, CBA_missionTime];
    if (count _sighted > 200) then { { if (CBA_missionTime - _y > 120) then { _sighted deleteAt _x; }; } forEach +_sighted; };
    private _munition = _entry select 0;
    if (isNull _munition) exitWith {};
    private _eye = eyePos _poolOwner;
    private _pos = getPosASL _munition;
    private _bearing = _eye getDir _pos;
    private _distance = _eye distance _pos;
    private _beamText = "";
    if (([_poolOwner] call aegism_system_fnc_turningRadar) isNotEqualTo []) then {
        private _beam = _poolOwner getVariable ["AEGISM_radarBeam", createHashMap];
        private _beamBearing = _beam getOrDefault ["bearing", getDir _poolOwner];
        _beamText = format ["; its beam on %1 deg (%2), %3 deg off the munition's bearing%4", round _beamBearing, _beam getOrDefault ["task", "?"],
            round (abs ((((_bearing - _beamBearing) + 540) mod 360) - 180)), ["", ", still swinging there"] select (CBA_missionTime < (_beam getOrDefault ["dwellFrom", -1]))];
    };
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " SIGHTED: %1 first sees %2 (%3) by %4 at %5m, %6 deg up, bearing %7 deg -- %8s after it was fired; its radar %9%10.",
        _poolOwner, _munitionKey, typeOf _munition, _sources joinString ", ", round _distance,
        round (asin (((((_pos select 2) - (_eye select 2)) / (_distance max 1)) max -1) min 1)), round _bearing,
        (CBA_missionTime - ((_entry select 7) getOrDefault ["firedAt", CBA_missionTime])) toFixed 1,
        if (_radarOn) then { format ["on for %1s", (CBA_missionTime - (_poolOwner getVariable ["AEGISM_radarOnAt", CBA_missionTime])) toFixed 1] } else { "off" },
        _beamText];
};

{
    _x params ["_target", "", "_relationship", ["_sensorSources", [], [[]]]];
    private _sources = (_sensorSources select { _x isEqualType "" }) apply { toLower _x };
    if (!_useDatalink) then { _sources = _sources - ["datalink"]; };
    // Seen by no sensor of this vehicle's own just now: skipped. That's one
    // only datalink reports (unless that's allowed), and one the game still
    // lists with no sensor on it at all -- lost, or only known of: Spartans,
    // whose IR reaches 4 km, "saw" rockets 9 km out, and a contact listed
    // that way never expired.
    private _datalinkOnly = _sources isEqualTo [];

    // IFF: getSensorTargets reports not-yet-identified contacts as
    // "unknown", including friendly aircraft at range -- engaging
    // "unknown" alone would shoot down friendlies. Require real hostility.
    if (!_datalinkOnly && {_relationship != "friendly"} && {_relationship != "destroyed"} && {!isNull _target} && {alive _target} && {[_ownSide, side _target] call aegism_detect_fnc_isHostile}) then {
        private _class = [_target] call aegism_detect_fnc_classifyTarget;

        if (_class in _allowlist) then {
            if !(([_target] call aegism_fnc_contactKey) in _ownPool) then {
                diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " DETECT: %1 sees %2 (%3, %4) at %5m via %6.", _poolOwner, _target, typeOf _target, _class, round (_poolOwner distance _target), _sensorSources];
            };
            [_poolOwner, _target, _class, 1, _sources] call aegism_detect_fnc_addContact;
            if (!isNull _network) then {
                [_network, _target, _class, 1, _sources] call aegism_detect_fnc_addContact;
            };
        } else {
            // A real sensor detection that never makes it into the pool
            // is otherwise invisible: a class that SHOULD be allowlisted
            // silently classifying as something else would look
            // identical to "never detected at all" in the RPT.
            private _rejectKey = netId _target;
            _rejects set [_rejectKey, true];
            if (!(_rejectKey in _lastRejects)) then {
                if (AEGISM_RPT_VERBOSE) then {
                    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " DETECT-REJECT: %1 sees %2 (%3, relationship=%4, classified=%5) but that class is not in this pool's allowlist %6.", _poolOwner, _target, typeOf _target, _relationship, _class, _allowlist];
                };
            };
        };
    };
} forEach (getSensorTargets _poolOwner);
_poolOwner setVariable ["AEGISM_lastDetectReject", _rejects, false];

// Munitions: every tracked one against this vehicle's sensors as they stand
// now (see header).
private _tracked = missionNamespace getVariable ["AEGISM_trackedMunitions", []];
if (_tracked isNotEqualTo []) then {
    private _view = [_poolOwner, _system] call aegism_detect_fnc_sensorView;
    {
        private _entry = _x;
        if ((_entry select 7) getOrDefault ["watched", true]) then {
            private _sources = [_view, _entry] call aegism_detect_fnc_munitionSeen;
            if (_sources isNotEqualTo []) then {
                private _munitionKey = _entry select 3;
                _seenMunitions set [_munitionKey, _sources];
                PERF_INC(PERF_MUNITIONS_SEEN);
                // Not in any pool yet: checked at once, not at its next turn
                // (aegism_detect_fnc_munitionTracker, every 0.5 s) -- this read
                // is stored below, before the tracker's next frame.
                if ((_entry select 4) isEqualTo []) then { _entry set [5, CBA_missionTime]; };
                if (AEGISM_RPT_VERBOSE && {!(_munitionKey in _sighted)}) then { [_munitionKey, _entry, _sources] call _fnSighted; };
            };
        };
    } forEach _tracked;
};
_poolOwner setVariable ["AEGISM_seenMunitions", [CBA_missionTime, _seenMunitions], false];

// Only this System's OWN pool is pruned here, and only by expiry. The Site
// pool is never touched: another sensor may still hold a contact this one
// lost, and munition contacts are pooled by the munition tracker, not here
// -- the old "not in this tick's sensor targets -> remove from both pools"
// step deleted every tracked munition (and its engagement assignment)
// every second. The Site pool is pruned by aegism_intercept_fnc_
// assignEngagements instead.
[_poolOwner] call aegism_detect_fnc_pruneStaleContacts;
PERF_ADD(PERF_SENSOR_MS,(diag_tickTime - _started) * 1000);
