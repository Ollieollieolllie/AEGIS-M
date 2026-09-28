/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_assignEngagements

Description:
    Site-level engagement coordinator, run once per Site every 0.5s on the
    server. Decides, for every pooled contact, which member System's weapon
    engages it; member engagement loops only execute these assignments.

    1. Prune the Site pool by expiry (aegism_detect_fnc_pruneStaleContacts).
       Sensors never delete from the shared pool directly any more -- they
       used to, which deleted assignments every second and restarted the
       crew reaction timer so launchers never fired.

    2. Review existing assignments (AEGISM_claims) and keep each unless:
         - its System is dead, or the contact left the pool
         - the weapon can no longer usefully engage it (aegism_intercept_
           fnc_canEngage: envelope, and a feasible intercept -- a gun is
           released from a jet flying away that its rounds can't catch)
         - launcher MISSED: salvo spent, AEGISM_INTERCEPTOR_SETTLE seconds
           since the last shot, and none of its interceptors are still in
           flight. This is judged from the real missiles (captured by
           aegism_intercept_fnc_onSystemFired), not a fixed timer -- the old
           8s timer called a long-range shot "failed" while its missile was
           still flying and fired a second one at the same target.
         - CIWS idle: hasn't fired for AEGISM_CIWS_IDLE_GRACE seconds
         - never fired within AEGISM_NEVER_FIRED_TIMEOUT seconds of being
           assigned (turret can't bear, LOS never clears) -- frees the
           contact for a better-placed weapon instead of holding it forever

    3. Assign free roles, contacts in Target Priority order. For each
       contact, a launcher and a CIWS weapon are chosen independently (CIWS
       runs in parallel with a launcher unless that gun's "CIWS last
       resort" is set). A candidate weapon must:
         - have live ammo
         - engage that target class (its vehicle's own settings)
         - have the contact inside its envelope
         - not be on a TURRET already committed to a DIFFERENT contact
           (two weapons sharing a turret, e.g. the Cheetah's gun and
           missiles, used to be assigned to different targets and fight
           over the turret's aim forever)
       Best fit: launcher warhead size closest to the threat's own size
       (within AEGISM_SIZE_TIE_TOLERANCE), then nearest.

    Threat re-assessment: after AEGISM_RETRY_THREAT_ASSESSMENT_THRESHOLD
    launcher attempts on a still-living contact, further launcher shots only
    go to it if no unassigned contact outranks it (aegism_intercept_fnc_
    threatValue).

    Per-vehicle settings: everything decided per WEAPON -- envelope, which
    target classes it engages, missiles per target, CIWS last resort -- uses
    that weapon's own vehicle's resolved settings ("AEGISM_resolved
    EngagementSettings": the Site's, plus any per-vehicle overrides, see
    aegism_system_fnc_applyOverrides). The Site's own doctrine decides the
    rest: engagement ORDER (Target Priority -- contacts are served
    highest-priority first, so when threats outnumber free weapons the
    priority rule decides who gets them; it used to be HashMap order, and
    the setting did nothing for a Site) and which classes the Site pool
    holds at all (the Site's allowlist plus any class a member vehicle's
    override adds, "AEGISM_contactAllowlist", read by aegism_detect_fnc_
    addContact).

    Writes AEGISM_claims: contact netId -> array of assignment records
    (HashMap: target, system, role, weaponInfo, assignedAt, lastShotAt,
    roundsFired, interceptors), and AEGISM_withheldCiws (diagnostic, for
    debugDraw). Consumers use the record's own "target" object rather than
    resolving the key back through objectFromNetId.

Parameters:
    _logic - the Site logic <OBJECT>

Returns:
    Nothing

Examples:
    [_site] call aegism_intercept_fnc_assignEngagements;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_INTERCEPTOR_SETTLE 1.5
#define AEGISM_CIWS_IDLE_GRACE 8
#define AEGISM_NEVER_FIRED_TIMEOUT 15
#define AEGISM_CIWS_OVERRIDE_RANGE_FRACTION 0.4
#define AEGISM_SIZE_TIE_TOLERANCE 50
#define AEGISM_RETRY_THREAT_ASSESSMENT_THRESHOLD 3

params ["_logic"];

if (isNull _logic) exitWith {};

private _engagementSettings = _logic getVariable "AEGISM_engagement";
if (isNil "_engagementSettings") exitWith {
    if (_logic getVariable ["AEGISM_lastAssignWarning", ""] != "no-engagement-settings") then {
        _logic setVariable ["AEGISM_lastAssignWarning", "no-engagement-settings", false];
        diag_log text format ["[AEGIS-M] WARNING: Site %1 has no AEGISM_engagement set -- cannot assign engagements.", _logic];
    };
};

[_logic] call aegism_detect_fnc_pruneStaleContacts;

private _members = _logic getVariable ["AEGISM_networkMembers", []];
private _pool = _logic getVariable ["AEGISM_pooledContacts", createHashMap];
private _claims = _logic getVariable ["AEGISM_claims", createHashMap];

private _fnHeight = { (ASLToAGL (getPosASL _this)) select 2 };

// A member vehicle's own resolved settings (Site + its overrides).
private _fnSettings = {
    private _settings = _this getVariable "AEGISM_resolvedEngagementSettings";
    if (isNil "_settings") then { _settings = [_this] call aegism_system_fnc_resolveEngagementSettings; };
    _settings
};

// Classes the Site pool holds: the Site's allowlist plus any class a live
// member's override adds (that member alone will engage it).
private _allowlist = +(_engagementSettings getOrDefault ["targetClassAllowlist", []]);
{
    if (!isNull _x && {alive _x}) then {
        { _allowlist pushBackUnique _x; } forEach ((_x call _fnSettings) getOrDefault ["targetClassAllowlist", []]);
    };
} forEach _members;
_logic setVariable ["AEGISM_contactAllowlist", _allowlist, false];

// --- 2. Review existing assignments ---------------------------------------
// Turrets committed to a contact: [system, turretPath, contactKey, role,
// holding]. "holding" = still needs the turret: always for a gun; for a
// launcher only until its salvo is away (its missiles then guide
// themselves and the launcher is free for its next target).
private _busyTurrets = [];

// Iterates a snapshot of the keys: entries are deleted/replaced below, which
// isn't safe while iterating the HashMap itself.
{
    private _contactKey = _x;
    private _records = _claims get _contactKey;
    private _entry = _pool getOrDefault [_contactKey, createHashMap];
    private _object = _entry getOrDefault ["object", objNull];

    if (isNull _object || {!alive _object} || {!((_entry getOrDefault ["class", ""]) in _allowlist)}) then {
        _claims deleteAt _contactKey;
    } else {
        private _kept = _records select {
            private _record = _x;
            private _system = _record get "system";
            private _role = _record get "role";
            private _weaponInfo = _record get "weaponInfo";
            private _lastShotAt = _record get "lastShotAt";
            private _alive = !isNull _system && {alive _system};
            private _systemSettings = if (_alive) then { _system call _fnSettings } else { createHashMap };
            private _engage = if (_alive) then { [_system, _role, _weaponInfo, _object, _systemSettings] call aegism_intercept_fnc_canEngage } else { [false, ""] };
            _record set ["flightTime", _engage param [2, 0]];

            private _reason = switch (true) do {
                case (!_alive): { "system dead" };
                case !((_entry get "class") in (_systemSettings getOrDefault ["targetClassAllowlist", []])): { format ["%1 not engaged by this vehicle (its settings)", _entry get "class"] };
                case !(_engage select 0): { _engage select 1 };
                case (_role == "launcher" && {(_record get "roundsFired") >= (_systemSettings getOrDefault ["salvoSize", 1])} && {time > _lastShotAt + AEGISM_INTERCEPTOR_SETTLE} && {((_record get "interceptors") findIf { !isNull _x && {alive _x} }) == -1}): { "missed (salvo spent, no interceptor still in flight)" };
                case (_role == "ciws" && {_lastShotAt >= 0} && {time > _lastShotAt + AEGISM_CIWS_IDLE_GRACE}): { "CIWS idle" };
                case (_lastShotAt < 0 && {time > (_record get "assignedAt") + AEGISM_NEVER_FIRED_TIMEOUT}): { "never fired (cannot bear or no LOS)" };
                default { "" };
            };

            if (_reason != "") then {
                diag_log text format ["[AEGIS-M] ASSIGN-CLEAR: %1 (%2) released %3 -- %4.", _system, _role, _object, _reason];
            };
            _reason == ""
        };

        if (_kept isEqualTo []) then {
            _claims deleteAt _contactKey;
        } else {
            _claims set [_contactKey, _kept];
            {
                private _record = _x;
                private _holding = (_record get "role") == "ciws"
                    || {(_record get "roundsFired") < (((_record get "system") call _fnSettings) getOrDefault ["salvoSize", 1])};
                _busyTurrets pushBack [_record get "system", (_record get "weaponInfo") select 0, _contactKey, _record get "role", _holding];
            } forEach _kept;
        };
    };
} forEach (keys _claims);

// --- Live weapons across every member ---------------------------------------
private _allWeapons = [];
{
    private _system = _x;
    if (!isNull _system && {alive _system}) then {
        private _systemData = _system getVariable "AEGISM_system";
        if (!isNil "_systemData") then {
            {
                private _role = _x;
                {
                    _x params ["_turretPath", "", "_magClass"];
                    if ((_system magazineTurretAmmo [_magClass, _turretPath]) > 0) then {
                        _allWeapons pushBack [_system, _role, _x];
                    };
                } forEach (_systemData getOrDefault [["launcherWeapons", "ciwsWeapons"] select (_role == "ciws"), []]);
            } forEach ["launcher", "ciws"];
        };
    };
} forEach _members;

if (_allWeapons isEqualTo []) exitWith {
    if (_logic getVariable ["AEGISM_lastAssignWarning", ""] != "no-weapons") then {
        _logic setVariable ["AEGISM_lastAssignWarning", "no-weapons", false];
        diag_log text format ["[AEGIS-M] WARNING: Site %1 has %2 member(s) but no live launcher/CIWS weapon (none adopted, dead, or out of ammo).", _logic, count _members];
    };
    _logic setVariable ["AEGISM_claims", _claims, false];
};
_logic setVariable ["AEGISM_lastAssignWarning", "", false];

// --- 3. Assign free roles ----------------------------------------------------
private _withheldCiws = [];

// Time to impact of every contact (aegism_intercept_fnc_timeToImpact), used
// for ordering, launcher queues, and in-time checks alike.
private _memberPositions = (_members select { !isNull _x && {alive _x} }) apply { getPosASL _x };
private _ttiByKey = createHashMap;
{
    private _object = _y getOrDefault ["object", objNull];
    if (!isNull _object && {alive _object}) then {
        _ttiByKey set [_x, [_object, _y get "class", _memberPositions] call aegism_intercept_fnc_timeToImpact];
    };
} forEach _pool;

// Serve contacts in the Site's Target Priority order, so when threats
// outnumber free weapons the priority rule decides which get them. The
// default, Soonest Impact, works a salvo front to back.
private _priority = _engagementSettings getOrDefault ["targetPriority", "soonestImpact"];
private _orderedKeys = keys _ttiByKey;
if (_memberPositions isNotEqualTo [] && {count _orderedKeys > 1}) then {
    private _scored = _orderedKeys apply {
        private _entry = _pool get _x;
        private _object = _entry get "object";
        private _pos = getPosASL _object;
        private _nearest = _memberPositions select 0;
        private _nearestDist = 1e10;
        {
            private _dist = _pos distance _x;
            if (_dist < _nearestDist) then { _nearestDist = _dist; _nearest = _x; };
        } forEach _memberPositions;
        private _score = switch (_priority) do {
            case "nearest": { -_nearestDist };
            case "fastestClosing": { (velocity _object) vectorDotProduct (_pos vectorFromTo _nearest) };
            case "highestValue": { ([_entry get "class"] call aegism_intercept_fnc_threatValue) * 1e6 - _nearestDist };
            default { -(_ttiByKey get _x) };
        };
        [_score, _x]
    };
    _scored sort false;
    _orderedKeys = _scored apply { _x select 1 };
};

// Seconds until one launcher turret can fire at a contact: crew reaction
// (none for an automated/UAV system), or its shot cooldown plus one shot
// spacing for every missile queued on it for a contact that impacts sooner
// (the launcher works its queue soonest-impact first). Shot spacing is the
// launcher's own MEASURED time per missile ("AEGISM_turretSpacing_<path>",
// aegism_intercept_fnc_engagementLoop), which includes lost reliability
// rolls and re-aiming between targets; before its first back-to-back shots
// it's estimated as Seconds Between Missiles / crew reliability. (Planning
// on the bare interval queued RAM launchers ~2x deeper than they could
// fire, so the back of a salvo was left to them until too late.)
private _fnLauncherEta = {
    params ["_candSystem", "_turretPath", "_contactKey", "_tti"];
    private _settings = _candSystem call _fnSettings;
    private _crew = _candSystem getVariable "AEGISM_resolvedCrew";
    if (isNil "_crew") then { _crew = [_candSystem] call aegism_system_fnc_resolveCrew; };
    private _mods = [_crew, _candSystem] call aegism_intercept_fnc_applyCrewModulation;
    private _reaction = _mods get "reactionTime";
    private _interval = (_settings getOrDefault ["minShotInterval", 4]) * (_mods get "shotIntervalMult");
    private _spacing = _candSystem getVariable [format ["AEGISM_turretSpacing_%1", _turretPath], _interval / ((_mods get "reliability") max 0.05)];
    private _ahead = {
        _x params ["_bSystem", "_bTurret", "_bKey", "_bRole", "_bHolding"];
        _bSystem == _candSystem && {_bTurret isEqualTo _turretPath} && {_bRole == "launcher"} && {_bHolding} && {_bKey != _contactKey}
            && {(_ttiByKey getOrDefault [_bKey, 1e10]) < _tti}
    } count _busyTurrets;
    private _cooldown = (((_candSystem getVariable [format ["AEGISM_turretShotAt_%1", _turretPath], -1e9]) + _interval) - time) max 0;
    _reaction max (_cooldown + _ahead * _spacing)
};

// Picks one weapon from the eligible list ([index in _allWeapons, flight
// time] pairs) for a contact. Returns [index in _allWeapons, seconds until it
// can fire].
//
//   gun - closest warhead size to the threat's (within AEGISM_SIZE_TIE_
//       TOLERANCE of the best), then nearest.
//   launcher - layered-defence doctrine, from each launcher's real values:
//       1. can fire IN TIME: _fnLauncherEta plus the missile's flight time
//          must beat the contact's time to impact
//       2. shortest reach first (weaponInfo maxRange, i.e. the missile's
//          own lock range): long-range interceptors are kept for threats
//          only they can reach. (If NO launcher is in time, the one that
//          would intercept soonest is taken instead.)
//       3. most rounds left, so deep magazines take the volume
//       4. soonest ready, then closest warhead size, then nearest
//   Config "cost" is deliberately NOT used: it's an AI value weight, not a
//   price, and it's inverted for this (vanilla long-range SAM base 500,
//   short-range 1000). The old rule was warhead size alone, which sent
//   Patriots (30m blast) at MLRS rockets while a 21-round, 1-second RAM
//   launcher sat idle.
private _fnPickWeapon = {
    params ["_eligible", "_role", "_contactKey", "_contactSize", "_targetPos", "_timeToImpact"];

    if (_role == "ciws") exitWith {
        private _sizeDiffs = _eligible apply { abs ((((_allWeapons select (_x select 0)) select 2) select 3) - _contactSize) };
        private _minSizeDiff = selectMin _sizeDiffs;
        private _best = -1;
        private _bestDist = 1e10;
        {
            private _dist = (getPosASL ((_allWeapons select ((_eligible select _forEachIndex) select 0)) select 0)) distance _targetPos;
            if (_x <= _minSizeDiff + AEGISM_SIZE_TIE_TOLERANCE && {_dist < _bestDist}) then { _best = _forEachIndex; _bestDist = _dist; };
        } forEach _sizeDiffs;
        [(_eligible select _best) select 0, 0, true]
    };

    private _scored = _eligible apply {
        _x params ["_weaponIndex", "_flightTime"];
        (_allWeapons select _weaponIndex) params ["_candSystem", "", "_candInfo"];
        _candInfo params ["_turretPath", "", "_magClass", ["_size", 0], "", ["_reach", 0]];
        private _readyIn = [_candSystem, _turretPath, _contactKey, _timeToImpact] call _fnLauncherEta;
        private _inTime = (_readyIn + _flightTime) < _timeToImpact;
        private _rounds = _candSystem magazineTurretAmmo [_magClass, _turretPath];
        [[1, 0] select _inTime, [_readyIn + _flightTime, _reach] select _inTime, -_rounds, _readyIn, abs (_size - _contactSize), (getPosASL _candSystem) distance _targetPos, _weaponIndex, _inTime]
    };
    _scored sort true;
    (_scored select 0) params ["", "", "", "_readyIn", "", "", "_weaponIndex", "_inTime"];
    [_weaponIndex, _readyIn, _inTime]
};

{
    private _contactKey = _x;
    private _entry = _pool get _contactKey;
    private _object = _entry get "object";
    private _class = _entry get "class";

    if (!isNull _object && {alive _object} && {_class in _allowlist}) then {
        private _targetPos = getPosASL _object;
        private _height = _object call _fnHeight;
        private _contactSize = [typeOf _object] call aegism_intercept_fnc_munitionSize;
        private _existing = _claims getOrDefault [_contactKey, []];
        private _hasLauncher = (_existing findIf { (_x get "role") == "launcher" }) != -1;
        private _hasCiws = (_existing findIf { (_x get "role") == "ciws" }) != -1;

        // A munition may be queued on a launcher still working an earlier
        // one; its time to impact bounds how long it can wait. Aircraft
        // aren't queued.
        private _isMunition = _entry getOrDefault ["isMunition", false];
        private _timeToImpact = _ttiByKey getOrDefault [_contactKey, 1e10];

        // HAND-OFF: a queued launcher claim (nothing fired yet) that can no
        // longer fire in time -- more urgent contacts were queued ahead of
        // it, or the launcher fires slower than planned -- is offered to the
        // other launchers. If one can make it, it takes over (HANDOFF);
        // otherwise the claim is restored untouched. Without this a claim sat
        // on a saturated launcher until its 15s never-fired timeout, and
        // a Patriot only got the back of the salvo when it was too late.
        private _handoff = [];
        if (_isMunition && {_hasLauncher}) then {
            private _index = _existing findIf { (_x get "role") == "launcher" && {(_x get "roundsFired") == 0} };
            if (_index != -1) then {
                private _record = _existing select _index;
                (_record get "weaponInfo") params ["_turretPath"];
                private _eta = [_record get "system", _turretPath, _contactKey, _timeToImpact] call _fnLauncherEta;
                if (_eta + (_record getOrDefault ["flightTime", 0]) >= _timeToImpact) then {
                    _handoff = [_record, _eta];
                    _existing deleteAt _index;
                    private _busyIndex = _busyTurrets findIf { (_x select 0) == (_record get "system") && {(_x select 1) isEqualTo _turretPath} && {(_x select 2) == _contactKey} };
                    if (_busyIndex != -1) then { _busyTurrets deleteAt _busyIndex; };
                    _hasLauncher = false;
                };
            };
        };

        {
            private _role = _x;
            private _covered = [_hasLauncher, _hasCiws] select (_role == "ciws");

            if (!_covered) then {
                // [index in _allWeapons, flight time] of every weapon that can
                // take this contact. Recomputed per role: a winner may be
                // removed from _allWeapons before the next role is scored.
                private _eligible = [];
                {
                    _x params ["_candSystem", "_candRole", "_candInfo"];
                    if (_candRole == _role) then {
                        private _candSettings = _candSystem call _fnSettings;
                        // A gun needs its turret to itself. A launcher only
                        // conflicts with a gun on the same turret, or with
                        // its own claims when this contact can't be queued
                        // (an aircraft).
                        private _conflict = (_busyTurrets findIf {
                            _x params ["_bSystem", "_bTurret", "_bKey", "_bRole", "_bHolding"];
                            _bSystem == _candSystem && {_bTurret isEqualTo (_candInfo select 0)} && {_bKey != _contactKey} && {_bHolding}
                                && {_role == "ciws" || {_bRole == "ciws"} || {!_isMunition}}
                        }) != -1;
                        if (!_conflict && {_class in (_candSettings getOrDefault ["targetClassAllowlist", []])}) then {
                            private _engage = [_candSystem, _role, _candInfo, _object, _candSettings] call aegism_intercept_fnc_canEngage;
                            if (_engage select 0) then { _eligible pushBack [_forEachIndex, _engage param [2, 0]]; };
                        };
                    };
                } forEach _allWeapons;

                // CIWS last resort (each gun's own setting): while a launcher
                // covers the contact, a last-resort gun holds unless the
                // contact is already deep inside its own reach.
                if (_role == "ciws" && {_hasLauncher} && {_eligible isNotEqualTo []}) then {
                    private _free = _eligible select {
                        (_allWeapons select (_x select 0)) params ["_candSystem", "", "_candInfo"];
                        !((_candSystem call _fnSettings) getOrDefault ["ciwsLastResort", false])
                            || {((getPosASL _candSystem) distance _targetPos) <= (_candInfo select 5) * AEGISM_CIWS_OVERRIDE_RANGE_FRACTION}
                    };
                    if (_free isEqualTo []) then { _withheldCiws pushBack [_contactKey, (_allWeapons select ((_eligible select 0) select 0)) select 0]; };
                    _eligible = _free;
                };

                if (_eligible isNotEqualTo []) then {
                    private _allowed = true;

                    if (_role == "launcher") then {
                        private _attempts = _entry getOrDefault ["launcherAttempts", 0];
                        if (_attempts >= AEGISM_RETRY_THREAT_ASSESSMENT_THRESHOLD) then {
                            private _thisValue = [_class] call aegism_intercept_fnc_threatValue;
                            private _outranking = (keys _pool) select {
                                private _otherEntry = _pool get _x;
                                private _otherObject = _otherEntry get "object";
                                _x != _contactKey && {!isNull _otherObject} && {alive _otherObject}
                                    && {(_otherEntry get "class") in _allowlist}
                                    && {((_claims getOrDefault [_x, []]) findIf { (_x get "role") == "launcher" }) == -1}
                                    && {([_otherEntry get "class"] call aegism_intercept_fnc_threatValue) > _thisValue}
                            };
                            _allowed = _outranking isEqualTo [];
                            if (!_allowed) then {
                                diag_log text format ["[AEGIS-M] RETRY-DECLINE: %1 (%2) has taken %3 launcher attempts -- %4 higher-value contact(s) unassigned.", _object, _class, _attempts, count _outranking];
                            };
                        };
                    };

                    if (_allowed) then {
                        ([_eligible, _role, _contactKey, _contactSize, _targetPos, _timeToImpact] call _fnPickWeapon) params ["_weaponIndex", "_readyIn", "_inTime"];
                        (_allWeapons select _weaponIndex) params ["_bestSystem", "_bestRole", "_bestInfo"];
                        private _flightTime = (_eligible select (_eligible findIf { (_x select 0) == _weaponIndex })) select 1;

                        // A hand-off only goes ahead if the new launcher is in
                        // time and actually a different one.
                        private _isHandoff = _role == "launcher" && {_handoff isNotEqualTo []};
                        private _handoffUseful = _isHandoff && {_inTime} && {
                            private _old = _handoff select 0;
                            (_old get "system") != _bestSystem || {((_old get "weaponInfo") select 0) isNotEqualTo (_bestInfo select 0)}
                        };

                        if (!_isHandoff || _handoffUseful) then {
                            if (_role == "launcher") then {
                                if (!_isHandoff) then { _entry set ["launcherAttempts", (_entry getOrDefault ["launcherAttempts", 0]) + 1]; };
                                _hasLauncher = true;
                            } else {
                                _hasCiws = true;
                            };

                            _existing pushBack createHashMapFromArray [
                                ["target", _object],
                                ["class", _class],
                                ["system", _bestSystem],
                                ["role", _bestRole],
                                ["weaponInfo", _bestInfo],
                                ["assignedAt", time],
                                ["lastShotAt", -1],
                                ["roundsFired", 0],
                                ["interceptors", []],
                                ["flightTime", _flightTime]
                            ];
                            _busyTurrets pushBack [_bestSystem, _bestInfo select 0, _contactKey, _bestRole, true];
                            // A launcher taking munitions stays available for
                            // more this cycle -- it queues them (bounded by each
                            // one's time to impact, see _fnLauncherEta).
                            if (_role == "ciws" || {!_isMunition}) then { _allWeapons deleteAt _weaponIndex; };

                            if (_isHandoff) then {
                                diag_log text format ["[AEGIS-M] HANDOFF: %1 can't fire at %2 in time (ready in ~%3s + %4s flight vs impact in %5s) -- %6 (%7) takes it, fires in ~%8s.",
                                    (_handoff select 0) get "system", _object, round ((_handoff select 1) * 10) / 10, round (((_handoff select 0) getOrDefault ["flightTime", 0]) * 10) / 10,
                                    round (_timeToImpact * 10) / 10, _bestSystem, _bestInfo select 1, round (_readyIn * 10) / 10];
                            } else {
                                diag_log text format ["[AEGIS-M] ASSIGN: %1 (%2, %3 %4) -> %5 (%6, %7m, %8m AGL)%9", _bestSystem, typeOf _bestSystem, _bestRole, _bestInfo select 1, _object, _class, round ((getPosASL _bestSystem) distance _targetPos), round _height,
                                    [["", format [", impact in %1s", round _timeToImpact]] select (_timeToImpact < 1e9), format [", fires in ~%1s, impact in %2s", round (_readyIn * 10) / 10, round _timeToImpact]] select (_role == "launcher" && {_readyIn > 0} && {_timeToImpact < 1e9})];
                            };
                        };
                    };
                };
            };

            // Hand-off found no launcher that could do better: restore the
            // original claim as it was (assignment time, reaction state).
            if (_role == "launcher" && {_handoff isNotEqualTo []} && {!_hasLauncher}) then {
                private _old = _handoff select 0;
                _existing pushBack _old;
                _busyTurrets pushBack [_old get "system", (_old get "weaponInfo") select 0, _contactKey, "launcher", true];
                _hasLauncher = true;
            };
        } forEach ["launcher", "ciws"];

        if (_existing isNotEqualTo []) then { _claims set [_contactKey, _existing]; };
    };
} forEach _orderedKeys;

_logic setVariable ["AEGISM_claims", _claims, false];
_logic setVariable ["AEGISM_withheldCiws", _withheldCiws, false];
