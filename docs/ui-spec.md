# JuiceSSH 3.2.2 (com.sonelli.juicessh) — UI Specification for Flutter Reimplementation

Derived **exclusively** from the apktool 3.0.3 decode at `D:\dev\_apk\juicessh\`.
Every value below is traceable to a file named inline. Anything not resolvable is
marked `UNRESOLVED: <what> (<why>)`.

**Source files used**

| Purpose | Path |
|---|---|
| Layouts | `res/layout/*.xml`, `res/layout-land`, `res/layout-sw360dp`, `res/layout-sw600dp`, `res/layout-sw360dp-land`, `res/layout-sw600dp-land` |
| Menus | `res/menu/*.xml` |
| Settings tree | `res/xml/settings.xml` |
| Colours | `res/values/colors.xml`, `res/values-night/colors.xml`, `res/values-zh-rCN/colors.xml` |
| Dimensions | `res/values/dimens.xml` (+ landscape/sw600dp/etc. overrides) |
| Styles | `res/values/styles.xml`, `res/values-night/styles.xml` |
| Strings | `res/values/strings.xml`, `res/values-zh-rCN/strings.xml` |
| Arrays | `res/values/arrays.xml`, `res/values-v29/arrays.xml` |
| Manifest | `AndroidManifest.xml` |
| Fonts | `assets/fonts/` |
| Drawables | `res/drawable*/` |

### Global conventions

* `match_parent` → Flutter `double.infinity` (or `Expanded` / `SizedBox.expand` inside a flex parent).
* `wrap_content` → intrinsic sizing (`MainAxisSize.min`, unconstrained `Row`/`Column` child).
* `layout_width="0dp"` + `layout_weight="W"` → `Expanded(flex: W)` in an unbounded-direction flex.
* `layout_height="0dp"` + `layout_weight="W"` → same, on the vertical axis.
* Every `style="?android:listSeparatorTextViewStyle"` section header is rendered by JuiceSSH with
  `android:textColor="@color/text_form_heading"` **overriding** the platform style's colour.
* `@id/...` and `@+id/...` are the same resource here (apktool emitted `@id/` for ids declared in
  `res/values/ids.xml`). All ids named below exist in `res/values/ids.xml`.
* `dp` in `android:textSize` is a JuiceSSH bug (should be `sp`); it is reproduced verbatim and flagged.

---

## 1. Navigation / screen map

From `AndroidManifest.xml`. Application theme (line 32): `@style/Theme.JuiceSSH.Material`.
Application label: `@string/app_name` = **"JuiceSSH"** (zh-CN: "JuiceSSH").

`android:parentActivityName` gives the up-navigation target.

| Activity | `android:label` (resolved) | parent | theme | Intent filter / notes |
|---|---|---|---|---|
| `activities.MainActivity` | `juicessh` = "JuiceSSH" | — | app default | **LAUNCHER** (`MAIN`+`LAUNCHER`+`MULTIWINDOW_LAUNCHER`); also `com.sonelli.juicessh.exception`. `windowSoftInputMode="stateAlwaysHidden"`. Not exported. |
| `activities.AddressBookActivity` | `juicessh` = "JuiceSSH" | MainActivity | default | not exported |
| `activities.TerminalEmulatorActivity` | `juicessh` = "JuiceSSH" | — | `@style/Theme.JuiceSSH.Material.Terminal` | exported; `VIEW`/`DEFAULT`/`BROWSABLE`, schemes `ssh`, `ssh-forward`, `telnet`, `local`, `mosh`. `windowSoftInputMode="adjustResize"`, huge `configChanges`. |
| `activities.ManageConnectionActivity` | `new_connection` = "New Connection" | AddressBookActivity | default | label is static (add/edit share label) |
| `activities.ManageIdentityActivity` | `new_identity` = "New Identity" | AddressBookActivity | default | |
| `activities.ManageGroupActivity` | `new_group` = "New Group" | AddressBookActivity | default | |
| `activities.ManagePortForwardActivity` | `new_port_forward` = "New Port Forward" | AddressBookActivity | default | **exported=true** |
| `activities.ManageSnippetsActivity` | `snippets` = "Snippets" | SettingsActivity | default | |
| `activities.SettingsActivity` | `settings` = "Settings" | MainActivity | default | |
| `activities.SoftwareLicensesActivity` | `components_and_licenses` = "Components and licenses" | SettingsActivity | default | |
| `activities.ViewLicenseActivity` | `components_and_licenses` = "Components and licenses" | SoftwareLicensesActivity | default | |
| `activities.LogViewerActivity` | `log_viewer` = "Log Viewer" | SettingsActivity | default | **exported=true** |
| `activities.LockoutActivity` | `juicessh` = "JuiceSSH" | — | `@style/Theme.JuiceSSH.Material.Terminal` | |
| `activities.ChangelogActivity` | `juicessh` = "JuiceSSH" | MainActivity | default | exported |
| `activities.AuthenticationMigrationActivity` | `juicessh` = "JuiceSSH" | MainActivity | default | exported |
| `activities.ReauthenticateActivity` | `signin_with_google` = "Sign In with Google" | MainActivity | default | exported |
| `activities.ThankYouForPurchasingActivity` | `app_name_pro` = "JuiceSSH Pro" | — | default | exported |
| `activities.ConfigureWidgetActivity` | `configure_widget` = "Configure Widget" | — | default | exported, `singleInstance`; `APPWIDGET_CONFIGURE` + `com.sonelli.juicessh.widget.action.REFRESH` |
| `activities.ManageShareActivity` | `manage_share` = "Manage Share" | AddressBookActivity | default | |

**Pro / team / cloud-sync features — listed, out of scope for a first pass**

| Activity | Label | Why pro |
|---|---|---|
| `activities.PurchaseActivity` | `unlock_pro_version` = "Unlock pro features" | purchase flow; `com.sonelli.juicessh.purchase` action |
| `activities.TeamShareActivity` | `teamshare` = "TeamShare" | TeamShare |
| `activities.ManageTeamActivity` | `new_team` = "New Team" | TeamShare |
| `activities.ManageCloudSyncActivity` | `cloudsync` = "CloudSync" | CloudSync |
| `activities.Ec2ProfilesActivity` | `ec2_sync_profiles` = "Amazon EC2 Link" | Ec2 Link |
| `activities.ManageEc2ProfileActivity` | `new_ec2_profile` = "New EC2 Profile" | Ec2 Link |
| `activities.PluginsActivity` | `Plugins` = "Plugins" | Plugins |
| `activities.BookclubActivity` | `bookclub` = "Tech Library" | Bookclub |

Also present but non-UI: `ConnectionPluginService`, `PluginService`, `SftpPluginService`,
`PushNotification` service/receiver, `ConnectionWidgetProvider` (+ `WidgetUpdateJob`,
`ConnectionWidgetService`), `CloudSync` service, `Ec2Link` service,
`ConnectionManagerService`, `PluginContentProvider` (authority `com.sonelli.juicessh.api.v1`),
plus GMS/Firebase plumbing.

---

## 2. Theme colours

### 2.1 `Theme.JuiceSSH` (base, `res/values/styles.xml` line 1975)

`parent="@style/Theme.AppCompat.DayNight"` (DayNight ⇒ follows system dark mode).

| Attribute | Reference | Resolved (light) | Resolved (night) |
|---|---|---|---|
| `android:windowBackground` | `@color/background` | `#FFFFFFFF` | `#FF000000` |
| `android:windowContentOverlay` | `@null` | none | none |
| `android:itemTextAppearance` | `@style/Theme.JuiceSSH.Material.MenuTextAppearance` | `textColor=@color/text_normal` = `#FF073642` | `@android:color/primary_text_dark` |
| `android:windowDisablePreview` | `true` | — | — |
| `actionBarStyle` | `@style/Theme.JuiceSSH.Material.Actionbar` | see below | see below |
| `actionBarWidgetTheme` | `@style/Theme.JuiceSSH.Material.Actionbar.Widget` | see below | see below |
| `actionMenuTextColor` | `@color/white` | `#FFFFFFFF` | `#FFFFFFFF` |
| `actionOverflowButtonStyle` | `@style/Theme.JuiceSSH.Material.Actionbar.Overflow` | `android:src=@drawable/ic_action_overflow` | same |
| `colorAccent` | `@color/accent_bold` | **`#FF586E75`** | `@color/primary_darker` = **`#FFD5BA31`** |
| `colorPrimary` | `@color/primary_bold` | **`#FFFFE24C`** | **`#FFD8C041`** |
| `colorPrimaryDark` | `@color/primary_darker` | **`#FFF0D235`** | **`#FFD5BA31`** |

### 2.2 `Theme.JuiceSSH.Material` (`styles.xml` line 1988)

```xml
<style name="Theme.JuiceSSH.Material" parent="@style/Theme.JuiceSSH" />
```

It declares **no** items of its own — it is a pure alias of `Theme.JuiceSSH`. All colours in
§2.1 apply verbatim. (This is a common source of confusion: `Theme.JuiceSSH.Material` is not a
Material-Components theme.)

### 2.3 `Theme.JuiceSSH.Material.Terminal` (`styles.xml` line 2029)

```xml
<style name="Theme.JuiceSSH.Material.Terminal" parent="@style/Theme.JuiceSSH.Material">
    <item name="android:windowBackground">@drawable/loading_screen</item>
    <item name="windowActionBar">false</item>
    <item name="windowNoTitle">true</item>
</style>
```

`@drawable/loading_screen` (`res/drawable/loading_screen.xml`):

```xml
<shape android:shape="rectangle">
    <gradient android:startColor="#ff292929" android:endColor="#ff090909"
              android:angle="0.0" android:type="radial" android:gradientRadius="600.0" />
</shape>
```

→ **radial gradient**, centre `#FF292929` → edge `#FF090909`, radius **600px**, `angle=0`.
So: `colorPrimary/colorPrimaryDark/colorAccent` inherited from §2.1, **no action bar**,
window background = the radial terminal gradient.

### 2.4 Action-bar sub-styles

| Style | parent | items |
|---|---|---|
| `Theme.JuiceSSH.Material.Actionbar` | `Widget.AppCompat.Light.ActionBar.Solid.Inverse` | `background=@color/primary_darker` = `#FFF0D235` (night `#FFD5BA31`); `displayOptions=showHome\|homeAsUp\|showTitle`; `homeAsUpIndicator=@drawable/ic_arrow_back_white_24dp`; `titleTextStyle=@style/Theme.JuiceSSH.Material.Actionbar.Text` |
| `Theme.JuiceSSH.Material.Actionbar.Text` | `Theme.JuiceSSH.Material.Actionbar` | `android:textColorPrimary=@color/white` `#FFFFFFFF`; `android:textColorSecondary=@color/white`; `android:textSize=24.0sp`; `android:textStyle=bold`; `android:textColor=@color/white`; `colorAccent=@color/white` |
| `Theme.JuiceSSH.Material.Actionbar.Overflow` | `Widget.AppCompat.ActionButton.Overflow` | `android:src=@drawable/ic_action_overflow` |
| `Theme.JuiceSSH.Material.Actionbar.List` | `Widget.AppCompat.ListView.DropDown` | `android:listSelector=@drawable/selectable_background_juicessh` |
| `Theme.JuiceSSH.Material.Actionbar.PopupMenu` | `Widget.AppCompat.PopupMenu` | `android:textColor=@color/text_normal`; `android:popupBackground=@color/background` |
| `Theme.JuiceSSH.Material.Actionbar.Widget` | `Theme.AppCompat.Light.DarkActionBar` | `dropDownListViewStyle=@style/…Actionbar.List`; `popupMenuStyle=@style/…Actionbar.PopupMenu` |
| `Theme.JuiceSSH.Material.MenuTextAppearance` | `Theme.JuiceSSH.Material` | `android:textColor=@color/text_normal` |
| `Theme.JuiceSSH.Material.NoActionBar.Fullscreen` | `Theme.JuiceSSH.Material` | `android:windowContentOverlay=@null`; `android:windowFullscreen=true`; `windowActionBar=false`; `windowNoTitle=true` |
| `Theme.JuiceSSH.Material.SelectableListItem` | `Theme.JuiceSSH.Material` | `android:background=@android:drawable/list_selector_background` |

**Action bar summary for Flutter:** AppBar background `#FFF0D235` (light) / `#FFD5BA31` (night),
title text white `#FFFFFFFF` **24sp bold**, back arrow `ic_arrow_back_white_24dp`,
overflow `ic_action_overflow`.

### 2.5 Resolved colour table (light, from `res/values/colors.xml`)

| Name | Raw value | Fully resolved |
|---|---|---|
| `primary_bold` | `#ffffe24c` | `#FFFFE24C` |
| `primary_darker` | `#fff0d235` | `#FFF0D235` |
| `primary_lighter` | `#ffffee96` | `#FFFFEE96` |
| `primary_bold_transparent` | `#55ffe24c` | `#55FFE24C` |
| `accent_bold` | `#ff586e75` | `#FF586E75` |
| `accent_darker` | `#ff073642` | `#FF073642` |
| `accent_lighter` | `#ffbccacf` | `#FFBCCACF` |
| `accent_lighter_transparent` | `#33bccacf` | `#33BCCACF` |
| `background` | `@color/white` | `#FFFFFFFF` |
| `white` | `@android:color/white` | `#FFFFFFFF` |
| `transparent` | `@android:color/transparent` | `#00000000` |
| `text_normal` | `@color/accent_darker` | `#FF073642` |
| `text_form` | `@color/accent_darker` | `#FF073642` |
| `text_form_heading` | `@color/accent_bold` | `#FF586E75` |
| `text_heading` | `@color/accent_bold` | `#FF586E75` |
| `text_subheading` | `@color/accent_bold` | `#FF586E75` |
| `text_item_title` | `@color/accent_darker` | `#FF073642` |
| `text_item_subtitle` | `@color/accent_bold` | `#FF586E75` |
| `icon_item` | `@color/accent_bold` | `#FF586E75` |
| `card_icon_color` | *(empty element)* | **UNRESOLVED: empty `<color name="card_icon_color" />`** — Android treats an empty colour as `#00000000` (fully transparent). List-row FontAwesome glyphs rendered with this colour are therefore invisible until the adapter sets them programmatically. |
| `card_item_background` | `@color/cardview_light_background` | `#FFFFFFFF` |
| `card_item_divider` | `@color/accent_lighter_transparent` | `#33BCCACF` |
| `card_item_icon` | `@color/text_heading` | `#FF586E75` |
| `card_item_pressed` | `@color/accent_bold` | `#FF586E75` |
| `cardview_light_background` | `#ffffffff` | `#FFFFFFFF` |
| `cardview_dark_background` | `#ff424242` | `#FF424242` |
| `button_background` | `@color/accent_bold` | `#FF586E75` |
| `button_text` | `@color/white` | `#FFFFFFFF` |
| `button_stroke` | `@color/transparent` | `#00000000` |
| `highlighted_text_material_light` | `#66009688` | `#66009688` |
| `pinlock_background` | `@android:color/black` | `#FF000000` |
| `log_viewer_background` | `#000000` | `#FF000000` |
| `log_viewer_foreground` | `#00ff00` | `#FF00FF00` |
| `table_row_highlight` | `#33bccacf` | `#33BCCACF` |
| `titlebar_background` | `#c1000000` | `#C1000000` |
| `juicessh_yellow` | `@color/primary_bold` | `#FFFFE24C` |
| `copy_instructions_background` / `…_start_selection_background` | `#f44336` | `#FFF44336` |
| `copy_instructions_end_selection_background` | `#4caf50` | `#FF4CAF50` |
| `copy_instructions_text` | `#ffffff` | `#FFFFFFFF` |
| `material_grey_50/100/300/600/800/850/900` | `#fffafafa` / `#fff5f5f5` / `#ffe0e0e0` / `#ff757575` / `#ff424242` / `#ff303030` / `#ff212121` | `#FFFAFAFA` / `#FFF5F5F5` / `#FFE0E0E0` / `#FF757575` / `#FF424242` / `#FF303030` / `#FF212121` |
| `material_deep_teal_200` / `_500` | `#ff80cbc4` / `#ff008577` | `#FF80CBC4` / `#FF008577` |
| `primary_text_default_material_light` | `#de000000` | `#DE000000` |
| `secondary_text_default_material_light` | `#8a000000` | `#8A000000` |

### 2.6 Night palette (`res/values-night/colors.xml`) — overrides only

| Name | Value |
|---|---|
| `accent_bold` | `@color/primary_darker` → `#FFD5BA31` |
| `accent_darker` | `@color/primary_darker` → `#FFD5BA31` |
| `accent_lighter` | `@color/primary_lighter` → `#FFFFE24C` |
| `accent_lighter_transparent` | `@color/primary_lighter` → `#FFFFE24C` *(note: loses its alpha in night mode)* |
| `background` | `@android:color/black` → `#FF000000` |
| `button_background` | `@color/transparent` → `#00000000` |
| `button_stroke` | `@color/accent_bold` → `#FFD5BA31` |
| `button_text` | `@color/accent_bold` → `#FFD5BA31` |
| `card_item_background` | `@color/background` → `#FF000000` |
| `card_item_divider` | `@color/transparent` → `#00000000` |
| `card_item_pressed` | `@color/text_heading` → `@android:color/primary_text_dark` |
| `primary_bold` | `#d8c041` → `#FFD8C041` |
| `primary_darker` | `#d5ba31` → `#FFD5BA31` |
| `primary_lighter` | `#ffffe24c` → `#FFFFE24C` |
| `text_form` | `@android:color/primary_text_dark` — **UNRESOLVED: framework value (`#FFFFFFFF` on the platform default dark theme)** |
| `text_form_heading` | `@android:color/secondary_text_dark` — **UNRESOLVED: framework value (`#B3FFFFFF` platform default)** |
| `text_heading` | `@android:color/primary_text_dark` — same caveat |
| `text_item_subtitle` | `@android:color/secondary_text_dark` — same caveat |
| `text_item_title` | `@android:color/primary_text_dark` — same caveat |
| `text_normal` | `@android:color/primary_text_dark` — same caveat |
| `text_subheading` | `@android:color/secondary_text_dark` — same caveat |

