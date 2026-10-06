class CfgPatches
{
    class aegism_modules_system
    {
        units[] = {};
        weapons[] = {};
        author = "Snow(Dryden)";
        requiredVersion = 2.10;
        requiredAddons[] = {"aegism_main", "aegism_detection", "aegism_intercept", "A3_3DEN"};
        #include "version.hpp"
    };
};

#include "CfgFunctions.hpp"

// See addons/main/config.cpp's own Extended_PreInit_EventHandlers comment
// -- CBA does not auto-run a bare XEH_postInit.sqf by filename, it has to
// be wired up explicitly per addon. Without this, aegism_system_fnc_
// scanForRoles's periodic discovery scan never registers at all, so no
// vehicle in the mission is ever recognized as an AEGIS-M System no matter
// how correctly configured -- the root cause of an entire mission running
// with zero AEGIS-M behavior and no diagnostic output whatsoever.
class Extended_PostInit_EventHandlers
{
    class aegism_modules_system
    {
        init = "call compile preprocessFileLineNumbers '\x\aegism\addons\modules_system\XEH_postInit.sqf'";
    };
};

// Per-vehicle overrides: an "AEGIS-M: Vehicle Overrides" category in every
// vehicle's own Eden attributes (condition objectVehicle), mirroring the Site
// module's sections. Nothing applies unless "Override Site Settings" is
// ticked, and every setting defaults to "Site setting" (combos) or blank
// (numbers): those are never written, so the variable stays nil and that
// setting keeps inheriting from the Site (or the defaults when standalone).
// Read back by aegism_system_fnc_applyOverrides, which also documents the
// "AEGISM_ovr_<key>" variables for setting the same thing from script
// (e.g. on a Zeus-placed vehicle).
#define AEGISM_OVR_NUMBER(CLASS,KEY_STR,EXPR,NAME,TIP) \
    class CLASS \
    { \
        displayName = NAME; \
        tooltip = TIP; \
        property = KEY_STR; \
        control = "Edit"; \
        expression = EXPR; \
        typeName = "STRING"; \
        defaultValue = "''"; \
        condition = "objectVehicle"; \
    }

class Cfg3DEN
{
    class Object
    {
        class AttributeCategories
        {
            class AEGISM_VehicleOverrides
            {
                displayName = "AEGIS-M: Vehicle Overrides";
                collapsed = 1;
                class Attributes
                {
                    class AEGISM_ovr_enabled
                    {
                        displayName = "Override Site Settings";
                        tooltip = "On: every setting below that isn't left on 'Site setting' (or blank) replaces the Site's value for THIS vehicle only. Everything left on 'Site setting' still follows the Site (or the AEGIS-M defaults if this vehicle has no Site). Only matters for vehicles AEGIS-M adopts (radars, SAM launchers, CIWS/SHORAD). A radar uses the Interception Targets section (what it reports into the Site, and which friendly munitions it treats as threats) and Radar Emission.";
                        property = "AEGISM_ovr_enabled";
                        control = "Checkbox";
                        expression = "_this setVariable ['AEGISM_ovr_enabled', _value];";
                        typeName = "BOOL";
                        defaultValue = "false";
                        condition = "objectVehicle";
                    };

