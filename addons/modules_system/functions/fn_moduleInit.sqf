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

    Every discovered launcher/CIWS turret also has its crew's own
    independent AI targeting/engagement suppressed (aegism_fnc_
    setWeaponAiSuppressed) the moment this System is recognized -- so that
    weapon can ONLY ever fire via AEGIS-M's own aegism_intercept_fnc_
    fireWeapon call, never because the crew spotted and independently
    decided to engage something themselves outside AEGIS-M's own
    assignment/ammo/reaction-time/cooldown/LOS/reliability gates. Runs on
    every machine (not isServer-gated), matching the rest of this
    function's non-loop-registration setup, since disableAI is local AI
    simulation state. A vehicle synced to a Site gets a broader, blunter
    version of this same suppression applied immediately at sync time
    (aegism_network_fnc_moduleInit), independent of whether discovery here
    ever actually recognizes it -- see that function's own doc comment.

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

// Aircraft and infantry are never AEGIS-M Systems -- they are what air
// defence shoots AT. Without this, an attack helicopter's radar + AA
// missiles + minigun made it a "System" and AEGIS-M suppressed its gunner.
if (_vehicle isKindOf "Air" || {_vehicle isKindOf "CAManBase"} || {!(_vehicle isKindOf "AllVehicles")}) exitWith {
    _vehicle setVariable ["AEGISM_systemInitialized", true, false];
};

private _capabilities = [_vehicle] call aegism_system_fnc_discoverCapabilities;
private _hasWeapons = (_capabilities get "launcherWeapons") isNotEqualTo [] || {(_capabilities get "ciwsWeapons") isNotEqualTo []};
private _hasAnyCapability = (_capabilities get "hasRadar") || _hasWeapons;
if (!_hasAnyCapability) exitWith {
    _vehicle setVariable ["AEGISM_systemInitialized", true, false];
    diag_log text format ["[AEGIS-M] DISCOVERY: %1 (%2) has no AEGIS-M-qualifying capability -- no radar sensor, no air-capable missile, no high-ROF air-capable gun.", _vehicle, typeOf _vehicle];
};

// Adoption policy: a vehicle synced to a Site is always adopted (the
// mission designer chose it). An UNSYNCED vehicle is only adopted as a
// standalone System if standalone air defence is enabled AND it is a
// self-contained AA platform -- its own radar plus its own AA weapons
// (a Cheetah/Tigris-style SPAAG). Anything else is deferred, not rejected:
// aegism_network_fnc_moduleInit re-runs this function when the vehicle is
// later synced to a Site.
private _synced = !isNull (_vehicle getVariable ["AEGISM_network", objNull]);
private _standaloneEligible = ("aegism_main_standaloneAdoption" call CBA_settings_fnc_get) && {_capabilities get "hasRadar"} && _hasWeapons;
if (!_synced && !_standaloneEligible) exitWith {
    if !(_vehicle getVariable ["AEGISM_systemDeferred", false]) then {
        _vehicle setVariable ["AEGISM_systemDeferred", true, false];
        diag_log text format ["[AEGIS-M] DISCOVERY: %1 (%2) has AEGIS-M capability (radar=%3 launchers=%4 ciws=%5) but is not synced to a Site and is not a self-contained AA platform (or standalone adoption is disabled) -- deferred until synced.", _vehicle, typeOf _vehicle, _capabilities get "hasRadar", count (_capabilities get "launcherWeapons"), count (_capabilities get "ciwsWeapons")];
    };
};

_vehicle setVariable ["AEGISM_systemInitialized", true, false];
_vehicle setVariable ["AEGISM_systemDeferred", false, false];
_vehicle setVariable ["AEGISM_system", _capabilities, false];

// Every recognized System, radar or not -- distinct from AEGISM_allPoolOwners
// below, which only ever gains a vehicle with real "ownRadar" capability
// (that list exists purely so the detection loop knows which vehicles have
// a pool worth scanning). A pure launcher/CIWS System with no radar of its
// own never has anything to pool locally, so it correctly never joined that
// list -- but aegism_fnc_debugDraw's own per-System state label (see its
// doc comment) needs to reach EVERY System to show "why isn't this launcher
// engaging" diagnostics, launchers included, so it walks this list instead.
// Local-only (setVariable false), matching AEGISM_system/
// AEGISM_systemInitialized above -- this whole function runs on every
// machine (not isServer-gated, see this function's own doc comment), so
// each machine builds its own list rather than depending on isServer/
// isDedicated to have a global one meaningfully shared.
private _allSystems = missionNamespace getVariable ["AEGISM_allSystems", []];
_allSystems pushBackUnique _vehicle;
missionNamespace setVariable ["AEGISM_allSystems", _allSystems, false];

// Cleanup PFH, NOT isServer-gated (unlike AEGISM_allPoolOwners' own cleanup
// below) -- AEGISM_allSystems is a per-machine local list read by aegism_
// fnc_debugDraw, which is itself a client-side-only concern (drawIcon3D has
// no meaning on a dedicated server), so every machine needs its own list
// kept correctly pruned independently rather than relying on the server's
// copy.
[{
    params ["_args", "_pfhHandle"];
    _args params ["_vehicle"];
    if (isNull _vehicle || {!alive _vehicle}) exitWith {
        private _allSystems = missionNamespace getVariable ["AEGISM_allSystems", []];
        missionNamespace setVariable ["AEGISM_allSystems", _allSystems - [_vehicle], false];
        [_pfhHandle] call CBA_fnc_removePerFrameHandler;
    };
}, 5, [_vehicle]] call CBA_fnc_addPerFrameHandler;

private _contactSource = [_vehicle] call aegism_system_fnc_resolveContactSource;
private _overrides = [];
private _engagementSettings = [_vehicle, _overrides] call aegism_system_fnc_resolveEngagementSettings;
private _crew = [_vehicle, _overrides] call aegism_system_fnc_resolveCrew;
if (_overrides isNotEqualTo []) then {
    diag_log text format ["[AEGIS-M] OVERRIDES: %1 uses its own vehicle settings instead of its Site's: %2", _vehicle, _overrides joinString ", "];
};

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

// Suppress the crew's own independent targeting/engagement on every
// discovered launcher/CIWS turret (see aegism_fnc_setWeaponAiSuppressed's
// own doc comment for why) -- runs on every machine, same as the rest of
// this function's non-loop-registration setup, since disableAI affects
// local AI simulation and needs to apply wherever this vehicle's crew is
// actually simulated, not just the server.
private _weaponTurretPaths = ((_capabilities get "launcherWeapons") + (_capabilities get "ciwsWeapons")) apply { _x select 0 };
if (_weaponTurretPaths isNotEqualTo []) then {
    [_vehicle, _weaponTurretPaths, true] call aegism_fnc_setWeaponAiSuppressed;
};

// CIWS ticks 5x faster than launchers: a gun has to keep re-aiming at a
// moving lead point, and a 0.5s cadence let fast crossing targets move
// several degrees between aim updates, so the 2-degree CIWS gate rarely
// passed. Launchers don't need it (guided rounds, 20-degree gate).
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
        }, [0.5, 0.1] select (_role == "ciws"), [_vehicle, _role]] call CBA_fnc_addPerFrameHandler;
    } forEach _activeWeaponRoles;
};

diag_log text format ["[AEGIS-M] System initialized on %1 -- hasRadar=%2 launcherWeapons=%3 ciwsWeapons=%4 contactSource=%5", _vehicle, _capabilities get "hasRadar", count (_capabilities get "launcherWeapons"), count (_capabilities get "ciwsWeapons"), _contactSource];
