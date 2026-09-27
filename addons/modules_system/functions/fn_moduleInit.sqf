/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_moduleInit

Description:
    Per-vehicle AEGIS-M System setup. There is no role checkbox or
    per-vehicle Attribute anymore -- capability is discovered entirely from
    the vehicle's own native config and current loadout (see aegism_system_
    fnc_discoverCapabilities): if it has a radar, it has a radar; if it has
    guided missiles, it's a launcher; if it also has a high-rate-of-fire gun
    (SHORAD or Tigris-style all-in-one vehicle), it's also a CIWS/CRAM.
    Called for every vehicle exactly once by aegism_system_fnc_
    scanForRoles's periodic discovery sweep (this addon's XEH_postInit.sqf).
    Guarded by "AEGISM_systemInitialized", set immediately regardless of
    outcome, so a vehicle with no AEGIS-M-relevant capability is checked
    once and never re-scanned, and a repeat call for one that does qualify
    is a harmless no-op.

    Stores the discovered capabilities on the vehicle ("AEGISM_system"),
    then resolves and caches its Doctrine and Personality (link validation
    rules in the AEGIS-M architecture plan, section 1), caching them as
    "AEGISM_resolvedEngagementSettings" / "AEGISM_resolvedCrew" -- these two
    are what aegism_intercept_fnc_engagementLoop actually reads every tick.
    "AEGISM_resolvedContactSource" is also cached (aegism_system_fnc_
    resolveContactSource), but it exists purely for that function's own
    diag_log warning ("this System has no contact source and will never
    detect anything") -- nothing currently reads the cached value itself, so
    don't add a real dependency on it without checking that function's own
    doc comment first. If it has radar, also initializes "AEGISM_
    pooledContacts" (HashMap, see aegism_detect_fnc_addContact) so the
    detection loop has somewhere to store this System's own sensor contacts.

    The capability discovery above only ever happens once, at this one-time
    init -- a vehicle's turrets/sensors are fixed for its lifetime (a
    magazine swap mid-mission changing which specific weapon fires doesn't
    change WHETHER it's a launcher/CIWS at all, since launcherWeapons/
    ciwsWeapons are re-checked for live ammo at fire time anyway, see
    aegism_intercept_fnc_engagementLoop). The three AEGISM_resolvedX caches
    are different: they depend on "AEGISM_engagement"/"AEGISM_crew"/
    "AEGISM_network", which CAN change later (AEGISM_Module_Site runs its
    own live-resync poll, see aegism_fnc_pollSyncedObjects), so this System
    also registers a server-only, 5-second re-resolution poll (below) that
    re-derives and overwrites all three caches from whatever those inputs
    currently are. This is what makes a Zeus operator syncing a new Site
    onto an already-running System actually take effect, instead of being
    silently ignored for the rest of the mission.

    Since this now runs from a periodic scan rather than an isGlobal=1
    module's guaranteed-everywhere activation, whichever machine's scan
    reaches a given vehicle first runs this in full -- the scan itself is
    deliberately not isServer-gated so it still reaches every client,
    matching the old per-machine-identical module behavior. The actual
    per-frame detection (aegism_detect_fnc_confidenceLoop) and engagement
    (aegism_intercept_fnc_engagementLoop) loops are different: they mutate
    shared pool/ammo state and command real weapons to fire, so registering
    them on every machine would make every client independently detect the
    same contact and fire its own redundant shot. Both loops are therefore
    only ever registered on the server (isServer), the single source of
    truth in both singleplayer (always isServer) and dedicated multiplayer.

Parameters:
    _vehicle - the vehicle to set up as an AEGIS-M System <OBJECT>

Returns:
    Nothing

Examples:
    [_tigris] call aegism_system_fnc_moduleInit;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_vehicle"];

if (isNull _vehicle) exitWith {};
if (_vehicle getVariable ["AEGISM_systemInitialized", false]) exitWith {};
_vehicle setVariable ["AEGISM_systemInitialized", true, false];

