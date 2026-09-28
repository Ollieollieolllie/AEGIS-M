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
    system, AEGISM_pooledContacts, AEGISM_claims, AEGISM_withheldCiws,
    AEGISM_engagementState_ROLE) rather than a dependent of them.

    Per pool owner (System or Network, from AEGISM_allPoolOwners):
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
          the contact, coloured yellow once it's fired at least one round
          (roundsFired > 0) or green if not yet, with a text label showing
          the role and rounds fired. Every entry in the Site's own AEGISM_
          withheldCiws (a CIWS eligible for this contact but held back by
          the "CIWS Engages as Last Resort Only" doctrine gate) draws a
          dashed-look (short-segment) orange line instead, labeled "CIWS
          WITHHELD (last resort)" -- distinct from an active assignment so
          a withheld-on-purpose CIWS doesn't read as simply idle/incapable.
        - For a STANDALONE System (no Network -- its own AEGISM_
          engagementState_ROLE, since it never appears as a claims
          assignee): the same line/label, drawn from its own local
          acquisition state instead, coloured grey if LOS is currently
          blocked.

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
            drawLine3D [_prevPos, _pos, _color];
        };
        _prevPos = _pos;
    };
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
        private _entry = _x;
        private _object = _entry get "object";
        if (!isNull _object) then {
            private _claimRecords = _claims getOrDefault [str (netId _object), []];
            private _claimed = count _claimRecords > 0;
            private _color = if (_claimed) then { [1, 0.2, 0.2, 1] } else { [1, 1, 1, 0.9] };

            drawIcon3D [
                "\a3\ui_f\data\igui\cfg\simpleTasks\types\destroy_ca.paa",
                _color, getPosASLVisual _object, 1, 1, 0,
                format ["%1 (%2s)%3", _entry get "class", round (time - (_entry get "firstSeen")), ["", " [CLAIMED]"] select _claimed],
                1, 0.035, "TahomaB"
            ];
        };
    } forEach (values _pool);

    // --- Active engagements, per role ---
    if (_isSystem) then {
        // Standalone: this System's own local acquisition state (it can
        // never appear as a claims assignee, having no Network).
        {
            private _role = _x;
            private _stateKey = format ["AEGISM_engagementState_%1", _role];
            private _state = _poolOwner getVariable _stateKey;
            if (!isNil "_state") then {
                private _targetNetId = _state get "targetNetId";
                if (_targetNetId != "") then {
                    private _target = objectFromNetId _targetNetId;
                    if (!isNull _target) then {
                        private _weaponPos = AGLToASL (eyePos _poolOwner);
                        private _targetPos = getPosASL _target;
                        private _roundsFired = _state getOrDefault ["roundsFiredThisEngagement", 0];
                        private _losClear = (lineIntersectsSurfaces [_weaponPos, _targetPos, _poolOwner, _target, true, 1]) isEqualTo [];
                        private _color = if (!_losClear) then { [0.5, 0.5, 0.5, 1] } else { if (_roundsFired > 0) then { [1, 0.8, 0, 1] } else { [0.2, 1, 0.2, 1] } };

                        drawLine3D [_weaponPos, _targetPos, _color];
                        drawIcon3D [
                            "\a3\ui_f\data\igui\cfg\simpleTasks\types\attack_ca.paa",
                            _color, _targetPos, 1, 1, 0,
                            format ["%1: %2 shot(s)%3", _role, _roundsFired, ["", " [NO LOS]"] select !_losClear],
                            1, 0.035, "TahomaB"
                        ];
                    };
                };
            };
        } forEach ["launcher", "ciws"];
    } else {
        // Networked (Site): every current assignment record across the
        // whole battery, from aegism_intercept_fnc_assignEngagements.
        {
            private _contactKey = _x;
            private _target = objectFromNetId _contactKey;
            if (!isNull _target) then {
                {
                    private _record = _x;
                    private _assignedSystem = _record get "system";
                    if (!isNull _assignedSystem) then {
                        private _weaponPos = AGLToASL (eyePos _assignedSystem);
                        private _targetPos = getPosASL _target;
                        private _roundsFired = _record get "roundsFired";
                        private _color = if (_roundsFired > 0) then { [1, 0.8, 0, 1] } else { [0.2, 1, 0.2, 1] };

                        drawLine3D [_weaponPos, _targetPos, _color];
                        drawIcon3D [
                            "\a3\ui_f\data\igui\cfg\simpleTasks\types\attack_ca.paa",
                            _color, _targetPos, 1, 1, 0,
                            format ["%1: %2 shot(s)", _record get "role", _roundsFired],
                            1, 0.035, "TahomaB"
                        ];
                    };
                } forEach (_claims get _contactKey);
            };
        } forEach (keys _claims);

        // Doctrine-withheld CIWS: eligible but held back this tick by the
        // "CIWS Engages as Last Resort Only" gate -- drawn distinctly from
        // an active assignment so it doesn't read as simply idle/incapable.
        {
            _x params ["_contactKey", "_withheldSystem"];
            private _target = objectFromNetId _contactKey;
            if (!isNull _target && {!isNull _withheldSystem}) then {
                private _weaponPos = AGLToASL (eyePos _withheldSystem);
                private _targetPos = getPosASL _target;
                private _segments = 6;
                for "_i" from 0 to (_segments - 1) do {
                    if (_i % 2 == 0) then {
                        private _from = _weaponPos vectorAdd ((_targetPos vectorDiff _weaponPos) vectorMultiply (_i / _segments));
                        private _to = _weaponPos vectorAdd ((_targetPos vectorDiff _weaponPos) vectorMultiply ((_i + 1) / _segments));
                        drawLine3D [_from, _to, [1, 0.5, 0, 1]];
                    };
                };
                drawIcon3D [
                    "\a3\ui_f\data\igui\cfg\simpleTasks\types\attack_ca.paa",
                    [1, 0.5, 0, 1], _weaponPos, 1, 1, 0,
                    "CIWS WITHHELD (last resort)",
                    1, 0.035, "TahomaB"
                ];
            };
        } forEach (_poolOwner getVariable ["AEGISM_withheldCiws", []]);
    };
};

{ [_x] call _fnDrawPoolOwner; } forEach (missionNamespace getVariable ["AEGISM_allPoolOwners", []]);
