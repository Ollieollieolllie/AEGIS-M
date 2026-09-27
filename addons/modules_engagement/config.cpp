class CfgPatches
{
    class aegism_modules_engagement
    {
        units[] = {"AEGISM_Module_EngagementSettings"};
        weapons[] = {};
        author = "Snow(Dryden)";
        requiredVersion = 2.10;
        requiredAddons[] = {"aegism_main"};
        #include "version.hpp"
    };
};

#include "CfgFunctions.hpp"

class CfgVehicles
{
    class Module_F;
    class ModuleDescription;

    class AEGISM_Module_EngagementSettings: Module_F
    {
        scope = 2;
        displayName = "AEGIS-M: Engagement Settings";
        icon = "a3\ui_f\data\IGUI\Cfg\Actions\repair_ca.paa";
        category = "AEGISM";
        function = "aegism_engagement_fnc_moduleInit";
        functionPriority = 2;
        isGlobal = 1;
        isTriggerActivated = 0;
        is3DEN = 1;

        class Attributes
        {
            class MinRange
            {
                displayName = "Envelope: Min Range (m, real-world base)";
                tooltip = "Minimum engagement range. Scaled at runtime by the AEGIS-M Range Scale setting.";
                property = "minRange";
                control = "Edit";
                expression = "_this setVariable ['minRange', _value];";
                typeName = "NUMBER";
                defaultValue = "500";
            };
            class MaxRange
            {
                displayName = "Envelope: Max Range (m, real-world base)";
                tooltip = "Maximum engagement range. Scaled at runtime by the AEGIS-M Range Scale setting.";
                property = "maxRange";
                control = "Edit";
                expression = "_this setVariable ['maxRange', _value];";
                typeName = "NUMBER";
                defaultValue = "8000";
            };
            class MinAltitude
            {
                displayName = "Envelope: Min Altitude (m)";
                tooltip = "Minimum target altitude to consider engaging.";
                property = "minAltitude";
                control = "Edit";
                expression = "_this setVariable ['minAltitude', _value];";
                typeName = "NUMBER";
                defaultValue = "0";
            };
            class MaxAltitude
            {
                displayName = "Envelope: Max Altitude (m)";
                tooltip = "Maximum target altitude to consider engaging.";
                property = "maxAltitude";
                control = "Edit";
                expression = "_this setVariable ['maxAltitude', _value];";
                typeName = "NUMBER";
                defaultValue = "6000";
            };
            class TargetPriority
            {
                displayName = "Target Priority Rule";
                tooltip = "nearest | fastestClosing | highestValue";
                property = "targetPriority";
                control = "Edit";
                expression = "_this setVariable ['targetPriority', _value];";
                typeName = "STRING";
                defaultValue = "'nearest'";
            };
            class SalvoSize
            {
                displayName = "Salvo: Rounds Per Engagement";
                tooltip = "Rounds fired per engagement under this doctrine.";
                property = "salvoSize";
                control = "Edit";
                expression = "_this setVariable ['salvoSize', _value];";
                typeName = "NUMBER";
                defaultValue = "1";
            };
            class MinShotInterval
            {
                displayName = "Salvo: Minimum Shot Interval (s)";
                tooltip = "Minimum seconds between shots within a salvo.";
                property = "minShotInterval";
                control = "Edit";
                expression = "_this setVariable ['minShotInterval', _value];";
                typeName = "NUMBER";
                defaultValue = "4";
            };
            class AllowMissile
            {
                displayName = "Allow: Missile";
                tooltip = "Permit engaging tracked missile contacts.";
                property = "allowMissile";
                control = "Checkbox";
                expression = "_this setVariable ['allowMissile', _value];";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class AllowRocket
            {
                displayName = "Allow: Rocket";
                tooltip = "Permit engaging tracked rocket contacts.";
                property = "allowRocket";
                control = "Checkbox";
                expression = "_this setVariable ['allowRocket', _value];";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class AllowBomb
            {
                displayName = "Allow: Bomb";
                tooltip = "Permit engaging tracked bomb contacts.";
                property = "allowBomb";
                control = "Checkbox";
                expression = "_this setVariable ['allowBomb', _value];";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class AllowArtilleryShell
            {
                displayName = "Allow: Artillery Shell";
                tooltip = "Permit engaging tracked artillery/mortar shell contacts (CRAM role).";
                property = "allowArtilleryShell";
                control = "Checkbox";
                expression = "_this setVariable ['allowArtilleryShell', _value];";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class AllowFixedWing
            {
                displayName = "Allow: Fixed-Wing Aircraft";
                tooltip = "Permit engaging fixed-wing aircraft.";
                property = "allowFixedWing";
                control = "Checkbox";
                expression = "_this setVariable ['allowFixedWing', _value];";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class AllowHelicopter
            {
                displayName = "Allow: Helicopter";
                tooltip = "Permit engaging helicopters.";
                property = "allowHelicopter";
                control = "Checkbox";
                expression = "_this setVariable ['allowHelicopter', _value];";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class AllowDrone
            {
                displayName = "Allow: Drone (UAV/UCAV)";
                tooltip = "Permit engaging unmanned aerial vehicles.";
                property = "allowDrone";
                control = "Checkbox";
                expression = "_this setVariable ['allowDrone', _value];";
                typeName = "BOOL";
                defaultValue = "true";
            };
        };

        class ModuleDescription: ModuleDescription
        {
            description = "Defines the by-the-book engagement doctrine (envelope, target priority, salvo policy, target-class allowlist) for one or more synced AEGIS-M Systems, or a whole AEGIS-M Network.";
            sync[] = {"AnyVehicle", "Logic"};
        };
    };
};
