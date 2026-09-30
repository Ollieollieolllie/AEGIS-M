/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_readSiteSettings

Description:
    The doctrine and personality a Site hands its members, read from the
    Site logic's own attribute variables (set by its Eden attributes, or in
    Zeus by aegism_network_fnc_zeusApplySite).

Parameters:
    _logic - the Site logic <OBJECT>

Returns:
    [engagement settings <HASHMAP>, crew settings <HASHMAP>] <ARRAY>

Examples:
    ([_site] call aegism_network_fnc_readSiteSettings) params ["_engagementData", "_crewData"];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_logic"];

private _allowlist = [];
{
    _x params ["_property", "_class"];
    if (_logic getVariable [_property, true]) then { _allowlist pushBack _class; };
} forEach [
    ["allowMissile", "missile"], ["allowRocket", "rocket"], ["allowBomb", "bomb"], ["allowArtilleryShell", "artilleryShell"],
    ["allowFixedWing", "fixedWing"], ["allowHelicopter", "helicopter"], ["allowDrone", "drone"]
];

[
    createHashMapFromArray [
        ["minRange", _logic getVariable ["minRange", 0]],
        ["maxRange", _logic getVariable ["maxRange", 0]],
        ["ciwsMaxRange", _logic getVariable ["ciwsMaxRange", 0]],
        ["minAltitude", _logic getVariable ["minAltitude", 0]],
        ["maxAltitude", _logic getVariable ["maxAltitude", 0]],
        ["targetPriority", _logic getVariable ["targetPriority", "soonestImpact"]],
        ["salvoSize", _logic getVariable ["salvoSize", 1]],
        ["minShotInterval", _logic getVariable ["minShotInterval", 0]],
        ["maxOffBore", _logic getVariable ["maxOffBore", 15]],
        ["ciwsBurstMin", _logic getVariable ["ciwsBurstMin", 3]],
        ["ciwsBurstMax", _logic getVariable ["ciwsBurstMax", 5]],
        ["ciwsBurstPause", _logic getVariable ["ciwsBurstPause", 1]],
        ["ciwsMinElevation", _logic getVariable ["ciwsMinElevation", 5]],
        ["ciwsOpenFireChance", _logic getVariable ["ciwsOpenFireChance", 40]],
        ["engageFriendlyThreats", _logic getVariable ["engageFriendlyThreats", true]],
        ["engageOnlyThreats", _logic getVariable ["engageOnlyThreats", true]],
        ["friendlyThreatRadius", _logic getVariable ["friendlyThreatRadius", 0]],
        ["targetClassAllowlist", _allowlist],
        ["ciwsLastResort", _logic getVariable ["ciwsLastResort", false]]
    ],
    createHashMapFromArray [
        ["skillTier", _logic getVariable ["skillTier", "regular"]],
        ["temperament", _logic getVariable ["temperament", "standard"]],
        ["costValueJudgment", _logic getVariable ["costValueJudgment", false]],
        ["crewOnAutomated", _logic getVariable ["crewOnAutomated", false]],
        ["combatReaction", _logic getVariable ["combatReaction", 50]]
    ]
]
