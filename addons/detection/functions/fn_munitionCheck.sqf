/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_munitionCheck

Description:
    One check of one tracked munition (aegism_detect_fnc_munitionTracker)
    against every AEGIS-M vehicle with a sensor of its own (AEGISM_
    allPoolOwners). Site logics are never checked directly -- they have no
    sensor of their own; a Site only receives a munition from a member that
    genuinely sees it.

    Detection is the game's: the vehicle's own sensors held the munition's
    sensor proxy (aegism_detect_fnc_trackMunition) on their last read
    (aegism_detect_fnc_confidenceLoop, "AEGISM_seenMunitions", once a
    second; a read older than AEGISM_SEEN_FRESH s doesn't count). So radar,
    IR and visual each by their own range, arc, line of sight, fog, night
    and speed limits, an active radar only while it emits, and what
    datalink shares from other vehicles. The contact records the sensor
    kinds that saw it ("activeradar", "ir", "datalink" ...).

    Where it goes:
        standalone vehicle - its own pool
        networked vehicle - its Site's pool (if the class is one this
            vehicle's own settings engage). Once one member of a Site has
            seen the munition, the Site's other members are skipped for
            this check: they could only add it again. (A networked
            vehicle's own pool isn't kept for munitions: nothing engages
            from it.)

    IFF and threat:
        hostile shooter - tracked outright, unless the Site's doctrine
            engageOnlyThreats is on (the default): then only while it's a
            threat to a Site vehicle (aegism_detect_fnc_munitionThreat) --
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
// Sites this munition already reached this check.
private _sitesDone = [];

{
    private _poolOwner = _x;
    private _system = _poolOwner getVariable "AEGISM_system";
    private _network = _poolOwner getVariable ["AEGISM_network", objNull];

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
            // munition's proxy, if they did.
            (_poolOwner getVariable ["AEGISM_seenMunitions", [-1e9, createHashMap]]) params ["_readAt", "_seenMunitions"];
            private _detected = time - _readAt <= AEGISM_SEEN_FRESH && {_key in _seenMunitions};
            private _seenBy = if (_detected) then { _seenMunitions get _key } else { [] };
            private _threat = [];

            if (_detected && {_needsThreat}) then {
                _threat = [_projectile, _class, _poolOwner, _settings getOrDefault ["friendlyThreatRadius", 0]] call aegism_detect_fnc_munitionThreat;
                _detected = _threat isNotEqualTo [];
                if (_detected) then {
                    if (!_hostile && {!(_flags getOrDefault ["friendlyLogged", false])}) then {
                        _flags set ["friendlyLogged", true];
                        _threat params ["_threatened", "_miss", "_radius", "_basis"];
                        diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " FRIENDLY-THREAT: %1 (%2) fired by %3 side -- %4 -- engaging it as a threat.", typeOf _projectile, _class, _shooterSide,
                            switch (_basis) do {
                                case "guided": { format ["guided at Site member %1", _threatened] };
                                case "heading": { format ["flying at Site member %1, passing %2m from it (threat radius %3m)", _threatened, round _miss, round _radius] };
                                default { format ["predicted impact %1m from %2 (threat radius %3m)", round _miss, _threatened, round _radius] };
                            }];
                    };
                } else {
                    if (_hostile && {!(_flags getOrDefault ["ignoredLogged", false])}) then {
                        _flags set ["ignoredLogged", true];
                        PERF_INC(PERF_IGNORED);
                        diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " IGNORED: %1 (%2) seen by %3 at %4m is no threat to any Site vehicle (not predicted to land near one, not guided or flying at one) -- not engaged while that holds (Site setting: Only Engage Munitions Threatening the Site).",
                            typeOf _projectile, _class, _poolOwner, round (_poolOwner distance _projectile)];
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
                    if (!_needsThreat && {(_network getVariable ["alarmIncoming", "auto"]) != "off" || {(_network getVariable ["alarmIncomingCustom", ""]) != ""}}) then {
                        _threat = [_projectile, _class, _poolOwner, _settings getOrDefault ["friendlyThreatRadius", 0]] call aegism_detect_fnc_munitionThreat;
                    };
                    if (_threat isNotEqualTo []) then { _network setVariable ["AEGISM_incomingAt", time]; };
                    if (_class in (_settings getOrDefault ["targetClassAllowlist", []])
                        && {[_network, _projectile, _class, 1, _seenBy] call aegism_detect_fnc_addContact}) then {
                        _addedTo pushBackUnique _network;
                    };
                };
                if (_firstDetection && {_addedTo isNotEqualTo []}) then {
                    _firstDetection = false;
                    diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " TRACKING: %1 (%2, %3) detected by %4 at %5m (%6).", typeOf _projectile, _class, _key, _poolOwner, round (_poolOwner distance _projectile), _seenBy joinString ", "];
                };
            };
        };
    };
} forEach _owners;