                    // ------------------------------------------ Site settings
                    class AEGISM_ovr_section_site
                    {
                        property = "AEGISM_ovr_section_site";
                        control = "SubCategory";
                        displayName = "Site Settings";
                        title = "Site Settings";
                        description = "";
                        condition = "objectVehicle";
                    };
                    class AEGISM_ovr_targetPriority
                    {
                        displayName = "Target Priority";
                        tooltip = "Only used when this vehicle is NOT synced to a Site (a Site orders engagements for all its vehicles). Soonest Impact / Nearest / Fastest Closing / Highest Value.";
                        property = "AEGISM_ovr_targetPriority";
                        control = "Combo";
                        expression = "if (_value != '') then {_this setVariable ['AEGISM_ovr_targetPriority', _value]};";
                        typeName = "STRING";
                        defaultValue = "''";
                        condition = "objectVehicle";
                        class Values
                        {
                            class Site { name = "Site setting"; value = ""; };
                            class SoonestImpact { name = "Soonest Impact"; value = "soonestImpact"; };
                            class Nearest { name = "Nearest"; value = "nearest"; };
                            class FastestClosing { name = "Fastest Closing"; value = "fastestClosing"; };
                            class HighestValue { name = "Highest Value"; value = "highestValue"; };
                        };
                    };
                    class AEGISM_ovr_skillTier
                    {
                        displayName = "Crew Skill";
                        tooltip = "Reaction time and reliability of this vehicle's crew. Green: 4.0s, 55%. Regular: 2.5s, 70%. Veteran: 1.2s, 85%. Elite: 0.5s, 95%.";
                        property = "AEGISM_ovr_skillTier";
                        control = "Combo";
                        expression = "if (_value != '') then {_this setVariable ['AEGISM_ovr_skillTier', _value]};";
                        typeName = "STRING";
                        defaultValue = "''";
                        condition = "objectVehicle";
                        class Values
                        {
                            class Site { name = "Site setting"; value = ""; };
                            class Green { name = "Green (4.0s, 55% reliable)"; value = "green"; };
                            class Regular { name = "Regular (2.5s, 70% reliable)"; value = "regular"; };
                            class Veteran { name = "Veteran (1.2s, 85% reliable)"; value = "veteran"; };
                            class Elite { name = "Elite (0.5s, 95% reliable)"; value = "elite"; };
                        };
                    };
                    class AEGISM_ovr_temperament
                    {
                        displayName = "Crew Temperament";
                        tooltip = "Scales this crew's reaction, reliability and pause between shots (see the Site module's tooltip for the multipliers).";
                        property = "AEGISM_ovr_temperament";
                        control = "Combo";
                        expression = "if (_value != '') then {_this setVariable ['AEGISM_ovr_temperament', _value]};";
                        typeName = "STRING";
                        defaultValue = "''";
                        condition = "objectVehicle";
                        class Values
                        {
                            class Site { name = "Site setting"; value = ""; };
                            class Cautious { name = "Cautious (slower, steadier)"; value = "cautious"; };
                            class Standard { name = "Standard (neutral)"; value = "standard"; };
                            class Aggressive { name = "Aggressive (faster, sloppier)"; value = "aggressive"; };
                            class Nervous { name = "Nervous (fastest, least reliable)"; value = "nervous"; };
                        };
                    };
                    class AEGISM_ovr_costValueJudgment
                    {
                        displayName = "Save Ammo for Bigger Threats";
                        tooltip = "Hold fire on a contact if firing would leave fewer rounds than there are tracked contacts of higher threat value.";
                        property = "AEGISM_ovr_costValueJudgment";
                        control = "Combo";
                        expression = "if (_value != '') then {_this setVariable ['AEGISM_ovr_costValueJudgment', _value == 'on']};";
                        typeName = "STRING";
                        defaultValue = "''";
                        condition = "objectVehicle";
                        class Values
                        {
                            class Site { name = "Site setting"; value = ""; };
                            class On { name = "On"; value = "on"; };
                            class Off { name = "Off"; value = "off"; };
                        };
                    };

                    AEGISM_OVR_NUMBER(AEGISM_ovr_combatReaction,"AEGISM_ovr_combatReaction","if (_value != '') then {_this setVariable ['AEGISM_ovr_combatReaction', parseNumber _value]};","Reaction Once in Combat (%)","Percent of its reaction time this crew takes on each new target once in combat. Blank = Site setting.");
                    class AEGISM_ovr_crewOnAutomated: AEGISM_ovr_costValueJudgment
                    {
                        displayName = "Crew Skill on Automated Systems";
                        tooltip = "For a UAV-crewed vehicle: whether Crew Skill and Temperament apply to it (reaction delay, skipped fire cycles, interval scaling). Off = it never hesitates or skips.";
                        property = "AEGISM_ovr_crewOnAutomated";
                        expression = "if (_value != '') then {_this setVariable ['AEGISM_ovr_crewOnAutomated', _value == 'on']};";
                    };

