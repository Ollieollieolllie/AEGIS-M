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
    either re-assign the SAME System (if it still has ammo and salvoSize
    budget left) or hand the contact to a different/better-fit weapon
    (including CIWS, once the "last resort" gate above allows it).

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
                    // distance alone breaks the tie. Two-key comparison
                    // done manually (sizeDiff, then distance) since SQF's
                    // "<" only compares numbers, not arrays/tuples.
                    private _sizeDiffs = _roleCandidates apply {
                        _x params ["", "", "_candWeaponInfo"];
                        _candWeaponInfo params ["", "", "", "_candSize"];
                        abs (_candSize - _contactSize)
                    };
                    private _dists = _roleCandidates apply { (getPosASL (_x select 0)) distance _targetPos };
                    private _bestIndex = 0;
                    for "_i" from 1 to (count _roleCandidates - 1) do {
                        private _better = (_sizeDiffs#_i < _sizeDiffs#_bestIndex) || {(_sizeDiffs#_i == _sizeDiffs#_bestIndex) && {_dists#_i < _dists#_bestIndex}};
                        if (_better) then { _bestIndex = _i; };
                    };
                    (_roleCandidates#_bestIndex) params ["_bestSystem", "_bestRole", "_bestWeaponInfo"];

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
