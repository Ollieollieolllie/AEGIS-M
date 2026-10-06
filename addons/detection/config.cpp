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

// Munitions are detected by AEGIS-M itself, from each sensor's own config
// (aegism_detect_fnc_sensorView, aegism_detect_fnc_munitionSeen): a fired
// projectile can't be a target of the game's sensors (CfgAmmo has no
// radar/IR/visual target properties). Each tracked munition used to carry an
// invisible vehicle here (AEGISM_MunitionProxy_*, built from the Darter)
// for the game's sensors to find instead; its signature, 2.5, is still the
// munitions' (AEGISM_MUNITION_SIGNATURE, sensing.hpp).

// See addons/main/config.cpp's own Extended_PreInit_EventHandlers comment
// -- CBA does not auto-run a bare XEH_preInit.sqf by filename, it has to be
// wired up explicitly per addon. Without this, the "Fired" class event
// handler (which starts tracking every threat munition) never
// registers at all, so incoming missiles/rockets/bombs are silently never
// tracked regardless of anything else in the mod being correct.
class Extended_PreInit_EventHandlers
{
    class aegism_detection
    {
        init = "call compile preprocessFileLineNumbers '\x\aegism\addons\detection\XEH_preInit.sqf'";
    };
};