                    // ----------------------------------- Interception targets
                    class AEGISM_ovr_section_targets
                    {
                        property = "AEGISM_ovr_section_targets";
                        control = "SubCategory";
                        displayName = "Interception Targets";
                        title = "Interception Targets";
                        description = "";
                        condition = "objectVehicle";
                    };
                    class AEGISM_ovr_allow_missile
                    {
                        displayName = "Missiles";
                        tooltip = "Engage (or ignore) guided missiles with this vehicle, whatever the Site says.";
                        property = "AEGISM_ovr_allow_missile";
                        control = "Combo";
                        expression = "if (_value != '') then {_this setVariable ['AEGISM_ovr_allow_missile', _value == 'on']};";
                        typeName = "STRING";
                        defaultValue = "''";
                        condition = "objectVehicle";
                        class Values
                        {
                            class Site { name = "Site setting"; value = ""; };
                            class On { name = "Engage"; value = "on"; };
                            class Off { name = "Ignore"; value = "off"; };
                        };
                    };
                    class AEGISM_ovr_allow_rocket: AEGISM_ovr_allow_missile
                    {
                        displayName = "Rockets";
                        tooltip = "Engage (or ignore) unguided rockets with this vehicle, whatever the Site says.";
                        property = "AEGISM_ovr_allow_rocket";
                        expression = "if (_value != '') then {_this setVariable ['AEGISM_ovr_allow_rocket', _value == 'on']};";
                    };
                    class AEGISM_ovr_allow_bomb: AEGISM_ovr_allow_missile
                    {
                        displayName = "Bombs";
                        tooltip = "Engage (or ignore) aircraft bombs with this vehicle, whatever the Site says.";
                        property = "AEGISM_ovr_allow_bomb";
                        expression = "if (_value != '') then {_this setVariable ['AEGISM_ovr_allow_bomb', _value == 'on']};";
                    };
                    class AEGISM_ovr_allow_artilleryShell: AEGISM_ovr_allow_missile
                    {
                        displayName = "Artillery, Mortar and MLRS Rounds";
                        tooltip = "Engage (or ignore) indirect-fire rounds with this vehicle, whatever the Site says -- e.g. set Ignore on a long-range SAM so it doesn't spend missiles on shells.";
                        property = "AEGISM_ovr_allow_artilleryShell";
                        expression = "if (_value != '') then {_this setVariable ['AEGISM_ovr_allow_artilleryShell', _value == 'on']};";
                    };
                    class AEGISM_ovr_allow_fixedWing: AEGISM_ovr_allow_missile
                    {
                        displayName = "Fixed-Wing Aircraft";
                        tooltip = "Engage (or ignore) planes with this vehicle, whatever the Site says.";
                        property = "AEGISM_ovr_allow_fixedWing";
                        expression = "if (_value != '') then {_this setVariable ['AEGISM_ovr_allow_fixedWing', _value == 'on']};";
                    };
                    class AEGISM_ovr_allow_helicopter: AEGISM_ovr_allow_missile
                    {
                        displayName = "Helicopters";
                        tooltip = "Engage (or ignore) helicopters with this vehicle, whatever the Site says.";
                        property = "AEGISM_ovr_allow_helicopter";
                        expression = "if (_value != '') then {_this setVariable ['AEGISM_ovr_allow_helicopter', _value == 'on']};";
                    };
                    class AEGISM_ovr_allow_drone: AEGISM_ovr_allow_missile
                    {
                        displayName = "Drones";
                        tooltip = "Engage (or ignore) unmanned aircraft with this vehicle, whatever the Site says.";
                        property = "AEGISM_ovr_allow_drone";
                        expression = "if (_value != '') then {_this setVariable ['AEGISM_ovr_allow_drone', _value == 'on']};";
                    };
                    AEGISM_OVR_NUMBER(AEGISM_ovr_minAltitude,"AEGISM_ovr_minAltitude","if (_value != '') then {_this setVariable ['AEGISM_ovr_minAltitude', parseNumber _value]};","Target Min Height (m above ground)","Blank = Site setting.");
                    AEGISM_OVR_NUMBER(AEGISM_ovr_maxAltitude,"AEGISM_ovr_maxAltitude","if (_value != '') then {_this setVariable ['AEGISM_ovr_maxAltitude', parseNumber _value]};","Target Max Height (m above ground)","0 = no limit. Blank = Site setting.");
                    class AEGISM_ovr_engageFriendlyThreats: AEGISM_ovr_costValueJudgment
                    {
                        displayName = "Engage Friendly Munitions Threatening the Site";
                        tooltip = "For a radar: whether it treats friendly/neutral munitions predicted to hit the Site as threats.";
                        property = "AEGISM_ovr_engageFriendlyThreats";
                        expression = "if (_value != '') then {_this setVariable ['AEGISM_ovr_engageFriendlyThreats', _value == 'on']};";
                    };
                    class AEGISM_ovr_engageOnlyThreats: AEGISM_ovr_costValueJudgment
                    {
                        displayName = "Only Engage Munitions Threatening the Site";
                        tooltip = "For a radar: whether a hostile munition it sees is only reported while it's a threat to a Site vehicle (predicted to land within the Threat Radius of one, or a missile guided or flying at one, or with one inside its seeker's view when its target can't be read).";
                        property = "AEGISM_ovr_engageOnlyThreats";
                        expression = "if (_value != '') then {_this setVariable ['AEGISM_ovr_engageOnlyThreats', _value == 'on']};";
                    };
                    AEGISM_OVR_NUMBER(AEGISM_ovr_friendlyThreatRadius,"AEGISM_ovr_friendlyThreatRadius","if (_value != '') then {_this setVariable ['AEGISM_ovr_friendlyThreatRadius', parseNumber _value]};","Threat Radius (m)","0 = the munition's own config danger radius. Blank = Site setting.");