*(The framework names are resolved by `android.R.color` at runtime and are not defined in this
APK's `colors.xml`; the platform-default values are quoted only as context, not as
APK-derived fact.)*

### 2.7 Shared drawables that carry colour

| Drawable | Definition |
|---|---|
| `drawable/highlight.xml` | `<selector />` — **empty selector**, i.e. no visual. Used as `ListView` `divider`/`childDivider` and as row `android:background`. The 0.5dp row dividers are therefore invisible; rows rely on their own separator. |
| `drawable/card_item.xml` | `<ripple android:color="@color/card_item_pressed" />` → ripple `#FF586E75` (light) / `@android:color/primary_text_dark` (night). Used as `CardView` `android:foreground`. |
| `drawable/button.xml` | `<ripple android:color="@color/accent_lighter">` wrapping `<shape><solid @color/button_background/><corners radius="2.0dp"/><stroke width="1.0dp" color="@color/button_stroke"/></shape>` → in light mode: fill `#FF586E75`, radius **2dp**, stroke **1dp** `#00000000`, ripple `#FFBCCACF`. In night mode: fill `#00000000`, radius 2dp, stroke 1dp `#FFD5BA31`, ripple `#FFFFE24C`. |
| `drawable/button_white.xml` | `<ripple android:color="@color/accent_lighter" />` (no shape) |
| `drawable/selectable_background_juicessh.xml` | `<selector android:exitFadeDuration="@android:integer/config_mediumAnimTime">`<br>`state_focused=true,state_pressed=false → @drawable/list_focused_juicessh`<br>`state_pressed=true → @drawable/list_pressed_juicessh`<br>`default → @android:color/transparent` |
| `list_focused_juicessh` | `.9.png`, mdpi 105 B / hdpi 121 B / xhdpi 129 B / xxhdpi 139 B — **UNRESOLVED: exact pixel dimensions and nine-patch content (binary `.9.png`)**; file size reported. Depicts a subtle focused-row highlight. |
| `list_pressed_juicessh` | `.9.png`, mdpi 100 B / hdpi 107 B / xhdpi 108 B / xxhdpi 121 B — same caveat. Pressed-row highlight. |
| `drawable/keyboard.xml` | see §6.3 |
| `drawable/keyboard_highlighted.xml` | see §6.3 |
| `drawable/loading_screen.xml` | see §2.3 |
| `drawable/pin_button.xml` | `<selector>`: focused+pressed → `pin_button_pressed`; not-focused+pressed → `pin_button_pressed`; focused → `pin_button_pressed`; default → `pin_button_unpressed` |
| `drawable/pin_button_pressed.xml` | `<layer-list><item><shape android:shape="oval"><stroke width="4.0dp" color="@color/primary_bold_transparent"/></shape></item></layer-list>` → **4dp oval ring**, `#55FFE24C` |
| `drawable/pin_button_unpressed.xml` | same but `stroke color="@color/primary_bold"` → **4dp oval ring**, `#FFFFE24C` |
| `drawable/button_transparent.xml` | `<selector>`: unpressed → `<shape solid="#00ffffff" stroke 3.0px "#ffffffff" padding L10/T4/R10/B4 corners 5dp>`; pressed → same with stroke `3.0px "#33ffffff"` |
| `drawable/widget_background.9.png` | mdpi 187 B / hdpi 232 B / xhdpi 298 B — nine-patch widget background |

---

## 3. Dimens table

All from `res/values/dimens.xml` unless the "override" column says otherwise.
Only JuiceSSH-authored dimens are listed (ActionBar/AppCompat/Material/Notification dimens are
upstream and omitted).

| Name | Value | Overrides |
|---|---|---|
| `action_bar_size` | `16.0dp` | |
| `activity_horizontal_margin` | `16.0dp` | `values-sw720dp-land` → `128.0dp`; `values-w820dp` → `64.0dp` |
| `activity_padding` | `16.0dp` | |
| `activity_vertical_margin` | `16.0dp` | |
| `app_defaultsize_h` | `598.0dp` | |
| `app_defaultsize_w` | `632.0dp` | |
| `app_minimumsize_h` | `598.0dp` | |
| `app_minimumsize_w` | `632.0dp` | |
| `card_list_divider` | `16.0dp` | |
| `card_list_padding` | `16.0dp` | |
| `dialog_padding_bottom` | `0.0dp` | |
| `dialog_padding_left` | `16.0dp` | |
| `dialog_padding_right` | `16.0dp` | |
| `dialog_padding_top` | `16.0dp` | |
| `list_item_height` | `72.0dp` | |
| `list_item_icon_width` | `40.0dp` | |
| `padding_large` | `16.0dp` | |
| `padding_medium` | `8.0dp` | `values-large` → `16.0dp` |
| `padding_small` | `8.0dp` | |
| `preference_fragment_padding_bottom` | `0.0dp` | |
| `preference_fragment_padding_side` | `0.0dp` | |
| `status_bar_height` | `25.0dp` | |
| `text_button` | `16.0sp` | |
| `text_heading` | `36.0sp` | |
| `text_item_subtitle` | `12.0sp` | |
| `text_item_title` | `16.0sp` | |
| `widget_margin` | `8.0dp` | |
| `cardview_default_elevation` | `2.0dp` | |
| `cardview_default_radius` | `2.0dp` | |

---

## 4. Connections list / Address book

### 4.1 `res/layout/address_book.xml` — the pager host

```
LinearLayout  orientation=vertical  fitsSystemWindows=true  w=match_parent h=match_parent
└─ androidx.viewpager.widget.ViewPager  id=@id/viewpager  w=match_parent  h=0dp  weight=1.0
   └─ androidx.viewpager.widget.PagerTabStrip  id=@id/pagerTabStrip
        textColor=@color/text_heading → #FF586E75 (light) / @android:color/primary_text_dark (night)
        layout_gravity=top   w=wrap_content  h=wrap_content
```

Three pages: **Connections**, **Identities**, **Port Forwards** (titles come from
`PagerAdapter` code, not from a layout — `UNRESOLVED: page titles (set in Java, not in any XML)`).
Note `PagerTabStrip` is a platform widget, not `TabLayout`; it draws its own indicator line.

### 4.2 Page: Connections — `res/layout/address_list.xml`

```
RelativeLayout  orientation=vertical  w=match_parent h=match_parent
└─ RelativeLayout  id=@id/list_container  w=match_parent h=match_parent
   ├─ ExpandableListView  id=@id/expandable_list  w=match_parent h=match_parent
   │     indicatorLeft=16.0dp  indicatorRight=56.0dp
   │     childDivider=@drawable/highlight   divider=@drawable/highlight   dividerHeight=0.5dp
   │     headerDividersEnabled=true  footerDividersEnabled=true
   ├─ LinearLayout  id=@id/empty   layout_gravity=center  orientation=vertical
   │     w=match_parent h=match_parent
   │  ├─ FrameLayout  w=match_parent h=0dp  weight=0.3
   │  └─ LinearLayout  orientation=vertical  padding=@dimen/activity_padding (=16dp)
   │        w=match_parent h=0dp weight=0.7
   │     ├─ TextView  id=@id/title
   │     │     textSize=@dimen/text_heading (36.0sp)  textColor=@color/text_heading #FF586E75
   │     │     gravity=center_horizontal  layout_gravity=center_horizontal
   │     │     clickable=true  w=wrap_content h=wrap_content
   │     │     text=@string/no_connections → "No Connections" / zh "无连接"
   │     └─ TextView  id=@id/subtitle
   │           textColor=@color/text_subheading #FF586E75  gravity=center_horizontal
   │           layout_gravity=center_horizontal  clickable=true
   │           w=wrap_content h=wrap_content  layout_marginTop=5.0dp
   │           text=@string/you_do_not_have_any_connections →
   │             EN "You do not currently have any connections configured. Use the button below to get started."
   │             zh "你还没有配置任何连接。点击下面的按钮开始"
   └─ FloatingActionButton  id=@id/fab_new_connection
         w=wrap_content h=wrap_content  layout_margin=16.0dp
         src=@drawable/ic_new   app:backgroundTint=@color/primary_bold (#FFFFE24C)
         app:tint=@color/white   layout_alignParentBottom=true  layout_alignParentEnd=true
```

Note: `@id/empty` has **no** `android:visibility="gone"` in this file (unlike `port_forwards.xml`)
— visibility is toggled from code.

### 4.3 Page: Identities — `res/layout/identity_list.xml`

Structurally identical to §4.2 with these differences:

| Element | This file |
|---|---|
| list view | `<ListView id=@id/page_list clickable=true w=match_parent h=match_parent divider=@drawable/highlight dividerHeight=0.5dp headerDividersEnabled=true footerDividersEnabled=true>` (a plain `ListView`, not `ExpandableListView`) |
| `@id/empty` | has `android:padding="@dimen/activity_padding"` (=16dp) on the outer `LinearLayout` |
| title text | `@string/no_identities` → "No Identities" / zh "无认证" |
| subtitle text | `@string/you_do_not_have_any_identities` → "You do not have any identities configured. Identities are sets of username, password and/or private keys that can be used by multiple connections." / zh "你还没有配置任何认证。认证是用户名、密码或私钥的集合，可用于多个连接" |
| FAB id | `@id/fab_new_identity`, same `ic_new`, same tints |

### 4.4 Page: Port Forwards — `res/layout/port_forwards.xml`

```
RelativeLayout  orientation=vertical  fitsSystemWindows=true  w=match_parent h=match_parent
├─ RelativeLayout  id=@id/list_container  w=match_parent h=match_parent
│  ├─ ListView  id=@id/page_list  clipToPadding=false  w=match_parent h=match_parent
│  │     divider=@drawable/highlight dividerHeight=0.5dp header/footerDividersEnabled=true
│  ├─ LinearLayout  id=@id/empty  layout_gravity=center  orientation=vertical
│  │     visibility=gone   w=match_parent h=match_parent
│  │  ├─ FrameLayout weight=0.3 h=0dp
│  │  └─ LinearLayout orientation=vertical padding=16dp w=match_parent h=0dp weight=0.7
│  │     ├─ TextView id=@id/title    textSize=36.0sp textColor=#FF586E75 gravity=center_horizontal
│  │     │     text=@string/no_port_forwards → "No Port Forwards" / zh "无端口转发"
│  │     └─ TextView id=@id/subtitle textColor=#FF586E75 marginTop=5.0dp
│  │           text=@string/you_do_not_have_any_port_forwards → "You do not have any port forwards configured" / zh "你还没有配置任何端口转发"
│  └─ FloatingActionButton id=@id/fab_new_portforward  margin=16dp src=@drawable/ic_new
│        backgroundTint=#FFFFE24C  tint=#FFFFFFFF  alignParentBottom/End=true
└─ RelativeLayout  id=@id/problock  w=match_parent h=match_parent        ← Pro upsell overlay
   ├─ LinearLayout  layout_gravity=center  orientation=vertical  w/h=match_parent
   │  ├─ FrameLayout weight=0.3 h=0dp
   │  └─ LinearLayout orientation=vertical padding=16dp w=match_parent h=0dp weight=0.7
   │     ├─ TextView id=@id/problock_title    textSize=36.0sp textColor=#FF586E75 gravity=center_horizontal
   │     │     text=@string/port_forwarding → "Port Forwarding" / zh "端口转发"
   │     └─ TextView id=@id/problock_subtitle textColor=#FF586E75 marginTop=5.0dp gravity=center_horizontal
   │           text=@string/port_forwarding_is_part_of_our_pro →
   │             EN "\"Port forwarding is part of our Pro pack.\\nClick below for a full list of all of the features included in our pro pack and to upgrade.\""
   │             zh "\"端口转发是专业版功能之一\\n点击下方查看专业版功能列表\""
   └─ FloatingActionButton id=@id/fab_purchase  margin=16dp src=@drawable/ic_new
         backgroundTint=#FFFFE24C  tint=#FFFFFFFF  alignParentBottom/End=true
```

### 4.5 Card list anatomy — `res/layout/card_list_item.xml`

This is the row template for the modern card list (used by CloudSync/Bookclub/plugin card lists;
the classic connection list uses the flat rows in §4.6/§4.7).

```
androidx.cardview.widget.CardView
    focusable=false focusableInTouchMode=false clickable=false
    w=match_parent  h=wrap_content
    android:foreground=@drawable/card_item           → ripple #FF586E75
    card_view:cardBackgroundColor=@color/card_item_background → #FFFFFFFF (night #FF000000)
    card_view:cardCornerRadius=2.0dp
└─ LinearLayout  orientation=vertical  w=match_parent h=wrap_content
   ├─ RelativeLayout  w=match_parent h=wrap_content
   │  ├─ RelativeLayout  id=@id/itemContainer  padding=16.0dp
   │  │      focusable=false focusableInTouchMode=false clickable=false
   │  │      w=match_parent h=wrap_content
   │  │  ├─ LinearLayout  orientation=vertical
   │  │  │      focusable=false focusableInTouchMode=false clickable=false
   │  │  │      w=wrap_content h=wrap_content
   │  │  │      layout_alignParentLeft=true  layout_centerVertical=true
   │  │  │  ├─ TextView  id=@id/itemTitle
   │  │  │  │     textSize=@dimen/text_item_title (16.0sp)
   │  │  │  │     textColor=@color/text_item_title → #FF073642
   │  │  │  │     ellipsize=end  paddingRight=32.0dp  w=match_parent h=wrap_content
   │  │  │  │     text=@string/menu_item_title → "Menu Item Title" / zh "菜单项标题"
   │  │  │  └─ TextView  id=@id/itemSubtitle
   │  │  │        textSize=@dimen/text_item_subtitle (12.0sp)
   │  │  │        textColor=@color/text_item_subtitle → #FF586E75
   │  │  │        ellipsize=end  paddingRight=32.0dp  w=match_parent h=wrap_content
   │  │  │        text=@string/menu_item_subtitle → "Menu Item Subtitle (can be quite long)" / zh "菜单项子标题 (可能非常长)"
   │  │  ├─ TextView  id=@id/itemTextIcon
   │  │  │     textSize=32.0dp (dp!, should be sp)
   │  │  │     textColor=@color/card_icon_color → transparent (#00000000, see §2.5)
   │  │  │     w=wrap_content h=wrap_content
   │  │  │     text=@string/icon_globe (U+F0AC)
   │  │  │     layout_alignParentRight=true  layout_centerVertical=true
   │  │  │     contentDescription=@string/icon → "Icon"
   │  │  └─ ImageView  id=@id/itemImageIcon
   │  │        focusable=false focusableInTouchMode=false clickable=false  visibility=gone
   │  │        w=32.0dp h=32.0dp  layout_alignParentRight=true  layout_centerVertical=true
   │  │        contentDescription=@string/icon → "Icon"
   │  └─ ImageView  id=@id/banner  visibility=gone
   │        w=72.0dp h=72.0dp  src=@drawable/new_banner (drawable/new_banner.png = 128x128 px, 12187 B)
   │        layout_alignParentTop=true  layout_alignParentRight=true
   ├─ LinearLayout  id=@id/itemContent  gravity=center  orientation=vertical
   │     padding=16.0dp  visibility=gone  w=match_parent h=wrap_content  layout_marginTop=-20.0dp
   ├─ View  id=@id/button1_divider
   │     background=@color/card_item_divider → #33BCCACF (night #00000000)
   │     visibility=gone  w=match_parent h=0.5dp
   │     layout_marginLeft=4.0dp  layout_marginRight=4.0dp
   └─ Button  id=@id/button1
         textSize=14.0sp  textColor=@color/accent_bold → #FF586E75
         background=@drawable/button_white  visibility=gone
         w=match_parent h=40.0dp  text=@string/more_information → "More Information" / zh "更多信息"
```

**Row anatomy summary:** 16dp inner padding → [title 16sp `#FF073642`, subtitle 12sp `#FF586E75`]
left-aligned, 32dp right padding to clear the trailing affordance → trailing 32sp FontAwesome
glyph (default `icon_globe` U+F0AC) *or* a 32x32dp `ImageView`, both `centerVertical` +
`alignParentRight` → optional 128x128px `new_banner` pinned top-right → optional expanded content
panel (`itemContent`, negative 20dp top margin to tuck under the title block) → optional
0.5dp divider (`card_item_divider`) inset 4dp each side → optional 40dp-high "More Information"
button. Pressed state = `card_item` ripple `#FF586E75` drawn as the CardView foreground.

### 4.6 Flat list rows

**`res/layout/connection_menu_item.xml`** — the primary connection row.

