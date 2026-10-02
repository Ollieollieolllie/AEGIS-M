class CfgPatches
{
    class aegism_detection
    {
        units[] = {};
        weapons[] = {};
        author = "Snow(Dryden)";
        requiredVersion = 2.10;
        requiredAddons[] = {"aegism_main", "A3_Drones_F_Air_F_Gamma_UAV_01"};
        #include "version.hpp"
    };
};

#include "CfgFunctions.hpp"

// Munition proxies: an invisible sensor target carried with every tracked
// munition (aegism_detect_fnc_proxyCreate: attached half a second after
// launch, or moved every frame by aegism_detect_fnc_proxyFollow where an
// ammo type doesn't carry attachments),
// so the game's own sensors decide whether a munition is seen -- radar, IR
// and visual, with each sensor's own range, arc, line of sight, fog, speed
// limits, ground clutter, and whether a radar is emitting; datalink shares
// what one vehicle sees. A fired projectile can't be a sensor target
// itself: CfgAmmo has no radar/IR/visual target properties.
//
// Built from the Darter (UAV_01_base_F), on the supply-drop crate's model
// with its one texture selection ("camo") blanked -- invisible, as the
// published Intercept Munitions mod uses it for its own UAV-based
// projectile proxies. It needs a real model: with an empty one no sensor
// ever saw the proxy, while an empty Darter beside it was seen. And not the
// Darter's own: its camo selection doesn't cover all of it, so parts of it
// showed. (hideObject would also hide it from radar.)
//
// Its signature is size 1 on radar, IR and visual -- not the Darter's 0.1:
// the game multiplies a sensor's range by the target's size (the Cheetah's
// 9000 m radar first saw a Darter at 852 m), and size 1 means each sensor
// sees a munition at its own configured range. The Darter has no heat
// signature (irTarget 0); a munition is hot, so IR is on (and it's made hot
// at creation, setVehicleTIPars). Everything that would make it more than a
// target is removed: no crew, no turret (the Darter's camera), no sensors
// or datalink of its own (so it costs no sensor simulation), not a UAV (so
// no terminal can connect to it).
//
// One class per AEGIS-M threat class (aegism_detect_fnc_classifyAmmoClass),
// "AEGISM_MunitionProxy_<class>", so each kind of munition can carry its
// own signature -- all size 1 for now.
class CfgVehicles
{
    class UAV_01_base_F;
    class AEGISM_MunitionProxy: UAV_01_base_F
    {
        scope = 0;
        scopeCurator = 0;
        displayName = "AEGIS-M Munition Proxy";
        model = "\A3\Weapons_F\Ammoboxes\Supplydrop.p3d";
        hiddenSelections[] = {"camo"};
        hiddenSelectionsTextures[] = {""};
        isUav = 0;
        crew = "";
        typicalCargo[] = {};
        reportRemoteTargets = 0;
        receiveRemoteTargets = 0;
        reportOwnPosition = 0;
        radarTarget = 1;
        radarTargetSize = 1;
        visualTarget = 1;
        visualTargetSize = 1;
        irTarget = 1;
        irTargetSize = 1;
        class Turrets {};
        class Components {};
    };
    class AEGISM_MunitionProxy_missile: AEGISM_MunitionProxy
    {
        scope = 1;
        displayName = "AEGIS-M Munition Proxy (missile)";
    };
    class AEGISM_MunitionProxy_rocket: AEGISM_MunitionProxy
    {
        scope = 1;
        displayName = "AEGIS-M Munition Proxy (rocket)";
    };
    class AEGISM_MunitionProxy_bomb: AEGISM_MunitionProxy
    {
        scope = 1;
        displayName = "AEGIS-M Munition Proxy (bomb)";
    };
    class AEGISM_MunitionProxy_artilleryShell: AEGISM_MunitionProxy
    {
        scope = 1;
        displayName = "AEGIS-M Munition Proxy (artillery, mortar, MLRS)";
    };
};

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
