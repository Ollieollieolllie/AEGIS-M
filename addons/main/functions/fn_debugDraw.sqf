/* ----------------------------------------------------------------------------
Function: aegism_fnc_debugDraw

Description:
    Per-frame 3D debug visualisation of AEGIS-M's live detection/engagement
    state: pooled contacts, network claims, and each
    System's acquired target + LOS check, all drawn directly from the same
    variables the real detection/intercept pipeline reads and writes, so
    what's on screen is exactly what the mod is actually doing, not a
    separate simulation of it.

    Gated entirely by the "aegism_main_debugDraw" CBA setting (client-side,
    no gameplay effect either way) and by drawing only when a debug 3D
    context is actually open (findDisplay 46/312, i.e. Zeus or the 3DEN
    equivalent) OR unconditionally in the main 3D view -- drawIcon3D/
    drawLine3D silently no-op outside a valid 3D draw context, so no extra
    guard is needed beyond the setting check itself.

    Reads (never writes) only plain getVariable state already maintained
    elsewhere, deliberately with NO calls into aegism_system_fnc_X, aegism_
    intercept_fnc_X, or aegism_detect_fnc_X functions -- this lives in
    aegism_main, which every other AEGIS-M addon depends on, not the other
    way around, so this file must stay a pure reader of the variable
    contract those addons already publish (AEGISM_allPoolOwners, AEGISM_
    allSystems, AEGISM_system, AEGISM_pooledContacts, AEGISM_claims,
    AEGISM_assigned, AEGISM_withheldCiws, and each System's AEGISM_turrets:
    per turret, its aim records "aim_<role>" and a standalone System's
    engagement states "standalone_<role>") rather than a dependent of them.
    Only draws where the engagement pipeline runs (singleplayer, Eden
    Preview, a hosted game's host).

    Two separate top-level loops, over two separate lists, NOT one: every
    recognized System (AEGISM_allSystems, aegism_system_fnc_moduleInit) gets
    its own persistent live state label (see below), but only a System with
    real radar capability, or a Network/Site logic, ever appears in
    AEGISM_allPoolOwners (that list is scoped to "has a pool worth
    scanning") -- so a pure launcher/CIWS System with no radar of its own
    would otherwise never be visited by this function at all, and never
    show a label, despite being exactly the kind of System "why doesn't
    this launcher ever engage" debugging most needs to see.

    Per System (AEGISM_allSystems): a persistent live state label at its own
    position -- ACE missileguidance-style continuous status, always visible
    while debug draw is on, rather than a one-shot command you have to think
    to run: whether it's networked or standalone, its resolvedContactSource
    (the single most useful field for diagnosing "why doesn't this launcher
    ever engage" -- see aegism_system_fnc_resolveContactSource's own doc
    comment), and per-role live ammo/assignment status (launcherWeapons/
    ciwsWeapons count with live rounds, and whether AEGISM_claims currently
    has an assignment for this System in that role). Colour follows the
    same readiness signal: red if this System has zero live ammo across
    every discovered weapon (nothing it could do even if assigned), orange
    if networked but resolvedContactSource doesn't include "network" (synced
    to a Site with no radar-capable member -- exactly the failure this was
    built to surface), white otherwise.

    Per pool owner (System with radar, or Network, from AEGISM_allPoolOwners):
        - A System with hasRadar draws a thin circle at its detection range
          (radarRange, unscaled -- the real native sensor reach) around its
          position.
        - Every pooled contact (AEGISM_pooledContacts) draws an icon3D + text
          label (class, age since firstSeen) at the contact's position,
          coloured red if currently claimed/assigned to some System (per the
          owning pool owner's own AEGISM_claims, if any) or white if not.
        - For a Network/Site: every assignment record in its own AEGISM_
          claims (aegism_intercept_fnc_assignEngagements' output) draws a
          line from the assigned System's weapon-ish position (eyePos) to
          the contact, coloured by that engagement's own state (aegism_fnc_
          statusStyle: queued, reacting, slewing, range hold, firing, in
          flight, ...), labelled with the weapon, that state, shots or
          bursts fired and the distance. Every entry in the Site's own AEGISM_
          withheldCiws (a CIWS eligible for this contact but held back by
          the "CIWS Engages as Last Resort Only" doctrine gate) draws a
          dashed-look (short-segment) orange line instead, labeled "CIWS
          WITHHELD (last resort)" -- distinct from an active assignment so
          a withheld-on-purpose CIWS doesn't read as simply idle/incapable.
        - For a STANDALONE System (no Network -- each weapon turret's own
          engagement state, since it never appears as a claims assignee):
          the same line/label and colours.

Parameters:
    None (reads the CBA setting and global pool-owner list itself)

Returns:
    Nothing (intended to be wrapped in a CBA_fnc_addPerFrameHandler, added
    once from aegism's XEH_postInit)

Examples:
    [] call aegism_fnc_debugDraw;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

if !("aegism_main_debugDraw" call CBA_settings_fnc_get) exitWith {};

#define AEGISM_DEBUG_CIRCLE_SEGMENTS 36

private _fnDrawRangeCircle = {
    params ["_center", "_radius", "_color"];
    private _prevPos = [];
    for "_i" from 0 to AEGISM_DEBUG_CIRCLE_SEGMENTS do {
        private _angle = (_i % AEGISM_DEBUG_CIRCLE_SEGMENTS) * (360 / AEGISM_DEBUG_CIRCLE_SEGMENTS);
        private _pos = _center vectorAdd [(_radius * sin _angle), (_radius * cos _angle), 0];
        if (_i > 0) then {
            drawLine3D [ASLToAGL _prevPos, ASLToAGL _pos, _color];
        };
        _prevPos = _pos;
    };
};

// Persistent live state label for one System -- see this function's own
// doc comment for what each field means and why. Reads only plain
// getVariable state, same as everything else in this file. Called for
// EVERY recognized System (AEGISM_allSystems, below), not just pool owners
// -- a pure launcher/CIWS System with no radar of its own never joins
// AEGISM_allPoolOwners (that list is scoped to "has a pool worth scanning",
// see aegism_system_fnc_moduleInit's own doc comment on AEGISM_allSystems),
// but this diagnostic needs to reach it too, since "why isn't this launcher
// engaging" is exactly the question this label exists to answer.
private _fnDrawSystemLabel = {
    params ["_vehicle", "_system"];

    private _network = _vehicle getVariable ["AEGISM_network", objNull];
    private _contactSource = _vehicle getVariable ["AEGISM_resolvedContactSource", []];
    private _launcherWeapons = _system get "launcherWeapons";
    private _ciwsWeapons = _system get "ciwsWeapons";

    private _fnRoleStatus = {
        params ["_vehicle", "_network", "_weapons", "_role"];
        if (_weapons isEqualTo []) exitWith { "" };
        private _liveRounds = 0;
        { _x params ["_turretPath", "", "_magClass"]; _liveRounds = _liveRounds + (_vehicle magazineTurretAmmo [_magClass, _turretPath]); } forEach _weapons;

        private _turrets = _vehicle getVariable ["AEGISM_turrets", createHashMap];
        private _assigned = if (isNull _network) then {
            (_weapons findIf {
                !isNull (((_turrets getOrDefault [_x select 0, createHashMap]) getOrDefault ["standalone_" + _role, createHashMap]) getOrDefault ["target", objNull])
            }) != -1
        } else {
            ((_vehicle getVariable ["AEGISM_assigned", createHashMap]) getOrDefault [_role, []]) isNotEqualTo []
        };

        // Live barrel alignment (the first weapon turret's aim record),
        // shown only while fresh (the loop is actually aiming this role).
        private _aimText = "";
        private _aim = (_turrets getOrDefault [(_weapons select 0) select 0, createHashMap]) getOrDefault ["aim_" + _role, []];
        if (_aim isNotEqualTo [] && {_assigned} && {time - (_aim select 2) < 1}) then {
            _aimText = format [",aim %1/%2", round ((_aim select 0) * 10) / 10, round ((_aim select 1) * 100) / 100];
        };

        format [" %1x%2(%3rnd%4%5)", count _weapons, _role, _liveRounds, ["", ",ASSIGNED"] select _assigned, _aimText]
    };

    private _statusLine = format [
        "%1 contactSrc=%2%3%4",
        ["STANDALONE", "NETWORKED"] select !isNull _network,
        _contactSource,
        [_vehicle, _network, _launcherWeapons, "launcher"] call _fnRoleStatus,
        [_vehicle, _network, _ciwsWeapons, "ciws"] call _fnRoleStatus
    ];

    private _totalLiveAmmo = 0;
    { _x params ["_turretPath", "", "_magClass"]; _totalLiveAmmo = _totalLiveAmmo + (_vehicle magazineTurretAmmo [_magClass, _turretPath]); } forEach (_launcherWeapons + _ciwsWeapons);

    // Orange: networked but the resolved contact source doesn't include
    // "network" -- synced to a Site with no radar-capable member, the
    // exact silent-dead-end this overlay exists to surface (see
    // aegism_system_fnc_resolveContactSource's own doc comment). Red:
    // zero live ammo anywhere -- nothing this System could do even if
    // assigned. White otherwise.
    private _statusColor = if (_totalLiveAmmo <= 0) then {
        [1, 0.2, 0.2, 1]
    } else {
        if (!isNull _network && {!("network" in _contactSource)}) then { [1, 0.6, 0, 1] } else { [1, 1, 1, 1] }
    };

    // Reuses attack_ca.paa (already proven to load without warning
    // elsewhere in this same file, below) rather than a plausible-looking
    // but non-existent path -- an earlier version of this used
    // ".../simpleTasks/types/dot_ca.paa", which doesn't actually exist at
    // that path and flooded the RPT with "Cannot load texture" warnings
    // every single frame for every System.
    drawIcon3D [
        "\a3\ui_f\data\igui\cfg\simpleTasks\types\attack_ca.paa",
        _statusColor, (ASLToAGL getPosASLVisual _vehicle) vectorAdd [0, 0, 2], 0.4, 0.4, 0,
        _statusLine,
        1, 0.03, "TahomaB"
    ];
};

private _fnDrawPoolOwner = {
    params ["_poolOwner"];
    if (isNull _poolOwner) exitWith {};

    private _system = _poolOwner getVariable "AEGISM_system";
    private _isSystem = !isNil "_system";

    // --- Radar range ring (System only -- a Network logic has no sensor) ---
    if (_isSystem && {_system get "hasRadar"}) then {
        [getPosASL _poolOwner, _system get "radarRange", [0, 0.6, 1, 0.5]] call _fnDrawRangeCircle;
    };

    // --- Pooled contacts ---
    private _claims = _poolOwner getVariable ["AEGISM_claims", createHashMap];
    private _pool = _poolOwner getVariable ["AEGISM_pooledContacts", createHashMap];
    {
        private _entry = _y;
        private _object = _entry get "object";
        if (!isNull _object) then {
            private _claimRecords = _claims getOrDefault [_x, []];
            private _claimed = count _claimRecords > 0;
            private _color = if (_claimed) then { [1, 0.2, 0.2, 1] } else { [1, 1, 1, 0.9] };

            drawIcon3D [
                "\a3\ui_f\data\igui\cfg\simpleTasks\types\destroy_ca.paa",
                _color, ASLToAGL getPosASLVisual _object, 1, 1, 0,
                format ["%1 (%2s)%3", _entry get "class", round (time - (_entry get "firstSeen")), ["", " [CLAIMED]"] select _claimed],
                1, 0.035, "TahomaB"
            ];
        };
    } forEach _pool;

    // --- Active engagements, per role ---
    if (_isSystem) then {
        // Standalone: each weapon turret's own engagement state (it can
        // never appear as a claims assignee, having no Network). LOS is the
        // engagement loop's own last check.
        private _weaponPos = eyePos _poolOwner; // already ASL
        {
            private _turretState = _y;
            {
                private _role = _x;
                private _state = _turretState getOrDefault ["standalone_" + _role, createHashMap];
                private _target = _state getOrDefault ["target", objNull];
                if (!isNull _target) then {
                    private _targetPos = getPosASL _target;
                    private _roundsFired = _state getOrDefault ["roundsFired", 0];
                    ([_state getOrDefault ["status", ""]] call aegism_fnc_statusStyle) params ["_statusText", "_color"];
                    private _isGun = _role == "ciws";

                    drawLine3D [ASLToAGL _weaponPos, ASLToAGL _targetPos, _color];
                    drawIcon3D [
                        "\a3\ui_f\data\igui\cfg\simpleTasks\types\attack_ca.paa",
                        _color, ASLToAGL _targetPos, 1, 1, 0,
                        format ["%1: %2, %3 %4, %5m", ["missile", "gun"] select _isGun, _statusText, _roundsFired, ["shot(s)", "burst(s)"] select _isGun,
                            round (_weaponPos distance _targetPos)],
                        1, 0.035, "TahomaB"
                    ];
                };
            } forEach ["launcher", "ciws"];
        } forEach (_poolOwner getVariable ["AEGISM_turrets", createHashMap]);
    } else {
        // Networked (Site): every current assignment record across the
        // whole battery, from aegism_intercept_fnc_assignEngagements.
        {
            private _contactKey = _x;
            {
                private _record = _x;
                private _target = _record getOrDefault ["target", objNull];
                private _assignedSystem = _record get "system";
                if (!isNull _target && {!isNull _assignedSystem}) then {
                        private _weaponPos = eyePos _assignedSystem; // already ASL
                        private _targetPos = getPosASL _target;
                        private _roundsFired = _record get "roundsFired";
                        // Each engagement in its own state's colour (aegism_fnc_
                        // statusStyle): a launcher's queue shows which one it's
                        // on, which wait behind it, and which have missiles up.
                        ([_record getOrDefault ["status", ""]] call aegism_fnc_statusStyle) params ["_statusText", "_color"];
                        private _isGun = (_record get "role") == "ciws";

                        // Which weapon, and how far: a vehicle with both
                        // missiles and a gun (a Cheetah) draws both from the
                        // same spot.
                        drawLine3D [ASLToAGL _weaponPos, ASLToAGL _targetPos, _color];
                        drawIcon3D [
                            "\a3\ui_f\data\igui\cfg\simpleTasks\types\attack_ca.paa",
                            _color, ASLToAGL _targetPos, 1, 1, 0,
                            format ["%1 %2: %3, %4 %5, %6m", ["missile", "gun"] select _isGun, (_record get "weaponInfo") select 1, _statusText, _roundsFired,
                                ["shot(s)", "burst(s)"] select _isGun, round (_weaponPos distance _targetPos)],
                            1, 0.035, "TahomaB"
                        ];
                };
            } forEach (_claims get _contactKey);
        } forEach (keys _claims);

        // Doctrine-withheld CIWS: eligible but held back this tick by the
        // "CIWS Engages as Last Resort Only" gate -- drawn distinctly from
        // an active assignment so it doesn't read as simply idle/incapable.
        {
            _x params ["_contactKey", "_withheldSystem"];
            private _target = (_pool getOrDefault [_contactKey, createHashMap]) getOrDefault ["object", objNull];
            if (!isNull _target && {!isNull _withheldSystem}) then {
                private _weaponPos = eyePos _withheldSystem; // already ASL
                private _targetPos = getPosASL _target;
                private _segments = 6;
                for "_i" from 0 to (_segments - 1) do {
                    if (_i % 2 == 0) then {
                        private _from = _weaponPos vectorAdd ((_targetPos vectorDiff _weaponPos) vectorMultiply (_i / _segments));
                        private _to = _weaponPos vectorAdd ((_targetPos vectorDiff _weaponPos) vectorMultiply ((_i + 1) / _segments));
                        drawLine3D [ASLToAGL _from, ASLToAGL _to, [1, 0.5, 0, 1]];
                    };
                };
                drawIcon3D [
                    "\a3\ui_f\data\igui\cfg\simpleTasks\types\attack_ca.paa",
                    [1, 0.5, 0, 1], ASLToAGL _weaponPos, 1, 1, 0,
                    "CIWS WITHHELD (last resort)",
                    1, 0.035, "TahomaB"
                ];
            };
        } forEach (_poolOwner getVariable ["AEGISM_withheldCiws", []]);
    };
};

{ [_x] call _fnDrawPoolOwner; } forEach (missionNamespace getVariable ["AEGISM_allPoolOwners", []]);

// Separate list, separate loop -- see _fnDrawSystemLabel's own comment for
// why this can't just reuse AEGISM_allPoolOwners above (that list excludes
// any System with no radar of its own, launchers included).
private _allSystems = (missionNamespace getVariable ["AEGISM_allSystems", []]) select { !isNull _x && {alive _x} };
missionNamespace setVariable ["AEGISM_allSystems", _allSystems, false];
{
    private _system = _x getVariable "AEGISM_system";
    if (!isNil "_system") then {
        [_x, _system] call _fnDrawSystemLabel;
    };
} forEach _allSystems;
