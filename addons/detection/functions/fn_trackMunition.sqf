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

    Each tick, the tracker checks every radar-capable System pool owner
    (Network pool owners are never checked directly here -- see below),
    gating detection by that radar's own discovered range/arc (aegism_
    system_fnc_discoverCapabilities's radarRange/radarArc -- read directly
    from the SAME sensor config getSensorTargets itself uses, not a
    mission-designer-set number, and deliberately NOT run through aegism_
    fnc_scaledRange: it's the engine's real native detection reach, not an
    abstracted "real-world-sourced" value AEGIS-M's range-scale setting was
    ever meant to apply to) plus a line-of-sight check
    (lineIntersectsSurfaces) -- a radar detects an incoming missile the
    same way it detects an aircraft: it has to actually be within reach
    and not behind terrain. This matters specifically for a low, terrain-
    following threat: it should not read as "detected" just because it's
    within range of some radar's position while a ridge sits between them.

    A detecting System pushes the contact into its own pool AND its
    Network's pool (if synced), mirroring aegism_detect_fnc_confidenceLoop's
    platform-sharing behaviour exactly. A Network's shared pool therefore
    only ever contains munitions at least one real member System's own
    sensor genuinely has LOS to -- there is no separate flat-range fallback
    for the Network pool owner itself, since a Network logic has no
    position or facing of its own to meaningfully check LOS/arc against;
    inventing one would let a terrain-masked missile appear "detected"
    network-wide when no member can actually see it, and a sibling System
    reading that shared pool would have no way to tell the difference from
    a real detection.

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

        // Network pool owners are never checked directly -- they have no
        // sensor/facing of their own; they only receive a contact via a
        // detecting member System's own push below.
        if (!isNil "_system" && {_system get "hasRadar"}) then {
            private _detected = false;
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

            if (_detected) then {
                private _added = [_poolOwner, _projectile, _class, 1] call aegism_detect_fnc_addContact;
                if (_added && {!(_poolOwner in _addedTo)}) then {
                    _addedTo pushBack _poolOwner;
                };

                private _network = _poolOwner getVariable ["AEGISM_network", objNull];
                if (!isNull _network) then {
                    private _addedNetwork = [_network, _projectile, _class, 1] call aegism_detect_fnc_addContact;
                    if (_addedNetwork && {!(_network in _addedTo)}) then {
                        _addedTo pushBack _network;
                    };
                };
            };
        };
    } forEach (missionNamespace getVariable ["AEGISM_allPoolOwners", []]);
}, 0.5, [_projectile, _class, _addedTo]] call CBA_fnc_addPerFrameHandler;
