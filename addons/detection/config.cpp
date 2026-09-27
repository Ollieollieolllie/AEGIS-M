class CfgPatches
{
    class aegism_detection
    {
        units[] = {};
        weapons[] = {};
        author = "Snow(Dryden)";
        requiredVersion = 2.10;
        requiredAddons[] = {"aegism_main"};
        #include "version.hpp"
    };
};

#include "CfgFunctions.hpp"

// See addons/main/config.cpp's own Extended_PreInit_EventHandlers comment
// -- CBA does not auto-run a bare XEH_preInit.sqf by filename, it has to be
// wired up explicitly per addon. Without this, the "Fired" class event
// handler (the munition half of the hybrid detection model) never
// registers at all, so incoming missiles/rockets/bombs are silently never
// tracked regardless of anything else in the mod being correct.
class Extended_PreInit_EventHandlers
{
    class aegism_detection
    {
        init = "call compile preprocessFileLineNumbers '\x\aegism\addons\detection\XEH_preInit.sqf'";
    };
};
