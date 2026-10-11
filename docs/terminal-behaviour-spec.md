# JuiceSSH 3.2.2 - Terminal (session) screen behaviour specification

Source of every claim: the apktool 3.0.3 decode of `com.sonelli.juicessh` 3.2.2 (versionCode 96)
located at `D:\dev\_apk\juicessh`. Paths below are relative to that directory. Line numbers are
1-based positions in the decoded `.smali` / `.xml` files.

Conventions used in this document:

* `\e` = the single byte `0x1B` (ESC), `\r` = `0x0D`, `\t` = `0x09`.
* "VERIFIED" facts come from a decoded file that was read directly; the citation is given inline.
* Anything that could not be confirmed from the decode is prefixed `INFERRED:`. There are no
  invented colours, strings or key sequences anywhere in this document - every literal is quoted
  from a decoded resource or smali constant.
* `@string/...` references are always resolved to the literal English value found in
  `res/values/strings.xml`.

Screen entry point: `com.sonelli.juicessh.activities.TerminalEmulatorActivity`
(`AndroidManifest.xml`): `android:label="@string/juicessh"`,
`android:theme="@style/Theme.JuiceSSH.Material.Terminal"`,
`android:windowSoftInputMode="adjustResize"`, `android:exported="true"`, and a single `VIEW`
intent-filter with categories `DEFAULT` + `BROWSABLE` and the data schemes
`ssh`, `ssh-forward`, `telnet`, `local`, `mosh`. Its `android:configChanges` list contains
`mcc|mnc|locale|touchscreen|keyboard|keyboardHidden|navigation|orientation|screenLayout|uiMode|screenSize|smallestScreenSize`.

---

## 0. Everything-at-a-glance defaults

All of the following are written by `com.sonelli.juicessh.models.Config.b(Context)`
(`smali/com/sonelli/juicessh/models/Config.smali:86-242`) the first time the app runs, i.e. these are
the shipped default values of the terminal screen's settings:

| Config key | Default value | Where it is consumed |
|---|---|---|
| `terminal:font_size` | `8` | `TerminalEmulatorActivity.smali:3104-3125` (`x()`), `:2503-2524` (`p(Z)`) |
| `terminal:type` | `linux` | `TerminalEmulatorActivity.smali:1131-1142` (F-key fallback), transports (`smali/com/sonelli/ei0.smali:329`) |
| `terminal:utf8` | `true` | transport layer (`smali/com/sonelli/ei0.smali:236`), not read by the activity |
| `terminal:keyboard_position` | `1` = below | `TerminalEmulatorActivity.smali:835` (`j()`), `:2896` (`v()`) |
| `terminal:theme` | `2` = Solarized Dark | `TerminalEmulatorActivity.smali:3063` (`x()`) |
| `terminal:bell_mode` | `0` = Disabled | `smali/com/sonelli/zi0.smali:186` |
| `terminal:autocomplete` | `0` | **never read** - see item 4 |
| `terminal:horizontal_swipe_mode` | `0` = Irssi | `smali/com/sonelli/util/TerminalGestureListener.smali` ctor |
| `terminal:margin` | `0` | `TerminalEmulatorActivity.smali:1435` (`m()`) |
| `terminal:margin_selection` | `0` | `TerminalEmulatorActivity$f.smali:39` |
| `terminal:font` | `""` (empty) | `smali/com/sonelli/aj0.smali` (`TerminalFont.c(Context)`) - empty resolves to the default font |
| `tutorial:terminal` | `false` | `TerminalEmulatorActivity.smali:1482` (`m()`) |
| `notifications:enabled` | `true` | notification paths |

`terminal:type`, `terminal:theme`, `terminal:horizontal_swipe_mode`, `terminal:keyboard_position` and
`terminal:bell_mode` are chosen from list preferences whose entries come from
`res/values/arrays.xml` (see items 4, 5, 8).

Terminal geometry: the emulator is initialised as **80 columns x 25 rows** -
`initializeEmulator(0x50, 0x19)` in `TerminalEmulatorActivity.smali:2615+` (`q(TermSession)`),
which calls `TermSession.initializeEmulator(columns, rows)`
(`smali/jackpal/androidterm/emulatorview/TermSession.smali:520-549`).

---

## 1. Session lifecycle

### 1.1 Building and attaching a session

| Step | Code | Behaviour |
|---|---|---|
| UI construction | `TerminalEmulatorActivity.j(Bundle)` `:547` | Builds a root `RelativeLayout a0` containing a vertical `LinearLayout b0` (gravity `0x11`); inflates `hacker_keyboard_pager` (`0x7f0c0047`) as the extra-keys `ViewPager P`; inflates the two copy-instruction bars; inflates the tutorial layout `tutorial_terminal` (`0x7f0c00c2`, `tutorial_button` = `0x7f090228`); adds the terminal container `RelativeLayout c0` (height `-2`, weight 1) to `b0`; ends by calling `ConnectionIntentParser.f(ctx, intent, this)` to resolve the launch intent. |
| Open a connection | `a(Connection, Snippet, Z)` `:79` | `Connection.s(FragmentActivity, BasicTransportChainListener)` -> builds the transport chain object `com.sonelli.ai0`, then `.x(snippet)` and `.v(boolean)`. |
| Re-attach an existing session | `b(int connectionId, UUID sessionId)` `:99` | Looks the session up in `ConnectionManager`; if a live chain for that `(connectionId, sessionId)` exists it is reused (`R.u(true)` + `x()`), otherwise the `TerminalView` is rebuilt and `ConnectionManager.b(ctx, ChainRequest)` is issued. |
| Port forward vs session | `c(ConnectionProvider, Z, Z)` `:192` | Chooses between the port-forwarding path and the interactive terminal chain. |
| Error | `d(int, String)` `:248` | Toast of the supplied error text, then `finish()`. |
| Attach to view | `m()` `:1275` | `getWindow().setSoftInputMode(0x10)` (`SOFT_INPUT_ADJUST_RESIZE`); takes the last provider of the chain `chain.p()`; if it implements `TerminalSessionProvider` it is stored in `S` and its terminal type string in `f0` (`f()`); if the current `TerminalView T` has no parent it is added to `c0`, otherwise the old view is removed and a brand-new view is created from `provider.e()` (the provider's `TermSession`) via `q(TermSession)`; then `x()` re-applies the theme/size, the `terminal:margin` is applied and the one-shot tutorial is shown if `tutorial:terminal` is `false`. |
| Session <-> view binding | `q(TermSession)` `:2615` | Creates `new TerminalView(R.b, ctx, session, displayMetrics)`, calls `attachSession`, and if the session is not already running calls `initializeEmulator(80, 25)` and installs `new com.sonelli.zi0(ctx, connectionId, uuid)` as the bell listener. Then: `setExtGestureListener(new TerminalGestureListener(...))`, **`setAltSendsEsc(false)` (hard-coded)**, `setMouseTracking(true)`, `setTermType(provider.f())`, backspace mode from the connection (mode 1 -> `"\u0008"` legacy `^H`, mode 0 (default) -> `"\u007f"` `^?`), **`setAutocomplete(false)` (hard-coded)**, `registerForContextMenu(view)`, and installs the `OnEscListener`/`OnBackListener`/`OnResizeListener`/`OnKeyPressListener` inner classes. |
| Foreground / resume-side work | `l()` `:1228` | `chain.u(true)` (mark the chain attached), `x()`, `setSoftInputMode(0x10)`, then `InputMethodManager.showSoftInput(TerminalView, 1 /*SHOW_IMPLICIT*/)`. |

### 1.2 Activity lifecycle

| Callback | Location | Behaviour |
|---|---|---|
| `onPause()` | `:2377` | `super`; `getWindow().clearFlags(0x80)` (drops `FLAG_KEEP_SCREEN_ON`); `Z = false` (screen-on flag); the `AtomicBoolean e0` is set to `false`; `chain.u(false)`; the soft keyboard is hidden with `InputMethodManager.hideSoftInputFromWindow(windowToken, 0)`. |
| `onStart()` | `:2437` | `super` only. |
| `onStop()` | `:2446` | `super` only - **the SSH session is NOT torn down when the activity stops**; it is kept alive by the `ConnectionManagerService` foreground service (item 12). |
| `onBackPressed()` | `:1768` | Shows `com.sonelli.util.BackgroundPrompt` (see below). |
| `onActivityResult(int,int,Intent)` | `:1690` | Handles request code `0x3620` (13856) - the "Save transcript" document picker; on `RESULT_OK` with data it opens the returned URI as an `OutputStream` and writes `TermSession.getTranscriptText().trim()` through a `BufferedWriter`; `IOException` is only logged via `printStackTrace()`. |
| `onContextItemSelected` / `onCreateContextMenu` | `:1786` / `:2108` | The session overflow menu - item 6. |

The activity declares a long `android:configChanges` list that includes `orientation`,
`screenSize`, `keyboardHidden` and `screenLayout`, so rotation and IME visibility changes do not
recreate it; the session survives rotation in-process.

`INFERRED:` `j(Bundle)` is the method that performs the `setContentView`-equivalent UI build and is
called from `onCreate` (the decode shows the method body but the call site sits in the base class
`com.sonelli.util.SessionedFragmentActivity`, whose `onCreate` was not re-read line by line).

### 1.3 Leaving the session

`onBackPressed()` builds `BackgroundPrompt` (`smali/com/sonelli/util/BackgroundPrompt.smali`):

* Title: `@string/app_name` = **"JuiceSSH"** (`:65-72`)
* Message: `@string/background_session` + `"\n\n"` + `@string/background_session_battery_warning`
  (`:30-58`) = **"Do you want to leave this session running in the background?"** + blank line +
  **"Warning: Sessions left running in the background will prevent your device from sleeping, and consume battery."**
* Positive button `@string/yes` = **"Yes"** (`:82-93`)
* Neutral/negative: on SDK >= 21 neutral = `@string/cancel` = **"Cancel"**, negative =
  `@string/no` = **"No"**; below 21 the two are swapped (`:106-146`).
* `setCancelable(false)` initially, then `setCancelable(true)`.

The listeners are `TerminalEmulatorActivity$l` (`onBackPressed`), `$c` (the extra-key that opens the
same prompt) and `BackgroundPrompt$a` (positive button). `TerminalEmulatorActivity$l.smali`:

* `a()` logs *"Closing terminal activity at users request (session not backgrounded)"*; if the chain
  is null it simply `finish()`es, otherwise it calls `f(connectionId, sessionUuid)` (the disconnect
  path) - `:38-71`.
* `b()` logs *"Closing terminal activity at users request (session backgrounded)"* and only calls
  `finish()` - `:73-88`, i.e. the session keeps running in the background.

`INFERRED:` the "Yes" button maps to `b()` (background) and the non-backgrounding button maps to
`a()` (disconnect); the exact button->listener wiring lives in `BackgroundPrompt$a/$b/$c` bodies,
which were not read line by line.

---

## 2. Multiple sessions / tabs

**The terminal screen shows exactly one session at a time and has no session tabs or session pager.**

Evidence:

* The activity holds a single chain field `R : Lcom/sonelli/ai0;`, a single session provider
  `S : TerminalSessionProvider` and a single `T : com.sonelli.juicessh.views.TerminalView`
  (`TerminalEmulatorActivity.smali` field list / usages at `:1232-1240`, `:1338-1395`).
* The only `ViewPager` in the terminal layout is `hacker_keyboard_pager`
  (`res/layout/hacker_keyboard_pager.xml`, inflated in `j()` at `:547`) and its adapter
  `com.sonelli.lh0` (`smali/com/sonelli/lh0.smali`, `.source "HackersKeyboardPagerAdapter.java"`)
  returns pages for the **extra-keys rows only**: page 0 = `hacker_keyboard` (`0x7f0c0045`) or the
  function-key row (`0x7f0c0046`, when field `a == 1`), page 1 = the autocomplete box
  (`autocomplete_box`, `0x7f0c0021`). `getCount()` is 2.
* Sessions are therefore handled by the connection service: `com.sonelli.juicessh.connections.ConnectionManager`
  keeps chains keyed by `(connectionId, sessionUuid)`; `TerminalEmulatorActivity.b(int, UUID)` `:99`
  re-attaches to a chain that is already running instead of creating a new one.
* Several concurrent sessions exist as several `TerminalEmulatorActivity` instances plus one
  ongoing notification per chain (item 12). The notification's content intent is
  `ssh://<connection>/resume?...&session_key=<uuid>` and the activity reads the
  `NOTIFICATION_TO_CANCEL` extra in `j()` to clear the notification it was resumed from.
* `INFERRED:` the app's own list of open sessions lives outside this activity (main activity /
  notification shade); no session-list UI exists inside the terminal screen.

