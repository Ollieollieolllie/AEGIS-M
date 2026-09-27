/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_assignEngagements

Description:
    Site-level engagement coordinator: runs once per Site (not once per
    System) to decide, for every pooled contact, which member System and
    which of its weapons should engage it -- replacing the old model where
    every System independently ran aegism_intercept_fnc_selectTarget against
    the shared pool with no awareness of what its siblings were doing beyond
    a same-instant claim check. A System with no Network (standalone, no
    Site synced) never goes through this function at all -- it still calls
    aegism_intercept_fnc_selectTarget directly, per its own doc comment.

    Weapon fit: a "launcher" weapon's fit for a contact is scored by how
    closely its loaded ammo's size (aegism_intercept_fnc_munitionSize --
    real indirectHitRange, metres) matches the contact's own classified
    munition's size where the contact IS a munition (closest-size match
    wins, i.e. don't spend a large anti-ship-class interceptor on a small
    inbound rocket if a smaller interceptor is also available, and don't
    send an undersized interceptor at a large inbound missile if a bigger
    one is available) -- for a non-munition contact (aircraft/helicopter/
    drone, which aegism_intercept_fnc_munitionSize can't size, having no
    ammo of its own) every launcher ties on size (sizeDiff 0 for all) and
    the nearest System's weapon wins instead. This is a coarser rule than
    aegism_intercept_fnc_selectTarget's own doctrine-driven targetPriority
    (nearest/fastestClosing/highestValue) scoring, deliberately: this
    function decides WHICH WEAPON takes a given contact, not WHICH CONTACT
    a weapon should prefer among several -- selectTarget's fuller scoring
    is still what a standalone (no-Network) System uses to choose between
    multiple candidate contacts in the first place.

    CIWS timing (AEGISM_Module_Site's "CIWS Engages as Last Resort Only"
    Doctrine toggle, default off): when off, a CIWS-capable System is
    assigned to any in-envelope, allowlisted contact its own weapon can
    reach, in parallel with any launcher assignment already covering the
    same contact -- a fast/close inbound threat shouldn't wait on an
    unproven missile shot. When on, a contact already covered by a live
    (unexpired, not yet failed) launcher assignment is withheld from CIWS
    entirely, UNLESS the contact is within that CIWS weapon's own doctrine-
    scaled max range at a fraction the missile intercept geometry no longer
    favours (AEGISM_CIWS_OVERRIDE_RANGE_FRACTION of maxRange) -- a real
    point-defense gun does not hold fire on something already inside its
    own effective bubble just because a missile was fired at it first.

    Failure/retry: a launcher assignment records its own lastShotAt/
    roundsFired. If AEGISM_ASSIGNMENT_FLIGHT_GRACE seconds have passed since
    its last shot and the contact is still alive and still pooled, that
    assignment is considered failed (the shot missed, or never got a clean
    shot off per aegism_intercept_fnc_fireWeapon's own reliability roll) --
    it's cleared from AEGISM_claims so the next tick's scoring pass can
    re-assign a launcher to it, scored completely fresh each time rather
    than preferring whichever System tried before (a launcher that's now
    further away or a worse size-fit than a sibling shouldn't keep the job
    just because it went first).

    Launcher fit is a two-key sort, size first then distance, but size
    ties are treated as a BAND (AEGISM_SIZE_TIE_TOLERANCE, not exact float
    equality) rather than an exact match -- interceptors are rarely
    identically sized even when "close enough" for a given threat, so
    without this band distance would almost never actually get to break a
    tie in practice, and the nearest-available launcher (which can usually
    engage soonest and most reliably) would lose out to a marginally
    closer-sized but much further-away one for no real benefit.

    Threat re-assessment on repeat attempts: once AEGISM_
    RETRY_THREAT_ASSESSMENT_THRESHOLD total launcher shots have already
    been fired at a contact (tracked cumulatively on its own pool entry,
    "launcherAttempts", surviving across individual assignments being
    created/cleared) and it's STILL alive, a further launcher shot is only
    authorized if no other currently-pooled, currently-unassigned contact
    outranks it by aegism_intercept_fnc_threatValue -- i.e. the battery
    doesn't keep feeding a stubborn target past a threshold hit count while
    something more dangerous sits unengaged for lack of a free launcher,
    but a target with nothing better competing for the resource is still
    retried without an arbitrary hard cap (there's no reason to give up on
    the only threat present just because it's proven tough to kill).

    Writes AEGISM_claims (per pool owner Network, i.e. this Site): HashMap
    keyed by contact netId string, value = ARRAY of assignment records (at
    most one per role currently active on that contact), each a HashMap
    with keys "system" <OBJECT>, "role" <STRING>, "weaponInfo" <ARRAY, see
    aegism_system_fnc_discoverCapabilities>, "assignedAt" <NUMBER (time)>,
    "lastShotAt" <NUMBER, -1 if never fired>, "roundsFired" <NUMBER>. This
    replaces the OLD claims shape (a single [claimant, timestamp] pair) --
    aegism_intercept_fnc_engagementLoop reads this new shape directly for
    any System synced to a Network, and no longer calls aegism_intercept_
    fnc_selectTarget for that case at all (selectTarget is now only used
    directly by a standalone System's own engagementLoop path, scoring
    against its own un-coordinated pool).

    Also writes AEGISM_withheldCiws: ARRAY of [contactKey, system] pairs,
    one per contact where a CIWS-capable weapon was otherwise eligible but
    withheld this tick by the "last resort" doctrine gate above. Purely
    diagnostic -- no engagement logic reads it, only aegism_fnc_debugDraw,
    so a withheld-by-doctrine CIWS is visually distinct from one that's
    simply out of range/ammo/envelope.

    Also sets "launcherAttempts" (NUMBER, incremented once per new launcher
    assignment created) directly on each contact's own AEGISM_pooledContacts
    entry -- technically a aegism_detect_fnc_addContact-owned data structure
    (see that function's own doc comment for the rest of its shape), but
    this field only ever exists to feed the threat re-assessment gate
    above, so it's simplest kept alongside "class"/"object"/"firstSeen"
    rather than a separate parallel HashMap solely for this one counter.
    addContact's own re-add path (aegism_detect_fnc_confidenceLoop/
    trackMunition refreshing an already-pooled contact) only ever touches
    "class"/"confidence" in place, so this field survives untouched across
    those refreshes for as long as the contact stays pooled.

Parameters:
    _logic - the Site logic object to coordinate <OBJECT>

Returns:
    Nothing (intended to be wrapped in a CBA_fnc_addPerFrameHandler by the
    caller, at the same cadence as aegism_intercept_fnc_engagementLoop so
    assignments are fresh each time a System's own loop consults them)

Examples:
    [_site] call aegism_intercept_fnc_assignEngagements;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_ASSIGNMENT_FLIGHT_GRACE 8
#define AEGISM_CIWS_OVERRIDE_RANGE_FRACTION 0.4
#define AEGISM_SIZE_TIE_TOLERANCE 50
#define AEGISM_RETRY_THREAT_ASSESSMENT_THRESHOLD 3

params ["_logic"];

if (isNull _logic) exitWith {};

private _members = _logic getVariable ["AEGISM_networkMembers", []];
private _pool = _logic getVariable ["AEGISM_pooledContacts", createHashMap];
private _claims = _logic getVariable ["AEGISM_claims", createHashMap];
private _engagementSettings = _logic getVariable "AEGISM_engagement";
if (isNil "_engagementSettings") exitWith {};

private _withheldCiws = [];
private _ciwsLastResort = _engagementSettings getOrDefault ["ciwsLastResort", false];
private _minRange = [_engagementSettings getOrDefault ["minRange", 500]] call aegism_fnc_scaledRange;
private _maxRange = [_engagementSettings getOrDefault ["maxRange", 8000]] call aegism_fnc_scaledRange;
private _minAltitude = _engagementSettings getOrDefault ["minAltitude", 0];
private _maxAltitude = _engagementSettings getOrDefault ["maxAltitude", 6000];
private _allowlist = _engagementSettings getOrDefault ["targetClassAllowlist", []];

// --- Collect every live weapon across every member System, tagged with its
// own System/role/position/live-ammo-check, once per tick rather than per
// contact. ---
private _allWeapons = [];
{
    private _system = _x;
    if (!isNull _system && {alive _system}) then {
        private _systemData = _system getVariable "AEGISM_system";
        if (!isNil "_systemData") then {
            {
                private _role = _x;
                private _weaponPool = _systemData get (["launcherWeapons", "ciwsWeapons"] select (_role == "ciws"));
                {
                    _x params ["_turretPath", "_weaponClass", "_magClass", "_size"];
                    if ((_system magazineTurretAmmo [_magClass, _turretPath]) > 0) then {
                        _allWeapons pushBack [_system, _role, _x];
                    };
                } forEach _weaponPool;
            } forEach ["launcher", "ciws"];
        };
    };
} forEach _members;

if (_allWeapons isEqualTo []) exitWith {};

// --- Score and (re)assign every pooled contact. ---
{
    private _contactKey = _x;
    private _entry = _pool get _contactKey;
    private _object = _entry get "object";
    private _class = _entry get "class";

    if (!isNull _object && {alive _object} && {_class in _allowlist}) then {
        private _targetPos = getPosASL _object;
        private _contactSize = [typeOf _object] call aegism_intercept_fnc_munitionSize;

        private _altitude = _targetPos select 2;

        private _existing = _claims getOrDefault [_contactKey, []];
        // Drop any assignment whose System died, lost the contact out of
        // envelope (range OR altitude -- a contact that climbed/dived out
        // of the altitude band but stayed within slant range must still be
        // freed up, same as one that flew out of range), or fired and got
        // AEGISM_ASSIGNMENT_FLIGHT_GRACE seconds of silence with the
        // contact still alive -- all four mean "this assignment is no
        // longer doing anything useful, free it up".
        _existing = _existing select {
            private _record = _x;
            private _system = _record get "system";
            private _dist = (getPosASL _system) distance _targetPos;
            private _failed = (_record get "lastShotAt") >= 0 && {time > (_record get "lastShotAt") + AEGISM_ASSIGNMENT_FLIGHT_GRACE};
            !isNull _system && {alive _system} && {_dist >= _minRange} && {_dist <= _maxRange} && {_altitude >= _minAltitude} && {_altitude <= _maxAltitude} && {!_failed}
        };

        private _hasLauncher = (_existing findIf { (_x get "role") == "launcher" }) != -1;
        private _hasCiws = (_existing findIf { (_x get "role") == "ciws" }) != -1;

        // Candidate indices into _allWeapons are (re)computed FRESH for
        // EACH role below, not once for both -- a winning "launcher"
        // candidate is deleteAt'd from _allWeapons (see below) before the
        // "ciws" role is scored, which shifts every later index; reusing
        // indices computed before that deletion would silently point at
        // the wrong (shifted) weapon or past the array's new end.
        {
            private _role = _x;
            private _roleIndices = [];
            for "_wi" from 0 to (count _allWeapons - 1) do {
                (_allWeapons#_wi) params ["_candSystem", "_candRole"];
                if (_candRole == _role) then {
                    private _alreadyCovered = [_hasLauncher, _hasCiws] select (_role == "ciws");
                    if (!_alreadyCovered) then {
                        private _dist = (getPosASL _candSystem) distance _targetPos;
                        if ((_dist >= _minRange) && {_dist <= _maxRange} && {_altitude >= _minAltitude} && {_altitude <= _maxAltitude}) then {
                            _roleIndices pushBack _wi;
                        };
                    };
                };
            };
            if (_roleIndices isNotEqualTo []) then {
                private _roleCandidates = _roleIndices apply { _allWeapons#_x };
                private _allowed = true;

                // CIWS-as-last-resort: withhold unless no launcher is
                // currently covering this contact, or the contact is
                // already well inside this weapon's own bubble (real
                // point-defense doesn't hold fire on something already
                // close just because a missile was fired at it first).
                if (_role == "ciws" && _ciwsLastResort && _hasLauncher) then {
                    private _nearestCiwsDist = selectMin (_roleCandidates apply { (getPosASL (_x select 0)) distance _targetPos });
                    _allowed = _nearestCiwsDist <= (_maxRange * AEGISM_CIWS_OVERRIDE_RANGE_FRACTION);
                    if (!_allowed) then {
                        // Recorded purely for aegism_fnc_debugDraw -- an
                        // eligible-but-doctrine-withheld CIWS should look
                        // different from one that's simply out of range or
                        // out of ammo, otherwise the one doctrine behaviour
                        // most worth visualizing (CIWS held back on purpose)
                        // is indistinguishable from CIWS just being idle.
                        // Not read by any engagement logic, only the draw.
                        _withheldCiws pushBack [_contactKey, _roleCandidates#0 select 0];
                    };
                };

                // Threat re-assessment: once this contact has already
                // eaten AEGISM_RETRY_THREAT_ASSESSMENT_THRESHOLD launcher
                // shots and is still alive, a further launcher shot is only
                // authorized if nothing else currently pooled and still
                // unassigned outranks it -- checked here, before scoring a
                // launcher candidate, so a stubborn target doesn't keep
                // consuming launchers while a higher-value contact sits
                // unengaged for lack of one. CIWS is unaffected (point-
                // defense doesn't "decide" a target isn't worth another
                // burst the way a limited missile stock does).
                if (_allowed && {_role == "launcher"}) then {
                    private _launcherAttempts = _entry getOrDefault ["launcherAttempts", 0];
                    if (_launcherAttempts >= AEGISM_RETRY_THREAT_ASSESSMENT_THRESHOLD) then {
                        private _thisValue = [_class] call aegism_intercept_fnc_threatValue;
                        // select (not count) -- exitWith inside a count code
                        // block aborts the WHOLE count early and returns
                        // whatever exitWith gave it (a Boolean here), not a
                        // per-element short-circuit like select/findIf; it
                        // would throw comparing that Boolean against 0 below.
                        private _outrankingContacts = (keys _pool) select {
                            private _otherKey = _x;
                            if (_otherKey == _contactKey) exitWith { false };
                            private _otherEntry = _pool get _otherKey;
                            private _otherObject = _otherEntry get "object";
                            (!isNull _otherObject) && {alive _otherObject} && {(_otherEntry get "class") in _allowlist} &&
                            {((_claims getOrDefault [_otherKey, []]) findIf { (_x get "role") == "launcher" }) == -1} &&
                            {([_otherEntry get "class"] call aegism_intercept_fnc_threatValue) > _thisValue}
                        };
                        _allowed = _outrankingContacts isEqualTo [];
                    };
                };

                if (_allowed) then {
                    // Best fit: for a launcher against a sized (munition)
                    // contact, closest warhead-size match wins first --
                    // a Titan-class interceptor against a small inbound
                    // rocket, or a heavier interceptor against a large
                    // inbound missile, whichever this System's actual
                    // loadout has closer to the threat's own size, rather
                    // than always grabbing the biggest or first-found
                    // weapon. Against a non-munition contact (_contactSize
                    // 0, aircraft/heli/drone) or for CIWS (size always 0),
                    // every candidate ties on size (sizeDiff 0 for all) and
                    // distance decides. Size ties are a TOLERANCE BAND
                    // (AEGISM_SIZE_TIE_TOLERANCE), not exact float equality
                    // -- interceptors are rarely identically sized even
                    // when equally "close enough" for a given threat, so an
                    // exact-match requirement would mean distance almost
                    // never actually gets to break a tie, and the nearest
                    // available launcher (usually the one that can engage
                    // soonest and most reliably) would lose out to a
                    // marginally closer-sized but much further-away one for
                    // no real benefit. Two-key comparison done manually
                    // (sizeDiff band, then distance) since SQF's "<" only
                    // compares numbers, not arrays/tuples.
                    private _sizeDiffs = _roleCandidates apply {
                        _x params ["", "", "_candWeaponInfo"];
                        _candWeaponInfo params ["", "", "", "_candSize"];
                        abs (_candSize - _contactSize)
                    };
                    private _dists = _roleCandidates apply { (getPosASL (_x select 0)) distance _targetPos };
                    // "Tied" is measured against the TRUE minimum sizeDiff,
                    // not by chaining pairwise comparisons against whichever
                    // candidate currently holds _bestIndex -- a tolerance
                    // BAND is not a transitive equivalence (A can tie B, and
                    // B can tie C, without A tying C), so a chained "is this
                    // one tied with the current best" walk can drift through
                    // a series of overlapping bands and end up picking a
                    // candidate whose size is nowhere near the true best fit,
                    // just because it looked good next to an intermediate
                    // "bridge" candidate. Finding the real minimum first and
                    // comparing every candidate against THAT fixed value
                    // avoids the drift entirely.
                    private _minSizeDiff = selectMin _sizeDiffs;
                    private _bestIndex = -1;
                    for "_i" from 0 to (count _roleCandidates - 1) do {
                        if (_sizeDiffs#_i <= (_minSizeDiff + AEGISM_SIZE_TIE_TOLERANCE)) then {
                            if (_bestIndex == -1 || {_dists#_i < _dists#_bestIndex}) then { _bestIndex = _i; };
                        };
                    };
                    (_roleCandidates#_bestIndex) params ["_bestSystem", "_bestRole", "_bestWeaponInfo"];

                    if (_role == "launcher") then {
                        _entry set ["launcherAttempts", (_entry getOrDefault ["launcherAttempts", 0]) + 1];
                    };

                    _existing pushBack createHashMapFromArray [
                        ["system", _bestSystem],
                        ["role", _bestRole],
                        ["weaponInfo", _bestWeaponInfo],
                        ["assignedAt", time],
                        ["lastShotAt", -1],
                        ["roundsFired", 0]
                    ];
                    if (_role == "ciws") then { _hasCiws = true; } else { _hasLauncher = true; };

                    // Remove the winning weapon from _allWeapons itself (not
                    // just this contact's local flags) so a LATER contact in
                    // this same forEach (keys _pool) pass can no longer see
                    // it as a candidate -- without this, the same physical
                    // weapon could win "best fit" for two different contacts
                    // in one tick, leaving one assignment a phantom no
                    // System ever executes (see this file's header comment).
                    _allWeapons deleteAt (_roleIndices#_bestIndex);
                };
            };
        } forEach ["launcher", "ciws"];

        if (_existing isEqualTo []) then {
            _claims deleteAt _contactKey;
        } else {
            _claims set [_contactKey, _existing];
        };
    } else {
        _claims deleteAt _contactKey;
    };
} forEach (keys _pool);

// Prune assignments for contacts no longer in the pool at all (destroyed/
// left simulation and already removed by aegism_detect_fnc_removeContact).
{
    if !(_x in (keys _pool)) then { _claims deleteAt _x; };
} forEach (keys _claims);

_logic setVariable ["AEGISM_claims", _claims, false];
_logic setVariable ["AEGISM_withheldCiws", _withheldCiws, false];
