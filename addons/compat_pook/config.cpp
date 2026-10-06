// AEGIS-M compatibility with POOK's SAM pack (Steam Workshop 1154375007).
// Loaded only when POOK's pack is (skipWhenMissingDependencies): without it,
// this addon is skipped with a line in the RPT and nothing else.
//
// Nothing here runs, compiles or calls any of POOK's scripts. What's
// changed, and why -- everything else of POOK's is left as it is:
//
// 1. The 20, 23 and 30 mm AA rounds' fixed 1 s airburst (CfgAmmo below).
//    Each is a submunition carrier that turns into an 8-12 m airburst
//    triggerTime s after it's fired: 1 s, 660-910 m out, wherever its
//    target is -- so the SA-19/SA-22, C-RAM and ZU-23 guns had a ~1 km
//    reach. The burst now comes at the end of the round's own life (POOK's
//    timeToLive), no later than when it would reach 6 km. Worked out on its
//    own speed (its magazine's initSpeed) and drag (its airFriction, the
//    engine's v^2 drag: distance ln(1 + k v0 t) / k):
//        pook_SA22_30mm_AA   960 m/s, -0.00095: 6 s, 1966 m, 148 m/s left
//        pook_20mm_HEI      1030 m/s, -0.00077: 4 s, 1855 m, 247 m/s left
//        pook_Quad_ZAP23_HET 910 m/s,  0      : 6.59 s, 6000 m (no drag;
//                                               capped at 6 km)
//        pook_ZAP23_HE       910 m/s, -0.000924: 11 s, 2519 m, 89 m/s left
//    With this drag no burst time gives them 5-6 km: the 30 mm would take
//    327 s to get there. timeToLive goes a second past the burst, so the
//    burst always comes before the round is removed. Where inside that a gun
//    actually opens fire is AEGIS-M's own (aegism_intercept_fnc_
//    openFireRange: one burst's chance of a hit), and any mod's airburst
//    round is read the same way (aegism_intercept_fnc_ammoBurst).
//
// 2. POOK's scripts that work a vehicle's weapons themselves are switched
//    off (CfgFunctions below): each of POOK's function entries is pointed
//    at a file that does nothing (functions\fn_blocked.sqf, logged once per
//    function as COMPAT). For every POOK vehicle, AEGIS-M's or not, while
//    this addon is loaded:
//        pook_SAM_fnc_incomingGroup, pook_SAM_fnc_incoming - a missile fired
//            at any of 52 POOK vehicle classes sent the nearest POOK SHORAD
//            (SA-15, SA-19, SA-22, SA-8, Patriot, C-RAM, MEADS) after it:
//            doWatch, doTarget and fireAtTarget in a loop with no wait until
//            the missile was gone, a hint and group chat -- uncommanded fire
//            on an AEGIS-M vehicle.
//        pook_SAM_fnc_AAA_Fuse, and the gun Fired handlers that lead to it
//            (pook_S60_fnc_S60_Fired / KS12_Fired / KS19_Fired / ZU23_Fired)
//            - the 57-100 mm guns' airburst fuse: burst each round at the
//            height of the vehicle's assignedTarget, or 250 m with none --
//            and AEGIS-M never assigns one (a munition can't be: aegism_
//            intercept_fnc_debugProbeMunitions). AEGIS-M's own fuse handles
//            its rounds; a gun AEGIS-M doesn't control fires plain shells.
//
// Left running: POOK's missile launch scripts (its SAM vehicles' Fired
// handlers). Three of them are the launch itself -- the SA-10, SA-15 and
// SA-20's turn each missile to leave vertically -- and with AEGIS-M
// controlling POOK's launchers they've worked. What they do to the radar
// (on at each launch, back to the AI after) AEGIS-M sets back for any mod
// (aegism_system_fnc_emconUpdate, RADAR-OVERRIDE). Not handled: POOK's site
// spawners (the "SITE" objects), whose radar scripts pick targets and fire
// the site's launchers themselves -- build AEGIS-M Sites from POOK's
// vehicles placed one by one (AEGIS-M logs UNCOMMANDED-FIRE if a script
// fires its weapon).

class CfgPatches
{
    class aegism_compat_pook
    {
        units[] = {};
        weapons[] = {};
        author = "Snow(Dryden)";
        requiredVersion = 2.14;
        requiredAddons[] = {"aegism_main", "aegism_intercept", "pook_SAM_Base"};
        skipWhenMissingDependencies = 1;
        #include "version.hpp"
    };
};

// POOK's own function entries, each pointed at the file that does nothing.
#define AEGISM_POOK_BLOCKED file = "\x\aegism\addons\compat_pook\functions\fn_blocked.sqf"
class CfgFunctions
{
    class pook_SAM
    {
        class Missiles
        {
            class incoming { AEGISM_POOK_BLOCKED; };
            class incomingGroup { AEGISM_POOK_BLOCKED; };
        };
        class AAA
        {
            class AAA_Fuse { AEGISM_POOK_BLOCKED; };
        };
    };
    class pook_S60
    {
        class AAA
        {
            class S60_Fired { AEGISM_POOK_BLOCKED; };
            class KS12_Fired { AEGISM_POOK_BLOCKED; };
            class KS19_Fired { AEGISM_POOK_BLOCKED; };
            class ZU23_Fired { AEGISM_POOK_BLOCKED; };
        };
    };
};

class CfgAmmo
{
    class SubmunitionBullet;
    class pook_SA22_30mm_AA: SubmunitionBullet
    {
        triggerTime = 6;
        timeToLive = 7;
    };
    class pook_20mm_HEI: SubmunitionBullet
    {
        triggerTime = 4;
        timeToLive = 5;
    };
    class pook_Quad_ZAP23_HET: SubmunitionBullet
    {
        triggerTime = 6.59;
        timeToLive = 11;
    };
    class pook_ZAP23_HE: pook_Quad_ZAP23_HET
    {
        triggerTime = 11;
        timeToLive = 12;
    };
};