---

## 3. Extra-keys "hacker" keyboard

### 3.1 Layout and hosting

* `res/layout/hacker_keyboard.xml` - a `TableLayout` (70dp tall) of `AutoRepeatButton` /
  `TerminalThemedButton` / `TerminalThemedImageButton`s, every one carrying
  `android:onClick="keyboardPress"` and an `android:tag` holding the payload.
* `res/layout/hacker_keyboard_function_keys.xml` - the F1..F12 page.
* Both are pages of the `ViewPager` from `res/layout/hacker_keyboard_pager.xml` (70dp tall), driven
  by `com.sonelli.lh0` (`HackersKeyboardPagerAdapter`) in `TerminalEmulatorActivity.j()` `:547`.
* A second, unused variant `res/layout/hacker_keyboard_qnx.xml` also exists (plain `Button`s, and it
  contains the only `exit_session` key, tag `-6`). Because `lh0` inflates `0x7f0c0045`/`0x7f0c0046`
  only, the QNX layout and its `exit_session` key are unreachable in 3.2.2.

### 3.2 Button table (`hacker_keyboard.xml`)

`keyboardPress(View)` `:904`: first `performHapticFeedback(1)`, then reads `getTag()` as an `int` and
`packed-switch`es on `-0x16 .. -1` (`pswitch_data` maps tag -1..-5 to `pswitch_1..pswitch_5`,
-6..-7 to `pswitch_6/pswitch_7`, -8..-10 and every positive tag to the default `pswitch_0`, and
-11..-22 to `pswitch_8`).

| Button id | `android:tag` | Case | Exact action |
|---|---|---|---|
| `keyboard_esc` | `111` | pswitch_0 | `dispatchKeyEvent(new KeyEvent(0 /*ACTION_DOWN*/, 111))` then `n()` -> ESC byte `0x1B` (see 3.3) |
| `keyboard_forwardslash` | `76` | pswitch_0 | `/` |
| `keyboard_pipe` | `-1` | pswitch_1 | `TermSession.write("|")` - writes the single byte `0x7C` directly, bypassing the key listener |
| `keyboard_dash` | `69` | pswitch_0 | `-` |
| `keyboard_home` | `122` | pswitch_0 | KEYCODE_MOVE_HOME |
| `keyboard_up` | `19` | pswitch_0 | `\e[A` |
| `keyboard_end` | `123` | pswitch_0 | KEYCODE_MOVE_END |
| `keyboard_pgup` | `92` | pswitch_0 | `\e[5~` |
| `keyboard_function_keys` | `-3` | pswitch_3 | FN: `Q.d()` reads the current pager page and `Q.f(0|1)` toggles between the normal row (page 0) and the F1..F12 row (page 1) |
| `keyboard_tab` | `61` | pswitch_0 | `\t` |
| `keyboard_ctrl` | `-2` | pswitch_2 | Latch toggle. On press: `TerminalView.sendControlKey()` (-> `mKeyListener.handleHardwareControlKey(true)`), sets `W = true`, tints the button `V.d(1)`. On release: `W = false`, `TerminalView.cancelSpecialKeyStatus()`, `V.d(0)` |
| `keyboard_alt` | `-4` | pswitch_4 | Latch toggle. Writes a raw `0x1B` byte via `TermSession.write(byte[], 0, 1)`, sets `Y = true`, `X.d(1)`; release clears it |
| `keyboard_left` | `21` | pswitch_0 | `\e[D` |
| `keyboard_down` | `20` | pswitch_0 | `\e[B` |
| `keyboard_right` | `22` | pswitch_0 | `\e[C` |
| `keyboard_pgdn` | `93` | pswitch_0 | `\e[6~` |
| `keyboard_toggle` | `-5` | pswitch_5 | `w()` -> `InputMethodManager.toggleSoftInput(2, 0)` (`SHOW_FORCED`) |
| `prev_keyboard` (F-key row) | `-7` | pswitch_7 | `v()` -> back to the normal extra-keys row (see item 4) |
| `exit_session` (QNX layout only) | `-6` | pswitch_6 | Shows the same `BackgroundPrompt` dialog as `onBackPressed` (dead code in 3.2.2) |
| F1..F12 (F-key row) | `-11` .. `-22` | pswitch_8 | `new ti0(f0).a()[abs(tag) - 11]` -> `TermSession.write(String)` (table in 3.4) |

`n()` `:1635-1672` is called after the `pswitch_0` dispatch and clears both latches (`W`/`V` for
Ctrl, `Y`/`X` for Alt), so Ctrl and Alt apply to exactly one following key press.

### 3.3 Key sequences emitted by the extra keys (via `dispatchKeyEvent`)

Positive tags are dispatched as `KeyEvent(ACTION_DOWN, keyCode)` with `metaState == 0` - Ctrl/Alt
latching is not carried in `metaState`, it is applied inside
`jackpal/androidterm/emulatorview/TermKeyListener` because `Ctrl` sets the hardware-control state on
the listener (`EmulatorView.sendControlKey()` -> `mKeyListener.handleHardwareControlKey(true)`,
`EmulatorView.smali:4130`).

`TermKeyListener.mKeyCodes` as extracted from `initKeyCodes()`
(`smali/jackpal/androidterm/emulatorview/TermKeyListener.smali:145+`):