private _capabilities = [_vehicle] call aegism_system_fnc_discoverCapabilities;
private _hasAnyCapability = (_capabilities get "hasRadar") || {(_capabilities get "launcherWeapons") isNotEqualTo []} || {(_capabilities get "ciwsWeapons") isNotEqualTo []};
if (!_hasAnyCapability) exitWith {
    // Deliberately verbose (every non-qualifying vehicle in the mission
    // logs once) -- when "nothing is engaging" turns out to mean "nothing
    // ever registered as a System at all", this is the line that proves it
    // and shows WHY discoverCapabilities came back empty for this vehicle,
    // rather than leaving that as a silent, hard-to-diagnose dead end.
    diag_log text format ["[AEGIS-M] DISCOVERY: %1 (%2) has no AEGIS-M-qualifying capability -- no radar sensor, no missile/rocket magazine, no high-ROF gun magazine found in its current loadout.", _vehicle, typeOf _vehicle];
};

_vehicle setVariable ["AEGISM_system", _capabilities, false];

private _contactSource = [_vehicle] call aegism_system_fnc_resolveContactSource;
private _engagementSettings = [_vehicle] call aegism_system_fnc_resolveEngagementSettings;
private _crew = [_vehicle] call aegism_system_fnc_resolveCrew;

_vehicle setVariable ["AEGISM_resolvedContactSource", _contactSource, false];
_vehicle setVariable ["AEGISM_resolvedEngagementSettings", _engagementSettings, false];
_vehicle setVariable ["AEGISM_resolvedCrew", _crew, false];

if (isServer) then {
    [{
        params ["_args", "_pfhHandle"];
        _args params ["_vehicle"];
        if (isNull _vehicle || {!alive _vehicle}) exitWith {
            [_pfhHandle] call CBA_fnc_removePerFrameHandler;
        };
        _vehicle setVariable ["AEGISM_resolvedContactSource", [_vehicle] call aegism_system_fnc_resolveContactSource, false];
        _vehicle setVariable ["AEGISM_resolvedEngagementSettings", [_vehicle] call aegism_system_fnc_resolveEngagementSettings, false];
        _vehicle setVariable ["AEGISM_resolvedCrew", [_vehicle] call aegism_system_fnc_resolveCrew, false];
    }, 5, [_vehicle]] call CBA_fnc_addPerFrameHandler;
};

if ("ownRadar" in _contactSource) then {
    _vehicle setVariable ["AEGISM_pooledContacts", createHashMap, false];

    if (isServer) then {
        private _allOwners = missionNamespace getVariable ["AEGISM_allPoolOwners", []];
        _allOwners pushBackUnique _vehicle;
        missionNamespace setVariable ["AEGISM_allPoolOwners", _allOwners];

        [{
            params ["_args", "_pfhHandle"];
            _args params ["_vehicle"];
            if (isNull _vehicle || {!alive _vehicle}) exitWith {
                private _allOwners = missionNamespace getVariable ["AEGISM_allPoolOwners", []];
                missionNamespace setVariable ["AEGISM_allPoolOwners", _allOwners - [_vehicle]];
                [_pfhHandle] call CBA_fnc_removePerFrameHandler;
            };
            [_vehicle] call aegism_detect_fnc_confidenceLoop;
        }, 1, [_vehicle]] call CBA_fnc_addPerFrameHandler;
    };
};

private _activeWeaponRoles = [];
if ((_capabilities get "launcherWeapons") isNotEqualTo []) then { _activeWeaponRoles pushBack "launcher"; };
if ((_capabilities get "ciwsWeapons") isNotEqualTo []) then { _activeWeaponRoles pushBack "ciws"; };

if (isServer) then {
    {
        private _role = _x;
        [{
            params ["_args", "_pfhHandle"];
            _args params ["_vehicle", "_role"];
            if (isNull _vehicle || {!alive _vehicle}) exitWith {
                [_pfhHandle] call CBA_fnc_removePerFrameHandler;
            };
            [_vehicle, _role] call aegism_intercept_fnc_engagementLoop;
        }, 0.5, [_vehicle, _role]] call CBA_fnc_addPerFrameHandler;
    } forEach _activeWeaponRoles;
};

diag_log text format ["[AEGIS-M] System initialized on %1 -- hasRadar=%2 launcherWeapons=%3 ciwsWeapons=%4 contactSource=%5", _vehicle, _capabilities get "hasRadar", count (_capabilities get "launcherWeapons"), count (_capabilities get "ciwsWeapons"), _contactSource];
