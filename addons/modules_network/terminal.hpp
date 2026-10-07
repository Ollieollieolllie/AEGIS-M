// Control ids of a terminal's screen (aegism_network_fnc_terminalOpen).
#define AEGISM_TERMINAL_GROUP_IDC 77801
#define AEGISM_TERMINAL_BOARD_IDC 77802
#define AEGISM_TERMINAL_LIST_IDC 77803
#define AEGISM_TERMINAL_FORM_IDC 77804
#define AEGISM_TERMINAL_TAB_STATUS_IDC 77805
#define AEGISM_TERMINAL_TAB_SETTINGS_IDC 77806
#define AEGISM_TERMINAL_APPLY_IDC 77807
#define AEGISM_TERMINAL_REVERT_IDC 77808
#define AEGISM_TERMINAL_NOTE_IDC 77809
#define AEGISM_TERMINAL_HEADING_IDC 77810
#define AEGISM_TERMINAL_BADGE_IDC 77811
// Its Interception page (aegism_network_fnc_terminalIntercept).
#define AEGISM_TERMINAL_TAB_INTERCEPT_IDC 77812
#define AEGISM_TERMINAL_MAP_IDC 77813
#define AEGISM_TERMINAL_TRACKS_IDC 77814
#define AEGISM_TERMINAL_WEAPONS_IDC 77815
#define AEGISM_TERMINAL_ENGAGE_IDC 77816
#define AEGISM_TERMINAL_CEASE_IDC 77817
#define AEGISM_TERMINAL_AUTO_IDC 77818
#define AEGISM_TERMINAL_TRACKS_HEAD_IDC 77819
#define AEGISM_TERMINAL_WEAPONS_HEAD_IDC 77820
#define AEGISM_TERMINAL_ORDERS_IDC 77821
#define AEGISM_TERMINAL_RADARS_HEAD_IDC 77822
#define AEGISM_TERMINAL_RADARS_IDC 77823
#define AEGISM_TERMINAL_RADAR_AUTO_IDC 77824
#define AEGISM_TERMINAL_RADAR_ON_IDC 77825
#define AEGISM_TERMINAL_RADAR_OFF_IDC 77826
#define AEGISM_TERMINAL_INTERCEPT_IDCS [AEGISM_TERMINAL_MAP_IDC, AEGISM_TERMINAL_TRACKS_IDC, AEGISM_TERMINAL_WEAPONS_IDC, AEGISM_TERMINAL_ENGAGE_IDC, AEGISM_TERMINAL_CEASE_IDC, AEGISM_TERMINAL_AUTO_IDC, AEGISM_TERMINAL_TRACKS_HEAD_IDC, AEGISM_TERMINAL_WEAPONS_HEAD_IDC, AEGISM_TERMINAL_ORDERS_IDC, AEGISM_TERMINAL_RADARS_HEAD_IDC, AEGISM_TERMINAL_RADARS_IDC, AEGISM_TERMINAL_RADAR_AUTO_IDC, AEGISM_TERMINAL_RADAR_ON_IDC, AEGISM_TERMINAL_RADAR_OFF_IDC]

// The screen's colours.
#define AEGISM_TERMINAL_ACCENT [0.31, 0.76, 0.97, 1]
#define AEGISM_TERMINAL_DIM [0.56, 0.64, 0.68, 1]
#define AEGISM_TERMINAL_ACCENT_HEX "#4FC3F7"
#define AEGISM_TERMINAL_DIM_HEX "#90A4AE"
#define AEGISM_TERMINAL_WARN_HEX "#FFA726"
#define AEGISM_TERMINAL_GOOD_HEX "#66BB6A"
// A track on the Interception page's map and list, by what it is to the
// Site: one it engages, one a terminal ordered a weapon onto, a hostile of a
// class it doesn't engage, a friendly, and anything else.
#define AEGISM_TERMINAL_TRACK_THREAT [0.94, 0.33, 0.31, 1]
#define AEGISM_TERMINAL_TRACK_ORDERED [0.9, 0.45, 0.95, 1]
#define AEGISM_TERMINAL_TRACK_HOSTILE [1, 0.79, 0.16, 1]
#define AEGISM_TERMINAL_TRACK_FRIENDLY [0.31, 0.76, 0.97, 1]
#define AEGISM_TERMINAL_TRACK_NEUTRAL [0.7, 0.7, 0.7, 1]
// The Site's own missiles in flight on the map (one fired on an order is
// the order colour), and a radar emitting or silent.
#define AEGISM_TERMINAL_MISSILE [1, 1, 1, 1]
#define AEGISM_TERMINAL_RADAR_ON [1, 0.79, 0.16, 1]
#define AEGISM_TERMINAL_RADAR_OFF [0.47, 0.56, 0.61, 1]

// A player has to be this close to a terminal for the server to take a
// change from it, m.
#define AEGISM_TERMINAL_REACH 10

// How long a vehicle's read of the aircraft its sensors see besides the
// Site's own contacts stays good for the Interception page, s.
#define AEGISM_TERMINAL_TRACK_FRESH 2
// Launchers of one type (and weapon) within this of another are one row of
// the page's weapon list, m.
#define AEGISM_TERMINAL_BATTERY_RADIUS 150
// The page's map opens on the Site or vehicle picked showing about this
// much ground across, m.
#define AEGISM_TERMINAL_MAP_SPAN 24000
// A click on the page's map picks the track nearest to it within this much
// of the screen.
#define AEGISM_TERMINAL_PICK_RADIUS 0.03
