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
// Turrets committed to a contact: [system, turretPath, contactKey].
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
            { _busyTurrets pushBack [_x get "system", (_x get "weaponInfo") select 0, _contactKey]; } forEach _kept;
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

// Serve contacts in the Site's Target Priority order, each scored against
// its nearest live Site vehicle, so when threats outnumber free weapons the
// priority rule decides which get them.
private _priority = _engagementSettings getOrDefault ["targetPriority", "nearest"];
private _memberPositions = (_members select { !isNull _x && {alive _x} }) apply { getPosASL _x };
private _orderedKeys = (keys _pool) select {
    private _object = (_pool get _x) getOrDefault ["object", objNull];
    !isNull _object && {alive _object}
};
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
            case "fastestClosing": { (velocity _object) vectorDotProduct (_pos vectorFromTo _nearest) };
            case "highestValue": { ([_entry get "class"] call aegism_intercept_fnc_threatValue) * 1e6 - _nearestDist };
            default { -_nearestDist };
        };
        [_score, _x]
    };
    _scored sort false;
    _orderedKeys = _scored apply { _x select 1 };
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

        {
            private _role = _x;
            private _covered = [_hasLauncher, _hasCiws] select (_role == "ciws");

            if (!_covered) then {
                // Indices recomputed per role: a launcher winner is removed
                // from _allWeapons before CIWS is scored.
                private _roleIndices = [];
                {
                    _x params ["_candSystem", "_candRole", "_candInfo"];
                    if (_candRole == _role) then {
                        private _candSettings = _candSystem call _fnSettings;
                        private _turretBusyElsewhere = (_busyTurrets findIf {
                            (_x select 0) == _candSystem && {(_x select 1) isEqualTo (_candInfo select 0)} && {(_x select 2) != _contactKey}
                        }) != -1;
                        if (!_turretBusyElsewhere
                            && {_class in (_candSettings getOrDefault ["targetClassAllowlist", []])}
                            && {([_candSystem, _role, _candInfo, _object, _candSettings] call aegism_intercept_fnc_canEngage) select 0}) then {
                            _roleIndices pushBack _forEachIndex;
                        };
                    };
                } forEach _allWeapons;

                // CIWS last resort (each gun's own setting): while a launcher
                // covers the contact, a last-resort gun holds unless the
                // contact is already deep inside its own reach.
                if (_role == "ciws" && {_hasLauncher} && {_roleIndices isNotEqualTo []}) then {
                    private _free = _roleIndices select {
                        (_allWeapons select _x) params ["_candSystem", "", "_candInfo"];
                        !((_candSystem call _fnSettings) getOrDefault ["ciwsLastResort", false])
                            || {((getPosASL _candSystem) distance _targetPos) <= (_candInfo select 5) * AEGISM_CIWS_OVERRIDE_RANGE_FRACTION}
                    };
                    if (_free isEqualTo []) then { _withheldCiws pushBack [_contactKey, (_allWeapons select (_roleIndices select 0)) select 0]; };
                    _roleIndices = _free;
                };

                if (_roleIndices isNotEqualTo []) then {
                    private _candidates = _roleIndices apply { _allWeapons select _x };
                    private _dists = _candidates apply { (getPosASL (_x select 0)) distance _targetPos };
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
                        // Size band first (against the TRUE minimum, since a
                        // tolerance band isn't transitive), then distance.
                        private _sizeDiffs = _candidates apply { abs (((_x select 2) select 3) - _contactSize) };
                        private _minSizeDiff = selectMin _sizeDiffs;
                        private _bestIndex = -1;
                        {
                            if (_x <= _minSizeDiff + AEGISM_SIZE_TIE_TOLERANCE && {_bestIndex == -1 || {(_dists select _forEachIndex) < (_dists select _bestIndex)}}) then {
                                _bestIndex = _forEachIndex;
                            };
                        } forEach _sizeDiffs;

                        (_candidates select _bestIndex) params ["_bestSystem", "_bestRole", "_bestInfo"];

                        if (_role == "launcher") then {
                            _entry set ["launcherAttempts", (_entry getOrDefault ["launcherAttempts", 0]) + 1];
                            _hasLauncher = true;
                        } else {
                            _hasCiws = true;
                        };

                        _existing pushBack createHashMapFromArray [
                            ["target", _object],
                            ["system", _bestSystem],
                            ["role", _bestRole],
                            ["weaponInfo", _bestInfo],
                            ["assignedAt", time],
                            ["lastShotAt", -1],
                            ["roundsFired", 0],
                            ["interceptors", []]
                        ];
                        _busyTurrets pushBack [_bestSystem, _bestInfo select 0, _contactKey];
                        _allWeapons deleteAt (_roleIndices select _bestIndex);

                        diag_log text format ["[AEGIS-M] ASSIGN: %1 (%2, %3 %4) -> %5 (%6, %7m, %8m AGL)", _bestSystem, typeOf _bestSystem, _bestRole, _bestInfo select 1, _object, _class, round (_dists select _bestIndex), round _height];
                    };
                };
            };
        } forEach ["launcher", "ciws"];

        if (_existing isNotEqualTo []) then { _claims set [_contactKey, _existing]; };
    };
} forEach _orderedKeys;

_logic setVariable ["AEGISM_claims", _claims, false];
_logic setVariable ["AEGISM_withheldCiws", _withheldCiws, false];