                    // ---------------------------------------------- Launchers
                    class AEGISM_ovr_section_launchers
                    {
                        property = "AEGISM_ovr_section_launchers";
                        control = "SubCategory";
                        displayName = "Launchers (Missiles)";
                        title = "Launchers (Missiles)";
                        description = "";
                        condition = "objectVehicle";
                    };
                    AEGISM_OVR_NUMBER(AEGISM_ovr_minRange,"AEGISM_ovr_minRange","if (_value != '') then {_this setVariable ['AEGISM_ovr_minRange', parseNumber _value]};","Min Range (m)","On top of the missile's own config minimum. 0 = only the missile's own. Blank = Site setting.");
                    AEGISM_OVR_NUMBER(AEGISM_ovr_maxRange,"AEGISM_ovr_maxRange","if (_value != '') then {_this setVariable ['AEGISM_ovr_maxRange', parseNumber _value]};","Max Range (m)","0 = the missile's own config reach. Blank = Site setting.");
                    AEGISM_OVR_NUMBER(AEGISM_ovr_salvoSize,"AEGISM_ovr_salvoSize","if (_value != '') then {_this setVariable ['AEGISM_ovr_salvoSize', parseNumber _value]};","Missiles per Target","Blank = Site setting.");
                    AEGISM_OVR_NUMBER(AEGISM_ovr_minShotInterval,"AEGISM_ovr_minShotInterval","if (_value != '') then {_this setVariable ['AEGISM_ovr_minShotInterval', parseNumber _value]};","Seconds Between Missiles","0 = Auto: this launcher's own config fire rate. Blank = Site setting.");
                    AEGISM_OVR_NUMBER(AEGISM_ovr_maxOffBoreSwing,"AEGISM_ovr_maxOffBoreSwing","if (_value != '') then {_this setVariable ['AEGISM_ovr_maxOffBoreSwing', parseNumber _value]};","Max Off-Bore Launch While Swinging (deg)","The most this launcher may fire away from the intercept while its turret is still swinging round, leaving the missile to turn. A fixed mount is exempt. Blank = Site setting.");
                    AEGISM_OVR_NUMBER(AEGISM_ovr_maxOffBoreLimit,"AEGISM_ovr_maxOffBoreLimit","if (_value != '') then {_this setVariable ['AEGISM_ovr_maxOffBoreLimit', parseNumber _value]};","Max Off-Bore Launch At Turret Limit (deg)","The most this launcher may fire away from the intercept once its turret is at its elevation or traverse limit, leaving the missile to turn. A fixed mount is exempt. Blank = Site setting.");