```
RelativeLayout  background=@drawable/highlight (empty selector)  padding=@dimen/activity_padding (16dp)
    w=match_parent  h=@dimen/list_item_height (72.0dp)
├─ com.sonelli.juicessh.views.FontAwesomeTextView  id=@id/itemIcon
│     textSize=30.0dp    textColor=@color/icon_item → #FF586E75
│     gravity=center     w=40.0dp h=40.0dp
│     text=@string/icon_globe (U+F0AC)
│     layout_alignParentLeft=true  layout_alignParentTop=true  contentDescription=@string/icon "Icon"
├─ LinearLayout  orientation=vertical  paddingLeft=16dp  paddingRight=16dp
│     w=match_parent h=match_parent  layout_toRightOf=@id/itemIcon
│  ├─ TextView id=@id/itemTitle
│  │     textSize=@dimen/text_item_title (16.0sp)  textColor=@color/text_item_title #FF073642
│  │     ellipsize=end  gravity=center_vertical  singleLine=true
│  │     w=wrap_content h=20.0dp
│  │     text=@string/menu_item_title "Menu Item Title"
│  └─ TextView id=@id/itemSubtitle
│        textSize=@dimen/text_item_subtitle (12.0sp)  textColor=@color/text_item_subtitle #FF586E75
│        ellipsize=end  gravity=center_vertical  lines=1  scrollHorizontally=true  singleLine=true
│        w=wrap_content h=20.0dp
│        text=@string/menu_item_subtitle "Menu Item Subtitle (can be quite long)"
└─ LinearLayout id=@id/bottom_separator  orientation=horizontal
      background=#eeeeee  visibility=gone
      w=match_parent h=1.0dp  layout_alignParentBottom=true
```

**`res/layout/identity_menu_item.xml`** — identical to the above except the icon is
**24.0dp** `textSize` and `text=@string/icon_user` (U+F007); title/subtitle `width=wrap_content`
with `layout_width=wrap_content`, and the inner `LinearLayout` has no fixed `h=match_parent`.

**`res/layout/port_forward_item.xml`** — connection-row layout plus a trailing switch:

```
RelativeLayout  background=@drawable/highlight  padding=16dp  clickable=true
    w=match_parent  h=@dimen/list_item_height (72dp)  minHeight=72dp
├─ FontAwesomeTextView id=@id/itemIcon  textSize=24.0dp  textColor=@color/icon_item #FF586E75
│     gravity=center  w=40dp h=40dp  text=@string/icon_share_alt (U+F064)
│     alignParentLeft/Top=true  contentDescription=@string/icon
├─ androidx.appcompat.widget.SwitchCompat id=@id/toggleIndicator
│     w=wrap_content h=wrap_content  checked=false
│     layout_alignParentRight=true  layout_centerVertical=true
├─ LinearLayout orientation=vertical
│     layout_marginLeft=16dp  layout_marginRight=16dp
│     layout_toLeftOf=@id/toggleIndicator  layout_toRightOf=@id/itemIcon
│  ├─ TextView id=@id/itemTitle  textSize=16.0sp  textColor=#FF073642  ellipsize=end
│  │     w=wrap_content h=20dp  lines=1  scrollHorizontally=true  singleLine=true  text=@string/menu_item_title
│  └─ TextView id=@id/itemSubtitle  textColor=@color/text_item_subtitle #FF586E75  ellipsize=end
│        w=wrap_content h=20dp  lines=1  scrollHorizontally=true  singleLine=true  text=@string/menu_item_subtitle
│        (NOTE: no android:textSize on this one → inherits the theme default,
│         UNRESOLVED: effective size (inherited from ?android:textAppearance / theme default))
└─ LinearLayout id=@id/bottom_separator  background=#eeeeee  visibility=gone  w=match_parent h=1dp alignParentBottom
```

**`res/layout/connection_menu_group_item.xml`** — the expandable group header row:

```
RelativeLayout background=@drawable/highlight padding=16dp w=match_parent h=72.0dp (hard-coded)
├─ LinearLayout orientation=vertical w=wrap_content h=match_parent layout_marginLeft=56.0dp
│  ├─ TextView id=@android:id/text1  textSize=16.0sp textColor=#FF073642 ellipsize=end
│  │     gravity=center_vertical w=wrap_content h=20dp singleLine=true text=@string/menu_item_title
│  └─ TextView id=@android:id/text2  textSize=12.0sp textColor=#FF586E75 ellipsize=end
│        gravity=center_vertical w=wrap_content h=20dp lines=1 scrollHorizontally=true singleLine=true
│        text=@string/menu_item_subtitle
└─ LinearLayout id=@id/bottom_separator background=#eeeeee visibility=gone h=1dp layout_alignParentBottom
```

The 56dp left margin is where the `ExpandableListView` indicator is drawn
(`indicatorLeft=16dp`, `indicatorRight=56dp` in §4.2). **In Flutter this maps to a
`ExpansionTile`-style group header with a 56dp leading inset for the chevron.**

### 4.7 Frequent / recent pages

**`res/layout/frequently_used_page.xml`**

```
LinearLayout orientation=vertical w=match_parent h=match_parent
├─ LinearLayout id=@id/loading  gravity=center  orientation=vertical  visibility=gone  w/h=match_parent
│  └─ ProgressBar w=50.0dp h=50.0dp
├─ LinearLayout id=@id/empty  layout_gravity=center  orientation=vertical  visibility=gone  w/h=match_parent
│  ├─ TextView id=@id/title
│  │     textColor=@color/text_heading #FF586E75  gravity=center|bottom
│  │     w=match_parent h=0dp weight=0.5  text=@string/welcome → "Welcome" / zh "欢迎"
│  └─ TextView id=@id/subtitle
│        textSize=@dimen/text_item_subtitle (12.0sp)  textColor=@color/text_item_subtitle #FF586E75
│        gravity=center|top  w=match_parent h=0dp weight=0.5
│        marginLeft=10dp marginTop=5dp marginRight=10dp  maxLines=10
│        text=@string/youve_not_connected_yet →
│          EN "\"You've not connected to any servers yet.\\nHit Connections above to get started.\""
│          zh "\"你还没有连接到任何服务器\\n点击上面的连接开始\""
└─ ListView id=@id/page_list  w=match_parent h=match_parent
      childDivider=@drawable/highlight  divider=@drawable/highlight  dividerHeight=0.5dp
      headerDividersEnabled=true  footerDividersEnabled=true
```

**`res/layout/frequently_used_item.xml`** — the recent-connection row.

```
RelativeLayout  background=@drawable/highlight  w=match_parent  h=55.0dp
├─ TextView id=@id/itemIcon
│     android:icon=@drawable/ic_action_search       (48dp hdpi / 32dp mdpi / 64dp xhdpi)
│     textSize=32.0dp   textColor=@color/card_icon_color → transparent
│     paddingLeft=8.0dp  paddingRight=16.0dp
│     w=wrap_content h=wrap_content  layout_marginTop=10.0dp
│     text=@string/icon_globe (U+F0AC)
│     layout_alignParentLeft=true  layout_alignParentTop=true  contentDescription=@string/icon
└─ LinearLayout  gravity=center_vertical  orientation=vertical
      paddingRight=@dimen/activity_padding (16dp)
      w=match_parent h=match_parent  layout_toRightOf=@id/itemIcon
   ├─ TextView id=@id/itemTitle    textSize=16.0sp textColor=#FF073642 ellipsize=end
   │     focusable=false focusableInTouchMode=false clickable=false
   │     w=wrap_content h=wrap_content  singleLine=true  text=@string/menu_item_title
   └─ TextView id=@id/itemSubtitle textSize=12.0sp textColor=#FF586E75 ellipsize=end
         w=wrap_content h=wrap_content  lines=1 scrollHorizontally=true singleLine=true  text=@string/menu_item_subtitle
```

Row height **55dp** (not 72dp) — this is the widget/recent list style.

### 4.8 Generic empty-state page — `res/layout/pager_list.xml` and `simple_list_activity.xml`

Both files are structurally identical:

```
RelativeLayout  orientation=vertical  fitsSystemWindows=true (simple_list_activity only)
    w=match_parent h=match_parent
├─ LinearLayout id=@id/empty  layout_gravity=center  orientation=vertical  w/h=match_parent
│  └─ LinearLayout gravity=center orientation=vertical padding=@dimen/activity_padding (16dp)
│        w=match_parent h=match_parent
│     ├─ TextView id=@id/emptyTitle
│     │     textSize=@dimen/text_heading (36.0sp)  textColor=@color/text_heading #FF586E75
│     │     gravity=center_horizontal  layout_gravity=center_horizontal
│     │     paddingLeft=16dp  paddingRight=16dp  w=match_parent h=wrap_content
│     │     layout_marginTop=-40.0dp          ← pulls the title up above centre
│     └─ TextView id=@id/emptyMessage
│           textColor=@color/text_subheading #FF586E75  gravity=center_horizontal
│           layout_gravity=center_horizontal  paddingLeft=16dp  paddingRight=16dp
│           w=match_parent h=wrap_content  layout_marginTop=8.0dp
├─ ListView id=@id/list  (pager_list: no clipToPadding; simple_list_activity: clipToPadding=false)
│     w=match_parent h=match_parent  divider=@drawable/highlight  dividerHeight=0.5dp
│     headerDividersEnabled=true  footerDividersEnabled=true
└─ FloatingActionButton id=@id/fab_new  margin=16dp  src=@drawable/ic_new
      backgroundTint=@color/primary_bold #FFFFE24C  tint=@color/white #FFFFFFFF
      layout_alignParentBottom=true  layout_alignParentEnd=true
```

`emptyTitle`/`emptyMessage`/`empty.padding` are set from code — the layout carries no `android:text`.

---

## 5. `manage_connection.xml` — connection editor

`res/layout/manage_connection.xml`.

```
RelativeLayout  orientation=vertical  fitsSystemWindows=true  w=match_parent h=match_parent
└─ ScrollView  padding=@dimen/activity_padding (16dp)  scrollbars=vertical
      clipToPadding=false  w=match_parent h=match_parent
   └─ LinearLayout  orientation=vertical  focusable=true  focusableInTouchMode=true
         w=match_parent h=wrap_content
      ├─ TableLayout  orientation=horizontal  id=@id/connectionTableForm
      │     w=match_parent h=wrap_content
      │  ├─ TextView  textColor=@color/text_form_heading (#FF586E75)
      │  │     w=match_parent h=wrap_content
      │  │     text=@string/basic_settings → "Basic Settings" / zh "基本设置"
      │  │     style="?android:listSeparatorTextViewStyle"
      │  ├─ TableRow  id=@id/nicknameRow  gravity=center_vertical  layout_marginTop=8.0dp
      │  │  ├─ TextView  textAppearance=?android:textAppearanceSmall
      │  │  │     textColor=@color/text_form (#FF073642)  layout_gravity=center_vertical
      │  │  │     w=wrap_content h=wrap_content  layout_marginRight=5.0dp
      │  │  │     text=@string/form_nickname → "Nickname:" / zh "昵称:"
      │  │  └─ EditText  id=@id/nickname_value
      │  │        textAppearance=?android:textAppearanceSmall  textColor=@color/text_form
      │  │        nextFocusLeft=@id/nickname_value  nextFocusUp=@id/nickname_value
      │  │        w=0dp h=wrap_content  layout_weight=1.0
      │  │        hint=@string/form_optional → "(Optional)" / zh "(可选)"
      │  ├─ TableRow  id=@id/typeRow  gravity=center_vertical  layout_marginTop=8.0dp
      │  │  ├─ TextView  … text=@string/type_colon → "Type:" / zh "类型:"
      │  │  └─ Spinner  id=@id/type_spinner  w=0dp h=36.0dp  layout_weight=1.0
      │  │        prompt=@string/pick_one → "(Pick one)" / zh "(选择一个)"
      │  ├─ TableRow  id=@id/addressRow  gravity=center_vertical  layout_marginTop=8.0dp
      │  │  ├─ TextView  … text=@string/form_address → "Address:" / zh "地址:"
      │  │  └─ EditText  id=@id/address_value  w=0dp h=wrap_content  layout_weight=1.0
      │  │        inputType=textVisiblePassword
      │  ├─ TableRow  id=@id/identityRow  gravity=center_vertical  layout_marginTop=8.0dp
      │  │  ├─ TextView  … text=@string/form_identity → "Identity:" / zh "认证:"
      │  │  └─ Spinner  id=@id/idSpinner  w=0dp h=36.0dp  layout_weight=1.0
      │  │        prompt=@string/choose_an_identity → "Choose an identity" / zh "选择认证"
      │  ├─ TextView  textColor=@color/text_form_heading  w=match_parent h=wrap_content
      │  │     layout_marginTop=8.0dp
      │  │     text=@string/advanced_settings → "Advanced Settings" / zh "高级设置"
      │  │     style="?android:listSeparatorTextViewStyle"
      │  ├─ TableRow  id=@id/portRow  gravity=center_vertical  layout_marginTop=8.0dp
      │  │  ├─ TextView  … text=@string/form_port → "Port:" / zh "端口:"
      │  │  └─ EditText  id=@id/port_value  w=wrap_content h=wrap_content
      │  │        hint=@string/form_22 → "22" / zh "22"
      │  │        maxEms=5  ems=5  maxLength=5  inputType=number
      │  ├─ TableRow  id=@id/viaRow  gravity=center_vertical  layout_marginTop=8.0dp
      │  │  ├─ TextView  … text=@string/form_connect_via → "Connect Via:" / zh "连接方式:"
      │  │  └─ Spinner  id=@id/via_spinner  w=0dp h=36.0dp  layout_weight=1.0
      │  │        prompt=@string/form_optional → "(Optional)"
      │  ├─ TableRow  id=@id/runOnConnectRow  gravity=center_vertical  layout_marginTop=8.0dp
      │  │  ├─ TextView  … text=@string/run_snippet → "Run Snippet:" / zh "运行代码片段:"
      │  │  └─ Spinner  id=@id/snippetSpinner  w=0dp h=36.0dp  layout_weight=1.0
      │  │        prompt=@string/choose_a_snippet → "Choose a snippet" / zh "选择代码片段"
      │  ├─ TableRow  id=@id/backspaceModeRow  gravity=center_vertical  layout_marginTop=8.0dp
      │  │  ├─ TextView  … text=@string/backspace_mode → "Backspace:" / zh "Backspace 模式:"
      │  │  └─ Spinner  id=@id/backspaceModeSpinner  w=0dp h=36.0dp  layout_weight=1.0  (no prompt)
      │  └─ TableRow  id=@id/mosh_command_row  gravity=center_vertical
      │        visibility=gone  layout_marginTop=8.0dp
      │     ├─ TextView  … text=@string/command → "Command:" / zh "命令:"
      │     └─ EditText  id=@id/mosh_command_value  w=0dp h=wrap_content  layout_weight=1.0
      │           inputType=textVisiblePassword
      ├─ TextView  textColor=@color/text_form_heading  w=match_parent h=wrap_content
      │     layout_marginTop=8.0dp  text=@string/groups → "Groups" / zh "连接组"
      │     style="?android:listSeparatorTextViewStyle"
      └─ LinearLayout  orientation=vertical  id=@id/group_selector_holder
            w=match_parent h=wrap_content      ← children added in code
```

**Flutter notes.**
* Every label column is `wrap_content` with `layout_marginRight=5dp`; every input is
  `weight=1` (i.e. `Expanded`) except `port_value`/`remote_port` which are fixed ~5-em number fields.
