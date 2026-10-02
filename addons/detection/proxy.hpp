// Munition sensor proxies (aegism_detect_fnc_proxyCreate, aegism_detect_fnc_
// proxyFollow, aegism_detect_fnc_proxyCheckAttach).

// How long after launch a munition's proxy is created: the proxy has real
// geometry, and created at the muzzle it's inside the launching vehicle.
// Half a second puts a rocket about a hundred metres clear.
#define AEGISM_PROXY_DELAY 0.5

// The proxy sits this far behind its munition, along its flight, so the
// munition always flies away from it and can never strike it. A few metres
// are nothing to a sensor kilometres away.
#define AEGISM_PROXY_TRAIL 5

// How long after attaching to check the proxy really came along.
#define AEGISM_PROXY_ATTACH_CHECK 0.25

// An attached proxy sits AEGISM_PROXY_TRAIL m behind its munition. One the
// munition didn't carry stays where it was made, and a rocket is over fifty
// metres away from it by the check -- 135 m for the MLRS carrier, half a
// second after launch, in testing.
#define AEGISM_PROXY_ATTACH_TOLERANCE 20