                    // --------------------------------------------------- CIWS
                    class AEGISM_ovr_section_ciws
                    {
                        property = "AEGISM_ovr_section_ciws";
                        control = "SubCategory";
                        displayName = "CIWS (Guns)";
                        title = "CIWS (Guns)";
                        description = "";
                        condition = "objectVehicle";
                    };
                    AEGISM_OVR_NUMBER(AEGISM_ovr_ciwsMaxRange,"AEGISM_ovr_ciwsMaxRange","if (_value != '') then {_this setVariable ['AEGISM_ovr_ciwsMaxRange', parseNumber _value]};","Max Range (m)","0 = the gun's own config reach. Blank = Site setting.");
                    AEGISM_OVR_NUMBER(AEGISM_ovr_ciwsMinElevation,"AEGISM_ovr_ciwsMinElevation","if (_value != '') then {_this setVariable ['AEGISM_ovr_ciwsMinElevation', parseNumber _value]};","Min Elevation (deg)","Blank = Site setting.");
                    AEGISM_OVR_NUMBER(AEGISM_ovr_ciwsOpenFireChance,"AEGISM_ovr_ciwsOpenFireChance","if (_value != '') then {_this setVariable ['AEGISM_ovr_ciwsOpenFireChance', parseNumber _value]};","Open Fire at Hit Chance (%)","Fires only where one burst is at least this likely to hit, from the gun's measured accuracy and the round's flight. 0 = its full reach. Blank = Site setting.");
                    AEGISM_OVR_NUMBER(AEGISM_ovr_ciwsCueAhead,"AEGISM_ovr_ciwsCueAhead","if (_value != '') then {_this setVariable ['AEGISM_ovr_ciwsCueAhead', parseNumber _value]};","Cue Before In Range (s)","Assigned a target this long before it's in reach, so it's on it by then. 0 = only once in reach. Blank = Site setting.");
                    AEGISM_OVR_NUMBER(AEGISM_ovr_ciwsMinWindow,"AEGISM_ovr_ciwsMinWindow","if (_value != '') then {_this setVariable ['AEGISM_ovr_ciwsMinWindow', parseNumber _value]};","Minimum Firing Window (s)","Only given an incoming munition it has this long to fire at before impact; one with less only with nothing better. 0 = any it can reach in time. Blank = Site setting.");
                    AEGISM_OVR_NUMBER(AEGISM_ovr_ciwsBurstMin,"AEGISM_ovr_ciwsBurstMin","if (_value != '') then {_this setVariable ['AEGISM_ovr_ciwsBurstMin', parseNumber _value]};","Burst Length Min (s)","Blank = Site setting.");
                    AEGISM_OVR_NUMBER(AEGISM_ovr_ciwsBurstMax,"AEGISM_ovr_ciwsBurstMax","if (_value != '') then {_this setVariable ['AEGISM_ovr_ciwsBurstMax', parseNumber _value]};","Burst Length Max (s)","Blank = Site setting.");
                    AEGISM_OVR_NUMBER(AEGISM_ovr_ciwsBurstPause,"AEGISM_ovr_ciwsBurstPause","if (_value != '') then {_this setVariable ['AEGISM_ovr_ciwsBurstPause', parseNumber _value]};","Pause Between Bursts (s)","Blank = Site setting.");
                    class AEGISM_ovr_ciwsLastResort: AEGISM_ovr_costValueJudgment
                    {
                        displayName = "Last Resort Only";
                        tooltip = "On: this gun holds while a launcher covers the contact, until the launcher fails or the contact closes inside 40% of the gun's reach.";
                        property = "AEGISM_ovr_ciwsLastResort";
                        expression = "if (_value != '') then {_this setVariable ['AEGISM_ovr_ciwsLastResort', _value == 'on']};";
                    };
                    class AEGISM_ovr_ciwsSelfDestruct: AEGISM_ovr_costValueJudgment
                    {
                        displayName = "Self-Destruct Rounds";
                        tooltip = "On: this gun's rounds that hit nothing detonate once past its reach (or just before their lifetime runs out, if sooner), instead of flying on and disappearing in mid-air.";
                        property = "AEGISM_ovr_ciwsSelfDestruct";
                        expression = "if (_value != '') then {_this setVariable ['AEGISM_ovr_ciwsSelfDestruct', _value == 'on']};";
                    };

