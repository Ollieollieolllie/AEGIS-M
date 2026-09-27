/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_trackMunition

Description:
    Attaches a per-frame tracker to a freshly-fired, already-classified
    munition -- the munition half of AEGIS-M's hybrid detection model. A
    fired CfgAmmo projectile is not a valid getSensorTargets result (it has
    none of the radarTargetSize/irTargetSize/visualTargetSize properties
    that make a CfgVehicles object sensor-visible), so incoming missiles/
    rockets/shells/bombs can't be picked up by aegism_detect_fnc_
    confidenceLoop's native-sensor platform pipeline; this dedicated
    pipeline exists specifically because of that gap.

    Each tick, the tracker locates every AEGIS-M pool owner (System or
    Network) and, for a System with real radar capability, gates detection
    by that radar's own discovered range/arc (aegism_system_fnc_
    discoverCapabilities's radarRange/radarArc -- read directly from the
    SAME sensor config getSensorTargets itself uses, not a mission-
    designer-set number, and deliberately NOT run through aegism_fnc_
    scaledRange: it's the engine's real native detection reach, not an
    abstracted "real-world-sourced" value AEGIS-M's range-scale setting was
    ever meant to apply to) plus a line-of-sight check (lineIntersectsSurfaces)
    -- a radar detects an incoming missile the same way it detects an
    aircraft: it has to actually be within reach and not behind terrain. A
    Network pool owner has no sensor or facing of its own (it's a sharing
    point member Systems populate, not a radar), so it stays gated by a
    generous flat range instead.

    Pushes/refreshes the munition as a full-confidence contact via
    aegism_detect_fnc_addContact (rejected silently if not on that pool
    owner's allowlist). Removes itself and calls aegism_detect_fnc_
    removeContact on every pool it added to once the munition is
    destroyed, lands, or leaves simulation.

    Pool owners are looked up via the global "AEGISM_allPoolOwners" list
    maintained by aegism_system_fnc_moduleInit / aegism_network_fnc_
    moduleInit rather than an every-tick nearestObjects scan for module
    logics.

Parameters:
    _projectile - the fired munition object <OBJECT>
    _class - pre-classified target class, from aegism_detect_fnc_
        classifyTarget <STRING>

Returns:
    Nothing

Examples:
    [_projectile, "missile"] call aegism_detect_fnc_trackMunition;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_MUNITION_NETWORK_FALLBACK_RANGE 8000

params ["_projectile", "_class"];

private _addedTo = [];

[{
    params ["_args", "_pfhHandle"];
    _args params ["_projectile", "_class", "_addedTo"];

    if (isNull _projectile || {!alive _projectile}) exitWith {
        {
            [_x, _projectile] call aegism_detect_fnc_removeContact;
        } forEach _addedTo;
        [_pfhHandle] call CBA_fnc_removePerFrameHandler;
    };

    private _pos = getPosASL _projectile;
    {
        private _poolOwner = _x;
        private _system = _poolOwner getVariable "AEGISM_system";
        private _detected = false;

        if (isNil "_system") then {
            _detected = (_poolOwner distance2D _projectile) <= AEGISM_MUNITION_NETWORK_FALLBACK_RANGE;
        } else {
            if (_system get "hasRadar") then {
                private _radarRange = _system get "radarRange";
                if ((_poolOwner distance2D _projectile) <= _radarRange) then {
                    private _ownerPos = AGLToASL (eyePos _poolOwner);
                    private _losClear = (lineIntersectsSurfaces [_ownerPos, _pos, _poolOwner, _projectile, true, 1]) isEqualTo [];
                    _detected = _losClear;

                    if (_detected) then {
                        private _radarArc = _system get "radarArc";
                        if (_radarArc < 360) then {
                            private _relBearing = _poolOwner getRelDir _projectile;
                            if (_relBearing > 180) then { _relBearing = _relBearing - 360; };
                            _detected = abs(_relBearing) <= (_radarArc / 2);
                        };
                    };
                };
            };
        };

        if (_detected) then {
            private _added = [_poolOwner, _projectile, _class, 1] call aegism_detect_fnc_addContact;
            if (_added && {!(_poolOwner in _addedTo)}) then {
                _addedTo pushBack _poolOwner;
            };
        };
    } forEach (missionNamespace getVariable ["AEGISM_allPoolOwners", []]);
}, 0.5, [_projectile, _class, _addedTo]] call CBA_fnc_addPerFrameHandler;