* This is a **cumulative** layout: the ScrollView is the whole screen and the action bar holds Save.
* `style="?android:listSeparatorTextViewStyle"` section headers get
  `textColor=@color/text_form_heading` = `#FF586E75`; the platform style additionally supplies
  `textSize` (14sp in AppCompat's `TextAppearance.AppCompat.Small` family) and a
  `?android:attr/listDivider` background — **UNRESOLVED: exact textSize/background of
  `?android:listSeparatorTextViewStyle` (platform attribute, not defined in this APK)**.
* `?android:textAppearanceSmall` resolves to the platform `TextAppearance.Small`
  (`textSize=14sp`) — **UNRESOLVED: exact value (framework attribute)**.

---

## 6. The "hacker keyboard"

This is the extra-keys row of the terminal emulator (`TerminalEmulatorActivity`, theme
`Theme.JuiceSSH.Material.Terminal`). Three layout files implement it;
`hacker_keyboard_pager.xml` is the host pager.

### 6.1 Host — `res/layout/hacker_keyboard_pager.xml`

```xml
<androidx.viewpager.widget.ViewPager
    android:layout_width="match_parent" android:layout_height="70.0dp" />
```

**The keyboard strip is exactly 70dp tall.** The `ViewPager` has **no id**. Two pages are
paged: page 0 = `hacker_keyboard.xml`, page 1 = `hacker_keyboard_function_keys.xml`.
There is **no `layout-land` / `layout-sw*` override** for any hacker-keyboard file
(verified: those directories do not contain them), so the strip is identical in every configuration.

### 6.2 `res/layout/hacker_keyboard.xml` — main page

```
TableLayout  gravity=center  layout_gravity=center_horizontal  clickable=true
    w=match_parent  h=70.0dp  stretchColumns="*"      ← all columns equal width
├─ TableRow  gravity=center  w=match_parent  h=wrap_content  stretchColumns="*"
│  1. AutoRepeatButton  id=@id/keyboard_esc        tag=111   text=@string/esc        textSize=14.0sp
│  2. LinearLayout  w=match_parent h=wrap_content  layout_span=2      ← spans 2 columns
│     ├─ AutoRepeatButton id=@id/keyboard_forwardslash tag=76  text=@string/forwardslash textSize=18.0sp
│     │     w=0dp h=35.0dp  layout_weight=0.33
│     ├─ AutoRepeatButton id=@id/keyboard_pipe         tag=-1  text=@string/pipe         textSize=18.0sp
│     │     w=0dp h=35.0dp  layout_weight=0.33
│     └─ AutoRepeatButton id=@id/keyboard_dash         tag=69  text=@string/dash         textSize=18.0sp
│           w=0dp h=35.0dp  layout_weight=0.33
│  3. AutoRepeatButton  id=@id/keyboard_home  tag=122  text=@string/home   textSize=14.0sp
│  4. AutoRepeatButton  id=@id/keyboard_up    tag=19   text=@string/up_arrow textSize=18.0sp textStyle=bold
│  5. AutoRepeatButton  id=@id/keyboard_end   tag=123  text=@string/end    textSize=14.0sp
│  6. AutoRepeatButton  id=@id/keyboard_pgup  tag=92   text=@string/page_up textSize=14.0sp
│  7. TerminalThemedButton id=@id/keyboard_function_keys tag=-3 text=@string/fn textSize=14.0sp
└─ TableRow  gravity=center  w=match_parent  h=wrap_content  stretchColumns="*"
   1. AutoRepeatButton  id=@id/keyboard_tab   tag=61  text=@string/tab   textSize=14.0sp
   2. TerminalThemedButton id=@id/keyboard_ctrl tag=-2 text=@string/ctrl textSize=14.0sp
   3. TerminalThemedButton id=@id/keyboard_alt  tag=-4 text=@string/alt  textSize=14.0sp
   4. AutoRepeatButton  id=@id/keyboard_left  tag=21  text=@string/left_arrow  textSize=18.0sp textStyle=bold
   5. AutoRepeatButton  id=@id/keyboard_down  tag=20  text=@string/down_arrow  textSize=18.0sp textStyle=bold
   6. AutoRepeatButton  id=@id/keyboard_right tag=22  text=@string/right_arrow textSize=18.0sp textStyle=bold
   7. AutoRepeatButton  id=@id/keyboard_pgdn  tag=93  text=@string/page_down   textSize=14.0sp
   8. TerminalThemedImageButton id=@id/keyboard_toggle tag=-5
        src=@drawable/ic_lockscreen_ime  contentDescription=@string/toggle_keyboard
```

Common to **every** key in this file:
`android:background="@drawable/keyboard"`, `android:layout_height="35.0dp"`,
`android:hapticFeedbackEnabled="true"`, `android:onClick="keyboardPress"`.
Keys inside a `TableRow` use `android:layout_width="0.0dp"` and inherit the
`stretchColumns="*"` equal-width behaviour (the `TableRow` has 8 logical columns because of the
`layout_span=2` cell in row 1: columns = esc | (fs,pipe,dash → 2 cols) | home | up | end | pgup | fn).

**Column grid (both rows, 8 columns wide, equal width):**

| Column | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| **Row 1 (35dp)** | `Esc` | `\|` `-` + `/` (3 sub-keys, span 2, weight .33 each) | | `Home` | `↑` | `End` | `PgUp` | `Fn` |
| **Row 2 (35dp)** | `Tab` | `Ctrl` | `Alt` | `←` | `↓` | `→` | `PgDn` | `ic_lockscreen_ime` |

Total strip height **70dp = 2 × 35dp**, zero gutter; keys butt against each other and are
separated only by their 1px implied edges (the background selector has no stroke).

> **Discrepancy worth noting for a faithful rebuild:** in row 1 the sub-`LinearLayout` uses
> `android:layout_width="match_parent"` (not `0dp`), which under `TableLayout` column stretching
> still yields the span-2 width; the three inner keys then split it 0.33/0.33/0.33 (+1% rounding).
> In Flutter: `Expanded(flex: 1)` × 3 inside a span-2 cell.

### 6.3 Key background — `res/drawable/keyboard.xml`

```xml
<selector>
    <item android:state_pressed="false"><shape><solid android:color="#00ffffff" /></shape></item>
    <item android:state_pressed="true"> <shape><solid android:color="#57ffffff" /></shape></item>
</selector>
```

**Default = fully transparent** (`#00FFFFFF`). **Pressed = `#57FFFFFF`** (34 % white).
No stroke, no corners, no padding. Keys therefore appear as plain text on the terminal
background and flash a translucent white rectangle when pressed.

`res/drawable/keyboard_highlighted.xml` is a *separate, richer* selector (used where a key needs a
visible cap — e.g. `TerminalThemedButton` in some paths). Both `state_pressed` items are identical:

```xml
<selector>
  <item android:state_pressed="true">
    <shape>
      <solid android:color="#ffb1b1b1" />
      <stroke android:width="1.0px" android:color="#ff000000" />
      <padding android:left="2.0dp" android:top="10.0dp" android:right="2.0dp" android:bottom="10.0dp" />
      <corners android:topLeftRadius="4.0dp" android:topRightRadius="4.0dp"
               android:bottomLeftRadius="4.0dp" android:bottomRightRadius="4.0dp" />
      <gradient android:startColor="#ffb1b1b1" android:endColor="#ffb1b1b1"
                android:angle="90.0" android:type="linear" android:centerColor="#ff7a7a7a" />
    </shape>
  </item>
  … identical shape for android:state_pressed="false" …
</selector>
```

→ grey `#FFB1B1B1` cap, 1px black border, **4dp corners**, dark centre band `#FF7A7A7A` on a
90° vertical linear gradient, inner padding 2dp left/right and 10dp top/bottom.

### 6.4 `res/layout/hacker_keyboard_function_keys.xml` — F-key page

```
TableLayout  layout_gravity=center_horizontal  clickable=true
    w=match_parent  h=70.0dp  stretchColumns="*"      ← NO android:gravity
├─ TableRow  w=match_parent  h=wrap_content  stretchColumns="*"     ← NO android:gravity
│  1..6. AutoRepeatButton  keyboard_f1..f6   tags -11..-16   text=@string/f1..f6  textSize=14.0sp
│  7.    TerminalThemedImageButton id=@id/prev_keyboard tag=-7
│          src=@drawable/ic_undo  contentDescription=@string/toggle_keyboard
└─ TableRow  w=match_parent  h=wrap_content  stretchColumns="*"
   1..6. AutoRepeatButton  keyboard_f7..f12  tags -17..-22  text=@string/f7..f12 textSize=14.0sp
   7.    TerminalThemedImageButton id=@id/keyboard_toggle tag=-5
          src=@drawable/ic_lockscreen_ime  contentDescription=@string/toggle_keyboard
```

7 equal columns per row; every key `w=0dp h=35.0dp background=@drawable/keyboard
hapticFeedbackEnabled=true onClick=keyboardPress`. Note `@string/toggle_keyboard`
("Toggle Keyboard" / zh "切换键盘") is the content description **for both** `prev_keyboard`
and `keyboard_toggle` — that is what the source says.

### 6.5 `res/layout/hacker_keyboard_qnx.xml` — QNX/legacy variant

Uses plain `android.widget.Button` instead of `AutoRepeatButton`/`TerminalThemedButton`, adds
`android:textColor="@android:color/white"`, `textSize=12.0sp`, and gives the root
`android:background="#ff232323"` (dark grey) with `layout_height="match_parent"`.

```
TableLayout  gravity=center  layout_gravity=center_horizontal
    background=#ff232323   clickable=true   w=match_parent   h=match_parent   stretchColumns="*"
├─ TableRow  gravity=center  w=match_parent h=wrap_content  stretchColumns="*"
│  1. Button id=@id/keyboard_esc           tag=111  text=@string/esc
│  2. LinearLayout  w=match_parent  h=wrap_content  layout_span=2
│     ├─ Button id=@id/keyboard_forwardslash tag=76  text=@string/forwardslash  w=0dp h=35dp weight=0.33
│     ├─ Button id=@id/keyboard_pipe         tag=-1  text=@string/pipe          w=0dp h=35dp weight=0.33
│     └─ Button id=@id/keyboard_backslash    tag=73  text=@string/backslash     w=0dp h=35dp weight=0.33
│  3. Button id=@id/keyboard_home  tag=122 text=@string/home
│  4. Button id=@id/keyboard_up    tag=19  text=@string/up_arrow
│  5. Button id=@id/keyboard_end   tag=123 text=@string/end
│  6. Button id=@id/keyboard_function_keys tag=-3 text=@string/fn
└─ TableRow  gravity=center  w=match_parent h=wrap_content  stretchColumns="*"
   1. Button id=@id/keyboard_tab   tag=61  text=@string/tab
   2. Button id=@id/keyboard_ctrl  tag=-2  text=@string/ctrl
   3. Button id=@id/keyboard_alt   tag=-4  text=@string/alt
   4. Button id=@id/keyboard_left  tag=21  text=@string/left_arrow
   5. Button id=@id/keyboard_down  tag=20  text=@string/down_arrow
   6. Button id=@id/keyboard_right tag=22  text=@string/right_arrow
   7. Button id=@id/exit_session   tag=-6  text=@string/exit
```

Differences vs. the main page: **`Backslash` replaces `Dash`** in the span-2 cell;
**drops `PgUp`/`PgDn`**; the last cell of row 2 is **`Exit`** instead of the keyboard-toggle
image button. All keys: `@drawable/keyboard` background, `h=35.0dp`,
`hapticFeedbackEnabled=true`, `onClick=keyboardPress`, `textSize=12.0sp`,
`textColor=@android:color/white` = `#FFFFFFFF`.

### 6.6 Key labels and their tags (`tag` = the keycode/behaviour id passed to `keyboardPress`)

| `android:id` | Resolved label (EN) | zh-CN | `tag` | Size | Style class |
|---|---|---|---|---|---|
| `keyboard_esc` | `@string/esc` = **Esc** | Esc | 111 | 14sp | AutoRepeatButton |
| `keyboard_forwardslash` | `@string/forwardslash` = **/** | / | 76 | 18sp | AutoRepeatButton |
| `keyboard_pipe` | `@string/pipe` = **\|** | \| | −1 | 18sp | AutoRepeatButton |
| `keyboard_dash` | `@string/dash` = **-** | - | 69 | 18sp | AutoRepeatButton |
| `keyboard_backslash` *(qnx only)* | `@string/backslash` = **\\** | \\ | 73 | 12sp | Button (qnx) |
| `keyboard_home` | `@string/home` = **Home** | Home | 122 | 14sp | AutoRepeatButton |
| `keyboard_up` | `@string/up_arrow` = **↑** | ↑ | 19 | 18sp **bold** | AutoRepeatButton |
| `keyboard_end` | `@string/end` = **End** | End | 123 | 14sp | AutoRepeatButton |
| `keyboard_pgup` | `@string/page_up` = **PgUp** | PgUp | 92 | 14sp | AutoRepeatButton |
| `keyboard_function_keys` | `@string/fn` = **Fn** | Fn | −3 | 14sp | TerminalThemedButton |
| `keyboard_tab` | `@string/tab` = **Tab** | Tab | 61 | 14sp | AutoRepeatButton |
| `keyboard_ctrl` | `@string/ctrl` = **Ctrl** | Ctrl | −2 | 14sp | TerminalThemedButton |
| `keyboard_alt` | `@string/alt` = **Alt** | Alt | −4 | 14sp | TerminalThemedButton |
| `keyboard_left` | `@string/left_arrow` = **←** | ← | 21 | 18sp **bold** | AutoRepeatButton |
| `keyboard_down` | `@string/down_arrow` = **↓** | ↓ | 20 | 18sp **bold** | AutoRepeatButton |
| `keyboard_right` | `@string/right_arrow` = **→** | → | 22 | 18sp **bold** | AutoRepeatButton |
| `keyboard_pgdn` | `@string/page_down` = **PgDn** | PgDn | 93 | 14sp | AutoRepeatButton |
| `keyboard_toggle` | *(image)* contentDescription `@string/toggle_keyboard` = **Toggle Keyboard** | 切换键盘 | −5 | — | TerminalThemedImageButton |
| `prev_keyboard` | *(image)* contentDescription `@string/toggle_keyboard` | 切换键盘 | −7 | — | TerminalThemedImageButton |
| `exit_session` *(qnx only)* | `@string/exit` = **Exit** | 退出 | −6 | 12sp | Button (qnx) |
| `keyboard_f1`…`keyboard_f12` | `@string/f1`…`@string/f12` = **F1**…**F12** | F1…F12 | −11…−22 | 14sp | AutoRepeatButton |

Only `toggle_keyboard`, `exit`, `alt` and `dash`(identical) have zh-CN overrides; all other
keyboard strings are untranslated ASCII/arrow glyphs.

### 6.7 Key drawables

| Drawable | File | Dimensions | Depicts |
|---|---|---|---|
| `ic_lockscreen_ime` | `drawable-mdpi/ic_lockscreen_ime.png` | **30×29 px**, 152 B | Keyboard-show/hide glyph (a downward chevron over a bar). Used by `keyboard_toggle` in both pages. |
| | `drawable-hdpi/…` | **45×45 px**, 189 B | |
| | `drawable-xhdpi/…` | **60×60 px**, 209 B | |
| `ic_undo` | `drawable-ldpi/…` | **24×24 px**, 355 B | Curved back-arrow ("undo") — used by `prev_keyboard`. |
| | `drawable-mdpi/…` | **32×32 px**, 422 B | |
| | `drawable-hdpi/…` | **48×48 px**, 684 B | |
| | `drawable-xhdpi/…` | **64×64 px**, 890 B | |

*(There is no `drawable-xxhdpi` variant of either; xxhdpi devices fall back to xhdpi.)*

### 6.8 Behaviour classes (from smali, for fidelity of interaction)

* `TerminalThemedButton` extends `UnswipableButton` extends `androidx.appcompat.widget.AppCompatButton`.
  It exposes `c(textColor, unpressedColor, pressedColor)` and `d(boolean pressed)`, which recolour
  the two `GradientDrawable` children of the `StateListDrawable` background from the **terminal
  colour scheme** (`views/TerminalThemedButton.smali` lines 31–95/97–173). So `Fn`, `Ctrl`, `Alt`
  are *stateful modifier keys* whose background + text colour change when latched.
* `AutoRepeatButton` extends `TerminalThemedButton`; it installs an `OnTouchListener` and
  auto-repeats the click. Repeats use `ViewConfiguration.getKeyRepeatTimeout()` for the initial
  delay and `getKeyRepeatDelay()` for the repeat interval on API ≥ 12; the field defaults are
  **500 ms** (`0x1f4`) initial delay and **50 ms** (`0x32`) repeat interval
  (`views/AutoRepeatButton.smali` lines 21–29, 44–81).
* `UnswipableButton` swallows horizontal swipes via a `GestureDetector` so that swiping across the
  keyboard strip does not page the terminal or trigger the swipe-mode shortcuts.

---

## 7. Settings screen tree

### 7.1 `res/xml/settings.xml` — full hierarchy

Root: `<PreferenceScreen android:id="@id/settings" layout_width=match_parent layout_height=match_parent>`.

Every preference carries `android:persistent="false"`, `android:background="@drawable/highlight"`
(the empty selector — no visual), and `android:layout="@layout/preference"` (= §7.2), so the
custom row layout is used **uniformly**.

#### Category 1 — `@string/general` = **"General"** / zh "基本" (key `general`)

| # | Type | Key | Title (resolved) | Summary (resolved) | Extras |
|---|---|---|---|---|---|
| 1 | `ListDBPreference` | `theme:dark` | `@string/dark_theme` = **"Dark Theme"** / zh "暗色主题" | — | `entries=@array/dark_theme_names`, `entryValues=@array/dark_theme_values` |
| 2 | `ActionPreference` | `action:manageSnippets` | `@string/manage_snippets` = **"Manage Snippets"** / zh "管理片段" | — | `android:id=@id/manage_snippets` |
| 3 | `ActionPreference` | `action:manageEc2SyncProfiles` | `@string/amazon_ec2_link` = **"Amazon EC2 Link"** / zh "Amazon EC2 连接" | — | `android:id=@id/ec2_sync_profiles` — **Pro feature** |

`dark_theme_names` = `["Automatic (system default)", "Light", "Dark"]`
`dark_theme_values` (`values/arrays.xml`) = `["3", "1", "2"]`;
**overridden in `values-v29/arrays.xml`** to `["-1", "1", "2"]` (i.e. on API 29+ the
"Automatic" sentinel is `-1` instead of `3`).

#### Category 2 — `@string/app_security` = **"App Security"** / zh "应用安全" (key `account`)

| # | Type | Key | Title | Summary |
|---|---|---|---|---|
| 1 | `EncSwitchDBPreference` | `pinlock:enabled` | `@string/security_lock` = **"Security Lock"** / zh "安全锁" | `@string/lock_juicessh_after` = **"Lock app after 5min inactivity"** / zh "在不活动 5 分钟后锁定应用" |
| 2 | `ActionPreference` | `action:clear_known_hosts` | `@string/clear_known_hosts` = **"Clear known hosts"** / zh "清除已知主机" | `@string/removes_host_keys` = **"Wipe previously seen host keys/fingerprints"** / zh "清除之前记录的主机密钥指纹" |
| 3 | `SwitchDBPreference` | `ssh:agent` | `@string/ssh_agent_forwarding` = **"SSH Agent Forwarding"** | — (zh-CN: **no translation present**) |

#### Category 3 — `@string/terminal` = **"Terminal"** / zh "终端" (key `terminal`)

| # | Type | Key | Title | Summary / custom attrs |
|---|---|---|---|---|
| 1 | `TerminalThemeDBPreference` | `terminal:theme` | `@string/theme_slash_colors` = **"Theme / Colors"** / zh "主题 / 配色" | `entries=@array/terminal_theme_names`, `entryValues=@array/terminal_theme_values` |
| 2 | `TerminalFontDBPreference` | `terminal:font` | `@string/font` = **"Font"** | `entries=@array/font_names`, `entryValues=@array/font_names` (same array for both) |
| 3 | `NumberDBPreference` | `terminal:font_size` | `@string/font_size` = **"Font size"** / zh "字体大小" | `custom:label=@string/font_size` "Font size"; `custom:minValue="1"`; `custom:maxValue="30"`; `custom:message=@string/you_can_adjust_the_font` = "You can also adjust the font during an SSH session by using the volume buttons on your device" / zh "你也可以在 SSH 会话中按音量键调节字体大小" |
| 4 | `NumberDBPreference` | `terminal:margin` | `@string/terminal_margin` = **"Terminal Margin"** | `summary=@string/useful_for_those_with_screen_protectors` = **"Useful if you have a screen protector"**; `custom:label=@string/pixels` = "Pixels"; `custom:minValue="0"`; `custom:maxValue="128"`; `custom:message=@string/specify_the_terminal_margin` = "\"Specify a terminal margin (in pixels) that will be shown around the contents of the terminal. This is useful for those that have screen protectors and cannot see the edges of the terminal.\n\n8 or 16 is usually a good starting point.\"" |
| 5 | `ListDBPreference` | `terminal:horizontal_swipe_mode` | `@string/horizontal_swipe` = **"Horizontal Swipe"** / zh "水平滑动" | `entries=@array/terminal_horizontal_swipe_mode_names`, `entryValues=@array/terminal_horizontal_swipe_mode_values` |
| 6 | `SwitchDBPreference` | `terminal:utf8` | `@string/utf8_support` = **"UTF-8 support"** / zh "支持 UTF-8" | — |
| 7 | `ListDBPreference` | `terminal:type` | `@string/emulator_type` = **"Emulator type"** / zh "终端模拟器类型" | `entries=@array/terminal_typeTitles`, `entryValues=@array/terminal_typeValues` |
| 8 | `ListDBPreference` | `terminal:bell_mode` | `@string/terminal_bell` = **"Terminal Bell"** / zh "终端响铃" | `entries=@array/terminal_bell_mode_names`, `entryValues=@array/terminal_bell_mode_values` |
| 9 | `ListDBPreference` | `terminal:keyboard_position` | `@string/popup_keyboard_position` = **"Popup keyboard position"** / zh "弹出键盘的位置" | `entries=@array/terminal_keyboard_position_names`, `entryValues=@array/terminal_keyboard_position_values` |

#### Category 4 — `@string/mosh` = **"Mosh"** (key `mosh`)

| # | Type | Key | Title | Summary |
|---|---|---|---|---|
| 1 | `TextDBPreference` | `mosh:mosh-server` | `@string/server_command` = **"Server Command"** / zh "服务端命令" | — |

#### Category 5 — `@string/about_us` = **"About Us"** / zh "关于我们" (key `about_us`)

| # | Type | Key | Title | Summary |
|---|---|---|---|---|
| 1 | `ActionPreference` | `action:rate_us` | `@string/rate_us` = **"Rate us"** / zh "给我们打分" | `@string/it_really_helps` = **"Show your appreciation if you like the app!"** / zh "如果你喜欢这个应用，给我们个好评吧!" |
| 2 | `ActionPreference` | `action:website` | `@string/website` = **"Website"** / zh "网站" | `@string/website_address` = **"https://juicessh.com"** / zh "https://juicessh.com" |
| 3 | `ActionPreference` | `action:software_licenses` | `@string/about` = **"About"** / zh "关于" | `@string/components_and_licenses` = **"Components and licenses"** / zh "组件和授权" |
| 4 | `ActionPreference` | `action:version` | `@string/application_version` = **"Version"** / zh "版本" | `@string/unknown_version` = **"JuiceSSH (Unknown Version)"** / zh "JuiceSSH (未知版本)"; `android:id=@id/version_menu_item` |

**No `PreferenceCategory` is collapsible and none is `PreferenceScreen`-nested.**

### 7.2 Custom preference row layout — `res/layout/preference.xml`

```
LinearLayout  gravity=center_vertical  orientation=horizontal
    w=match_parent  h=wrap_content  baselineAligned=false
    minHeight="?android:listPreferredItemHeight"
├─ RelativeLayout  padding=@dimen/activity_padding (16dp)
│     w=0dp  h=wrap_content  layout_weight=1.0
│  ├─ TextView  id=@android:id/title
│  │     textSize=@dimen/text_item_title (16.0sp)  textColor=@color/text_item_title #FF073642
│  │     ellipsize=marquee  fadingEdge=horizontal  w=wrap_content h=wrap_content  singleLine=true
│  └─ TextView  id=@android:id/summary
│        textSize=@dimen/text_item_subtitle (12.0sp)  textColor=@color/text_item_subtitle #FF586E75
│        w=wrap_content h=wrap_content  maxLines=2  layout_below=@android:id/title
│        layout_alignLeft=@android:id/title
└─ LinearLayout  id=@android:id/widget_frame
      gravity=center_vertical  orientation=vertical
      w=wrap_content  h=match_parent
```

### 7.3 Switch preference row layout — `res/layout/switch_preference.xml`

Same as §7.2 but the row itself is the tap target and the widget frame adds padding:

```
LinearLayout  gravity=center_vertical  orientation=horizontal
    focusable=false  focusableInTouchMode=false  clickable=true
    descendantFocusability=blocksDescendants
    w=match_parent  h=wrap_content  baselineAligned=false
    minHeight="?android:listPreferredItemHeight"
    style="@style/Theme.JuiceSSH.Material.SelectableListItem"     → android:background=@android:drawable/list_selector_background
├─ RelativeLayout  padding=16dp  w=0dp h=wrap_content  weight=1.0
│  ├─ TextView id=@android:id/title    textSize=16.0sp textColor=#FF073642 ellipsize=marquee singleLine=true
│  └─ TextView id=@android:id/summary  textSize=12.0sp textColor=#FF586E75 maxLines=2
│        layout_below=@android:id/title  layout_alignLeft=@android:id/title
└─ LinearLayout id=@android:id/widget_frame  gravity=center_vertical  orientation=vertical
      padding=@dimen/activity_padding (16dp)  w=wrap_content  h=match_parent
   └─ androidx.appcompat.widget.SwitchCompat  id=@id/switch_compat
         focusable=false  clickable=false  w=wrap_content  h=wrap_content
```

### 7.4 Terminal theme / font picker rows

`res/layout/terminal_theme_item.xml` — visual swatch preview row:

```
LinearLayout  gravity=center  orientation=horizontal  paddingLeft=16dp paddingRight=16dp
    w=match_parent h=match_parent
├─ TextView  id=@id/theme_name  textSize=12.0sp  ellipsize=end  gravity=center_vertical
│     w=0dp h=48.0dp  lines=1  layout_weight=1.0
└─ TableLayout  gravity=right  w=wrap_content h=wrap_content
   ├─ TableRow  layout_marginBottom=4.0dp
   │   FrameLayout id=@id/theme_color_0   background=#ff000000  24.0x8.0dp
   │   FrameLayout id=@id/theme_color_1   background=#ff00cc00  24.0x8.0dp
   │   FrameLayout id=@id/theme_color_2   background=#ff00ccff  24.0x8.0dp
   │   FrameLayout id=@id/theme_color_3   background=#ffffccff  24.0x8.0dp
   └─ TableRow  layout_marginTop=4.0dp
       FrameLayout id=@id/theme_color_4   background=#ff0000cc  24.0x8.0dp
       FrameLayout id=@id/theme_color_5   background=#ffeeee00  24.0x8.0dp
       FrameLayout id=@id/theme_color_6   background=#ffffcc00  24.0x8.0dp
       FrameLayout id=@id/theme_color_7   background=#ff0ddffc  24.0x8.0dp
```

Eight 24×8dp swatches in a 4×2 grid — the hard-coded colours above are only placeholder
defaults; the adapter overwrites each `FrameLayout`'s background from the real terminal palette.

`res/layout/terminal_font_item.xml`:

```
LinearLayout  gravity=center  orientation=horizontal  paddingLeft=16dp paddingRight=16dp
    w=match_parent h=match_parent
└─ TextView  id=@id/font_name  textSize=12.0sp  ellipsize=end  gravity=center_vertical
      w=0dp  h=48.0dp  lines=1  layout_weight=1.0
```

### 7.5 Settings list-preference arrays (`res/values/arrays.xml`, resolved)

| Array | Entries (in order) | Values |
|---|---|---|
| `dark_theme_names` | Automatic (system default), Light, Dark | `dark_theme_values` = `3, 1, 2` (API 29+: `-1, 1, 2`) |
| `terminal_theme_names` | Dark, Light, Solarized Dark, Solarized Light, "80's Hacker", Monokai, Tiger Orange, Tiger Black, Bifrost | `0,1,2,3,4,5,6,7,8` |
| `font_names` | Cascadia Code Mono, Sauce Code Pro, Roboto Mono, JetBrains Mono, Fira Code, Open Dyslexic, Inconsolata, Droid Sans Mono | identical |
| `terminal_horizontal_swipe_mode_names` | Irssi next/prev window, WeeChat next/prev window, Tmux next/prev window, Screen next/prev window, Disabled | `0,1,2,3,4` |
| `terminal_bell_mode_names` | `@string/disabled` = "Disabled" / zh "已禁用"; `@string/vibrate_device` = "Vibrate Device" / zh "振动设备"; `@string/show_notification` = "Show Notification" / zh "显示通知" | `0,1,2` |
| `terminal_keyboard_position_names` | `@string/above_terminal` = "Above Terminal" / zh "终端上方"; `@string/below_terminal` = "Below Terminal" / zh "终端下方"; `@string/disabled` = "Disabled" / zh "已禁用" | `0,1,2` |
| `terminal_typeTitles` | linux, xterm, xterm-color, xterm-256color, vt100 | identical to `terminal_typeValues` |
| `terminal_alt_behaviour_names` *(not referenced by settings.xml)* | `@string/alt_mode_default` = "Default" / zh "默认"; `@string/alt_sends_esc` = "ALT sends ESC" / zh "ALT 键发送 ESC" | `0,1` |
| `widget_update_frequencies_names` *(widget config)* | `@string/hourly` "hourly"/"每小时"; `@string/daily` "daily"/"每天"; `@string/weekly` "weekly"/"每周"; `@string/monthly` "monthly"/"每月" | `3600, 86400, 604800, 2419200` |

---

## 8. Identity / snippet / port-forward management

### 8.1 `res/layout/manage_identity.xml`

```
RelativeLayout  orientation=vertical  id=@id/main_content  fitsSystemWindows=true
    w=match_parent  h=wrap_content
├─ ScrollView  id=@id/scroll_view  padding=@dimen/activity_padding (16dp)
│     scrollbars=vertical  clipToPadding=false  w=match_parent  h=wrap_content
│  └─ TableLayout  orientation=horizontal  focusable=true  focusableInTouchMode=true
│        w=match_parent  h=wrap_content
│     ├─ TableRow  w=match_parent
│     │  └─ TextView  textColor=@color/text_form_heading #FF586E75
│     │        w=match_parent h=wrap_content  layout_column=0  layout_weight=1.0
│     │        text=@string/identity → "Identity" / zh "认证信息"
│     │        style="?android:listSeparatorTextViewStyle"
│     ├─ TableRow  layout_marginTop=8.0dp
│     │  ├─ TextView  textAppearance=?android:textAppearanceSmall  textColor=@color/text_form #FF073642
│     │  │     w=wrap_content h=wrap_content  layout_marginRight=5.0dp
│     │  │     text=@string/nickname_colon → "Nickname:" / zh "昵称:"
│     │  └─ EditText  id=@id/identityNickname_value  textAppearance=?android:textAppearanceSmall
│     │        textColor=@color/text_form  w=0dp h=wrap_content  layout_weight=1.0
│     │        hint=@string/optional → "(Optional)" / zh "(可选)"
│     ├─ TableRow  layout_marginTop=8.0dp
│     │  ├─ TextView  … text=@string/username_colon → "Username:" / zh "用户名:"
│     │  └─ EditText  id=@id/identityUsername_value  w=0dp h=wrap_content  layout_weight=1.0
│     │        inputType=textVisiblePassword
│     ├─ TableRow  gravity=center_vertical  layout_marginTop=8.0dp
│     │  ├─ TextView  … text=@string/password_colon → "Password:" / zh "密码:"
│     │  ├─ TextView  id=@id/identityPassword_status
│     │  │     textSize=12.0sp  textColor=@color/text_form  visibility=gone
│     │  │     w=0dp h=wrap_content  layout_weight=1.0  text=@string/not_set → "Not set" / zh "未设置"
│     │  └─ Button  id=@id/identityPasswordButton
│     │        textSize=@dimen/text_button (16.0sp)  textColor=@android:color/white #FFFFFFFF
│     │        ellipsize=end  gravity=center  layout_gravity=right
│     │        background=@drawable/button  padding=5.0dp
│     │        w=0dp h=36.0dp  layout_marginLeft=4.0dp  maxLines=1  layout_weight=1.0
│     │        text=@string/set_optional → "Set (optional)" / zh "设置 (可选)"
│     ├─ TableRow  gravity=center_vertical  layout_marginTop=8.0dp
│     │  ├─ TextView  … text=@string/private_key_colon → "Private Key:" / zh "私钥:"
│     │  ├─ TextView  id=@id/identityPrivateKey_status
│     │  │     textAppearance=?android:textAppearanceSmall  textColor=@color/text_form
│     │  │     visibility=gone  w=0dp h=wrap_content  layout_weight=1.0
│     │  │     text=@string/not_set → "Not set" / zh "未设置"
│     │  └─ Button  id=@id/identityPrivateKey_button
│     │        textSize=16.0sp  textColor=#FFFFFFFF  ellipsize=end  gravity=center
│     │        layout_gravity=right  background=@drawable/button  padding=5.0dp
│     │        w=0dp h=36.0dp  layout_marginLeft=4.0dp  maxLines=1  layout_weight=1.0
│     │        text=@string/set_optional → "Set (optional)" / zh "设置 (可选)"
│     ├─ TableRow  id=@id/snippet_header_row  w=match_parent  layout_marginTop=8.0dp
│     │  └─ TextView  textColor=@color/text_form_heading  w=match_parent h=wrap_content
│     │        layout_column=0  layout_weight=1.0  text=@string/snippet → "Snippet" / zh "代码片段"
│     │        style="?android:listSeparatorTextViewStyle"
│     ├─ TableRow  layout_gravity=center_vertical  id=@id/snippet_row
│     │     w=match_parent  layout_marginTop=8.0dp
│     │  └─ TextView  textAppearance=?android:textAppearanceSmall  textColor=@color/text_form
│     │        w=0dp h=wrap_content  layout_weight=1.0
│     │        text=@string/pro_users_can_public_key_snippet →
│     │          "JuiceSSH Pro users can take advantage of an automatically generated snippet to add a public key to a servers ~/.ssh/authorized_keys file and set the correct permissions."
│     │          zh "JuiceSSH Pro 用户可以自动创建一个代码片段，该代码可用于添加公钥到服务器上的 ~/.ssh/authorized_keys 文件并设置正确的权限"
│     └─ TableRow  gravity=center_vertical  id=@id/snippet_button_row
│           visibility=visible  w=match_parent  layout_marginTop=16.0dp
│        └─ Button  id=@id/generate_snippet
│              textSize=@dimen/text_button (16.0sp)  textColor=@android:color/white
│              gravity=center  layout_gravity=right  background=@drawable/button
│              w=0dp h=42.0dp  layout_weight=1.0
│              text=@string/generate_snippet → "Generate Snippet" / zh "生成代码片段"
└─ LinearLayout  gravity=right  orientation=horizontal  id=@id/bottom_buttons
      visibility=gone  w=match_parent  h=wrap_content
      layout_marginBottom=@dimen/activity_padding (16dp)  layout_below=@id/scroll_view
   ├─ Button  id=@id/button_cancel  w=wrap_content h=wrap_content
   │     text=@string/cancel → "Cancel" / zh "取消"  style="?android:buttonBarNegativeButtonStyle"
   └─ Button  id=@id/button_ok  w=wrap_content h=wrap_content
         text=@string/ok → "OK" / zh "确定"  style="?android:buttonBarPositiveButtonStyle"
```

`?android:buttonBarNegativeButtonStyle` / `?android:buttonBarPositiveButtonStyle` and
`?android:textAppearanceSmall` are framework attributes — **UNRESOLVED: exact text size/colour
(defined by the platform/AppCompat theme, not in this APK)**.

### 8.2 `res/layout/manage_group.xml`

```
RelativeLayout  orientation=vertical  fitsSystemWindows=true  clipToPadding=false
    w=match_parent h=match_parent
└─ LinearLayout  orientation=vertical  visibility=visible  w=match_parent h=match_parent
   └─ ScrollView  scrollbars=vertical  w=match_parent h=match_parent
      └─ LinearLayout  orientation=vertical  id=@id/main_content
            w=match_parent h=wrap_content  layout_marginLeft=10.0dp  layout_marginRight=10.0dp
         └─ TableLayout  orientation=horizontal  w=match_parent h=wrap_content
            ├─ TextView  textColor=@color/text_form_heading #FF586E75
            │     w=match_parent h=wrap_content  layout_marginTop=8.0dp
            │     text=@string/connection_group → "Connection Group" / zh "连接组"
            │     style="?android:listSeparatorTextViewStyle"
            └─ TableRow  layout_marginTop=8.0dp
               ├─ TextView  textAppearance=?android:textAppearanceSmall  textColor=@color/text_form
               │     w=wrap_content h=wrap_content  layout_marginRight=5.0dp
               │     text=@string/group_name_colon → "Group Name:" / zh "群组名称:"
               └─ EditText  id=@id/groupName_value  textAppearance=?android:textAppearanceSmall
                     textColor=@color/text_form  w=0dp h=wrap_content  layout_weight=1.0
                     inputType=textNoSuggestions
```

Note: the ScrollView here has **no** `activity_padding`; the 10dp left/right margins live on
`main_content` instead.

### 8.3 `res/layout/manage_port_forward.xml`

```
RelativeLayout  orientation=vertical  fitsSystemWindows=true  w=match_parent h=match_parent
└─ ScrollView  padding=@dimen/activity_padding (16dp)  scrollbars=vertical
      clipToPadding=false  w=match_parent  h=wrap_content
   └─ TableLayout  orientation=horizontal  id=@id/table  focusable=true  focusableInTouchMode=true
         w=match_parent h=wrap_content
      ├─ TableRow  w=match_parent
      │  └─ TextView  textColor=@color/text_form_heading #FF586E75  w=match_parent h=wrap_content
      │        layout_column=0  layout_weight=1.0  text=@string/port_forward → "Port Forward" / zh "端口转发"
      │        style="?android:listSeparatorTextViewStyle"
      ├─ TableRow  gravity=center_vertical  layout_marginTop=8.0dp
      │  ├─ TextView … text=@string/name → "Name:" / zh "名称:"
      │  └─ EditText  id=@id/name  w=0dp h=wrap_content  layout_weight=1.0  inputType=text
      ├─ TableRow  gravity=center_vertical  layout_marginTop=8.0dp
      │  ├─ TextView … text=@string/connection_colon → "Connection:" / zh "连接:"
      │  └─ Spinner  id=@id/connection_spinner  w=0dp h=36.0dp  layout_weight=1.0
      ├─ TableRow  gravity=center_vertical  layout_marginTop=8.0dp
      │  ├─ TextView … text=@string/mode_colon → "Mode:" / zh "模式:"
      │  └─ Spinner  id=@id/mode_spinner  w=0dp h=36.0dp  layout_weight=1.0
      ├─ TableRow  gravity=center_vertical  id=@id/row_local_port  layout_marginTop=8.0dp
      │  ├─ TextView … text=@string/port_from → "Port (from):" / zh "端口 (从):"
      │  └─ EditText  id=@id/local_port  w=wrap_content h=wrap_content
      │        maxEms=5 ems=5 maxLength=5 inputType=number
      ├─ TableRow  gravity=center_vertical  id=@id/row_remote_host
      │     visibility=gone  layout_marginTop=8.0dp
      │  ├─ TextView … text=@string/destination → "Destination:" / zh "目标:"
      │  └─ EditText  id=@id/remote_host  w=0dp h=wrap_content  layout_weight=1.0
      │        hint=@string/localhost → "127.0.0.1" / zh "127.0.0.1"  inputType=textVisiblePassword
      ├─ TableRow  gravity=center_vertical  id=@id/row_remote_port
      │     visibility=gone  layout_marginTop=8.0dp
      │  ├─ TextView … text=@string/port_to → "Port (to):" / zh "端口 (到):"
      │  └─ EditText  id=@id/remote_port  w=wrap_content h=wrap_content
      │        maxEms=5 ems=5 maxLength=5 inputType=number
      ├─ TableRow  gravity=center_vertical  id=@id/row_open_in_browser
      │     visibility=gone  layout_marginTop=8.0dp
      │  └─ CheckBox  id=@id/open_in_browser  textAppearance=?android:textAppearanceSmall
      │        textColor=@color/text_form  w=0dp h=wrap_content  layout_marginRight=5.0dp
      │        layout_weight=1.0  text=@string/open_in_browser → "Open in browser after connecting" / zh "连接后在浏览器打开"
      ├─ TableRow  gravity=center_vertical  id=@id/row_socks_explanation
      │     visibility=gone  layout_marginTop=8.0dp
      │  └─ TextView  id=@id/socks_explanation  textAppearance=?android:textAppearanceSmall
      │        textColor=@color/text_form  autoLink=web  paddingTop=8.0dp
      │        w=0dp h=wrap_content  layout_marginRight=5.0dp  layout_weight=1.0
      │        text=@string/socks_description →
      │          "\"Please note that due to Android security restrictions JuiceSSH is not able to automatically route your traffic through this dynamic forward.\n\nYou can find more information on how to make use of SOCKS forwarding within Android at http://juicessh.com/socks\""
      │          zh "\"请注意，由于 Android 的安全限制， JuiceSSH 无法自动通过动态转发代理你的流量\n\n你可以在这里查看如何在 Android 使用 SOCKS 转发流量 http://juicessh.com/socks\""
      └─ TableRow  gravity=center_vertical  id=@id/row_use_as_proxy
            visibility=gone  layout_marginTop=8.0dp
         └─ CheckBox  id=@id/use_as_proxy  w=0dp h=wrap_content  layout_marginRight=5.0dp
               layout_weight=1.0  text=@string/set_as_browser_proxy → "Set as browser proxy" / zh "设置为浏览器代理"
```

Row visibility is driven by the selected `Mode:` (local / remote / dynamic SOCKS).

### 8.4 Snippet editing — `res/layout/snippet_dialog.xml`

```
LinearLayout  orientation=vertical
    paddingLeft=@dimen/dialog_padding_left (16dp)
    paddingTop=@dimen/dialog_padding_top (16dp)
    paddingRight=@dimen/dialog_padding_right (16dp)
    paddingBottom=@dimen/dialog_padding_bottom (0dp)
    w=match_parent  h=wrap_content
├─ EditText  id=@id/nickname   w=match_parent h=wrap_content  hint=@string/nickname → "Nickname" / zh "昵称"
└─ EditText  id=@id/snippet_content  gravity=top  w=match_parent h=wrap_content
      hint=@string/example_snippet →
        "# Enter command or script to run\n# For example:\n\necho 'Hello world';\nexit 0;\n"
        zh "# 输入命令或脚本以运行\n# 示例: \n\necho 'Hello world';\nexit 0;\n"
      minLines=7  inputType=textMultiLine|textNoSuggestions
```

### 8.5 Multi-selector (group membership / mappings) — `res/layout/multi_selector.xml`

```
LinearLayout  orientation=vertical  w=match_parent h=match_parent  layout_marginTop=10.0dp
├─ TextView  id=@id/multi_selector_title
│     textAppearance=?android:textAppearanceMedium  textColor=@color/text_form #FF073642
│     w=match_parent h=wrap_content  layout_marginBottom=10.0dp          (text set in code)
└─ LinearLayout  orientation=vertical  id=@id/multi_selector_form  visibility=visible
      w=match_parent  h=0dp  layout_weight=1.0
      layout_marginLeft=16.0dp  layout_marginTop=5.0dp  layout_marginRight=16.0dp
   └─ Button  id=@id/multi_selector_add
         textSize=@dimen/text_button (16.0sp)  textColor=@android:color/white #FFFFFFFF
         background=@drawable/button  w=match_parent  h=36.0dp  onClick="addItem"
         (text set in code)
```

**`res/layout/multi_selector_item.xml`** — one row of the selector; inflated N times:

```
LinearLayout  gravity=center_vertical  orientation=horizontal
    w=match_parent  h=match_parent  layout_marginTop=5.0dp  layout_marginBottom=5.0dp
├─ Spinner  id=@id/multi_selector_spinner  w=0dp h=40.0dp  layout_weight=1.0
└─ Button   id=@id/multi_selector_remove
      textSize=12.0dp (dp!)  textColor=@android:color/white #FFFFFFFF
      background=@drawable/button  w=30.0dp h=30.0dp  text=@string/X → "X" / zh "X"
```

`res/layout/mapping_multi_selector_item.xml` also exists (EC2 mapping variant, uses
`@drawable/button`, `@string/contains` → **"Contains"** / zh "包含", and `@string/X` → **"X"** / zh "X").

---

## 9. Dialogs

All dialog content layouts wrap their children in a vertical `LinearLayout` with the same
padding quartet: **left 16dp, top 16dp, right 16dp, bottom 0dp**
(`dialog_padding_left/top/right/bottom` in §3), and `layout_width=match_parent`.

### 9.1 `res/layout/confirm_dialog.xml`

```
ScrollView  id=@id/scrollView  fitsSystemWindows=true  w=match_parent  h=wrap_content
└─ LinearLayout  orientation=vertical  id=@id/content
      paddingLeft=16dp paddingTop=16dp paddingRight=16dp paddingBottom=0dp
      w=match_parent h=wrap_content
   ├─ TextView  id=@id/message  w=match_parent h=wrap_content  style="?android:textAppearanceMedium"
   └─ CheckBox  id=@id/dont_show_again  w=match_parent h=wrap_content  layout_marginTop=16.0dp
         text=@string/dont_show_this_message_again → "\"Don't show this message again\"" / zh "不再显示"
```

### 9.2 `res/layout/text_prompt.xml`

```
LinearLayout  orientation=vertical  [16/16/16/0 dp padding]  w=match_parent  h=match_parent
└─ EditText  id=@id/text1  w=match_parent  h=wrap_content  inputType=textEmailAddress
```
No hint, no label, no text — set entirely in code.

### 9.3 `res/layout/new_group_prompt.xml`

```
LinearLayout  orientation=vertical  [16/16/16/0]  w=match_parent h=match_parent
└─ EditText  id=@id/text1  w=match_parent h=wrap_content
      hint=@string/group_name → "Group name" / zh "群组名称"
```

### 9.4 `res/layout/password_prompt.xml`

```
LinearLayout  orientation=vertical  [16/16/16/0]  w=match_parent h=match_parent
├─ EditText  id=@id/password  w=match_parent h=wrap_content  inputType=textPassword
└─ LinearLayout  orientation=horizontal  w=match_parent h=wrap_content  baselineAligned=false
   ├─ LinearLayout  gravity=left  orientation=horizontal  id=@id/showPasswordLayout
   │     clickable=true  w=wrap_content h=wrap_content  layout_marginLeft=10.0dp  layout_weight=0.5
   │  ├─ CheckBox  id=@id/showPassword  clickable=false  w/h=wrap_content  checked=false
   │  └─ TextView  textSize=10.0sp  w=wrap_content h=wrap_content
   │        text=@string/show_password → "Show Password" / zh "显示密码"
   └─ LinearLayout  gravity=right  orientation=horizontal  id=@id/rememberPasswordLayout
         clickable=true  w=wrap_content h=wrap_content  layout_marginRight=20.0dp  layout_weight=0.5
      ├─ CheckBox  id=@id/rememberPassword  clickable=false  w/h=wrap_content  checked=false
      └─ TextView  textSize=10.0sp  w=wrap_content h=wrap_content
            text=@string/remember_password → "Remember Password" / zh "记住密码"
```

Both `TextView`s have **no `textColor`** → they inherit the theme's default text colour.

### 9.5 `res/layout/pin_prompt.xml`

```
LinearLayout  orientation=vertical  [16/16/16/0]  w=match_parent h=match_parent
├─ LinearLayout  gravity=center  layout_gravity=center  orientation=horizontal  id=@id/holder
│     w=match_parent  h=wrap_content  layout_marginLeft=15.0dp  layout_marginRight=15.0dp
│     (PIN digit boxes are added programmatically)
└─ LinearLayout  gravity=left|center  orientation=horizontal  id=@id/showCharsLayout
      clickable=true  w=match_parent h=wrap_content  layout_marginLeft=10.0dp  baselineAligned=false
   ├─ CheckBox  id=@id/showChars  clickable=false  w/h=wrap_content  checked=false
   └─ TextView  textSize=10.0sp  w=wrap_content h=wrap_content  text=@string/show → "Show" / zh "显示"
```

### 9.6 `res/layout/numeric_pin_prompt.xml` — the PIN lock screen

Full-screen keypad (this is the `LockoutActivity` / security-lock UI). `_hdpi`/tablet variants
override sizes. Verified overrides:

* `res/layout-sw600dp/numeric_pin_prompt.xml`, `res/layout-sw360dp/…`,
  `res/layout-sw600dp-land/…`, `res/layout-sw360dp-land/…` → keypad cells **72×72dp**,
  `@id/message` and `@id/passphrase` **72dp** tall.
* `res/layout-land/numeric_pin_prompt.xml` → adds `android:padding="@dimen/activity_padding"` (16dp)
  on the root and reduces key `textSize` to **16.0sp** (from 20sp).

Base (`res/layout/`) sizes below:

```
LinearLayout  gravity=center  orientation=vertical
    background=@color/pinlock_background → #FF000000
    w=match_parent  h=match_parent
├─ TextView  id=@id/message  textColor=@color/primary_bold #FFFFE24C  gravity=center
│     w=match_parent  h=56.0dp          (72.0dp in layout-sw600dp sw360dp family)
│     text=@string/enter_your_pin_to_unlock → "Please enter your PIN to unlock JuiceSSH" / zh "请输入 PIN 来解锁 JuiceSSH"
├─ LinearLayout  orientation=horizontal  w=match_parent  h=wrap_content
│  ├─ FrameLayout  w=0dp h=wrap_content  layout_weight=1.0
│  ├─ EditText  id=@id/passphrase
│  │     enabled=false  textSize=24.0sp  textColor=@color/primary_bold #FFFFE24C  gravity=center
│  │     w=232.0dp  h=56.0dp (72dp sw600dp)  layout_weight=0.0  inputType=textPassword
│  │     text="disabled"                      ← literal placeholder string
│  └─ FrameLayout  w=0dp h=wrap_content  layout_weight=1.0
└─ TableLayout  gravity=center  w=match_parent  h=wrap_content
   ├─ TableRow gravity=center: Button button_1 tag=1 "1" | button_2 tag=2 "2" | button_3 tag=3 "3"
   ├─ TableRow gravity=center: Button button_4 tag=4 "4" | button_5 tag=5 "5" | button_6 tag=6 "6"
   ├─ TableRow gravity=center: Button button_7 tag=7 "7" | button_8 tag=8 "8" | button_9 tag=9 "9"
   └─ TableRow gravity=center:
        FontAwesomeTextView button_backspace  text=@string/icon_eraser (U+F12D)
        Button              button_0 tag=0 "0"
        FontAwesomeTextView button_ok         text=@string/ok → "OK" / zh "确定"
```

Every one of the 12 keypad cells:
`textSize=20.0sp` (16sp in `layout-land`), `textColor=@color/primary_bold` `#FFFFE24C`,
`gravity=center`, `background=@drawable/pin_button` (4dp oval ring),
`w=56.0dp h=56.0dp` (72×72dp in the sw600dp/sw360dp families), `layout_margin=16.0dp`.
Ids: `@id/button_1` … `@id/button_9`, `@id/button_0`, `@id/button_backspace`, `@id/button_ok`,
plus `@id/message`, `@id/passphrase`.
The `EditText` is `enabled=false` — it is a **display** for the masked PIN, not a real input;
taps come from the keypad buttons.

### 9.7 `res/layout/quick_connect_prompt.xml`

```
LinearLayout  orientation=vertical  [16/16/16/0]  w=match_parent h=match_parent
├─ LinearLayout  orientation=horizontal  w=match_parent h=wrap_content  layout_marginBottom=10.0dp
│  ├─ TextView  gravity=center  padding=10.0dp  w=wrap_content  h=40.0dp
│  │     text=@string/type_colon → "Type:" / zh "类型:"
│  └─ Spinner  id=@id/quickConnectType  w=match_parent  h=40.0dp
├─ EditText  id=@id/quickConnectHost  w=match_parent  h=wrap_content
│     layout_marginLeft=5.0dp  layout_marginBottom=10.0dp  inputType=textEmailAddress
└─ CheckBox  id=@id/saveCheckbox  w=match_parent  h=wrap_content  checked=true
      text=@string/save_for_future_use → "Save connection for future use" / zh "保存连接以供以后使用"
```

### 9.8 `res/layout/identity_prompt.xml`

```
LinearLayout  orientation=vertical  [16/16/16/0]  w=match_parent h=match_parent
└─ Spinner  id=@id/sp_identity  layout_gravity=center  w=match_parent  h=40.0dp
```

### 9.9 `res/layout/private_key_prompt.xml`

```
TabHost  id=@id/tabhost  w=match_parent  h=wrap_content
├─ TabWidget  id=@android:id/tabs  w=match_parent  h=50.0dp
└─ FrameLayout  gravity=center  id=@android:id/tabcontent
      paddingTop=60.0dp  paddingBottom=10.0dp  w=match_parent  h=wrap_content
   └─ LinearLayout  orientation=vertical  id=@id/content
         [16/16/16/0 dp padding]  w=wrap_content  h=wrap_content
```

Three tab pages are inflated into `@id/content` from:
* `private_key_prompt_generatepage.xml`
* `private_key_prompt_importpage.xml`
* `private_key_prompt_pastepage.xml`

**`private_key_prompt_importpage.xml`** (full file):

```
LinearLayout  orientation=vertical  id=@id/ll_importpagelayout  inputType=textNoSuggestions
    w=match_parent  h=wrap_content
├─ RadioGroup  orientation=vertical  id=@id/radiogroup_import_type  w=match_parent  h=wrap_content
│  ├─ RadioButton  id=@id/radio_file_path   textColor=@android:color/black  checked=true
│  │     w=wrap_content h=wrap_content  text=@string/file_path → "File Path" / zh "文件路径"
│  └─ RadioButton  id=@id/radio_smart_search  textColor=@android:color/black
│        w=wrap_content h=wrap_content  text=@string/smart_search → "Smart Search" / zh "智能搜索"
├─ AutoCompleteTextView  id=@id/ac_manual_import_path_text
│     paddingTop=20.0dp  paddingBottom=20.0dp  w=match_parent  h=wrap_content
│     hint=@string/enter_path_relative_to_sdcard → "Enter path (relative to SD card)" / zh "输入路径 (相对于SD卡)"
│     inputType=textUri
├─ ImageView  id=@id/iv_loading_smart_search  layout_gravity=center  visibility=gone
│     w=wrap_content h=wrap_content  layout_marginTop=10.0dp  src=@drawable/spinner_black_16
│     contentDescription=@string/this_is_a_loading_indicator → "This is a loading indicator" / zh "这是载入中的标志"
├─ TextView  id=@id/tv_loading_smart_search  gravity=center
│     paddingTop=5.0dp  paddingBottom=10.0dp  visibility=gone  w=match_parent  h=wrap_content
│     text=@string/searching → "Searching…" / zh "搜索中…"
├─ ListView  id=@id/lv_smart_search_suggestions  visibility=gone  w=match_parent  h=wrap_content
└─ TextView  id=@id/no_keys_found  textAppearance=?android:textAppearanceSmall  autoLink=web
      padding=8.0dp  visibility=gone  w=match_parent  h=wrap_content
      text=@string/no_private_keys_found →
        "\"No private keys found, please make sure your key is in OpenSSH format (not Putty generated PPK format)\nMore information in the FAQ at:\nhttp://juicessh.com/keys\""
```

*(The exact structure of `private_key_prompt_generatepage.xml` and `private_key_prompt_pastepage.xml`
was read at the string-reference level only; their referenced strings are:*
`form_key_format` = "Key Format:", `form_key_strength` = "Key Strength:",
`form_optional` = "(Optional)", `form_passphrase` = "Passphrase:",
`generating_key` = "Generating key…",
`juicessh_will_automatically_push_keys` = "JuiceSSH will automatically offer to push the public key
to your ~/.ssh/authorized_keys when you connect to a server with this identity.",
`you_can_export_key` = "Once generated, you can export the public key by long-pressing the identity
in the identity list. You will need to place it within the ~/.ssh/authorized_keys file of your
servers." *Their full attribute-level breakdown is left shallow — see §14.)*

### 9.10 `res/layout/new_identity_prompt.xml` (legacy identity dialog)

```
ScrollView  scrollbars=vertical  w=match_parent  h=match_parent
    layout_marginLeft=10.0dp  layout_marginRight=10.0dp
└─ LinearLayout  orientation=vertical  w=match_parent h=match_parent
   ├─ TableLayout  orientation=horizontal  w=match_parent h=match_parent
   │  ├─ TableRow  layout_marginTop=10.0dp
   │  │  ├─ TextView  textSize=18.0sp  textColor=#ff6c6c6c  layout_marginRight=5.0dp
   │  │  │     text=@string/nickname_colon → "Nickname:" / zh "昵称:"
   │  │  └─ EditText  id=@id/identityNickname_value  textSize=12.0sp  textColor=#ff6c6c6c
   │  │        w=0dp h=wrap_content  layout_weight=1.0  hint=@string/optional → "(Optional)"
   │  │        inputType=textNoSuggestions
   │  └─ TableRow  layout_marginTop=10.0dp
   │     ├─ TextView  textSize=18.0sp  textColor=#ff6c6c6c  text=@string/username_colon → "Username:"
   │     └─ EditText  id=@id/identityUsername_value  textSize=12.0sp  textColor=#ff6c6c6c
   │           w=0dp h=wrap_content  layout_weight=1.0  inputType=textNoSuggestions
   ├─ LinearLayout  orientation=horizontal  id=@id/show_password_clickable  clickable=true
   │     w=match_parent h=wrap_content  layout_marginTop=10.0dp
   │  ├─ TextView  textSize=18.0sp textColor=#ff6c6c6c marginRight=5dp  text="Password"   ← literal, not a @string
   │  └─ TextView  textSize=12.0sp textColor=#ff6c6c6c                    text="(show less)" ← literal
   ├─ LinearLayout  orientation=horizontal  id=@id/password_set_layout
   │     w=wrap_content h=wrap_content  layout_marginLeft=16.0dp  layout_marginTop=10.0dp
   │  ├─ Button  id=@id/password_clear_button  textSize=12.0sp  textColor=@android:color/white
   │  │     gravity=center  background=@drawable/button  padding=5.0dp
   │  │     w=wrap_content h=30.0dp  layout_marginRight=5.0dp  text=@string/clear → "Clear" / zh "清除"
   │  └─ TextView  id=@id/password_set_date  textSize=12.0sp  textColor=#ff6c6c6c
   │        text="Last Set: 4 days ago"                                          ← literal placeholder
   ├─ EditText  id=@id/edit_password  textSize=12.0sp  textColor=#ff6c6c6c  visibility=gone
   │     w=match_parent h=wrap_content  hint=@string/optional → "(Optional)"  inputType=textPassword
   ├─ LinearLayout  orientation=horizontal  id=@id/show_key_clickable  clickable=true  w=match_parent h=wrap_content
   │  ├─ TextView  textSize=18.0sp textColor=#ff6c6c6c marginRight=5dp  text="Private Key"    ← literal
   │  └─ TextView  id=@id/show_more_text  textSize=12.0sp textColor=#ff6c6c6c  text="(show more)" ← literal
   ├─ LinearLayout  orientation=horizontal  w=wrap_content h=wrap_content
   │  ├─ Button  id=@id/identityPrivateKey_button  textSize=12.0sp  textColor=#FFFFFFFF
   │  │     gravity=center  background=@drawable/button  padding=5.0dp
   │  │     w=wrap_content h=30.0dp  layout_marginRight=5.0dp  text=@string/clear
   │  └─ TextView  textSize=12.0sp  textColor=#ff6c6c6c  text="Last Set: 4 days ago"      ← literal
   ├─ RadioGroup  orientation=vertical  id=@id/radiogroup_import_type  visibility=gone
   │     w=match_parent h=wrap_content
   │  ├─ RadioButton  id=@id/radio_file_path   textColor=@android:color/black  checked=true
   │  │     text=@string/smart_search → "Smart Search" / zh "智能搜索"
   │  └─ RadioButton  id=@id/radio_smart_search  textColor=@android:color/black
   │        text=@string/paste → "Paste" / zh "粘贴"
   ├─ ImageView  id=@id/iv_loading_smart_search  layout_gravity=center  visibility=gone
   │     w=wrap_content h=wrap_content  layout_marginTop=10.0dp  src=@drawable/spinner_black_16
   │     contentDescription=@string/this_is_a_loading_indicator → "This is a loading indicator" / zh "这是载入中的标志"
   ├─ TextView  id=@id/tv_loading_smart_search  gravity=center  paddingTop=5.0dp paddingBottom=10.0dp
   │     visibility=gone  w=match_parent h=wrap_content  text=@string/searching → "Searching…"
   └─ FrameLayout  id=@id/lv_smart_search_suggestions  w=match_parent  h=wrap_content
```

Note the **radio button labels appear swapped** relative to their ids in the source
(`radio_file_path` is labelled "Smart Search", `radio_smart_search` is labelled "Paste").
That is exactly what `new_identity_prompt.xml` contains; reproduce or fix deliberately.

### 9.11 Legacy alert layouts

**`res/layout/alert_dialog_message.xml`**

```
ScrollView  id=@id/scrollView
    paddingLeft=14.0dp  paddingTop=2.0dp  paddingRight=10.0dp  paddingBottom=12.0dp
    w=match_parent  h=wrap_content
└─ LinearLayout  orientation=vertical  id=@id/content  w=match_parent  h=wrap_content
   └─ TextView  id=@id/message  textColor=#000000  padding=5.0dp  w=match_parent  h=wrap_content
         style="?android:textAppearanceMedium"
```

**`res/layout/alert_dialog_title.xml`**

```
TextView  id=@id/alertTitle  textColor=#000000  ellipsize=end
    layout_marginLeft=10.0dp  layout_marginTop=6.0dp  layout_marginRight=10.0dp  layout_marginBottom=9.0dp
    w=match_parent  h=wrap_content  singleLine=true  style="?android:textAppearanceLarge"
```

These are Holo-era fallbacks with hard-coded `#000000` text (illegible on the dark theme) —
still shipped in the APK.

### 9.12 `res/layout/custom_dialog.xml`

```
RelativeLayout  w=match_parent  h=match_parent
└─ Button  id=@id/dialog_button  w=100.0px  h=wrap_content
      layout_marginTop=5.0dp  layout_marginRight=5.0dp  text=" Ok "   ← literal with surrounding spaces
```

---

## 10. Action bars — every menu, every item

All items below have **no `android:orderInCategory`** unless stated, and **no `android:icon`**
unless stated. `app:showAsAction` values are reproduced verbatim; a missing attribute means the
platform default (`never` for `Menu` items in AppCompat is effectively "overflow", but the
literal default is `never`).

| Menu file | Item id | Title (key → EN / zh-CN) | Icon | showAsAction | Screen it belongs to |
|---|---|---|---|---|---|
| `menu_base.xml` | `menu_item_faq` | `view_our_faq` → "View our FAQ" / "查看常见问题 (FAQ)" | `@drawable/ic_help` | `ifRoom` | Base/inherited menu; item is `android:visible="false"` |
| `menu_home.xml` | `menu_item_faq` | `view_our_faq` → "View our FAQ" / "查看常见问题 (FAQ)" | `@drawable/ic_help` | `never` | `MainActivity` |
| | `menu_rate_juicessh` | `rate_juicessh` → "Rate JuiceSSH" / "给 JuiceSSH 打分" | — | `never` | |
| `menu_addressbook_connections.xml` | `menu_item_new_connection` | `new_connection` → "New Connection" / "新建连接" | — | `never` | `AddressBookActivity`, Connections page (`visible=false`) |
| | `menu_item_new_group` | `new_group` → "New Group" / "新建连接组" | — | `never` | |
| `menu_addressbook_identities.xml` | `menu_item_new_identity` | `new_identity` → "New Identity" / "新建认证" | `@drawable/ic_new` | `ifRoom` | `AddressBookActivity`, Identities page (`visible=false`) |
| `menu_addressbook_portforwards.xml` | `menu_item_new_portforward` | `new_port_forward` → "New Port Forward" / "新建端口转发" | `@drawable/ic_new` | `ifRoom` | `AddressBookActivity`, Port Forwards page (`visible=false`) |
| `menu_manage_connection.xml` | `menu_item_save` | `save` → "Save" / "保存" | `@drawable/ic_accept` | `ifRoom` | `ManageConnectionActivity` |
| `menu_manage_identity.xml` | `menu_item_save` | `save` → "Save" / "保存" | `@drawable/ic_accept` | `ifRoom` | `ManageIdentityActivity` |
| `menu_manage_group.xml` | `menu_item_save` | `save` → "Save" / "保存" | `@drawable/ic_accept` | `ifRoom` | `ManageGroupActivity` |
| `menu_manage_portforward.xml` | `menu_item_save` | `save` → "Save" / "保存" | `@drawable/ic_accept` | `ifRoom` | `ManagePortForwardActivity` |
| `menu_manage_snippets.xml` | `menu_item_new_snippet` | `new_snippet` → "New Snippet" / "新代码片段" | `@drawable/ic_new` | `ifRoom` | `ManageSnippetsActivity` |
| `menu_manage_share.xml` | `menu_item_save` | `save` → "Save" / "保存" | `@drawable/ic_accept` | `ifRoom` | `ManageShareActivity` |
| `menu_manage_team.xml` | `menu_item_save` | `save` → "Save" / "保存" | `@drawable/ic_accept` | `ifRoom` | `ManageTeamActivity` (Pro) |
| `menu_manage_ec2_profile.xml` | `menu_item_save` | `save` → "Save" / "保存" | `@drawable/ic_accept` | `ifRoom` | `ManageEc2ProfileActivity` (Pro) |
| | `menu_item_add_mapping` | `add_mapping` → "Add Mapping" / "新建映射" | — | `never` | |
| `menu_manage_ec2_mapping.xml` | `menu_item_save` | `save` → "Save" / "保存" | `@drawable/ic_accept` | `ifRoom` | EC2 mapping editor (Pro) |
| | `menu_item_remove_mapping` | `remove_this_mapping` → "Remove This Mapping" / "移除映射" | — | `never` | |
| `menu_widget_configure.xml` | `menu_item_save` | `save` → "Save" / "保存" | `@drawable/ic_accept` | `ifRoom` | `ConfigureWidgetActivity` |
| `menu_log_viewer.xml` | `menu_item_refresh` | `refresh` → "Refresh" / "刷新" | `@drawable/ic_refresh_white` | `ifRoom` | `LogViewerActivity` |
| | `menu_item_email` | `email_logs` → "Email Logs" / "发送日志" | `@drawable/ic_share_white` | `ifRoom` | |
| `menu_settings.xml` | *(none)* | — | — | — | `SettingsActivity` — **empty `<menu />`** |
| `menu_teamshare_invites.xml` | *(none)* | — | — | — | TeamShare invites (Pro) — empty `<menu />` |
| `menu_bookclub.xml` | `menu_item_remove_booklub` | `remove_bookclub` → "Disable Tech Library" / "禁用技术库" | — | `never` | `BookclubActivity` |
| `menu_teamshare_team.xml` | `update_api_key` | `change_team_password` → "Change team password" / "修改团队密码" | — | *(unset)* | TeamShare team (Pro) |
| | `rename` | `rename_team` → "Rename team" / "重命名团队" | — | *(unset)* | |
| | `leave` | `leave_team` → "Leave team" / "离开团队" | — | *(unset)* | |
| | `delete` | `delete_team` → "Delete team" / "删除团队" | — | *(unset)* | |

### 10.1 Context menus (long-press on list rows)

These use only `android:id` + `android:title` + `android:orderInCategory="100"`; no icons,
no `showAsAction`.

| Menu file | Items (id → title) | Applies to |
|---|---|---|
| `connection_context_menu.xml` | `edit` → "Edit" / "编辑"; `duplicate` → "Duplicate" / "重复"; `share` → "Share" / "分享"; `clearHistory` → "Clear history" / "清除历史"; `homescreen` → "Homescreen shortcut" / "主屏快捷方式"; `delete` → "Delete" / "删除" | long-press a connection row |
| `group_context_menu.xml` | `edit` → "Edit"; `share` → "Share"; `delete` → "Delete" | long-press a connection group header |
| `identity_context_menu.xml` | `edit` → "Edit"; `export_private_key` → "Export Private Key" / "导出私钥"; `export_public_key` → "Export Public Key" / "导出公钥"; `delete` → "Delete" | long-press an identity row |
| `port_forward_context_menu.xml` | `edit` → "Edit"; `duplicate` → "Duplicate"; `homescreen` → "Homescreen shortcut"; `delete` → "Delete" | long-press a port-forward row |
| `snippet_context_menu.xml` | `edit` → "Edit"; `delete` → "Delete" | long-press a snippet row |
| `ec2_profile_context_menu.xml` | `sync_now` → "Sync Now" / "立即同步"; `edit` → "Edit"; `delete` → "Delete" | long-press an EC2 profile (Pro) |
| `team_member_context_menu.xml` | `remove` → "Remove" / "移除" | long-press a team member (Pro) |

### 10.2 Toolbar geometry (framework)

`actionBarStyle` → `Widget.AppCompat.Light.ActionBar.Solid.Inverse`, height
`@dimen/abc_action_bar_default_height_material` = **56dp** (landscape override **48dp**,
sw600dp **64dp**). Title text is white `#FFFFFFFF` at **24sp bold**; overflow icon is
`ic_action_overflow` at mdpi 16×16, hdpi 24×24, xhdpi 32×32, xxhdpi 48×48 px; up indicator is
`ic_arrow_back_white_24dp` at mdpi 24×24, xhdpi 48×48, xxhdpi 72×72 px.

---

## 11. Drawable inventory (used by the screens above)

| Drawable | Type | Dims / size | Depicts |
|---|---|---|---|
| `ic_new` | PNG | ldpi 24×24, mdpi 32×32, hdpi 48×48, xhdpi 64×64 | White "plus" — FAB / "new" action bar item |
| `ic_accept` | PNG | ldpi 24×24, mdpi 32×32, hdpi 48×48, xhdpi 64×64 | White check mark — Save |
| `ic_help` | PNG | ldpi 24×24, mdpi 32×32, hdpi 48×48, xhdpi 64×64 | Question mark — FAQ |
| `ic_action_overflow` | PNG | mdpi 16×16, hdpi 24×24, xhdpi 32×32, xxhdpi 48×48 | Three vertical dots — action-bar overflow |
| `ic_arrow_back_white_24dp` | PNG | mdpi 24×24, xhdpi 48×48, xxhdpi 72×72 | White back arrow — action-bar up indicator |
| `ic_ab_back_holo_light` | PNG | mdpi 16×16, hdpi 24×24, xhdpi 32×32 | Back chevron — `indicated_page` left indicator |
| `ic_ab_forward_holo_light` | PNG | mdpi 16×16, hdpi 24×24 | Forward chevron — `indicated_page` right indicator |
| `ic_refresh_white` | PNG | ldpi 24×24, mdpi 32×32, hdpi 48×48, xhdpi 64×64 | White circular refresh arrow |
| `ic_share_white` | PNG | ldpi 24×24, mdpi 32×32, hdpi 48×48, xhdpi 64×64 | White share glyph |
| `ic_undo` | PNG | ldpi 24×24, mdpi 32×32, hdpi 48×48, xhdpi 64×64 | Curved back arrow — `prev_keyboard` |
| `ic_lockscreen_ime` | PNG | mdpi 30×29, hdpi 45×45, xhdpi 60×60 | Keyboard show/hide — `keyboard_toggle` |
| `ic_action_search` | PNG | mdpi 32×32, hdpi 48×48, xhdpi 64×64 | Magnifier — `frequently_used_item` `android:icon` |
| `ic_contact_picture` | PNG | ldpi 41×41, mdpi 64×64, hdpi 96×96, xhdpi 128×128 | Generic contact/avatar placeholder — `spinner_item` |
| `ic_menu_btn_add` | PNG | mdpi 32×32, hdpi 48×48, xhdpi 64×64 | Legacy "add" menu icon — widget |
| `ic_menu_manage` | PNG | ldpi 36×36, mdpi 32×32, hdpi 48×48, xhdpi 64×64 | Legacy "settings/manage" — widget + `manage_team.xml` |
| `ic_menu_refresh` | PNG | ldpi 36×36, mdpi 32×32, hdpi 48×48, xhdpi 64×64 | Legacy refresh — widget |
| `ic_launcher` | PNG / adaptive XML | mdpi 48×48, hdpi 72×72, xhdpi 96×96, xxhdpi 144×144; `mipmap-anydpi/ic_launcher.xml` 271 B | App icon; also the `connecting`/`loading`/`lockout` 100dp hero image |
| `new_banner` | PNG | **128×128 px**, 12187 B (only in `drawable/`, no density variants) | Orange "NEW" corner banner — `card_list_item` `@id/banner` (72×72dp) |
| `warning` | PNG | xhdpi 64×64 (only xhdpi exists) | Warning triangle — `error.xml` `@id/errorImage` |
| `spinner_black_16` | PNG | ldpi 12×12, mdpi 16×16, hdpi 24×24, xhdpi 32×32 | Black indeterminate spinner — "searching" indicators |
| `widget_background` | `.9.png` | mdpi 187 B, hdpi 232 B, xhdpi 298 B | Widget rounded background |
| `keyboard` | selector XML | — | see §6.3 |
| `keyboard_highlighted` | selector XML | — | see §6.3 |
| `highlight` | empty selector | — | no-op row divider/background |
| `card_item` | ripple | — | `@color/card_item_pressed` |
| `button` | ripple+shape | — | see §2.7 |
| `button_white` | ripple | — | `@color/accent_lighter` |
| `button_transparent` | selector | — | see §2.7 |
| `pin_button` / `pin_button_pressed` / `pin_button_unpressed` | selector / layer-list | — | see §2.7 |
| `loading_screen` | shape | — | see §2.3 |
| `selectable_background_juicessh`, `list_focused_juicessh`, `list_pressed_juicessh` | selector / `.9.png` | — | see §2.7 |

Fonts shipped in `assets/fonts/` (used by the `terminal:font` setting; all "Nerd Font Complete"):

| File | Size |
|---|---|
| `Caskaydia.Cove.Regular.Nerd.Font.Complete.Mono.otf` | 3 410 624 B |
| `Droid.Sans.Mono.Nerd.Font.Complete.otf` | 2 096 384 B |
| `Fira.Code.Regular.Nerd.Font.Complete.ttf` | 1 149 928 B |
| `Inconsolata.Nerd.Font.Complete.Mono.otf` | 3 222 768 B |
| `JetBrains.Mono.Regular.Nerd.Font.Complete.Mono.ttf` | 934 260 B |
| `OpenDyslexic.Regular.Nerd.Font.Complete.Mono.otf` | 3 207 184 B |
| `Roboto.Mono.Nerd.Font.Complete.Mono.ttf` | 935 784 B |
| `Sauce.Code.Pro.Nerd.Font.Complete.ttf` | 969 780 B |
| `fontawesome-webfont.ttf` | 79 076 B |

### 11.1 FontAwesome glyph map (from `res/values/strings.xml`)

`views/FontAwesomeTextView` (smali) sets `Typeface.createFromAsset(getAssets(),
"fonts/fontawesome-webfont.ttf")`, so these string values render as icons:

| String key | Codepoint | Glyph |
|---|---|---|
| `icon_globe` | `U+F0AC` | globe — connection/list-row default icon |
| `icon_user` | `U+F007` | user — identity rows |
| `icon_share_alt` | `U+F064` | share — port-forward rows |
| `icon_warning_sign` | `U+F071` | warning triangle — `card_list.xml` error state |
| `icon_eraser` | `U+F12D` | eraser — numeric PIN backspace |
| `icon_check` | `U+F046` | check — purchase feature list |
| `icon_refresh` | `U+F021` | refresh |
| `icon_plus` | `U+F067` | plus |
| `icon_search` | `U+F002` | magnifier |
| `icon_hdd` | `U+F0A0` | hard drive |
| `icon_lock` | `U+F023` | padlock |
| `icon_cog` | `U+F013` | gear |
| `icon_wrench` | `U+F0AD` | wrench |
| `icon_bolt` | `U+F0E7` | lightning |
| `icon_exchange` | `U+F0EC` | exchange arrows |
| `icon_folder_open` | `U+F07C` | open folder |
| `icon_save` | `U+F0C7` | floppy disk |
| `icon_play` | `U+F04B` | play triangle |
| `icon_stop` | `U+F04D` | stop square |
| `icon_chevron_right` | `U+F054` | chevron right |
| `icon_chevron_down` | `U+F078` | chevron down |
| `icon_caret_down` | `U+F0D7` | caret down |
| `icon_caret_right` | `U+F0DA` | caret right |

*(`icon`, `icon_menu`, `icon_times`, `icon_power_off` are not FontAwesome glyphs / not present:
`icon` = the literal word "Icon" (accessibility), and the other three keys do not exist in
`res/values/strings.xml`.)*

---

## 12. Splash / loading / error scaffolds

**`res/layout/loading.xml`** (app boot)

```
LinearLayout  orientation=vertical  background=@color/primary_darker #FFF0D235
    fitsSystemWindows=true  w=match_parent h=match_parent
└─ LinearLayout  orientation=vertical  background=@drawable/loading_screen
      fitsSystemWindows=true  clipToPadding=false  w=match_parent h=match_parent
   ├─ FrameLayout  background=@color/transparent  w=match_parent h=0dp  weight=1.2
   ├─ RelativeLayout  layout_gravity=center  w=match_parent  h=0dp  weight=1.5
   │  └─ ImageView  id=@id/loading_icon  w=100.0dp h=100.0dp  src=@drawable/ic_launcher
   │        layout_centerInParent=true  contentDescription=@string/app_name → "JuiceSSH"
   └─ LinearLayout  gravity=center_horizontal  orientation=vertical
         w=match_parent  h=0dp  weight=1.8
      ├─ TextView  id=@id/loading_title  textSize=26.0sp  textStyle=bold
      │     textColor=@android:color/white #FFFFFFFF  gravity=center_horizontal
      │     w=match_parent h=wrap_content  text=@string/app_name → "JuiceSSH"
      └─ TextView  id=@id/loading_subtitle  textSize=12.0sp  textStyle=italic
            textColor=@android:color/darker_gray  gravity=center_horizontal
            w=match_parent h=wrap_content  text=@string/loading_dot_dot_dot → "Loading…" / zh "载入中…"
```

**`res/layout/connecting.xml`** — same structure, weights `1.6 / 1.6 / 1.8`, and the bottom block is:

```
   └─ LinearLayout  gravity=center_horizontal  orientation=vertical  w=match_parent h=0dp weight=1.8
      ├─ TextView  id=@id/loading_title  textSize=26.0sp bold  textColor=@android:color/white
      │     gravity=center_horizontal  w=match_parent h=wrap_content
      │     text=@string/connecting → "Connecting…" / zh "连接中…"
      ├─ LinearLayout  gravity=center  orientation=horizontal
      │     w=match_parent h=wrap_content  layout_marginTop=20.0dp
      │  ├─ ProgressBar  id=@id/progressbar  w=15.0dp h=match_parent
      │  │     layout_marginLeft=0.0dp  layout_marginRight=5.0dp  indeterminate=true
      │  │     style="@android:style/Widget.ProgressBar.Small"
      │  └─ TextView  id=@id/subtitle  textSize=12.0sp italic  textColor=@android:color/darker_gray
      │        gravity=center_horizontal  w=wrap_content h=wrap_content
      │        text=@string/establishing_connection → "Establishing connection" / zh "建立连接中"
      └─ TextView  id=@id/log_text  textSize=9.0sp  typeface=monospace
            textColor=#99ffffff  gravity=left|bottom
            w=match_parent h=match_parent  layout_marginTop=20.0dp
```

**`res/layout/lockout.xml`** — weights `1.8 / 2.0 / 1.8`, same as `connecting.xml` minus the
progress row:

* title = `@string/locked_out` → "Locked Out" / zh "锁定"
* subtitle = `@string/too_many_incorrect_security_lock_attempts` →
  "\"Too many incorrect security lock attempts\nPlease try again in %s\"" /
  zh "\"失败次数过多\n请等待 %s 后重试\"" (a `%s` placeholder, substituted with the time remaining)

**`res/layout/error.xml`**

```
LinearLayout  gravity=center  orientation=vertical  w=match_parent  h=match_parent
├─ ImageView  id=@id/errorImage  w=wrap_content h=wrap_content  src=@drawable/warning
│     contentDescription=@android:string/dialog_alert_title   (framework string)
└─ TextView  id=@id/errorText  textColor=#9e9e9e  gravity=center
      w=wrap_content  h=wrap_content
      layout_marginLeft=40.0dp  layout_marginTop=10.0dp  layout_marginRight=40.0dp
```

**`res/layout/card_list.xml`** — a full-screen list scaffold with loading and error overlays:

```
FrameLayout  orientation=vertical  fitsSystemWindows=true  w=match_parent h=match_parent
└─ RelativeLayout  w=match_parent  h=match_parent
   ├─ ListView  id=@id/list  padding=@dimen/card_list_padding (16dp)  visibility=visible
   │     clipToPadding=false  w=match_parent h=match_parent
   │     divider=#00000000  dividerHeight=@dimen/card_list_divider (16dp)
   ├─ LinearLayout  gravity=center  orientation=vertical  id=@id/loading_layout
   │     padding=16.0dp  focusable=false  focusableInTouchMode=false
   │     visibility=gone  clickable=false  w=match_parent h=match_parent
   │  ├─ ProgressBar  w=50.0dp  h=50.0dp
   │  └─ TextView  textSize=18.0sp  textStyle=bold  textColor=@color/text_item_subtitle #FF586E75
   │        gravity=center_horizontal  padding=8.0dp  w=match_parent h=wrap_content
   │        text=@string/loading_dot_dot_dot → "Loading…" / zh "载入中…"
   └─ LinearLayout  gravity=center  orientation=vertical  id=@id/error_layout
         padding=16.0dp  focusable=false  focusableInTouchMode=false
         visibility=gone  clickable=true  w=match_parent h=match_parent
      ├─ com.sonelli.juicessh.views.FontAwesomeTextView  textSize=50.0dp (dp!)
      │     textColor=@color/icon_item #FF586E75  gravity=center_horizontal  padding=8.0dp
      │     clickable=false  w=match_parent h=wrap_content
      │     text=@string/icon_warning_sign (U+F071)
      ├─ TextView  textSize=18.0sp  textStyle=bold  textColor=@color/text_item_title #FF073642
      │     gravity=center_horizontal  padding=8.0dp  clickable=false
      │     w=match_parent h=wrap_content
      │     text=@string/an_error_has_occurred → "An error has occurred" / zh "发生错误"
      └─ TextView  id=@id/error_message  textSize=14.0sp  textColor=@color/text_item_subtitle #FF586E75
            gravity=center_horizontal  padding=8.0dp  clickable=false
            w=match_parent h=wrap_content
            text=@string/please_try_again_later → "Please try again later" / zh "请稍后重试"
```

`res/layout/blank.xml` is a bare vertical `LinearLayout` with `match_parent`/`match_parent` and no
children — a placeholder page.

---

## 13. Terminal auto-complete strip

`res/layout/autocomplete_box.xml`:

```
<com.sonelli.juicessh.views.TerminalAutoCompleteBox
    android:textSize="12.0dp"          ← dp!, should be sp
    android:gravity="center"
    android:paddingLeft="4.0dp"  android:paddingTop="0.0dp"
    android:paddingRight="4.0dp" android:paddingBottom="35.0dp"
    android:focusable="true"  android:focusableInTouchMode="true"
    android:layout_width="match_parent"  android:layout_height="84.0dp"
    android:hint="@string/use_this_to_enter_text" />
```

`@string/use_this_to_enter_text` = "\"Use this text box to input autocompleted text.\nSwipe left
to return to the popup keyboard.\"" / zh "\"这个文本框提供自动补全功能\n左滑返回弹出键盘\"".

The **35dp bottom padding** is deliberate: it keeps the caret clear of the 35dp key row below.
`android:textCursorDrawable="@null"` removes the caret handle.
`inputType="textLongMessage|textMultiLine"`, `imeOptions="actionDone"`.
`views/TerminalAutoCompleteBox` and `views/TerminalAutoCompleteBox$a`/`$a$a` implement the
suggestion popup (`res/layout/` contains no separate popup layout for it).

---

## 14. Shallow / not covered

The following were **not** read attribute-by-attribute and should be treated as shallow:

* `res/layout/tutorial_terminal.xml` (+ `layout-sw360dp` / `layout-sw600dp` variants) — first-run
  terminal tutorial. Referenced strings (resolved from `res/values/strings.xml`):
  `tutorial` = "Tutorial"; `tap_the_terminal` = "Tap the terminal to bring up a popup keyboard with
  all the normally hard to find characters (ctrl, arrows etc). Swipe it right to enable/disable
  autocomplete (useful for IRC etc)."; `long_press_the_terminal` = "Long press the terminal for
  copy & paste and to share or save your session transcript."; `popup_keyboard` = "Popup Keyboard";
  `font_size` = "Font size"; `copy_paste_share_save` = "Copy & Paste / Save Transcript / Hide
  Keyboard"; `use_the_volume` = "Use the volume buttons on your device to adjust the font size on
  the fly."; `ok_i_got_it` = "\"OK - I've got it!\""; `@drawable/button_transparent`.
* `res/layout/private_key_prompt_generatepage.xml` and `private_key_prompt_pastepage.xml` —
  full attribute breakdown not captured (strings only, §9.9).
* Pro/team/share screens: `purchase.xml`, `teamshare.xml`, `manage_team.xml`,
  `team_member_prompt.xml`, `invite_menu_item.xml`, `team_member_menu_item.xml`,
  `teamshare_menu_item.xml`, `manage_share.xml`, `manage_cloudsync_*.xml`,
  `ec2profiles.xml`, `manage_ec2profile*.xml`, `bookclub_card_content.xml`,
  `license_*.xml`, `plugin_card_content.xml`, `signin.xml`, `signin_failed.xml`,
  `reauthenticate.xml`, `changelog.xml`, `thank_you_for_purchasing.xml`,
  `authentication_migration.xml`, `email_prompt.xml`, `log_viewer.xml`, `copy_instructions_*.xml`,
  `centered_progress_spinner.xml`, `license_view.xml`, `card_text_content.xml`,
  `tutorial_terminal.xml`, `widget_*.xml`.
* `res/layout-watch/` — contains **no** JuiceSSH layouts.
* `res/values-zh-rCN/colors.xml` (1 450 B) and `res/values-zh-rCN/styles.xml` (3 817 B) were
  **not read**; only `values-zh-rCN/strings.xml` was used for translations.
* The `PagerAdapter` page titles (Connections / Identities / Port Forwards) are set in Java and do
  not appear in any layout — `UNRESOLVED: exact page title strings and the tab-strip indicator colour`.
* List-row `itemTitle`/`itemSubtitle` **runtime content** (connection nicknames, `user@host`,
  `via <connection>`, "Connected N times") is assembled in the adapters
  (`views/CardListItem*.smali`); only the static placeholder strings are documented.
* `android:textAppearanceSmall`, `android:textAppearanceMedium`, `android:textAppearanceLarge`,
  `?android:listSeparatorTextViewStyle`, `?android:buttonBarPositiveButtonStyle`,
  `?android:buttonBarNegativeButtonStyle`, `?spinnerDropDownItemStyle`,
  `?android:listPreferredItemHeight` are **framework/AppCompat attributes**; their concrete
  text sizes, paddings and backgrounds are not defined in this APK and are therefore
  `UNRESOLVED` where noted.
* `.9.png` nine-patch padding/stretch regions were not decoded — file sizes are reported instead.
* `res/values-hdpi/styles.xml` and `res/values-v28/styles.xml` / `values-land/styles.xml` /
  `values-large/styles.xml` / `values-sw600dp/styles.xml` / `values-watch/styles.xml`
  overrides were not read (the `values-night` ones were).
