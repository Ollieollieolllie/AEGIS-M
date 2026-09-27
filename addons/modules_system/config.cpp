class CfgPatches
{
    class aegism_modules_system
    {
        units[] = {"AEGISM_Module_System"};
        weapons[] = {};
        author = "Snow(Dryden)";
        requiredVersion = 2.10;
        requiredAddons[] = {"aegism_main", "aegism_detection"};
        #include "version.hpp"
    };
};

#include "CfgFunctions.hpp"

class CfgVehicles
{
    class Module_F;
    class ModuleDescription;

    class AEGISM_Module_System: Module_F
    {
        scope = 2;
        displayName = "AEGIS-M: System";
        icon = "a3\ui_f\data\IGUI\Cfg\Actions\repair_ca.paa";
        category = "AEGISM";
        function = "aegism_system_fnc_moduleInit";
        functionPriority = 1;
        isGlobal = 1;
        isTriggerActivated = 0;
        is3DEN = 1;

        class Attributes
        {
            class RoleRadar
            {
                displayName = "Role: Radar";
                tooltip = "This vehicle performs the Radar role -- detects and publishes contacts.";
                property = "roleRadar";
                control = "Checkbox";
                expression = "_this setVariable ['roleRadar', _value];";
                typeName = "BOOL";
                defaultValue = "false";
            };
            class RoleLauncher
            {
                displayName = "Role: Launcher";
                tooltip = "This vehicle performs the Launcher (SAM) role -- engages allowlisted contacts in envelope.";
                property = "roleLauncher";
                control = "Checkbox";
                expression = "_this setVariable ['roleLauncher', _value];";
                typeName = "BOOL";
                defaultValue = "false";
            };
            class RoleCiws
            {
                displayName = "Role: CIWS/CRAM";
                tooltip = "This vehicle performs the CIWS/CRAM role -- short-range, high-rate point defense.";
                property = "roleCiws";
                control = "Checkbox";
                expression = "_this setVariable ['roleCiws', _value];";
                typeName = "BOOL";
                defaultValue = "false";
            };
            class RadarDetectionRange
            {
                displayName = "Radar: Detection Range (m, real-world base)";
                tooltip = "Real-world-sourced base detection range. Scaled at runtime by the AEGIS-M Range Scale setting.";
                property = "radarDetectionRange";
                control = "Edit";
                expression = "_this setVariable ['radarDetectionRange', _value];";
                typeName = "NUMBER";
                defaultValue = "4000";
            };
            class RadarArc
            {
                displayName = "Radar: Arc (degrees)";
                tooltip = "Detection arc in degrees; 360 for omnidirectional.";
                property = "radarArc";
                control = "Edit";
                expression = "_this setVariable ['radarArc', _value];";
                typeName = "NUMBER";
                defaultValue = "360";
            };
            class PassiveOpticalRange
            {
                displayName = "Radar: Passive-Optical Range (m, real-world base)";
                tooltip = "Range for passive LOS/optics-based detection before active radar emission.";
                property = "passiveOpticalRange";
                control = "Edit";
                expression = "_this setVariable ['passiveOpticalRange', _value];";
                typeName = "NUMBER";
                defaultValue = "2000";
            };
            class MissileCount
            {
                displayName = "Launcher: Missile Count";
                tooltip = "Number of interceptor missiles carried before reload.";
                property = "missileCount";
                control = "Edit";
                expression = "_this setVariable ['missileCount', _value];";
                typeName = "NUMBER";
                defaultValue = "4";
            };
            class ReloadTime
            {
                displayName = "Launcher: Reload Time (s)";
                tooltip = "Seconds to reload after expending the missile count.";
                property = "reloadTime";
                control = "Edit";
                expression = "_this setVariable ['reloadTime', _value];";
                typeName = "NUMBER";
                defaultValue = "30";
            };
            class GuidanceSpeed
            {
                displayName = "Launcher: Guidance Speed (m/s)";
                tooltip = "Interceptor missile speed for guidance-loop resolution.";
                property = "guidanceSpeed";
                control = "Edit";
                expression = "_this setVariable ['guidanceSpeed', _value];";
                typeName = "NUMBER";
                defaultValue = "800";
            };
            class GuidanceN
            {
                displayName = "Launcher: Guidance N Constant";
                tooltip = "Proportional-navigation constant for the interceptor guidance loop.";
                property = "guidanceN";
                control = "Edit";
                expression = "_this setVariable ['guidanceN', _value];";
                typeName = "NUMBER";
                defaultValue = "4";
            };
            class CiwsGuidanceSpeed
            {
                displayName = "CIWS: Guidance Speed (m/s)";
                tooltip = "CIWS/CRAM interceptor speed -- tuned faster than SAM by default.";
                property = "ciwsGuidanceSpeed";
                control = "Edit";
                expression = "_this setVariable ['ciwsGuidanceSpeed', _value];";
                typeName = "NUMBER";
                defaultValue = "1100";
            };
            class CiwsGuidanceN
            {
                displayName = "CIWS: Guidance N Constant";
                tooltip = "Proportional-navigation constant for the CIWS/CRAM guidance loop -- tuned tighter than SAM by default.";
                property = "ciwsGuidanceN";
                control = "Edit";
                expression = "_this setVariable ['ciwsGuidanceN', _value];";
                typeName = "NUMBER";
                defaultValue = "5";
            };
        };

        class ModuleDescription: ModuleDescription
        {
            description = "Declares a vehicle's air-defense capability role(s): Radar, Launcher, and/or CIWS/CRAM. Self-contained vehicles (e.g. Tigris/ZSU-style) check all three on one instance.";
            sync[] = {"AnyVehicle"};
        };
    };
};
