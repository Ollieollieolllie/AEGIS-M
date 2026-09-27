/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_confidenceLoop

Description:
    Interval-based (not true per-frame, for performance) scan run once per
    pool owner (System with its own Radar role, or Network) that finds
    candidate platforms (aircraft/helicopters/drones) within scaled radar
    range, scores each via aegism_detect_fnc_computeConfidence, and adds/
    removes them from the pool as their confidence crosses the detection
    threshold. This is the platform half of the AEGIS-M architecture plan's
    (section 2) two-pipeline detection model; munitions are handled
    separately and immediately via aegism_detect_fnc_trackMunition.

    Registered once per qualifying pool owner (see aegism_detect_fnc_
    registerConfidenceLoop / XEH_preInit.sqf) via CBA_fnc_addPerFrameHandler
    at a fixed interval, not once globally -- each pool owner's loop scans
    only its own vicinity.

Parameters:
    _poolOwner - the System vehicle (with own Radar role) or Network logic
        to scan around <OBJECT>

Returns:
    Nothing (intended to be wrapped in a CBA_fnc_addPerFrameHandler by the
    caller, which supplies the recurring interval)

Examples:
    [_radarTruck] call aegism_detect_fnc_confidenceLoop;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_CONFIDENCE_THRESHOLD 0.35

params ["_poolOwner"];

if (isNull _poolOwner) exitWith {};

private _system = _poolOwner getVariable "AEGISM_system";
if (isNil "_system") exitWith {}; // Network itself has no sensor -- its platform detection comes from member Systems' own loops

private _engagementSettings = [_poolOwner] call aegism_system_fnc_resolveEngagementSettings;
private _allowlist = _engagementSettings getOrDefault ["targetClassAllowlist", []];
private _platformClasses = _allowlist select { _x in ["fixedWing", "helicopter", "drone"] };
if (_platformClasses isEqualTo []) exitWith {}; // doctrine doesn't want platforms at all -- skip the scan entirely

private _crew = [_poolOwner] call aegism_system_fnc_resolveCrew;
private _radarRange = [_system getOrDefault ["radarDetectionRange", 4000]] call aegism_fnc_scaledRange;
private _crewUnit = (crew _poolOwner) select 0;
if (isNil "_crewUnit") then { _crewUnit = objNull; };
private _radarActive = _poolOwner getVariable ["AEGISM_radarActive", false];

private _candidates = _poolOwner nearEntities [["Air"], _radarRange];
{
    private _target = _x;
    private _class = [_target] call aegism_detect_fnc_classifyTarget;

    if (_class in _platformClasses) then {
        private _confidence = [_poolOwner, _target, _crewUnit, _radarActive] call aegism_detect_fnc_computeConfidence;

        if (_confidence >= AEGISM_CONFIDENCE_THRESHOLD) then {
            [_poolOwner, _target, _class, _confidence] call aegism_detect_fnc_addContact;
        } else {
            [_poolOwner, _target] call aegism_detect_fnc_removeContact;
        };
    };
} forEach _candidates;