                    // ----------------------------------------- Radar emission
                    class AEGISM_ovr_section_emcon
                    {
                        property = "AEGISM_ovr_section_emcon";
                        control = "SubCategory";
                        displayName = "Radar Emission";
                        title = "Radar Emission";
                        description = "";
                        condition = "objectVehicle";
                    };
                    class AEGISM_ovr_emcon
                    {
                        displayName = "Radar Emission";
                        tooltip = "When this vehicle's active radar emits (see the Site module's tooltip). E.g. keep a long-range search radar Always on while the rest of the Site stays Silent until cued.";
                        property = "AEGISM_ovr_emcon";
                        control = "Combo";
                        expression = "if (_value != '') then {_this setVariable ['AEGISM_ovr_emcon', _value]};";
                        typeName = "STRING";
                        defaultValue = "''";
                        condition = "objectVehicle";
                        class Values
                        {
                            class Site { name = "Site setting"; value = ""; };
                            class Auto { name = "Automatic"; value = "auto"; };
                            class Ai { name = "AI decides"; value = "ai"; };
                            class On { name = "Always on"; value = "on"; };
                            class Cued { name = "Silent until cued"; value = "cued"; };
                            class Intermittent { name = "Intermittent"; value = "intermittent"; };
                        };
                    };
                    AEGISM_OVR_NUMBER(AEGISM_ovr_emconHold,"AEGISM_ovr_emconHold","if (_value != '') then {_this setVariable ['AEGISM_ovr_emconHold', parseNumber _value]};","Stay Lit After Last Contact (s)","Blank = Site setting.");
                    AEGISM_OVR_NUMBER(AEGISM_ovr_emconBurstOn,"AEGISM_ovr_emconBurstOn","if (_value != '') then {_this setVariable ['AEGISM_ovr_emconBurstOn', parseNumber _value]};","Search Burst: Seconds On","Blank = Site setting.");
                    AEGISM_OVR_NUMBER(AEGISM_ovr_emconBurstOff,"AEGISM_ovr_emconBurstOff","if (_value != '') then {_this setVariable ['AEGISM_ovr_emconBurstOff', parseNumber _value]};","Search Burst: Seconds Off","Blank = Site setting.");
                    class AEGISM_ovr_armShutdown: AEGISM_ovr_costValueJudgment
                    {
                        displayName = "Shut Down for Anti-Radiation Missiles";
                        tooltip = "On: this radar shuts down while an anti-radiation missile is inbound on it, in every Radar Emission mode.";
                        property = "AEGISM_ovr_armShutdown";
                        expression = "if (_value != '') then {_this setVariable ['AEGISM_ovr_armShutdown', _value == 'on']};";
                    };
                };
            };
        };
    };
};
