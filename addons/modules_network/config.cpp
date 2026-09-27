class CfgPatches
{
    class aegism_modules_network
    {
        units[] = {"AEGISM_Module_Network"};
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

    class AEGISM_Module_Network: Module_F
    {
        scope = 2;
        displayName = "AEGIS-M: Network";
        icon = "a3\ui_f\data\IGUI\Cfg\Actions\repair_ca.paa";
        category = "AEGISM";
        function = "aegism_network_fnc_moduleInit";
        functionPriority = 0;
        isGlobal = 1;
        isTriggerActivated = 0;
        is3DEN = 1;

        class ModuleDescription: ModuleDescription
        {
            description = "Groups one or more AEGIS-M Systems into a battery: pools Radar-role contacts across the group, and acts as a fallback sync target for Engagement Settings and Crew so one doctrine/personality can apply to the whole battery. Must be synced to its member Systems.";
            sync[] = {"AnyVehicle"};
        };
    };
};
