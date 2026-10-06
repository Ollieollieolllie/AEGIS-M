// Scripted munition detection (aegism_detect_fnc_sensorView, aegism_detect_
// fnc_munitionSeen).

// A munition's signature to radar, IR and visual sensors alike: a sensor's
// range is scaled by its target's size (the game does the same -- the
// Cheetah's 9000 m radar first saw a Darter, size 0.1, at 852 m). 2.5 is
// what the munition sensor proxies carried (radarTargetSize, irTargetSize,
// visualTargetSize) when the game's own sensors did the detecting: raised
// from 1, where many munitions went unseen, and kept when the proxies went.
#define AEGISM_MUNITION_SIGNATURE 2.5

// A clear line of sight from a vehicle to a munition isn't traced again for
// this long (a blocked one is, every read): the rays, kilometres long, are
// most of what detection costs in a salvo. Inside the pools' 3 s contact
// expiry, so a munition that goes behind a ridge still drops out within a
// few seconds.
#define AEGISM_LOS_REUSE 2

// lineIntersectsSurfaces' own hard limit, m: objects in the way are looked
// for along the first this much of a line of sight (terrain all the way).
#define AEGISM_LOS_OBJECT_REACH 5000
