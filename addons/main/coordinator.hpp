// How the Site coordinator (aegism_intercept_fnc_assignEngagements) spends a
// frame, shared with what calls on it (aegism_network_fnc_moduleInit,
// aegism_detect_fnc_munitionCheck).

// Seconds between the coordinator's runs (assignments, links, alarm).
#define AEGISM_COORDINATOR_INTERVAL 0.5

// A munition this close to impact is urgent: half a second, or a few frames,
// is a real part of what's left to engage it in -- a crew's reaction, a
// turret's swing, a gun's cue and minimum firing window and a short-range
// missile's flight all come out of it. New to a Site, it has the coordinator
// run at once instead of at its next turn, and its shots are worked out in
// that run however long that takes. One further out can wait for both.
#define AEGISM_URGENT_TTI 20

// The longest a munition that isn't urgent goes before its launchers are
// looked at again -- its place in the reserve plan, a launcher for it, its
// claim's hand-off (aegism_intercept_fnc_assignEngagements, _asleep): a
// tenth of the least time such a munition has left. It's looked at sooner
// when a launcher is planned to fire at it sooner, or loses its launcher.
#define AEGISM_FAR_INTERVAL 2

// New steps of launcher shots (intercept solves along a munition's path,
// aegism_intercept_fnc_planShot) a coordinator run works out before it puts
// off the looks that can wait (aegism_intercept_fnc_assignEngagements,
// _mustLook): about what one frame of working ahead gets through (at most 11
// a frame in one test, 2026-10-06). A count, not a time: diag_tickTime is
// too coarse to time single steps after an hour (perf.hpp).
#define AEGISM_PLAN_STEPS 10

// Seconds a frame between the coordinator's runs may spend working out the
// launcher shots of the munitions a run put off (aegism_intercept_fnc_
// planAhead): about a sixth of a frame at 30 fps. A salvo coming into view
// costs several short frames that way instead of one long one (60 ms in one
// test, 345 ms in another).
#define AEGISM_PLAN_BUDGET 0.005