| Keycode | Name | Sequence |
|---|---|---|
| 19 (0x13) | DPAD_UP | `\e[A` |
| 20 (0x14) | DPAD_DOWN | `\e[B` |
| 21 (0x15) | DPAD_LEFT | `\e[D` |
| 22 (0x16) | DPAD_RIGHT | `\e[C` |
| 23 (0x17) | DPAD_CENTER | `\r` |
| 61 (0x3d) | TAB | `\t` |
| 66 (0x42) | ENTER | `\r` |
| 67 (0x43) | DEL (backspace) | `\x7f` |
| 92 (0x5c) | PAGE_UP | `\e[5~` |
| 93 (0x5d) | PAGE_DOWN | `\e[6~` |
| 111 (0x6f) | ESCAPE | `\e` |
| 112 (0x70) | FORWARD_DEL | `\e[3~` |
| 120 (0x78) | SYSRQ | `\e[32~` |
| 121 (0x79) | BREAK | `\e[34~` |
| 124 (0x7c) | INSERT | `\e[2~` |
| 143 (0x8f) | NUM_LOCK | `\eOP` |
| 144..153 (0x90..0x99) | NUMPAD_0..9 | `\eOp`,`\eOq`,`\eOr`,`\eOs`,`\eOt`,`\eOu`,`\eOv`,`\eOw`,`\eOx`,`\eOy` |
| 154..161 (0x9a..0xa1) | NUMPAD_DIVIDE/MULTIPLY/SUBTRACT/ADD/DOT/COMMA/ENTER/EQUALS | `\eOo`,`\eOj`,`\eOm`,`\eOk`,`\eOn`,`\eOl`,`\eOM`,`\eOX` |

Note that the hardware F1..F12 keycodes (131..142) have **no** entry in `mKeyCodes` - JuiceSSH's F-key
row uses its own `EscapeCharacters` table instead (3.4).

`mKeyMap` (in the same method) additionally holds the *modified* variants keyed by a composite key
composed of `0x20000000` (Shift), `0x80000000` (Alt), `0xA0000000` (Shift+Alt) and `0x40000000`
(Ctrl) plus the keycode, e.g. the modified arrows `\e[1;2D` .. `\e[1;8D`, `\e[3;2~`/`[3;3~`/`[3;5~`,
`\e[2;2~`/`[2;3~`/`[2;5~`, `\e[1;5H`, `\e[1;5F`, `\e\r`, `\e[1;2P`..`[1;2S`, `\e[15;2~`,
`\e[17;2~`..`\e[21;2~`.

`setCursorKeysApplicationMode(boolean)` (`TermKeyListener.smali:2752`) swaps the cursor keys between
`\e[A..\e[D` and `\eOA..\eOD` when the remote application requests application-cursor mode.

