// A launcher's planned shot at a munition (aegism_intercept_fnc_planShot),
// shared with the Site coordinator (aegism_intercept_fnc_assignEngagements).

// Seconds between the projected positions checked along a munition's path.
#define AEGISM_RESERVE_PLAN_STEP 1
// A cached plan scan is reused while the munition stays within this many
// metres of the path it was scanned on, for at most this many seconds.
#define AEGISM_PLAN_CACHE_TOLERANCE 25
#define AEGISM_PLAN_CACHE_MAX_AGE 10
