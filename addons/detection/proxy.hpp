// Munition sensor proxies (aegism_detect_fnc_proxyCreate, aegism_detect_fnc_
// proxyFollow, aegism_detect_fnc_proxyCheckAttach).

// When a munition's proxy is created (aegism_detect_fnc_proxyCreate): the
// earlier it exists, the sooner the sensors can see the munition.
//   attached (the usual) - AEGISM_PROXY_MIN_DELAY s after launch, attached at
//       once. An attached proxy doesn't collide with the launching vehicle:
//       made half a second after release, a bomb's proxy was still beside
//       its aircraft (a bomb leaves at the aircraft's own speed) and nothing
//       happened.
//   moved every frame (an ammo type that didn't carry one, aegism_detect_
//       fnc_proxyCheckAttach) - a free, simulated vehicle, so not until its
//       munition is clear of whatever fired it: farther from the shooter than
//       the shooter's bounding radius, plus AEGISM_PROXY_OFFSET, plus the
//       proxy's own bounding radius -- or AEGISM_PROXY_MAX_DELAY s after
//       launch at the latest (half a second puts a rocket about a hundred
//       metres clear).
#define AEGISM_PROXY_MIN_DELAY 0.1
#define AEGISM_PROXY_MAX_DELAY 0.5

// The proxy sits this far above its munition, square to its flight: off the
// path, so neither the munition nor the next round of its salvo can strike
// it. (It used to trail 5 m behind -- right where the next rocket of a
// ripple flies, and they flew into it.) A few metres are nothing to a sensor
// kilometres away.
#define AEGISM_PROXY_OFFSET 6

// How long after attaching to check the proxy really came along: at least
// AEGISM_PROXY_ATTACH_CHECK s, and once the munition is more than twice
// AEGISM_PROXY_ATTACH_TOLERANCE from where the proxy was made -- so one left
// behind is unmistakably off -- or AEGISM_PROXY_ATTACH_TIMEOUT s after that
// for a slow one. (A proxy made a tenth of a second after launch, the munition
// still slow, couldn't be judged on a fixed quarter second.)
#define AEGISM_PROXY_ATTACH_CHECK 0.25
#define AEGISM_PROXY_ATTACH_TIMEOUT 2

// An attached proxy sits AEGISM_PROXY_OFFSET m from its munition. One the
// munition didn't carry stays where it was made -- the MLRS carrier was 135 m
// from it a quarter second after it was made half a second after launch, in
// testing.
#define AEGISM_PROXY_ATTACH_TOLERANCE 20

// A proxy hit by the incoming side's own blast (aegism_detect_fnc_
// proxyCreate) only counts within this many seconds of AEGIS-M destroying a
// munition whose blast reaches it (aegism_detect_fnc_destroyMunition) -- the
// salvo neighbours an intercept takes out with it. Otherwise it's the salvo
// landing: the MLRS's own warheads going off at impact were logged as kills.
#define AEGISM_KILL_NOTE 0.5