Ctrl+letter control characters are produced by `mapControlChar(boolean ctrl, boolean fn, int keyCode)`
(`TermKeyListener.smali:2248`), called from `keyDown(...)` `:1787`; it contains no string literals and
returns either a control character or a value `>= 0xa00000` meaning "handle keycode
`value - 0xa00000` as a sequence".
`INFERRED:` the individual Ctrl+key mappings follow the upstream Android Terminal Emulator table
(`Ctrl+A`..`Ctrl+Z` -> `0x01`..`0x1A`, `Ctrl+Space` -> `0x00`, `Ctrl+[` -> `0x1B`, `Ctrl+\` -> `0x1C`,
`Ctrl+]` -> `0x1D`, `Ctrl+^` -> `0x1E`, `Ctrl+_` -> `0x1F`, `Ctrl+?` -> `0x7F`); each branch was not
re-extracted individually.

### 3.4 F1..F12 sequences per `terminal:type`

`com.sonelli.ti0` (`EscapeCharacters.java`) maps the type string to an enum in its constructor
(`smali/com/sonelli/ti0.smali:19-107`: `linux`->`O`, `xterm`->`P`, `xterm-color`->`Q`,
`xterm-256color`->`R`, `vt100`->`S`) and `ti0$a.a` maps those to the switch values 1..5
(`smali/com/sonelli/ti0$a.smali:37-111`). `a()` (`smali/com/sonelli/ti0.smali:111-407`) returns a
12-element `String[]` indexed `abs(tag) - 11`, i.e. index 0 = F1 .. index 11 = F12. The key press
uses `f0` (the session's terminal type) and only falls back to `Config` `terminal:type` when `f0` is
null (`TerminalEmulatorActivity.smali:1130-1183`).

`linux` (default), switch value 1:
`F1 \e[[A`, `F2 \e[[B`, `F3 \e[[C`, `F4 \e[[D`, `F5 \e[[E`, `F6 \e[17~`, `F7 \e[18~`, `F8 \e[19~`,
`F9 \e[20~`, `F10 \e[21~`, `F11 \e[23~`, `F12 \e[24~`

`xterm` (value 2) and `xterm-256color` (value 4):
`F1 \eOP`, `F2 \eOQ`, `F3 \eOR`, `F4 \eOS`, `F5 \e[15~`, `F6 \e[17~`, `F7 \e[18~`, `F8 \e[19~`,
`F9 \e[20~`, `F10 \e[21~`, `F11 \e[23~`, `F12 \e[24~`

`xterm-color` (value 3):
`F1 \e[11~`, `F2 \e[12~`, `F3 \e[13~`, `F4 \e[14~`, `F5 \e[15~`, `F6 \e[17~`, `F7 \e[18~`,
`F8 \e[19~`, `F9 \e[20~`, `F10 \e[21~`, `F11 \e[23~`, `F12 \e[24~`

`vt100` (value 5):
`F1 \eOP`, `F2 \eOQ`, `F3 \eOR`, `F4 \eOS`, `F5 \eOt`, `F6 \eOu`, `F7 \eOv`, `F8 \eOl`, `F9 \eOw`,
`F10 \eOx`, `F11 ""`, `F12 ""` (empty strings - F11/F12 send nothing)

For an unknown/absent type the constructor stores `null`, so `a()` would throw; the settings UI only
offers the five values above, and `Config` defaults the key to `linux`.

---

## 4. Soft keyboard interaction and `terminal:keyboard_position`

* `TerminalView` is constructed with `setUseCookedIME(true)` (`smali/com/sonelli/juicessh/views/TerminalView.smali`
  constructor) - the IME, not the app, composes text.
* `windowSoftInputMode` is `adjustResize` in the manifest, and `m()`/`l()` both call
  `getWindow().setSoftInputMode(0x10)` at runtime.
* Layout order, from `j(Bundle)` `:547`: root `RelativeLayout a0` -> vertical `LinearLayout b0`
  (gravity `0x11`) -> [optional extra-keys `ViewPager P`] + terminal container `RelativeLayout c0`
  (height `-2`, weight 1) + [optional copy-instruction bar].
* `terminal:keyboard_position` is read at `:835`:
  * `0` = `@string/above_terminal` = **"Above Terminal"** -> `b0.addView(P, 0)` (inserted *above* the terminal)
  * `1` = `@string/below_terminal` = **"Below Terminal"** (default) -> `b0.addView(P)` (appended *below*)
  * `2` = `@string/disabled` = **"Disabled"** -> the pager is never added to the layout
  (Names/values from `res/values/arrays.xml:55-64`; preference title
  `@string/popup_keyboard_position` = **"Popup keyboard position"**.)
* `v()` `:2865` is the "restore/toggle the popup keyboard" action:
  1. if the pager is not on page 0 (`Q.d() != 0`) -> `Q.f(0)` (back to the extra-keys page);
  2. else if the pager has no parent (i.e. it was removed because the position setting was
     "Disabled") -> re-add it according to `terminal:keyboard_position`;
  3. else -> `w()` = `InputMethodManager.toggleSoftInput(2, 0)`.
* Showing the IME by tapping the terminal: `TerminalGestureListener.onSingleTapUp` calls
  `InputMethodManager.showSoftInput(view, 0, ResultReceiver)`
  (`smali/com/sonelli/util/TerminalGestureListener.smali`, inner class `$2`).
* `terminal:autocomplete` (`0`) is **never read anywhere**: `TerminalEmulatorActivity` calls
  `setAutocomplete(false)` unconditionally in `q(TermSession)` `:2615+`, no file in
  `res/xml/` references the `autocomplete` preference, and `com/sonelli/juicessh/views` contains no
  read of the key. The autocomplete page nevertheless exists in the pager
  (`res/layout/autocomplete_box.xml` = `com.sonelli.juicessh.views.TerminalAutoCompleteBox`):
  an `EditText` with hint `@string/use_this_to_enter_text` =
  **"Use this text box to input autocompleted text.\nSwipe left to return to the popup keyboard."**,
  `textSize 12dp`, `layout_height 84dp`, `paddingBottom 35dp`,
  `inputType="textLongMessage|textMultiLine"`, `imeOptions="actionDone"`, `textCursorDrawable="@null"`.
  `INFERRED:` text typed into that box is written to the session when the IME "Done" action fires
  (the box's IME-action handler is in `TerminalEmulatorActivity$n`/`$o`, whose bodies were not read
  line by line).

---

## 5. Gestures

`com.sonelli.juicessh.views.TerminalView.onTouchEvent`
(`smali/com/sonelli/juicessh/views/TerminalView.smali:250`) gives the custom listener
`com.sonelli.util.TerminalGestureListener` first refusal on every `MotionEvent` and otherwise
delegates to `EmulatorView.onTouchEvent` (`smali/jackpal/androidterm/emulatorview/EmulatorView.smali:4026`),
which routes to a `GestureDetector` (or to text-selection handling while selecting).

### 5.1 Gesture list

| Gesture | Implementation | Effect |
|---|---|---|
| Single tap | `TerminalGestureListener.onSingleTapUp` | `showSoftInput(view, 0, ResultReceiver)`; when the IME reports `RESULT_SHOWN` (2) and the pager is on page 1 (the autocomplete box) it calls `activity.v()` (return to the popup keyboard); otherwise it maps the tap to a character cell using the 48dp grid from `com.sonelli.cl0.a(ctx, x, y, charWidth)`, extracts the word with `getWordAt(x, y, 0x823)` (`GET_WORD_AND_LINE`) and passes it to `cl0.c(activity, word)` - the URL/phone/email chooser of item 7. If nothing matched, a `Runnable` (`$2$a`) runs on the UI thread and calls `activity.v()` |
| Long press (500 ms) | `TerminalGestureListener` inner `$a` `Runnable` posted on a 500 ms handler | `activity.openContextMenu(TerminalView)` if the activity is not finishing - this opens the menu of item 6 |
| Vertical drag | not consumed by the extension listener -> `EmulatorView.onScroll` `:3807` | Scrolls the transcript: the vertical distance is accumulated in `mScrollRemainder` and divided by `mCharacterHeight` to move `mTopRow` by whole lines |
| Vertical fling | `EmulatorView.onFling` `:3280` | If mouse tracking is active (JuiceSSH sets `setMouseTracking(true)` unconditionally) the `MouseTrackingFlingRunner` starts an `android.widget.Scroller` with `fling(..., 0.15f)` and emits mouse-wheel reports (`0x40`/`0x41`) instead of scrolling; if mouse tracking is not active it flings the transcript with a `0.25f` resistance factor |
| Horizontal fling | `TerminalGestureListener.onFling` -> `c(int)` `:79` | Window-switching escape sequences, see 5.2 |
| Pinch zoom | **does not exist** | No `ScaleGestureDetector`/`onScale` anywhere in `smali/com/sonelli/util`, `smali/com/sonelli/juicessh/views` or `smali/jackpal/androidterm/emulatorview`. Font size is changed with the volume keys (`dispatchKeyEvent` keycodes 24/25) or in Settings |
| Double tap | **does not exist** | No `onDoubleTap` override in `TerminalGestureListener` or `EmulatorView`; `SimpleOnGestureListener`'s default (return `false`) applies |

### 5.2 Horizontal swipe modes (`terminal:horizontal_swipe_mode`)

`TerminalGestureListener` reads the setting into field `Q` in its constructor; `onFling` calls
`c(1)` when `dx > 0` (finger moves right) and `c(0)` when `dx < 0` (finger moves left). Non-fling or
too-slow motion never reaches `c()`.

Preference names/values (`res/values/arrays.xml:41-54`), title `@string/horizontal_swipe` =
**"Horizontal Swipe"**:

| `Q` | Preference label | `c(0)` - finger left | `c(1)` - finger right |
|---|---|---|---|
| 0 | Irssi next/prev window | `KeyEvent` with `metaState = META_CTRL_ON (0x1000)` and keyCode `44` (P) | same with keyCode `42` (N) |
| 1 | WeeChat next/prev window | `KeyEvent` with `metaState = META_ALT_ON (0x02)` and keyCode `21` (DPAD_LEFT) | same with keyCode `22` (DPAD_RIGHT) |
| 2 | Tmux next/prev window | `KeyEvent` `META_CTRL_ON` + keyCode `30` (B), then a second `KeyEvent` with no meta and keyCode `44` (P) | same prefix, second event keyCode `42` (N) |
| 3 | Screen next/prev window | prefix `META_CTRL_ON` + keyCode `29` (A), then keyCode `44` (P) | same prefix, then keyCode `42` (N) |
| 4 | Disabled | returns immediately | returns immediately |

Because these are real `KeyEvent`s they are delivered to `TermKeyListener`, so the Ctrl forms become
the control characters `0x0E`/`0x10` (Irssi `Ctrl+N`/`Ctrl+P`) and the Tmux/Screen forms become
`Ctrl+B`, `Ctrl+A` followed by `N`/`P`.

---

## 6. Session overflow / context menu

The menu is registered on the `TerminalView` in `q(TermSession)` (`registerForContextMenu(view)`) and
opened by the 500 ms long-press (5.1). `onCreateContextMenu` `:2108-2375` and
`onContextItemSelected` `:1786-2105` define it completely; every label below is the literal English
string.

Header title: `@string/terminal` = **"Terminal"** (`0x7f1103ce`, `:2114-2117`).

| Group | Item id | Literal label | Condition | Action (handler) |
|---|---|---|---|---|
| 0x0 | 0 | **"Copy (from screen)"** (`copy_from_screen`) | always | `o()` `:1675` -> `EmulatorView.toggleSelectingText(new TerminalEmulatorActivity$f(...))` = on-screen text selection mode (item 7) |
| 0x0 | 1 | **"Copy (whole session)"** (`copy_whole_session`) | always | `p(false)` `:2455` -> "Make a selection" dialog (item 7) |
| 0x0 | 2 | **"Paste"** (`paste`) | always | Reads `android.text.ClipboardManager.getText()`; if non-null writes it with `TermSession.write(String)` `:2046-2075` |
| 0x0 | 3 | **"Snippets"** (`snippets`) - a **submenu** | only when `kj0.a().x()` is true (Pro/sharing feature flag) | submenu container; selecting it does nothing (`pswitch_0`) |
| 0x0 | 6 | **"Create snippet"** (`create_snippet`) | inside the Snippets submenu | `p(true)` -> the create-snippet dialog (item 7) |
| 0x0 | 7 | `[` + snippet name + `] ` + snippet content (one item per stored snippet, name falls back to `@string/snippet` = **"Snippet"** when null) | inside the Snippets submenu | Takes the item title, cuts everything after the first `]` (offset+2) and writes that text to the session `:1865-1913` |
| 0x0 | 4 | **"Save transcript"** (`save_transcript`) | always | `ACTION_CREATE_DOCUMENT` + category `OPENABLE`, type `application/text`, extra `android.intent.extra.TITLE` = `<provider.d()>_yyyyMMddHHmmss.txt`, `startActivityForResult(..., 0x3620)` `:1972-2044` |
| 0x0 | 5 | **"Share transcript"** (`share_transcript`) | always | `com.sonelli.bl0.a(ctx, provider)` -> share `Intent`; `ActivityNotFoundException` -> Toast **"No capable applications found"**; null intent -> Toast **"An error has occurred"** `:1922-1969` |
| 0x0 | 8 | **"Keep screen on"** (`keep_screen_on`) | only while `Z == false` | `wk0` dialog titled `@string/warning` = **"Warning"** with text `@string/screen_on_warning` = **"The screen will now be kept on until this session is closed or sent to the background. This can have a significant impact on battery life."**, then `Window.addFlags(0x80)` (`FLAG_KEEP_SCREEN_ON`) and `Z = true` `:1820-1862` |
| 0x0 | 9 | **"Clear"** (`clear`) | always | `TermSession.reset()` `:1808-1818` |

Additional facts:

* When the Pro submenu is not available (`kj0.a().y()` true) the submenu title is suffixed with
  `@string/pro_users_only` = **"Pro users only"** and the submenu is disabled.
* `p(Z)` `:2455-2612` is shared by "Copy (whole session)" (`Z == false`) and "Create snippet"
  (`Z == true`); see item 7.
* The `Keep screen on` flag is cleared again in `onPause()` (`clearFlags(0x80)`), which matches the
  wording of the warning text.

---

## 7. Copy and paste, URL handling

### 7.1 Two copy paths

**(a) "Copy (from screen)"** (`onContextItemSelected` id 0 -> `o()` `:1675`) activates the emulator's
on-canvas selection mode: `EmulatorView.toggleSelectingText(SelectingTextListener)`
(`smali/jackpal/androidterm/emulatorview/EmulatorView.smali:4379`), with
`TerminalEmulatorActivity$f` as the listener:

* `onSelectionStart()` (`TerminalEmulatorActivity$f.smali:119-194`): if `terminal:margin_selection`
  is > 0 it is converted with `TypedValue.applyDimension(1 /*COMPLEX_UNIT_DIP*/, value, metrics)`
  and written to the `TerminalView`'s `leftMargin`/`rightMargin` (the previous left margin is saved
  in field `a`); the context menu is unregistered for the view
  (`unregisterForContextMenu`); `u()` adds the "start selection" instruction bar.
* `onStartPointSelected()` -> `t()` `:2832`: removes the start bar and adds the "end selection" bar
  (`s()` `:2819` removes the end bar again).
* `onSelectionFinish()`: restores the saved margins, re-registers the context menu, shows the
  hard-coded Toast **"Copied to Clipboard"** (`:103-109` - this string is not a resource) and calls
  `s()`. The copy itself is performed by the emulator, which has already put the selected text on
  the clipboard.

The two instruction bars are `res/layout/copy_instructions_start_selection.xml` and
`res/layout/copy_instructions_end_selection.xml`: a 40dp bar with a bold, centred `TextView` bound
to `@string/copy_instructions_start_selection` = **"Drag the cursor to the start of your selection"**
and `@string/copy_instructions_end_selection` = **"Now drag the cursor to the end of your selection"**
(colours from `copy_instructions_text`, `copy_instructions_start_selection_background`,
`copy_instructions_end_selection_background`).

**(b) "Copy (whole session)"** (`id 1` -> `p(false)` `:2455-2612`) opens an `AlertDialog` (`vk0`)
whose:

* title is `@string/make_a_selection` = **"Make a selection"** (`0x7f1102c0`),
* body is a `TextView` (not an `EditText`) holding `TermSession.getTranscriptText().trim()`
  (`:2553-2561`), with `setTextSize(2 /*COMPLEX_UNIT_SP*/, terminal:font_size or 8)`
  (`:2503-2524`), `LayoutParams(MATCH_PARENT, MATCH_PARENT)`, `setTextIsSelectable(true)`,
  `setCursorVisible(true)`, `setSelectAllOnFocus(true)` (`:2535-2544`),
* positive button `@string/copy` = **"Copy"**, negative button `@string/cancel` = **"Cancel"**.

The positive listener `TerminalEmulatorActivity$e` (`TerminalEmulatorActivity$e.smali:205-249`) copies
`ClipData.newPlainText("JuiceSSH", text.subSequence(getSelectionStart(), getSelectionEnd()))` to the
`ClipboardManager`; `RuntimeException` is swallowed with `printStackTrace()`. Because the view has
`setSelectAllOnFocus(true)` and is focused after `show()`, the default selection is the whole
transcript - which is what makes the menu entry "Copy (whole session)".

**(c) "Create snippet"** (`id 6` -> `p(true)`) reuses the same dialog method with an `EditText`
(`:2496-2498`), title `@string/create_snippet` = **"Create snippet"** (`0x7f1100bb`), positive button
`@string/save` = **"Save"** (`0x7f11037c`). Its listener (`$e`, `:50-204`) takes the current selection
and, when a selection exists, toasts `@string/saving_snippet_from_selected_text` =
**"Saving snippet from selected text"** (`0x7f110381`); otherwise it uses the whole text. It then
inserts a `Snippet` named `"Session Snippet - " + new Date().getTime()` with that content through the
Snippet DAO (`com.sonelli.juicessh.db.DB.d(Snippet.class, ctx)`); a `SQLException` logs
*"Failed to create new snippet"* and toasts `@string/failed_to_save_snippet` =
**"Failed to save snippet"** (`0x7f11010a`).

### 7.2 Paste

`onContextItemSelected` id 2 (`:2046-2075`) obtains `android.text.ClipboardManager.getText()` and, if
non-null, calls `TermSession.write(String)` with it. There is **no** bracketed paste, no paste
confirmation and no newline translation on this path - the clipboard string is written to the session
verbatim as bytes (`TermSession.write(String)` -> `write(byte[])`).
`INFERRED:` byte-level detail of `TermSession.write(String)` (whether `\n` is converted to `\r`) was
taken from the upstream ATE source rather than re-read in this decode.

### 7.3 URL / phone / e-mail detection

`com.sonelli.cl0` (`URLScan.java`, `smali/com/sonelli/cl0.smali`) is driven from
`TerminalGestureListener.onSingleTapUp`:

* `cl0.a(Context, float x, float y, float charWidth)` builds the character grid from a 48dp box.
* The tapped word is taken with `EmulatorView.getWordAt(x, y, 0x823)` (`GET_WORD_AND_LINE`).
* `cl0.b(String)` classifies the word; the enum `cl0$b` values are `NOTAURL`, `BROWSER`,
  `ABSOLUTEPATH`, `PHONE`, `EMAIL`, `TWITTER`, `SSH`, `SFTP`, `FTP`, `MARKETPLACE`. A word is only a
  `BROWSER` URL if it matches `android.util.Patterns.WEB_URL` and already carries an `http://` or
  `https://` prefix, otherwise it is `NOTAURL`.
* `cl0.c(Context, String)` builds a chooser with `FLAG_ACTIVITY_NEW_TASK` plus the flags
  `0x40080000`, and titles it with the kind of target: `@string/open_address` = **"Open %s"**
  (`0x7f11031f`), `@string/dial_number` = **"Dial %s"** (`0x7f1100cb`),
  `@string/email_person` = **"Email %s"** (`0x7f1100e2`). Scheme-less web addresses are prefixed with
  `http://` before the intent is built. The string `@string/there_are_no_browsers_available` =
  **"There are no browsers available"** (`0x7f1103d9`) exists for the no-handler case.
  `INFERRED:` which exact branch emits that toast.

When nothing matched, the gesture listener schedules the same "restore the popup keyboard" action
(`activity.v()`) that the IME-shown callback uses (item 4).

---

## 8. Terminal emulator configuration

The emulator is the vendored Android Terminal Emulator package
`jackpal.androidterm.emulatorview` (`TermSession`, `TerminalEmulator`, `TranscriptScreen`,
`EmulatorView`), wrapped by `com.sonelli.juicessh.views.TerminalView`.

| Setting | Key | Values / default | Literal labels | Applied where |
|---|---|---|---|---|
| Emulator type | `terminal:type` | `linux` (default), `xterm`, `xterm-color`, `xterm-256color`, `vt100` (`arrays.xml:87-100`) | title `@string/emulator_type` = **"Emulator type"** | F-key tables (3.4) and `TerminalView.setTermType(provider.f())` -> `TermSession.setTermType` (`q()`, `:2615+`); transports read the key themselves for local/mosh (`smali/com/sonelli/ei0.smali:329`) |
| UTF-8 | `terminal:utf8` | `true` (default) / `false` | title `@string/utf8_support` = **"UTF-8 support"** | transport layer only (`smali/com/sonelli/ei0.smali:236`); the activity never reads it |
| Bell | `terminal:bell_mode` | `0` Disabled (default), `1` Vibrate Device, `2` Show Notification (`arrays.xml:31-40`) | title `@string/terminal_bell` = **"Terminal Bell"** | `com.sonelli.zi0.onBellRecieved()` `:180-258` (item 12) |
| Font size | `terminal:font_size` | `8` (default), 1..30 | title `@string/font_size` = **"Font size"**, message `@string/you_can_adjust_the_font` = **"You can also adjust the font during an SSH session by using the volume buttons on your device"** | `x()` `:3104-3125` -> `TerminalView.setTextSize(COMPLEX_UNIT_SP, U)`; volume keys in `dispatchKeyEvent` `:271` (keycode 24 = +1, 25 = -1 while `U > 1`), persisted with `Config.h("terminal:font_size", …)` |
| Margin | `terminal:margin` | `0` (default), 0..128 | title `@string/terminal_margin` = **"Terminal Margin"**, summary `@string/useful_for_those_with_screen_protectors` = **"Useful if you have a screen protector"**, label `@string/pixels` = **"Pixels"**, message the "Specify a terminal margin (in pixels) …" text | `m()` `:1435-1479`: `TypedValue.applyDimension(COMPLEX_UNIT_PX = 0, value, metrics)` -> `leftMargin`/`rightMargin` of the `TerminalView` (raw pixels) |
| Selection margin | `terminal:margin_selection` | `0` (default) | (not exposed in the terminal settings screen) | `TerminalEmulatorActivity$f.onSelectionStart()` in `COMPLEX_UNIT_DIP` (item 7) |
| Scrollback | - | fixed 10000 rows | - | `TermSession.smali:22`, `:528` (item 11) |
| ALT sends ESC | `terminal:alt_behaviour` (arrays only) | `0` Default / `1` ALT sends ESC (`arrays.xml:23-30`) | `@string/alt_mode_default` = **"Default"**, `@string/alt_sends_esc` = **"ALT sends ESC"** | **dead setting** - no `res/xml` preference references the arrays and no smali reads the key; `setAltSendsEsc(false)` is hard-coded in `q()` and `TermKeyListener.keyDown` recomputes `mAltSendsEsc` per event (`getDeviceId() > 0` -> `mAltSendsEsc = (metaState & 0x20) == 0`, else `false`) |
| Autocomplete | `terminal:autocomplete` | `0` (default) | - | **dead setting** - `setAutocomplete(false)` hard-coded in `q()`; no smali reads the key |
| Mouse tracking | - | always on | - | `setMouseTracking(true)` in `q()` `:2615+` |
| Cooked IME | - | always on | - | `TerminalView` constructor -> `setUseCookedIME(true)` |
| Backspace | per-connection | mode 1 -> `"\u0008"` (`^H`), mode 0 (default) -> `"\u007f"` (`^?`) | - | `q()` `:2615+` |
| Force dark | - | disabled | - | `x()` `:3044-3061`: on SDK >= 29 `setForceDarkAllowed(false)` on the root layout and the terminal view |

Extra behaviour that belongs to this item:

* Terminal resizing: `TerminalView.setColumns(int)` and `setColors`/`setTextSize` notify the
  `OnResizeListener`; the activity's listener is `TerminalEmulatorActivity$i`.
* Cursor keys in application mode are switched by the escape sequence handler through
  `TermKeyListener.setCursorKeysApplicationMode(boolean)` (`TermKeyListener.smali:2752`).

---

## 9. Colour schemes

### 9.1 Data structure and index semantics

`com.sonelli.ni0` (`Colors.java`) holds **nine** `static int[]` fields, each allocated as
`const/16 v0, 0x104` = **260** entries in `<clinit>` (`smali/com/sonelli/ni0.smali:27`), with the
array literals at lines 97 (`array_0`), 361 (`array_1`), 625 (`array_2`), 889 (`array_3`),
1153 (`array_4`), 1417 (`array_5`), 1681 (`array_6`), 1945 (`array_7`) and 2209 (`array_8`).
`ni0.a(int themeIndex)` (`:2474`) is a `packed-switch` over 0..8 that returns the array belonging to
that theme; its default branch returns a **new `int[0x101]` (257)** array, which is a latent
out-of-range bug.

Index semantics are fixed by the emulator, `smali/jackpal/androidterm/emulatorview/TextStyle.smali`:

| Constant | Value | Meaning |
|---|---|---|
| `ciForeground` | `0x100` = **256** | default foreground |
| `ciBackground` | `0x101` = **257** | default background |
| `ciCursorForeground` | `0x102` = **258** | cursor foreground |
| `ciCursorBackground` | `0x103` = **259** | cursor background |
| `ciColorLength` | `0x104` = **260** | total array length |

**Confirmed:** indices 0..255 are the ANSI/256-colour palette, index **256 is the foreground** and
index **257 is the background** - exactly as stated in the request. In addition, slots **258** and
**259** carry a cursor foreground/background pair.

How the array is consumed: `com.sonelli.juicessh.views.TerminalView.setColors(int[])` ->
`EmulatorView.setColors` (`EmulatorView.smali:4246`) simply stores it; `EmulatorView.updateText()`
(`:2015`) requires `array-length == 0x104` and builds `new ColorScheme(colors[0x100], colors[0x101])`
with the two-argument constructor, i.e. the cursor colours are taken from `ColorScheme` defaults
rather than from 258/259. The only observed writes to 258/259 are in
`EmulatorView.toggleSelectingText()` (`:4379`), which sets `colors[0x103] = colors[1]`.
So in 3.2.2 only slots 256/257 are functionally observable.

### 9.2 Where a scheme is applied

`TerminalEmulatorActivity.x()` `:3025-3207`:

1. theme index = `Integer.parseInt(Config "terminal:theme")`, or **0** when the stored string is
   missing/empty (`:3063-3102`) - note the shipped default is `2`;
2. `int[] c = ni0.a(themeIndex)`; `TerminalView.setColors(c)` (`:3133-3140`);
3. `c[0x100]`/`c[0x101]` are handed to `lh0.g(int, int)` so the extra-keys row is themed with the
   scheme's foreground/background;
4. `c[0x101]` is set as the root `RelativeLayout`'s background colour, the window status-bar colour
   and (API >= 21) the navigation-bar colour;
5. on API >= 29 force-dark is disabled on both the root layout and the terminal view.

### 9.3 Theme index -> array mapping

| Index | `terminal_theme_names` label | Array | Field | `ni0.a` case |
|---|---|---|---|---|
| 0 | Dark | `array_3` (`ni0.smali:889`) | `i` | pswitch_2 |
| 1 | Light | `array_4` (`ni0.smali:1153`) | `a` | pswitch_1 |
| 2 | Solarized Dark | `array_6` (`ni0.smali:1681`) | `g` | pswitch_5 |
| 3 | Solarized Light | `array_5` (`ni0.smali:1417`) | `f` | pswitch_4 |
| 4 | "80's Hacker" | `array_2` (`ni0.smali:625`) | `b` | pswitch_3 |
| 5 | Monokai | `array_7` (`ni0.smali:1945`) | `e` | pswitch_6 |
| 6 | Tiger Orange | `array_1` (`ni0.smali:361`) | `h` | pswitch_7 |
| 7 | Tiger Black | `array_0` (`ni0.smali:97`) | `c` | pswitch_8 |
| 8 | Bifrost | `array_8` (`ni0.smali:2209`) | `d` | pswitch_0 |

### 9.4 Indices 16..255 (identical in all nine schemes)

Indices **16..255 are byte-for-byte identical in all nine arrays**: they are the standard xterm
256-colour palette, which none of the schemes overrides.

* 16..231: the 6x6x6 colour cube. Levels per channel are `0x00, 0x5F, 0x87, 0xAF, 0xD7, 0xFF`
  (0, 95, 135, 175, 215, 255), index = `16 + 36*r + 6*g + b`, always fully opaque (`alpha = 0xFF`).
* 232..255: the greyscale ramp `0x08 + 10*i` for `i = 0..23`, i.e. `#FF080808`, `#FF121212`, ...,
  `#FFEEEEEE`.

A full dump of all 260 values x 9 schemes is kept next to this document's research artefacts at
`.research/colors_hex.json` and `.research/palette_16_255.txt`.

### 9.5 Per-scheme values for 0..15 and 256..259

#### 0 - Dark

Source: `array_3 (smali/com/sonelli/ni0.smali:889)`, reached from `ni0.a(int)` pswitch `pswitch_2`.

| ANSI | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| normal (0-7) | #FF000000 | #FFCD0000 | #FF00CD00 | #FFCDCD00 | #FF0000EE | #FFCD00CD | #FF00CDCD | #FFE5E5E5 |
| bright (8-15) | #FF7F7F7F | #FFFF0000 | #FF00FF00 | #FFFFFF00 | #FF5C5CFF | #FFFF00FF | #FF00FFFF | #FFFFFFFF |

| slot | index | value | meaning (TextStyle) |
|---|---|---|---|
| foreground | 256 (0x100) | #FFCCCCCC | `ciForeground` |
| background | 257 (0x101) | #FF000000 | `ciBackground` |
| cursor foreground | 258 (0x102) | #FFCCCCCC | `ciCursorForeground` |
| cursor background | 259 (0x103) | #55808080 | `ciCursorBackground` |

#### 1 - Light

Source: `array_4 (smali/com/sonelli/ni0.smali:1153)`, reached from `ni0.a(int)` pswitch `pswitch_1`.

| ANSI | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| normal (0-7) | #FF000000 | #FFDC0000 | #FF00CF00 | #FFC5CA00 | #FF1E00CE | #FFDE00CB | #FF00CCCA | #FFC7C7C7 |
| bright (8-15) | #FF686868 | #FFFF575D | #FF00FF59 | #FFFDFF4B | #FF6F5DFF | #FFFF48FF | #FF00FFFF | #FFFFFFFF |

| slot | index | value | meaning (TextStyle) |
|---|---|---|---|
| foreground | 256 (0x100) | #FF000000 | `ciForeground` |
| background | 257 (0x101) | #FFFFFFFF | `ciBackground` |
| cursor foreground | 258 (0x102) | #FF000000 | `ciCursorForeground` |
| cursor background | 259 (0x103) | #55808080 | `ciCursorBackground` |

#### 2 - Solarized Dark

Source: `array_6 (smali/com/sonelli/ni0.smali:1681)`, reached from `ni0.a(int)` pswitch `pswitch_5`.

| ANSI | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| normal (0-7) | #FF073642 | #FFD30102 | #FF859900 | #FFB58900 | #FF268BD2 | #FFD33682 | #FF2AA198 | #FFEEE8D5 |
| bright (8-15) | #FF002B36 | #FFCB4B16 | #FF586E75 | #FF657B83 | #FF839496 | #FF6C71C4 | #FF93A1A1 | #FFFDF6E3 |

| slot | index | value | meaning (TextStyle) |
|---|---|---|---|
| foreground | 256 (0x100) | #FFEEE8D5 | `ciForeground` |
| background | 257 (0x101) | #FF073642 | `ciBackground` |
| cursor foreground | 258 (0x102) | #FFEEE8D5 | `ciCursorForeground` |
| cursor background | 259 (0x103) | #33FFFFFF | `ciCursorBackground` |

#### 3 - Solarized Light

Source: `array_5 (smali/com/sonelli/ni0.smali:1417)`, reached from `ni0.a(int)` pswitch `pswitch_4`.

| ANSI | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| normal (0-7) | #FF073642 | #FFD30102 | #FF859900 | #FFB58900 | #FF268BD2 | #FFD33682 | #FF2AA198 | #FFEEE8D5 |
| bright (8-15) | #FF002B36 | #FFCB4B16 | #FF586E75 | #FF657B83 | #FF839496 | #FF6C71C4 | #FF93A1A1 | #FFFDF6E3 |

| slot | index | value | meaning (TextStyle) |
|---|---|---|---|
| foreground | 256 (0x100) | #FF002B36 | `ciForeground` |
| background | 257 (0x101) | #FFEEE8D5 | `ciBackground` |
| cursor foreground | 258 (0x102) | #FF002B36 | `ciCursorForeground` |
| cursor background | 259 (0x103) | #55808080 | `ciCursorBackground` |

#### 4 - 80's Hacker

Source: `array_2 (smali/com/sonelli/ni0.smali:625)`, reached from `ni0.a(int)` pswitch `pswitch_3`.

| ANSI | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| normal (0-7) | #FF000000 | #FFCD0000 | #FF00CD00 | #FFCDCD00 | #FF0000EE | #FFCD00CD | #FF00CDCD | #FFE5E5E5 |
| bright (8-15) | #FF7F7F7F | #FFFF0000 | #FF00FF00 | #FFFFFF00 | #FF5C5CFF | #FFFF00FF | #FF00FFFF | #FFFFFFFF |

| slot | index | value | meaning (TextStyle) |
|---|---|---|---|
| foreground | 256 (0x100) | #FF33FF66 | `ciForeground` |
| background | 257 (0x101) | #FF000000 | `ciBackground` |
| cursor foreground | 258 (0x102) | #FF33FF66 | `ciCursorForeground` |
| cursor background | 259 (0x103) | #55808080 | `ciCursorBackground` |

#### 5 - Monokai

Source: `array_7 (smali/com/sonelli/ni0.smali:1945)`, reached from `ni0.a(int)` pswitch `pswitch_6`.

| ANSI | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| normal (0-7) | #FF101010 | #FF960050 | #FF66AA11 | #FFC47F2C | #FF30309B | #FF7E40A5 | #FF89B6E2 | #FF9999AA |
| bright (8-15) | #FF75715E | #FFFF0090 | #FF80FF00 | #FFFFBA68 | #FF5F5FEE | #FFBB88DD | #FF4EB4FA | #FFFFFFFF |

| slot | index | value | meaning (TextStyle) |
|---|---|---|---|
| foreground | 256 (0x100) | #FFFFFFFF | `ciForeground` |
| background | 257 (0x101) | #FF272822 | `ciBackground` |
| cursor foreground | 258 (0x102) | #FF7E40A5 | `ciCursorForeground` |
| cursor background | 259 (0x103) | #33FFFFFF | `ciCursorBackground` |

#### 6 - Tiger Orange

Source: `array_1 (smali/com/sonelli/ni0.smali:361)`, reached from `ni0.a(int)` pswitch `pswitch_7`.

| ANSI | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| normal (0-7) | #FF000000 | #FF2B9F1E | #FF9F1E2B | #FF9F921E | #FF1E2B9F | #FF921E9F | #FF1E9F92 | #FFD9D9D9 |
| bright (8-15) | #FF1F1F1F | #FFEB949D | #FF9DEB94 | #FFEBE294 | #FF949DEB | #FFE294EB | #FF94EBE2 | #FFFFFFFF |

| slot | index | value | meaning (TextStyle) |
|---|---|---|---|
| foreground | 256 (0x100) | #FF000000 | `ciForeground` |
| background | 257 (0x101) | #FFD44E00 | `ciBackground` |
| cursor foreground | 258 (0x102) | #FF000000 | `ciCursorForeground` |
| cursor background | 259 (0x103) | #55808080 | `ciCursorBackground` |

#### 7 - Tiger Black

Source: `array_0 (smali/com/sonelli/ni0.smali:97)`, reached from `ni0.a(int)` pswitch `pswitch_8`.

| ANSI | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| normal (0-7) | #FF000000 | #FF9F1E2B | #FF2B9F1E | #FF9F921E | #FF1E2B9F | #FF921E9F | #FF1E9F92 | #FFD9D9D9 |
| bright (8-15) | #FF1F1F1F | #FFEB949D | #FF9DEB94 | #FFEBE294 | #FF949DEB | #FFE294EB | #FF94EBE2 | #FFFFFFFF |

| slot | index | value | meaning (TextStyle) |
|---|---|---|---|
| foreground | 256 (0x100) | #FFEF2D0B | `ciForeground` |
| background | 257 (0x101) | #FF000000 | `ciBackground` |
| cursor foreground | 258 (0x102) | #FFEF2D0B | `ciCursorForeground` |
| cursor background | 259 (0x103) | #55808080 | `ciCursorBackground` |

#### 8 - Bifrost

Source: `array_8 (smali/com/sonelli/ni0.smali:2209)`, reached from `ni0.a(int)` pswitch `pswitch_0`.

| ANSI | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| normal (0-7) | #FF404040 | #FFF03669 | #FFB8E346 | #FFFFA402 | #FF02A2FF | #FF875C8D | #FF3DA698 | #FFD2D2D2 |
| bright (8-15) | #FF606060 | #FFC75B79 | #FFC8E37E | #FFFFBE4A | #FF71CBFF | #FFE62E94 | #FF9CF0ED | #FFFFFFFF |

| slot | index | value | meaning (TextStyle) |
|---|---|---|---|
| foreground | 256 (0x100) | #FFFFFFFF | `ciForeground` |
| background | 257 (0x101) | #FF000000 | `ciBackground` |
| cursor foreground | 258 (0x102) | #FFEF2D0B | `ciCursorForeground` |
| cursor background | 259 (0x103) | #55808080 | `ciCursorBackground` |

---

## 10. Fonts

Eight monospaced fonts, all Nerd Font "Complete" builds shipped in `assets/fonts/`
(`com.sonelli.aj0` = `TerminalFont.java`, enum `aj0$a`; preference array
`res/values/arrays.xml:13-22`):

| Preference index | Display name (`font_names`) | Asset file | Enum constant |
|---|---|---|---|
| 0 | Cascadia Code Mono | `fonts/Caskaydia.Cove.Regular.Nerd.Font.Complete.Mono.otf` | `aj0$a.Q` |
| 1 | Sauce Code Pro | `fonts/Sauce.Code.Pro.Nerd.Font.Complete.ttf` | `aj0$a.R` |
| 2 | Roboto Mono | `fonts/Roboto.Mono.Nerd.Font.Complete.Mono.ttf` | `aj0$a.T` |
| 3 | JetBrains Mono | `fonts/JetBrains.Mono.Regular.Nerd.Font.Complete.Mono.ttf` | `aj0$a.U` |
| 4 | Fira Code | `fonts/Fira.Code.Regular.Nerd.Font.Complete.ttf` | `aj0$a.V` |
| 5 | Open Dyslexic | `fonts/OpenDyslexic.Regular.Nerd.Font.Complete.Mono.otf` | `aj0$a.W` |
| 6 | Inconsolata | `fonts/Inconsolata.Nerd.Font.Complete.Mono.otf` | `aj0$a.S` |
| 7 | Droid Sans Mono | `fonts/Droid.Sans.Mono.Nerd.Font.Complete.otf` | `aj0$a.X` |

* The preference is a `TerminalFontDBPreference` bound to the key `terminal:font` whose
  `entries` and `entryValues` both reference the `font_names` array (`0x7f030002`); the class itself
  maps the chosen display name to the matching asset path. Preference title
  `@string/font` = **"Font"** (`0x7f110111`).
* `aj0.b` is the ordered enum list used by the preference and is ordered `Q, R, T, U, V, W, S, X` -
  the same order as `font_names`, i.e. the display order in the settings list.
* **Default: `aj0.a = aj0$a.Q` = "Cascadia Code Mono"**, reached because the shipped value of
  `terminal:font` is the empty string (`Config.smali:237-240`) and `aj0.a(String)` falls back to the
  default when a name does not resolve, logging `"Could not load font: "` via `aj0.c(Context)`.
* `TerminalView.getFont()` (`smali/com/sonelli/juicessh/views/TerminalView.smali:172`) loads the
  typeface with `Typeface.createFromAsset(getResources().getAssets(), aj0.c(context))`.
* `assets/fonts/` contains a ninth file, `fontawesome-webfont.ttf` (an icon font for the app UI).
  `INFERRED:` it is not selectable for the terminal because it is absent from `font_names` and from
  the `aj0$a` enum.
* `INFERRED:` the exact upstream release/version of each bundled Nerd Font cannot be established from
  the decode; only the filenames above are verifiable.

---

## 11. Scrollback / transcript

* `TermSession.TRANSCRIPT_ROWS = 0x2710 = 10000` (`smali/jackpal/androidterm/emulatorview/TermSession.smali:22`)
  and `initializeEmulator(columns, rows)` constructs
  `new TranscriptScreen(columns, 0x2710, rows, colorScheme)` (`:520-532`). The transcript therefore
  always holds **10000 rows in total, including the on-screen rows** (80x25 = 2000 characters per
  screen page); the scrollback above the screen is `10000 - rows` lines (9975 for the default 25
  rows). There is no user-facing scrollback size setting.
* The session's input queue is a `ByteQueue` of `0x1000` = 4096 bytes (`TermSession.smali:134-168`).
* The viewport position is `EmulatorView.mTopRow`; `EmulatorView.page(int)` (`:4052-4095`) clamps it
  to `[-TranscriptScreen.getActiveTranscriptRows(), 0]`, so `0` is the live screen and negative values
  move into the scrollback. Vertical drag/fling moves it (item 5).
* `TranscriptScreen` API used by JuiceSSH: `getTranscriptText()` /
  `getTranscriptText(GrowableIntArray)`, `getSelectedText(...)`, `getActiveRows()`,
  `getActiveTranscriptRows()`, `getScriptLine(int)`, `getScriptLineWrap(int)`, `resize(int,int,int)`,
  `fastResize(int,int,int[])`, `blockCopy`, `blockSet`, `finish()`
  (`smali/jackpal/androidterm/emulatorview/TranscriptScreen.smali`).
* Transcript consumers, all reading `getTranscriptText().trim()`:
  * "Copy (whole session)" dialog body (`TerminalEmulatorActivity.smali:2553-2561`),
  * "Create snippet" (`TerminalEmulatorActivity$e`),
  * "Save transcript" (`onActivityResult` `:1730-1751`),
  * "Share transcript" (`bl0.a(Context, TerminalSessionProvider)`).
* "Clear" in the menu calls `TermSession.reset()` (`:1808-1818`), which discards the transcript and
  resets the emulator state.
* Resizing goes `TerminalView.setColumns(int)` -> `TermSession.updateSize(...)`; the activity's
  `OnResizeListener` (`TerminalEmulatorActivity$i`) re-applies colours/margins/font size.

---

## 12. Notifications and background behaviour

### 12.1 Foreground service

`AndroidManifest.xml` declares the permissions `android.permission.FOREGROUND_SERVICE` and
`android.permission.WAKE_LOCK`, and the service
`com.sonelli.juicessh.connections.ConnectionManagerService` (`android:enabled="true"`,
`android:exported="false"`).

* `onCreate()` (`smali/com/sonelli/juicessh/connections/ConnectionManagerService.smali:849-903`):
  `stopForeground(true)`; creates a `NotificationChannel` with id **`"juicessh"`**, name
  `@string/app_name` = **"JuiceSSH"** and importance `0` (`IMPORTANCE_NONE`); stores the
  `NotificationManager`.
* Locks (`:595-637`): `PowerManager.newWakeLock(1 /*PARTIAL_WAKE_LOCK*/, "JuiceSSH: background sessions")`
  and `WifiManager.createWifiLock(1 /*WIFI_MODE_FULL*/, "JuiceSSH background sessions")`. The poller
  thread (`ConnectionManagerService$b`) acquires them while at least one chain exists and releases
  them when none does, logging `"Releasing wakelock for ConnectionManagerService"` /
  `"Releasing wifilock for ConnectionManagerService"`.
* `startForeground(notificationId, notification)` is called with the chain's notification builder
  (`ai0.o()` for the in-progress/failed state, `ai0.q()` for the healthy state); the log lines are
  `"Using transport chain <id> to prevent ConnectionManager from being killed"` and
  `"Couldn't put ConnectionManagerService into foreground mode without a valid notification"`.
  The notification id is `ai0.n()` -> the last provider's `l()` (the connection id), or `-1`
  (`smali/com/sonelli/ai0.smali:384-436`, `:489-514`).

### 12.2 Session notification content

The builders are implemented by the transports (`ai0` delegates to the last provider's `m()`/`n()`;
implementations found in `smali/com/sonelli/ei0.smali`, `fi0`, `gi0`, `hi0`, `ii0`). Literal strings
used there:

| Purpose | Literal text | Id |
|---|---|---|
| Title while the chain is broken | `@string/app_name` + `": "` + `@string/connection_failed` = **"JuiceSSH: Connection Failed"** | `0x7f110036`, `0x7f11009e` |
| Title while healthy | `@string/app_name` + `": "` + `@string/connected` = **"JuiceSSH: Connected"** | `0x7f110036`, `0x7f110096` |
| Action on the failed notification | **"Reconnect"** | `0x7f110368` |
| Action on the healthy notification | **"Disconnect"** | `0x7f1100cd` |
| Additional action present in the same builders | **"SFTP"** | `0x7f110396` |

The notification is `setOngoing(true)` while the session is live, uses the app's notification small
icon, and its content intent is the `ssh://…/resume?session_key=<uuid>` URI (with the extras
`"do-not-cache"` and `"NOTIFICATION_TO_CANCEL"`), while the disconnect action targets
`ssh://…/disconnect`. `TerminalEmulatorActivity.j()` `:547` reads the `NOTIFICATION_TO_CANCEL` extra
and cancels the corresponding notification when it is resumed from one.
`INFERRED:` the exact binding of the "SFTP" action to the SSH transport.

### 12.3 Terminal bell

`com.sonelli.zi0` (`TerminalBellListener`, installed in `q(TermSession)`) implements
`TermSession$OnBellListener`:

* `onBellRecieved()` `:180-258` reads `terminal:bell_mode` with `Config.f(Context, String)`:
  * value `-1`/`0` -> log **"Got a terminal bell - but bell is disabled"**, nothing else;
  * value `1` -> log **"Got a terminal bell - vibrating device!"** and
    `Vibrator.vibrate(0x64)` = **100 ms**;
  * value `2` -> log **"Got a terminal bell - showing notification!"** and issues
    `ConnectionManager.b(ctx, new zi0$a(this))`.
* `zi0.e(ai0)` `:85-178` runs the notification: it `getAndSet(0)`s the bell counter and returns if it
  was `< 1`; otherwise it posts `NotificationManager.notify(connectionId, n)` where `n` is
  `chain.q()` (the session's healthy notification builder) whose content title is overwritten with
  **"JuiceSSH: Connected"** (`@string/app_name` + `": "` + `@string/connected`), plus `setNumber(0)`
  and `setDefaults(0)`.

### 12.4 Keeping the screen on and surviving backgrounding

* Menu "Keep screen on" adds `FLAG_KEEP_SCREEN_ON` (`0x80`) and sets flag `Z`; `onPause()` clears the
  flag again (`:2377`).
* `onStop()` only calls `super` (`:2446`), and the session object lives in the foreground
  `ConnectionManagerService`, so the SSH session keeps running while the activity is backgrounded or
  destroyed. Returning to it either re-attaches the existing chain
  (`TerminalEmulatorActivity.b(int, UUID)` `:99` / `ConnectionManager`) or resumes through the
  notification's `resume` intent.
* Disconnecting happens either through the notification's "Disconnect" action or through the
  back-press dialog's non-backgrounding choice (`TerminalEmulatorActivity$l.a()` ->
  `f(connectionId, sessionUuid)`).

---

## Appendix A - decode file map

| Concern | File |
|---|---|
| Session activity | `smali/com/sonelli/juicessh/activities/TerminalEmulatorActivity.smali` (3207 lines) + inner classes `$c`, `$e`, `$f`, `$i`, `$j`, `$l`, `$m`, `$n`, `$o` |
| Terminal view | `smali/com/sonelli/juicessh/views/TerminalView.smali` |
| Gestures | `smali/com/sonelli/util/TerminalGestureListener.smali` |
| Back-press dialog | `smali/com/sonelli/util/BackgroundPrompt.smali` (+ `$a`, `$b`, `$c`) |
| Colour schemes | `smali/com/sonelli/ni0.smali` (`Colors.java`) |
| Fonts | `smali/com/sonelli/aj0.smali` + `smali/com/sonelli/aj0$a.smali` (`TerminalFont.java`) |
| F-key escapes | `smali/com/sonelli/ti0.smali` + `smali/com/sonelli/ti0$a.smali`/`ti0$b.smali` (`EscapeCharacters.java`) |
| URL scanning | `smali/com/sonelli/cl0.smali` + `smali/com/sonelli/cl0$b.smali` (`URLScan.java`) |
| Extra-keys pager | `smali/com/sonelli/lh0.smali` (`HackersKeyboardPagerAdapter.java`) |
| Bell | `smali/com/sonelli/zi0.smali` (+ `$a`) |
| Transport chain | `smali/com/sonelli/ai0.smali`, `mi0.smali`, `ei0/fi0/gi0/hi0/ii0.smali` |
| Connection service | `smali/com/sonelli/juicessh/connections/ConnectionManagerService.smali` (+ `$b`, `$b$a`) |
| Settings defaults | `smali/com/sonelli/juicessh/models/Config.smali` |
| Emulator | `smali/jackpal/androidterm/emulatorview/*` (`TermSession`, `EmulatorView`, `TermKeyListener`, `TranscriptScreen`, `TextStyle`, `ColorScheme`) |
| Layouts | `res/layout/hacker_keyboard*.xml`, `autocomplete_box.xml`, `copy_instructions_*.xml`, `connecting.xml`, `error.xml`, `tutorial_terminal.xml` |
| Arrays / strings | `res/values/arrays.xml`, `res/values/strings.xml`, `res/values/public.xml` |

## Appendix B - explicitly unverified / incomplete

1. `TermKeyListener.mapControlChar(boolean, boolean, int)` individual Ctrl+key mappings - the table
   in 3.3 is `INFERRED:` from the upstream Android Terminal Emulator behaviour; only the method's
   existence, location and calling convention were verified in this decode.
2. The call site of `TerminalEmulatorActivity.j(Bundle)` (assumed `onCreate` of the base class
   `com.sonelli.util.SessionedFragmentActivity`).
3. The button -> listener mapping inside `BackgroundPrompt$a`/`$b`/`$c` (two behaviours are verified:
   background-and-finish, and disconnect-then-finish).
4. `TerminalAutoCompleteBox`'s IME "Done" send path (`TerminalEmulatorActivity$n`/`$o` bodies).
5. Composition of the share intent in `com.sonelli.bl0.a(Context, TerminalSessionProvider)`.
6. `VIBRATE` permission presence in `AndroidManifest.xml` (not checked; the code does call
   `Vibrator.vibrate` for bell mode 1).
7. `res/layout/connecting.xml` / `error.xml` were read as layouts, but the exact conditions under
   which the terminal activity itself shows them were not traced (the activity's failure path uses
   `d(int, String)` -> Toast + `finish()`, and there is no loading overlay in
   `TerminalEmulatorActivity`; `connecting.xml` carries `@string/connecting` = **"Connecting…"**,
   `@string/establishing_connection` = **"Establishing connection"**, a progress bar and a monospace
   `log_text` at `9sp` `#99ffffff`).
8. Upstream provenance/version of the eight bundled Nerd Fonts.
9. The per-item byte-level translation performed by `TermSession.write(String)` on paste.
10. Which branch emits `@string/there_are_no_browsers_available` = **"There are no browsers
    available"** in `cl0.c(Context, String)`.

Items 1 (lifecycle), 2 (multiple sessions/tabs), 3 (extra keys), 4 (soft keyboard), 5 (gestures),
6 (context menu), 7 (copy/paste/URLs), 8 (emulator configuration), 9 (colour schemes), 10 (fonts),
11 (scrollback/transcript) and 12 (notifications/background) are all covered above; item 9, item 3,
item 5 and item 10 are complete, with the specific exceptions listed in this appendix.
