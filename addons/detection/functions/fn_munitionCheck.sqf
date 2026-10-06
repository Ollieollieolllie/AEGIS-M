/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_munitionCheck

Description:
    One check of one tracked munition (aegism_detect_fnc_munitionTracker)
    against every AEGIS-M vehicle with a sensor of its own (AEGISM_
    allPoolOwners). Site logics are never checked directly -- they have no
    sensor of their own; a Site only receives a munition from a member that
    genuinely sees it.

    Detection: the vehicle's own sensors saw the munition on their last
    read (aegism_detect_fnc_confidenceLoop, "AEGISM_seenMunitions", four
    times a second while a munition flies; a read older than
    AEGISM_SEEN_FRESH s doesn't count) -- AEGIS-M's own judgement, from each
    sensor's config (aegism_detect_fnc_munitionSeen): radar, IR and visual
    each by their own range, arc, line of sight, fog, night, ground clutter
    and speed limits, an active radar only while it emits. The contact
    records the sensor kinds that saw it ("activeradar", "ir", "visual").

    Where it goes:
        standalone vehicle - its own pool
        networked vehicle - its Site's pool (if the class is one this
            vehicle's own settings engage). Once one member of a Site has
            judged the munition, the Site's other members aren't judged
            again this check; those that see it too only add their sensor
            kinds to the contact (a radar and a Spartan's IR both show).
            (A networked vehicle's own pool isn't kept for munitions:
            nothing engages from it.)

    IFF and threat:
        hostile shooter - tracked outright, unless the Site's doctrine
            engageOnlyThreats is on (the default): then only while it's a
            threat to a Site vehicle or to a Site's protected area (aegism_
            detect_fnc_munitionThreat) --
            a shell or rocket predicted to land within the threat radius, a
            missile guided at a Site vehicle or flying on a line that passes
            within it, a bomb whose fall or line of flight does. One landing
            3km away, or a missile flying at something else, isn't worth a
            single round, and never becomes a contact, a claim or a burst.
            Logged once (IGNORED); re-judged every check, so one that turns
            toward the Site is picked up.
        friendly/neutral shooter - only while predicted to hit the Site, and
            only if its doctrine engageFriendlyThreats is on. An AEGIS-M
            System's own interceptors ("AEGISM_fromSystem") never are.

    An anti-radiation missile one of a Site's vehicles sees also marks the
    radars it threatens, so they shut down (aegism_detect_fnc_armInbound),
    whatever the Site engages.

Parameters:
    _entry - the tracked munition's entry (aegism_detect_fnc_trackMunition) <ARRAY>
    _owners - AEGISM_allPoolOwners <ARRAY>

Returns:
    Nothing

Examples:
    [_entry, _owners] call aegism_detect_fnc_munitionCheck;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\perf.hpp"

// How old a vehicle's last sensor read may be and still count: its reads
// come once a second, plus a frame or two.
#define AEGISM_SEEN_FRESH 1.5

params ["_entry", "_owners"];
_entry params ["_projectile", "_class", "_shooterSide", "_key", "_addedTo", "", "", "_flags"];

private _firstDetection = _addedTo isEqualTo [];
private _fromSystem = _projectile getVariable ["AEGISM_fromSystem", false];

// Why a munition is a threat (aegism_detect_fnc_munitionThreat's result),
// for the RPT.
private _fnThreatText = {
    _this params ["_threatened", "_miss", "_radius", "_basis", ["_detail", 0], ["_aimedAt", objNull]];
    switch (_basis) do {
        case "guided": { format ["guided at Site member %1", _threatened] };
        case "heading": { format ["flying at Site member %1, passing %2m from it (threat radius %3m)", _threatened, round _miss, round _radius] };
        case "seeker": { format ["Site member %1 is inside its seeker's view, %2 deg off its flight (its target can't be read)", _threatened, round _detail] };
        case "area": {
            switch (_detail) do {
                case "guided": { format ["guided at %1 (%2), inside Site %3's %4m protected area, %5m from its centre", _aimedAt, typeOf _aimedAt, _threatened, round _radius, round _miss] };
                case "heading": { format ["flying down into Site %1's %2m protected area, %3m from its centre", _threatened, round _radius, round _miss] };
                default { format ["predicted to land inside Site %1's %2m protected area, %3m from its centre", _threatened, round _radius, round _miss] };
            }
        };
        default { format ["predicted impact %1m from %2 (threat radius %3m)", round _miss, _threatened, round _radius] };
    }
};
// How far an object is from the nearest live vehicle a pool owner protects
// (its linked group's, or itself).
private _fnNearestMember = {
    params ["_object", "_owner"];
    private _ownerNetwork = _owner getVariable ["AEGISM_network", objNull];
    private _members = if (isNull _ownerNetwork) then { [_owner] } else {
        _ownerNetwork getVariable ["AEGISM_groupMembers", _ownerNetwork getVariable ["AEGISM_networkMembers", []]]
    };
    private _nearest = 1e10;
    { if (!isNull _x && {alive _x}) then { _nearest = _nearest min (_x distance _object); }; } forEach _members;
    _nearest
};
// Sites this munition already reached this check, and those it went into.
private _sitesDone = [];
private _sitesAdded = [];
// An anti-radiation missile: the radars it threatens shut down (aegism_
// detect_fnc_armInbound), whatever the Site engages -- once a check per Site
// (or standalone vehicle) that sees it.
private _isArm = _class == "missile" && {!_fromSystem} && {([typeOf _projectile] call aegism_detect_fnc_antiRadiation) isNotEqualTo []};
private _armDone = [];
// Its path, for UNSEEN if it's gone without ever coming into a Site's
// picture (aegism_detect_fnc_munitionTracker): [nearest AEGIS-M sensor
// vehicle m, that vehicle, lowest height above ground m, top speed m/s,
// sensor kinds that saw it, its elevation from that vehicle then, degrees
// (below 0: seen against the ground)]. Not for an AEGIS-M interceptor.
if (!_fromSystem) then {
    private _path = _flags getOrDefault ["path", [1e10, objNull, 1e10, 0, [], 0]];
    {
        if (!isNil { _x getVariable "AEGISM_system" }) then {
            private _distance = _x distance _projectile;
            if (_distance < (_path select 0)) then {
                _path set [0, _distance];
                _path set [1, _x];
                _path set [5, asin (((((getPosASL _projectile) select 2) - ((eyePos _x) select 2)) / (_distance max 1) max -1) min 1)];
            };
            (_x getVariable ["AEGISM_seenMunitions", [-1e9, createHashMap]]) params ["_readAt", "_seen"];
            if (CBA_missionTime - _readAt <= AEGISM_SEEN_FRESH && {_key in _seen}) then { { (_path select 4) pushBackUnique _x; } forEach (_seen get _key); };
        };
    } forEach _owners;
    _path set [2, (_path select 2) min ((ASLToAGL getPosASL _projectile) select 2)];
    _path set [3, (_path select 3) max (vectorMagnitude velocity _projectile)];
    _flags set ["path", _path];
};

// Its last known state, for ARM-END when it's gone (aegism_detect_fnc_
// munitionTracker): [type, position, what it's homing on, seen by a Site].
if (_isArm) then {
    private _armState = _flags getOrDefault ["arm", [typeOf _projectile, [], objNull, false]];
    _armState set [1, getPosASL _projectile];
    _armState set [2, missileTarget _projectile];
    _flags set ["arm", _armState];
};

{
    private _poolOwner = _x;
    private _system = _poolOwner getVariable "AEGISM_system";
    private _network = _poolOwner getVariable ["AEGISM_network", objNull];

    if (_isArm && {!isNil "_system"} && {!(([_network, _poolOwner] select (isNull _network)) in _armDone)}) then {
        (_poolOwner getVariable ["AEGISM_seenMunitions", [-1e9, createHashMap]]) params ["_readAt", "_seenMunitions"];
        if (CBA_missionTime - _readAt <= AEGISM_SEEN_FRESH && {_key in _seenMunitions}) then {
            (_flags get "arm") set [3, true];
            _armDone pushBack ([_network, _poolOwner] select (isNull _network));
            [_projectile, _key, _poolOwner, _seenMunitions get _key, [side _poolOwner, _shooterSide] call aegism_detect_fnc_isHostile] call aegism_detect_fnc_armInbound;
        };
    };

    // Another member of a Site the munition already went into this check:
    // nothing to judge, but its own sensors' sighting is added to the
    // contact, so it records every kind of sensor on the Site that sees it
    // -- the first member (usually the radar, set up first) used to be the
    // only one, and a Spartan's IR never showed on a munition.
    if (!isNil "_system" && {!isNull _network} && {_network in _sitesAdded}) then {
        (_poolOwner getVariable ["AEGISM_seenMunitions", [-1e9, createHashMap]]) params ["_readAt", "_seenMunitions"];
        if (CBA_missionTime - _readAt <= AEGISM_SEEN_FRESH && {_key in _seenMunitions}) then {
            [_network, _projectile, _class, 1, _seenMunitions get _key] call aegism_detect_fnc_addContact;
        };
    };

    if (!isNil "_system" && {isNull _network || {!(_network in _sitesDone)}}) then {
        private _hostile = [side _poolOwner, _shooterSide] call aegism_detect_fnc_isHostile;
        private _settings = _poolOwner getVariable "AEGISM_resolvedEngagementSettings";
        if (isNil "_settings") then { _settings = [_poolOwner] call aegism_system_fnc_resolveEngagementSettings; };

        // A threat check needed: a friendly munition (if this Site engages
        // those), or a hostile one (if it only engages threats).
        private _needsThreat = if (_hostile) then {
            _settings getOrDefault ["engageOnlyThreats", true]
        } else {
            _settings getOrDefault ["engageFriendlyThreats", true]
        };
        if (_hostile || {_needsThreat && {!_fromSystem}}) then {
            // Its sensors' last read: the sensor kinds that saw this
            // munition, if they did.
            (_poolOwner getVariable ["AEGISM_seenMunitions", [-1e9, createHashMap]]) params ["_readAt", "_seenMunitions"];
            private _detected = CBA_missionTime - _readAt <= AEGISM_SEEN_FRESH && {_key in _seenMunitions};
            private _seenBy = if (_detected) then { _seenMunitions get _key } else { [] };
            private _threat = [];

            if (_detected && {_needsThreat}) then {
                _threat = [_projectile, _class, _poolOwner, _settings getOrDefault ["friendlyThreatRadius", 0], _flags, _hostile] call aegism_detect_fnc_munitionThreat;
                _detected = _threat isNotEqualTo [];
                if (_detected) then {
                    if (!_hostile && {!(_flags getOrDefault ["friendlyLogged", false])}) then {
                        _flags set ["friendlyLogged", true];
                        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " FRIENDLY-THREAT: %1 (%2) fired by %3 side -- %4 -- engaging it as a threat.", typeOf _projectile, _class, _shooterSide, _threat call _fnThreatText];
                    };
                } else {
                    if (_hostile && {!(_flags getOrDefault ["ignoredLogged", false])}) then {
                        _flags set ["ignoredLogged", true];
                        PERF_INC(PERF_IGNORED);
                        // What a missile is homing on, if it can be read.
                        private _homing = if (_class == "missile") then { missileTarget _projectile } else { objNull };
                        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " IGNORED: %1 (%2) seen by %3 at %4m is no threat to any Site vehicle (%5) -- not engaged while that holds (Site setting: Only Engage Munitions Threatening the Site).",
                            typeOf _projectile, _class, _poolOwner, round (_poolOwner distance _projectile),
                            switch (true) do {
                                case (!isNull _homing): { format ["homing on %1 (%2), %3m from the nearest Site vehicle", _homing, typeOf _homing, round ([_homing, _poolOwner] call _fnNearestMember)] };
                                case (_class == "missile" && {([typeOf _projectile] call aegism_detect_fnc_seekerCone) >= 0}): {
                                    format ["its target can't be read, and no Site vehicle is inside its %1-degree seeker view", [typeOf _projectile] call aegism_detect_fnc_seekerCone]
                                };
                                default { "not predicted to land near one or inside a protected area, nor flying at one" };
                            }];
                    };
                };
            };

            if (_detected) then {
                if (isNull _network) then {
                    if ([_poolOwner, _projectile, _class, 1, _seenBy] call aegism_detect_fnc_addContact) then { _addedTo pushBackUnique _poolOwner; };
                } else {
                    // Reported to the Site only if this vehicle's own settings
                    // engage the class, so a radar's per-vehicle override
                    // controls what it reports. The Site records the sensors
                    // of the first member that saw it this check.
                    _sitesDone pushBack _network;
                    // The Site's incoming alarm (aegism_network_fnc_siteAlarm):
                    // a munition threatening it, engaged or not. Judged here
                    // only if the check above didn't already, and only while
                    // that alarm is on.
                    private _alarmSettings = [_network] call aegism_fnc_siteSettingsSource;
                    if (!_needsThreat && {(_alarmSettings getVariable ["alarmIncoming", "auto"]) != "off" || {(_alarmSettings getVariable ["alarmIncomingCustom", ""]) != ""}}) then {
                        _threat = [_projectile, _class, _poolOwner, _settings getOrDefault ["friendlyThreatRadius", 0], _flags, _hostile] call aegism_detect_fnc_munitionThreat;
                    };
                    // Every Site of a linked group (aegism_network_fnc_linkSites).
                    if (_threat isNotEqualTo []) then {
                        { _x setVariable ["AEGISM_incomingAt", CBA_missionTime]; } forEach (_network getVariable ["AEGISM_linkSites", [_network]]);
                    };
                    if (_class in (_settings getOrDefault ["targetClassAllowlist", []])
                        && {[_network, _projectile, _class, 1, _seenBy] call aegism_detect_fnc_addContact}) then {
                        // New to the Site: its coordinator runs at once, not
                        // at its next turn (aegism_network_fnc_moduleInit).
                        if !(_network in _addedTo) then {
                            (_network getVariable ["AEGISM_linkLead", _network]) setVariable ["AEGISM_assignNow", true, false];
                        };
                        _addedTo pushBackUnique _network;
                        _sitesAdded pushBack _network;
                    };
                };
                if (_firstDetection && {_addedTo isNotEqualTo []}) then {
                    _firstDetection = false;
                    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " TRACKING: %1 (%2, %3) detected by %4 at %5m (%6), %7s after it was fired%8.", typeOf _projectile, _class, _key, _poolOwner, round (_poolOwner distance _projectile), _seenBy joinString ", ",
                        (CBA_missionTime - (_flags getOrDefault ["firedAt", CBA_missionTime])) toFixed 1, if (_threat isEqualTo []) then { "" } else { " -- " + (_threat call _fnThreatText) }];
                };
            };
        };
    };
} forEach _owners;
