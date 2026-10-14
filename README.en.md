[繁體中文](README.md) | **English**

# Battery & System Monitor (macbookBatteryMonitor)

A macOS menu bar app for battery and system information. On a MacBook the menu bar shows the charge level; click it to see time remaining, battery health, power flow (expandable down to individual components), a charge limit slider, smart charging, history charts, a daily recap, the apps using the most energy, and the battery levels of Bluetooth keyboards, mice and headphones. Desktop Macs (Mac mini, iMac, Mac Studio and so on) show system power instead. Optional system monitor modules cover CPU/GPU (with fans and temperatures), memory, disks (including external drives) and network.

The app's interface is in Traditional Chinese.

- **One app for every Mac** (v1.7.1+): Apple silicon and Intel, MacBooks and desktop Macs use the same download, which decides by itself whether to show the battery or system power. Macs on macOS 12 or 13 have a separate build
- **System monitors on or off** (v1.7.1+): the first launch asks whether you want the battery only or battery plus system monitors; switch any time in Settings → System monitors. With them off, none of the four modules sample anything, as light as the former battery edition
- **Charge limit slider**: drag the slider in the info card to change the macOS charge limit (80–100%). It is the same setting as in System Settings and stays in sync; no admin rights needed (v1.6.0+)
- **Smart charging** (v1.7.1+): choose "charged to X% by a time" (in 1/2/3 hours, a custom time or a weekly schedule). The Mac stays at a care limit, the limit is raised just in time for macOS to charge to the target, and your original limit is restored afterwards
- **Charging companion** (v1.7.1+): an animated cat next to the charge limit slider that breathes and swishes its tail, and lies on a glowing charging pad while charging. You can switch it to a battery buddy whose face follows the charging state, or a simple energy bar. MacBooks that can't change the charge limit (such as Intel models) show it at the top of the panel too, just without the slider
- **Today** (v1.7.1+): how much battery you used and charged today, how many times you plugged in, and how long you ran on battery
- **No hidden charging control**: the app only changes the macOS charge limit when you drag the slider (the same as doing it in System Settings) or when you set up smart charging; macOS does the actual charging. No admin rights by default; only the optional admin CPU sampling and the smart charging "precise wake" ask for authorization
- **Updates every second**: the menu bar and panel refresh every second by default (2, 5 or 10 seconds in Settings). With the panel closed CPU use is about 0.2% (battery only) or about 1% (all four system monitors), and the app never keeps the Mac awake
- **Power saving mode**: static power flow icons, at most one update every 2 seconds, and no companion animation; can apply only while on battery (v1.7.1+)
- **Pick what to show**: power flow details (display backlight, chip, CPU/GPU/ANE) and detail fields can be hidden one by one; ANE and backlight hide automatically on Macs that don't report them
- **One-click update**: when a new version is out, one click downloads, verifies and installs it (v1.5.0+). New versions trigger a notification you can turn off (v1.7.1+). Manual checks also find beta releases, which ask for confirmation before installing (v1.7.1+)
- **No Xcode needed**: Command Line Tools are enough to build it

## Download

From [Releases](https://github.com/sgeric910601/macbookBatteryMonitor/releases):

| Your Mac | File |
|---|---|
| macOS 14 or later (Apple silicon or Intel, laptop or desktop) | `macbookBatteryMonitor-<version>-macOS-universal.zip` (universal) |
| macOS 12 or 13 (Apple silicon or Intel) | `macbookBatteryMonitor-<version>-macOS12.zip` (older systems) |

- From v1.7.1 there is a single app: choose battery only or battery plus system monitors on first launch and switch later in Settings. The `…-battery-macOS-arm64.zip` and `…-status-macOS-arm64.zip` files in newer releases only exist for the one-click update of v1.6.2 and earlier; their content is the same as the universal build
- The older-systems build is for Macs on macOS 12 or 13 (for example 2015–2017 MacBooks, or older Macs upgraded with OpenCore Legacy Patcher) and has the same features. Once the system is on macOS 14 or later, one-click update switches to the universal build
- Already on v1.5.0 or later? Settings → Update → "一鍵更新" (one-click update) installs it

| | Battery only | Battery plus system monitors |
|---|---|---|
| How to choose | On first launch; later turn off Settings → System monitors | On first launch; later turn on Settings → System monitors |
| Battery (system power on desktops), power flow, charge limit, smart charging, notifications | ✓ | ✓ |
| CPU/GPU, memory, disk, network modules | — | ✓ (one menu bar icon each, each can be turned off; fans, temperatures and external drives included) |
| Peripheral battery levels with per-device alerts, Today recap | ✓ | ✓ |
| Update interval (1/2/5/10 s), power saving mode | ✓ | ✓ |
| One-click update, update notifications, app icon colors | ✓ | ✓ |
| CPU with the panel closed | about 0.2% | about 1% (all four modules) |
| CPU with the panel closed, power saving | about 0.15% | about 0.5% (all four modules) |

The app is called "電池與系統監控" (shown as Battery & System Monitor on English systems); the app folder is `macbookBatteryMonitor.app`. Upgrading from v1.6.x doesn't ask anything: the former battery edition stays battery only and the system monitor edition keeps its monitors on. If you only see the battery icon, check the master switch in Settings → System monitors; on MacBooks with a notch macOS may also hide icons that don't fit, so turn off the modules you don't need.

### Battery only

![Battery only: menu bar battery icon and the battery panel, with the charging companion beside the charge limit slider and the smart charging status below it](docs/screenshots/edition-battery.png)

### Battery plus system monitors

![Battery plus system monitors: CPU/GPU, memory, disk and network menu bar icons with their panels, including fans, temperatures and external drives](docs/screenshots/edition-status.png)

### Smart charging and Today

![Smart charging: plugged in and held at an 80% care limit, charged to the original 95% limit by 7:30 tomorrow; the Today recap on the left and the smart charging page on the right](docs/screenshots/smart-charging.png)

### Desktop Macs

Macs without a battery (Mac mini, iMac, Mac Studio, Mac Pro) show a computer icon with system power in the menu bar. The panel shows system power with a 3-minute average, a power breakdown (chip, CPU/GPU/ANE, other), power history, the most energy-hungry apps and peripherals. Battery notifications, the charge limit and smart charging are hidden in Settings.

![Desktop Mac: system power in the menu bar and the power breakdown panel](docs/screenshots/desktop.png)

### Intel Macs

From v1.7.1, Intel Macs are supported (the universal build needs macOS 14 or later, roughly 2018 models and newer; older ones use the macOS 12 build). Tested on a 2018 Mac mini (Intel Core i5-8500B, macOS 15):

- **Temperatures**: per-core SMC keys for the CPU (from `TC1C`; cores that report -127 are skipped), falling back to PECI/die/proximity (`TCXC`, `TC0F`, `TC0P`); integrated GPU `TCGC`, discrete GPU `TG0D`/`TG0P`; SSD `TH0a`/`TH0b`; MacBook battery `TB0T` and siblings
- **CPU and integrated GPU power**: SMC `PCPC`/`PCPG` (signed 8.7 fixed point), no admin password needed, so Intel Macs don't show admin CPU sampling
- **GPU memory**: Intel integrated graphics report `inUseSysMemoryBytes`; occasional overflow values (larger than physical memory) under load are dropped
- Intel Macs can't change the charge limit from an app, so there is no charge limit slider and no smart charging; the charging companion still sits at the top of the panel, and clicking it lets you change its look
- Intel MacBooks were tested on a 2015 MacBook Air (macOS 13, using the macOS 12 build): level, voltage, current, cycle count and capacity match `pmset` and `ioreg`, and CPU and battery temperatures, fan speed and CPU/integrated GPU power all read correctly. Health (maximum capacity) and live adapter voltage and current aren't provided by macOS on that Mac and show "—"; the computed capacity is still there

### Peripherals

The Peripherals tab lists connected Bluetooth keyboards, mice, trackpads and headphones. AirPods and similar show "左" (left), "右" (right) and "盒" (case) side by side on one row (v1.7.1+). Non-Apple Bluetooth Low Energy mice and keyboards from Logitech, Razer and others show up too (v1.6.2+, requires Bluetooth permission, asked on first launch; the app has no Apple developer signature, so macOS treats each new version as a new app and may ask again after an update). The bell next to each device sets its own low battery alert: off, or below 10%, 15%, 20%, 30% or 50% (20% by default).

![Peripherals: AirPods, keyboard and mouse battery levels with alert settings](docs/screenshots/peripherals.png)

### Update interval and power saving

Settings → Update interval and power saving:

- **Update interval**: every second (default), 2, 5 or 10 seconds. Battery, system monitors and the app rankings all sample at this interval; slower saves more power
- **Power saving mode**: the power flow uses static icons and arrows (the v1.0.0 style), component flows and the charging companion don't animate, and updates happen at most every 2 seconds. "Only on battery" (v1.7.1+) switches back to normal mode while plugged in

![Power saving mode: static power flow](docs/screenshots/power-saving.png)

> Screenshots use demo data. CPU figures were measured on an M1 MacBook Air.

### Older versions (known bugs, not recommended)

Older versions remain on Releases but have the bugs below, all fixed in the latest version. Versions v1.4.0–v1.6.1 with the Peripherals tab also don't show Logitech, Razer and other Bluetooth Low Energy mice and keyboards, and list some newer AirPods twice (fixed in v1.6.2); up to v1.6.2 headphones show a single number (the lowest of the three) with left, right and case squeezed into small text under the name (three columns since v1.7.1). One-click update exists since v1.5.0. To save power, use the latest version with battery only and power saving mode or a slower interval instead of an old version.

| Known bug | v1.0.0 | v1.1.0 | v1.2.1 | v1.2.2 | v1.3.0 | v1.4.1 |
|---|---|---|---|---|---|---|
| While plugged in, the battery chip's "charging" flag sticks: the header says charging is paused while the flow chart shows charging power, and the status icon flickers near the charge limit | yes | yes | yes | yes | yes | — |
| With a charge limit, the top right shows the time to the limit while the system estimate in Details shows the time to 100% | yes | yes | yes | yes | yes | — |
| System power in the flow chart lags the adapter by one second, so battery power near the limit has about ±4 W of noise | — | — | yes | yes | yes | — |
| Plugged in but still discharging (weak charger or heavy load): no time remaining and **no low battery alert** | yes | yes | yes | yes | — | — |
| A "fully charged" notification on every login | yes | yes | yes | yes | — | — |
| The "Optimized Battery Charging" pause is mistaken for a charge limit, showing 80% without one | yes | yes | yes | yes | — | — |
| Launch at login can start two copies, with two icons and duplicate notifications | yes | yes | yes | yes | — | — |
| A failed read of the history file overwrites it with an empty file, losing all history | yes | yes | yes | yes | — | — |
| Plugging or unplugging with the panel open can crash (cache accessed from two threads) | — | — | yes | yes | — | — |
| After `top` is killed, one CPU core stays at 100% and the energy ranking freezes | — | — | — | yes | — | — |
| Rounded clipping of the power flow can hit a drawing assertion at tiny sizes and crash in rare cases | — | yes | yes | yes | — | — |
| Wrong power flow and numbers for about a minute after plugging in or unplugging | yes | yes | — | — | — | — |
| Discharging down to the charge limit draws the adapter as the power source | yes | yes | — | — | — | — |
| Animations rebuilt on every update while the panel is open, using more power | — | yes | — | — | — | — |
| After changing the app icon color, open Finder windows and LaunchServices keep the old icon | — | — | — | — | — | yes |

| Version | Highlights | Download |
|---|---|---|
| v1.6.2 | Logitech, Razer and other Bluetooth Low Energy mice and keyboards (headphones show a single number; one-click update to the latest works) | [Release](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.6.2) |
| v1.6.1 | Separate app names for the two editions (peripheral issues above; one-click update to the latest works) | [Release](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.6.1) |
| v1.6.0 | Charge limit slider (peripheral issues above; one-click update to the latest works) | [Release](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.6.0) |
| v1.5.3 | External drives, fans and temperatures (peripheral issues above; one-click update to the latest works) | [Release](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.5.3) |
| v1.5.0 | One-click update (peripheral issues above; one-click update to the latest works) | [Release](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.5.0) |
| v1.4.1 | New app icon with color choices | [Release](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.4.1) |
| v1.4.0 | Peripherals, adjustable update interval and display items (peripheral issues above, no one-click update) | [Release](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.4.0) |
| v1.3.0 | Battery and system monitor editions, power saving mode | [Release](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.3.0) |
| v1.2.2 | Per-second updates, expandable component details | [Release](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.2.2) |
| v1.2.1 | Menu bar updates every 30 seconds, expandable component details | [Release](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.2.1) |
| v1.1.0 | Animated Sankey power flow, menu bar updates every 30 seconds | [Release](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.1.0) |
| v1.0.0 | Static icons and arrows, menu bar updates every 30 seconds | [Release](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.0.0) |

## Install

1. Download the zip from the table above and unzip it
2. Drag the app (Finder shows "電池與系統監控", the file is `macbookBatteryMonitor.app`) into Applications
3. macOS blocks the first launch (the app isn't signed with an Apple developer certificate). Allow it either way:
   - In System Settings → Privacy & Security, find the app near the bottom and click "Open Anyway"
   - Or run in Terminal:
     ```bash
     xattr -dr com.apple.quarantine /Applications/macbookBatteryMonitor.app
     ```
4. The first launch (v1.7.1+) asks whether you want battery only or battery plus system monitors (power only / power plus system monitors on desktops), whether to turn on admin CPU sampling (Apple silicon), and for notification and Bluetooth permissions (Bluetooth is only used to read the battery of Logitech, Razer and similar mice and keyboards). It also adds itself to login items (can be turned off in Settings; on macOS 13 the system drops the login item when a new version replaces the app, so the app adds it again)

Already on v1.5.0 or later: Settings → Update → "一鍵更新" (one-click update) installs the new version without downloading it yourself. The bottom of the Settings page shows the app name and version.

## Features

**Menu bar** (Settings → Menu bar → Display)
- Icon and percentage, icon only, percentage only, icon and time remaining
- Percentage inside the icon plus time remaining (v1.2+): shows "—" without a time estimate, and "fully charged", "plugged in" or "limit reached" in those states
- A bolt while charging, a plug when plugged in but not charging, red when low

**Panel**
- Charge level, charging state, time remaining or time to full (to the charge limit when one is set)
- Smart charging (v1.7.1+, Macs that can change the charge limit): the charging companion or an energy bar sits left of the charge limit slider, with the plan status (waiting, charging, ready and so on) below the slider; click either to open the smart charging page. MacBooks without support show only the companion with a note that smart charging isn't available; click it to change its look
- Charge limit slider (v1.6.0+): 80–100% in 5% steps (as provided by macOS). The limit is written when you release the slider and read back to confirm macOS applied it; changes made in System Settings show up right away. Dragging it during a smart charging plan ends the plan in favor of your setting. Hidden on Macs that can't change the limit
- Estimated time to 0% and **to 10%**: the system estimate plus one based on the last 3 minutes of power use
- Time on battery since unplugging
- Power flow between adapter, system and battery
- System details (v1.2+): display backlight, chip and other (estimated); click the chip for CPU/GPU/ANE. ANE hides on Macs without that channel, and the backlight on Macs without its sensor ("other" then includes the display). Each item can be hidden in Settings → Display items
- Details: battery voltage, current and power, system power, system estimate, battery temperature, health, cycle count, capacity (mAh), adapter rating, live adapter voltage and current, charge limit (only on the slider where there is one); each field can be hidden
- History chart (1 hour, 24 hours, 7 days; the first launch backfills a few days from `pmset` logs)
- Energy ranking: top 5 apps, child processes merged into their app, refreshed at the update interval
- Peripherals: connected Bluetooth keyboards, mice, trackpads and headphones including Bluetooth Low Energy devices from Logitech, Razer and others (v1.6.2+), headphones with left, right and case side by side (v1.7.1+), refreshed every 60 seconds with per-device alerts
- Today (v1.7.1+): battery used and charged today with the net change, how often you plugged in, total time on battery and the longest stretch, computed from the history
- When the panel would be taller than the screen (small or scaled displays) it scrolls instead of being cut off (v1.7.1+)

**System monitor modules** (Settings → System monitors: a master switch plus one per module)
- CPU/GPU: CPU and GPU usage in the menu bar; the panel has user/system split, a 2-minute chart, per-core bars (performance and efficiency cores), GPU memory, load average, top CPU apps, and fans and temperatures (fan speed and its share of the maximum on Macs with fans; CPU, GPU, SoC, battery and storage temperatures where available)
- Memory: usage in the menu bar (orange or red under memory pressure); the panel breaks it into app memory, wired, compressed, cached files and free, with a 2-minute chart, swap and top memory apps
- Disk: used space of the startup disk in the menu bar; the panel lists the startup disk and mounted external drives (USB, Thunderbolt, SD cards; no disk images or network volumes) with used/free space, file system, connection, SMART status, read/write speed with charts and totals
- Network: upload and download speed in the menu bar; the panel shows the active interface (Wi-Fi, Ethernet) and IP, a speed chart and totals since boot
- Child processes (such as browser tabs) are merged into their app

**Other**
- Low battery and fully charged notifications (adjustable thresholds; also when the system charge limit is reached). Low battery alerts still fire when plugged in but discharging. When macOS has notifications turned off for the app, the Notifications card in Settings says so and opens the right System Settings page
- Smart charging notifications (v1.7.1+): one when the plan finishes in time (for example "已充到 95%", charged to 95%) and one when it looks like it won't make it
- Peripheral alerts: once when a device drops below its threshold, again only after it charges back above it
- Clicking outside the panel closes it (v1.7.1+)
- Admin CPU sampling (optional): on Macs whose CPU energy counters don't update, CPU power comes from `powermetrics`
- App icon colors: mint (built in), peach, night blue, sky blue (see below)
- One-click update and update notifications (see below)
- Launch at login

## Usage

- **Left click** the menu bar icon: open the panel
- **Right click**: open the panel, Settings, Quit
- **Power flow** (v1.2+): click "系統" (System) for component details, then the chip for CPU/GPU/ANE
- **System monitor modules** (when on): left click opens the module's panel, right click opens Settings or quits; hold ⌘ and drag to reorder icons
- **Smart charging**: click the charging companion left of the charge limit slider (or the status below it) and choose 1/2/3 hours, a finish time or a weekly schedule (see below)
- **Peripherals**: the Peripherals tab at the bottom; the bell next to a device sets its alert, the arrow at the bottom right refreshes now
- **Charge limit**: drag the slider in the info card and release to apply it to macOS; 100% means no limit
- **Updates**: a notification and a "有新版本" (new version) button at the bottom of the panel both open Settings → Update, then press "一鍵更新"
- **Settings**: menu bar display, app icon color, one-click update, display items, update interval and power saving, system monitor switches, admin CPU sampling (Apple silicon), notification thresholds and update notifications, charge limit and whether the companion or an energy bar sits beside the slider, launch at login

## Smart charging (v1.7.1+)

Requires a Mac whose charge limit can be changed by apps (an Apple silicon MacBook whose System Settings → Battery has "Charge Limit"); other Macs have no smart charging and only show the charging companion at the top of the panel.

**How it works**

1. Click the charging companion left of the charge limit slider (or the status below the slider) and choose "1 小時後" / "2 小時後" / "3 小時後" (in 1/2/3 hours), pick a finish time, or select weekdays and a time to save a weekly schedule (for example workdays at 8:00). Before you press anything, each option shows a forecast from the current level and charging speed: "可準時充到 95%：先維持 80%，約 8:07 開始充" (on time: holds at 80% and starts around 8:07), "會直接充到 95%" (charges straight to 95% when the level is already close) or "來不及充到 100%，預計最多約 90%" (won't make it, about 90% at most). Going from 80% to 100% usually takes over an hour, so "in 1 hour" can't make it
2. While waiting, the app sets the macOS charge limit to the care limit (80% by default). If the battery is already above it, the limit isn't lowered below the current level (macOS would first drain the battery down to the care limit and then charge it back, an extra cycle for nothing); it stays at the current level rounded up to the next 5% step, for example 95% at 93%
3. The start time is worked out backwards from the time needed to charge: the current charging speed if the Mac is charging, otherwise the median charging speed of the last seven days, otherwise 20% per hour. Charging slows down above 80%, so that part is multiplied by 1.8, and a 15-minute buffer is added
4. At the start time the limit is raised to the target (by default your original limit, the system charge limit when the plan was created; pick 100% when you need it) and macOS charges on its own. Once started, the limit isn't lowered again even if the estimate gets shorter, so charging doesn't stop halfway
5. When the target is reached a notification says so. A one-time plan restores your original limit after you unplug (or 2 hours after the finish time if you don't); a weekly plan moves on to its next time
6. If it can't make it at the current speed, the status says "可能無法準時" (may be late) with one notification, and charging continues

The target and the care limit are set under "目標與保養上限" (Target and care limit) on the smart charging page and apply to plans you create afterwards. The target defaults to "原本的上限" (your original limit), so the Mac stops at your usual limit instead of charging to 100%.

**Your changes win**: if you drag the charge limit slider or change the limit in System Settings during a plan, the app ends the plan and leaves your value alone, without restoring. "取消排程並還原" (Cancel and restore) on the smart charging page restores the limit you had before the plan.

**Every write is confirmed**: the app reads the limit back after writing and only counts it as done when it matches; failed writes are retried after a minute, and a failed restore keeps the plan around to try again.

**While asleep** ("睡眠時" on the smart charging page):

- **Ready on time** (default): an app can't raise the limit while the Mac sleeps, so if the plan is still waiting when the Mac goes to sleep, the limit is raised to the target first and macOS charges during sleep (possibly finishing early). After waking, if it's still before the start time, the limit goes back to the care limit. The app delays sleep by at most 5 seconds for the write to finish
- **Precise wake**: the Mac is woken one minute before charging should start and the app raises the limit right away (a woken Mac may fall back asleep within seconds, so it doesn't wait for the start time); the care limit holds the whole time until then. A wake is only scheduled while the plan is waiting, so the Mac isn't woken for nothing when it's already charged or unplugged, and a scheduled wake is kept even if a Wi-Fi or Bluetooth maintenance wake happens seconds before it. This needs admin authorization once and installs the same system service as admin CPU sampling. The wake event always uses the identifier `com.kuan.batterymonitor.charging` (visible in `pmset -g sched`), and the service only accepts a single time between 1 minute and 7 days ahead. If authorization is cancelled or the service is unavailable, the app falls back to "ready on time". Services installed before v1.7.1 only do CPU sampling; choosing precise wake for the first time reinstalls the service, while CPU sampling keeps working without re-authorizing

**Limits**: macOS still controls the actual charging. Temperature protection, Optimized Battery Charging and similar system behavior can pause it (shown as "macOS 暫停充電"), so finishing on time isn't guaranteed.

**Log**: every status change, limit write with the value read back, sleep and wake, and wake scheduling is recorded in `~/Library/Logs/macbookBatteryMonitor/charging-plan.log` (local only; trimmed to its second half above 256 KB). `macbookBatteryMonitor --charging-plan-status` (see Development) prints the current plan, the system charge limit, the battery level, scheduled wake events and the latest log lines without changing anything.

**Charging companion**: "滑桿旁顯示" (shown beside the slider; "面板上方顯示" on Macs that can't change the charge limit) at the top of the smart charging page (or in Settings → Charge limit) switches between three looks:

- **Charging companion (cat, default)**: a 6-second looping HEVC animation with a transparent background: its belly rises and falls, its tail sweeps slowly now and then and the tip flicks, and the dangling front paw sways. While charging it lies on a glowing charging pad with charging waves above it; it shows a sleep badge while waiting and a check mark when done. It only plays while the panel is open and shows a still image when the panel is closed, in power saving mode, with Reduce Motion on, or on Macs without HEVC hardware decoding (such as 2015 Intel models)
- **Battery buddy**: a battery with a face, filled to the current level. Neutral without a plan, asleep while waiting, smiling while charging, beaming when done and frowning when late or paused; it blinks now and then while the panel is open
- **Energy bar**: a level bar with a light dot flowing right while charging

## App icon

The icon is a Ragdoll cat lying on its back on a wireless charging pad (a cut-out photo). Settings → App icon offers background colors: mint (built in), peach, night blue, sky blue.

![The four app icon background colors](docs/screenshots/app-icons.png)

- This changes the icon shown in Applications, Finder, Launchpad and Spotlight, like pasting a custom icon in Get Info; notifications and login items keep the built-in mint icon
- With a color other than mint the app gets a custom icon file at its top level, so `codesign --verify --strict` reports an extra file; the app runs normally and switching back to mint removes it
- Replacing the app with a new version removes the custom icon; the app reapplies your color at launch

## One-click update

Settings → Update checks GitHub for new versions; press "一鍵更新" (one-click update) when one is available:

1. Downloads the universal zip (the macOS 12 build downloads `…-macOS12.zip`, or the universal zip once the system is on macOS 14 or later; releases without a universal zip use the older file names), only from `github.com` and `githubusercontent.com`
2. Verifies it against the release's `SHA256SUMS.txt` and checks the app's identifier, version, beta number and signature
3. Replaces the app after it quits and relaunches it; if the swap fails the original is put back. Settings, history, smart charging plans and your icon color are kept; temporary files are removed if the download or verification fails or the update is interrupted

"自動檢查更新" (check automatically) is on by default: shortly after launch and every 6 hours, but it only contacts `api.github.com` if the last check was more than a day ago. It only tells you; nothing installs on its own. With the app running, a new release is noticed within about a day.

"有新版本時通知" (notify about new versions, v1.7.1+) is on by default: an automatic check that finds a new stable version posts one macOS notification per version; clicking it opens Settings at the Update card. Turn it off in Settings → Update. If the app isn't in a writable location (for example installed by an administrator), one-click update can't run and points you to GitHub.

**Beta releases** (v1.7.1+): betas marked as pre-releases on GitHub (for example v1.8.0-beta.1) are only listed when you press "檢查更新" (Check for updates). Automatic checks never mention them, the panel doesn't show them and there are no notifications. "安裝 Beta…" (Install beta) first explains that betas may be unstable, and only a second click on "安裝 Beta" downloads and installs it (with the same checksum and signature checks). If a stable version newer than the beta exists, only the stable one is listed. On a beta, the next beta also needs a manual check, while stable versions are announced as usual. To go back to the stable version, download it from GitHub and reinstall.

Versions up to v1.4.1 have no one-click update; download a new version manually once.

## Admin CPU sampling (optional, off by default)

On some Macs (such as the M1 and M2 Pro below) the CPU energy counter doesn't update, so the CPU shows 0 W. If you want CPU power, turn on Settings → CPU power → admin CPU sampling to read it with the built-in `powermetrics`. Otherwise leave it off.

- **Turning on**: asked once on first launch; after that the macOS admin prompt only appears when you turn it on yourself in Settings. It installs a system service, stores no password and doesn't touch sudoers. If you cancel or it fails, the option turns itself off; no password prompt at app launch or login
- **Sampling**: connects only while the main panel is open, at the update interval. Closing the panel, opening Settings, sleeping or quitting disconnects and stops `powermetrics` immediately; the service exits after 30 seconds of idling
- **Turning off**: stops and removes the service (no password needed). If smart charging's precise wake also uses it, it only disconnects; the service is removed when both are off
- **Power**: `powermetrics` runs only while the main panel is open. On an M1 MacBook Air the service and `powermetrics` add about 1% CPU with the panel open (about 0.3% in power saving mode); nothing with the panel closed
- **Security**: the service only accepts connections from the user who installed it. It can only start and stop `powermetrics` with fixed arguments (intervals of 1, 2, 5 or 10 seconds), schedule or cancel one smart charging wake with a fixed identifier and a bounded time range, or remove itself. It never accepts arbitrary commands, paths or PIDs
- **Location**: the service lives in `/Library/PrivilegedHelperTools/com.kuan.batterymonitor.cpu/` with its launch daemon at `/Library/LaunchDaemons/com.kuan.batterymonitor.cpu.plist`

Old values are never shown while waiting for authorization, before data arrives or after data goes stale; system power and CPU sampling windows are only roughly aligned.

## Power overview and component power (v1.2+)

The main panel samples at the update interval (every second by default) and stops when the panel closes, Settings opens or the Mac sleeps. No admin rights needed (except the optional `powermetrics` CPU sampling).

**Stable display while plugged in**

- **Is it charging**: the battery chip's "charging" flag can lag (on an M1, it reported "not charging, 0 mA" for over ten seconds while about 14 W went into the battery), so live SMC power wins when available: 3 W or more into the battery is charging, 0.5 W or less is not, and only in between does the chip flag decide. At the charge limit both must agree. On Intel Macs near full, when the charging current is small, the SMC-derived battery power can be slightly negative (−3 W at 86% on a 2015 MacBook Air), so when the battery chip clearly reports charging with a positive current the chip wins and the app doesn't claim a weak charger
- **10-second confirmation**: while plugged in, switching between charging, limit reached and not charging needs to hold for 10 seconds, so the icon doesn't flicker as macOS pauses and resumes around the limit; actually plugging or unplugging updates immediately
- **Full charge buffer** (without a system charge limit): the display stays "fully charged" through brief dips to 99%/98%, and returns to normal below 98%
- **Flow follows the state**: when plugged in but not charging (full, at the limit, paused), battery power within ±2 W is drawn as the adapter powering the system directly, and flow changes need 10 seconds to switch. When full, the power flow header shows the live signed battery power. A weak adapter, or a battery above the limit that is discharging, is drawn as it is
- **Consistent estimates**: with a charge limit, the top right and the system estimate in Details both show the time to the limit
- **Just plugged in** (v1.7.1+): Intel chargers take ten seconds or more to start charging, and the battery may keep discharging until then. For 30 seconds after plugging in, the card says it was just plugged in, the menu bar doesn't show a time remaining and the flow doesn't draw the battery as a source; when the flow goes from battery assist to charging it switches at once, and the battery path never shows negative watts
- **Times right after charging starts or after unplugging** (v1.7.1+): the current is still ramping up during the first minute of charging, so the average charging current shows "計算中…" (calculating). While macOS is still estimating the time to full, the top right and the charging card show "計算中…" too instead of a straight-line guess (which ignores the slower charging above 80%; on an Intel Mac at 70% it gave 37 minutes where macOS said over 80). While macOS is still estimating the time remaining, the system estimate shows "計算中…" instead of falling back to the battery chip's average (right after unplugging that average lags and gave over 12 hours on an Intel Mac), and the top right uses the estimate from current power use; on Intel Macs the first minute after unplugging reads too little current, so it's left out of the average too instead of making the time remaining keep dropping

**Power overview** (adapter, system, battery)

- **Adapter input** reads SMC `PDTR`, **system power** reads SMC `PSTR`
- **Battery power** is "adapter input − system power", so the three numbers always add up. Both sensors update every second, but `PSTR` lags `PDTR` by one update, so subtracting values read at the same moment gives about ±4 W of noise; system power is paired with the adapter reading from one second earlier. At slower update intervals the adapter is read once, one second before each update, bringing the idle error from about 4 W to 0.00 W. SMC `PPBR` doesn't match real battery power on some Macs and isn't used. Without `PDTR` or `PSTR`, IORegistry voltage × current is used instead
- `PDTR` can hold a stale value right after unplugging, so input only counts once the system confirms external power
- When macOS discharges down to the charge limit it stops drawing from the adapter; this still counts as plugged in and shows "limit reached"
- SMC values update immediately, unlike the battery chip (IORegistry), which lags about a minute after plugging in or unplugging. After a power change notification the values are re-read at 1, 3 and 6 seconds

**Component details**

- **System total**: SMC `PSTR`, falling back to IORegistry `SystemLoad`
- **Display backlight**: SMC sensors (`PDBR`/`PBwo`). Macs without them (such as the M1 MacBook Air) hide the backlight and count it in "other (including display)"
- **CPU/GPU/ANE**: IOReport Energy Model energy deltas divided by the actual sampling time; the first sample only sets a baseline. Macs without an ANE channel hide ANE
- **Other (estimated)**: the total minus backlight and the chip power that was read; with chip details missing it is labeled "uncategorized (estimated)"
- The chip total only covers the CPU, GPU and ANE that were read; it isn't the full SoC power and excludes external displays
- Each item can be hidden in Settings → Display items; hiding the chip also hides CPU/GPU/ANE

IOReport is a private interface whose availability depends on the chip and macOS version. Items a Mac doesn't have are hidden; items that can't be read at the moment show "—":

| Mac | System total | Backlight | GPU | CPU | ANE |
|---|---|---|---|---|---|
| M2 Pro | ✓ | ✓ | ✓ | Shows 0 W (channel doesn't keep updating); admin CPU sampling reads it | 0 W when idle |
| M1 MacBook Air | ✓ | No sensor, hidden (counted in "other (including display)") | ✓ | Shows 0 W (channel doesn't keep updating); admin CPU sampling reads it | No channel, hidden |

## Update interval and power design

Everything live updates every second by default (2/5/10 seconds selectable; at least 2 seconds in power saving mode), but each update only reads what is needed. Measured on an M1 MacBook Air:

| Situation | Every second | Power saving (every 2 s) |
|---|---|---|
| Panel closed, battery only (system monitors off) | about 0.2% | about 0.15% |
| Panel closed, all four system monitors on | about 1% | about 0.5% |
| Battery panel open (energy ranking tab) | about 4%, plus about 6% for `top` | about 2%, plus about 3% for `top` |
| CPU or memory module panel open | about 3%, plus about 6% for `top` | about 2%, plus about 3% for `top` |

`top` only runs while the energy ranking tab or the CPU/memory panel is open and stops when you switch away or close the panel.

- With the panel closed, only what the menu bar needs (level, state, power, time remaining) is read at the update interval; plugging in or unplugging also triggers an immediate update
- The menu bar icon is only redrawn when its number, time or state changes
- Each SMC key's format is looked up once; afterwards every value is a single SMC call, and only `PDTR` and `PSTR` are read every second
- Adapter details are read every 30 seconds while plugged in; the system charge limit is read at launch, when the panel opens and when macOS reports a change, never every second
- Smart charging only evaluates the plan on each update (nothing at all without a plan) and only calls macOS when the limit has to change; the precise wake service is only contacted to schedule or cancel the wake
- The charging companion is a small hardware-decoded video (152×160 pixels) that only plays while the panel is open; Macs without HEVC hardware decoding get a still image instead of decoding it on the CPU
- The panel is built when it opens and released completely with its window when it closes; nothing draws in the background
- Component details and SMC temperatures are only read while the panel is open; optional admin CPU sampling only connects while the main panel is open
- Flow animations and the energy bar's moving dot are composited by Core Animation (not redrawn frame by frame in SwiftUI) and only play while the panel is open and that path carries power; Reduce Motion is respected and power saving mode doesn't animate at all
- System monitors only sample enabled modules; with the master switch off no module icons or timers exist; menu bar icon widths are fixed
- Disk space is read with `statfs()` every second, with purgeable space recalibrated every 5 minutes; network only queries the active interface; external drives are listed with `getfsstat(MNT_NOWAIT)`, so offline network volumes can't block it
- SMART status needs `diskutil` and can wake sleeping external drives, so it is only checked while the disk panel is open, at most every 10 minutes per drive
- Fans and temperatures are read in the background every 2 seconds only while the CPU panel is open
- Peripheral levels are checked every 60 seconds: keyboards, mice and trackpads via IORegistry; headphones need `system_profiler`, so background checks only run it while a Bluetooth audio device is connected; Bluetooth Low Energy devices are read through CoreBluetooth from already connected devices without new connections
- History is recorded every minute (written every 15 minutes and before sleep and quit); health is checked every 6 hours

## Data sources

| Item | Source |
|---|---|
| Level, voltage, raw current, capacity, cycle count | IORegistry `AppleSmartBattery` |
| Adapter input, system power, backlight | SMC (read only: `PDTR`, `PSTR`, `PDBR`/`PBwo`); desktops only read `PSTR` (whole system) |
| Live adapter voltage and current | SMC (read only: `VD0R`, `ID0R`); otherwise IORegistry `PowerTelemetryData` `SystemCurrentIn` |
| Battery power | "adapter input − system power"; IORegistry voltage × current when either is missing (`PPBR` isn't used) |
| CPU/GPU/ANE power | Apple silicon: IOReport Energy Model, `powermetrics` for the CPU in admin mode; Intel: SMC `PCPC`/`PCPG` (read only) |
| System time estimate | IOKit Power Sources |
| Charging or not | Live SMC battery power first, the IOKit Power Sources/IORegistry charging flag when ambiguous |
| Health (maximum capacity), battery condition | `system_profiler SPPowerDataType` |
| Battery temperature (Details) | SMC (read only, `TB0T`–`TB2T`) |
| Energy ranking | `top -o power` |
| History backfill, unplug time | `pmset -g log` |
| Charge limit (setting, slider and smart charging changes) | The macOS charge limit service (PowerUI `PowerUISmartChargeClient`, which System Settings also uses); change notification `com.apple.powerui.mclstatuschanged`. No admin rights needed |
| Charge limit (currently applied) | `/Library/Preferences/com.apple.powerd.charging.plist` (read only; exists only while plugged in) |
| Smart charging speed | The average current while charging; otherwise the median charging speed of the last seven days of history |
| Smart charging precise wake | The admin service schedules a `wake` event with IOKit `IOPMSchedulePowerEvent` (identifier `com.kuan.batterymonitor.charging`) |
| Writing before sleep | IOKit system power notifications (`IORegisterForSystemPower`), delaying sleep by at most 5 seconds |
| Today recap | Battery history (one sample per minute) |
| CPU usage, per core | Tick deltas from `host_processor_info`; core types from `hw.perflevel0/1` |
| Load average | `getloadavg` |
| GPU usage, GPU memory | IORegistry `IOAccelerator` `PerformanceStatistics` (`inUseSysMemoryBytes` on Intel integrated graphics) |
| Memory breakdown, pressure, swap | `host_statistics64`, `kern.memorystatus_vm_pressure_level`, `vm.swapusage` |
| Disk space | `statfs()` plus periodically recalibrated purgeable space (matches Finder) |
| Disk reads and writes | IORegistry `IOBlockStorageDriver` cumulative byte counters |
| External drives, connection type | `getfsstat`, DiskArbitration (`DeviceInternal`, `DeviceProtocol`) |
| Disk health | `SMARTStatus` from `diskutil info -plist` |
| Fan speed | SMC (read only, `F<n>Ac`, `F<n>Mn`, `F<n>Mx`) |
| Temperatures in the CPU panel | IOHIDEventSystem temperature sensors (private interface, hidden if missing); M2 Macs use SMC core temperature keys; Intel uses SMC core, PECI/die/proximity, integrated GPU, SSD and battery keys |
| Network speed and totals | 64-bit interface counters from `sysctl` (`NET_RT_IFLIST2`), active interface only |
| Network interface and IP | `SCDynamicStore` (default route interface), `getifaddrs` |
| CPU/memory app rankings | `top -o cpu`, `top -o mem` |
| New versions (one-click update) | GitHub API `releases` (latest 20; betas only on manual checks), automatic checks at most once a day; downloads verified with the release's `SHA256SUMS.txt` |
| Peripheral levels (keyboards, mice, trackpads) | IORegistry services with `BatteryPercent` |
| Peripheral levels (Bluetooth Low Energy mice and keyboards) | CoreBluetooth: the Battery Level (`0x2A19`) of the standard Battery Service (`0x180F`) on connected devices, requires Bluetooth permission; IORegistry HID usage decides mouse or keyboard when the name doesn't tell |
| Peripheral levels (headphone left, right, case) | `system_profiler SPBluetoothDataType`; whether Bluetooth headphones are connected comes from the CoreAudio device list |

## Where data is stored

- History: `~/Library/Application Support/BatteryMonitor/history.json` (kept for 7 days)
- Settings and smart charging plans: `com.kuan.batterymonitor` (UserDefaults)
- Smart charging log: `~/Library/Logs/macbookBatteryMonitor/charging-plan.log`
- Admin service (only while admin CPU sampling or precise wake is on): `/Library/PrivilegedHelperTools/com.kuan.batterymonitor.cpu/`, `/Library/LaunchDaemons/com.kuan.batterymonitor.cpu.plist`

## Uninstall

1. If you set up smart charging, press "取消排程並還原" (Cancel and restore) on the smart charging page first to restore your charge limit
2. In Settings, turn off admin CPU sampling, set smart charging's "睡眠時" (While asleep) back to "優先準時完成" (Ready on time) (this removes the system service if it was installed), turn off launch at login, then quit the app
3. Delete `/Applications/macbookBatteryMonitor.app`
4. If the app was deleted first and the system service is still there, run:
   ```bash
   sudo launchctl bootout system/com.kuan.batterymonitor.cpu
   sudo rm -f /Library/LaunchDaemons/com.kuan.batterymonitor.cpu.plist
   sudo rm -rf /Library/PrivilegedHelperTools/com.kuan.batterymonitor.cpu
   ```
5. (Optional) remove its data:
   ```bash
   rm -rf ~/Library/Application\ Support/BatteryMonitor ~/Library/Logs/macbookBatteryMonitor
   defaults delete com.kuan.batterymonitor
   ```

## Building from source

Only Command Line Tools are needed (`xcode-select --install`), not Xcode.

```bash
git clone https://github.com/sgeric910601/macbookBatteryMonitor.git
cd macbookBatteryMonitor
git checkout v1.7.1          # or another tag; without it you get the latest development version
./build.sh                   # universal build (Apple silicon + Intel): build/macbookBatteryMonitor.app
./build.sh install           # and install it to /Applications and launch it
```

## Development

```bash
Scripts/test-power.sh    # unit conversions, power state transitions, stable plugged-in display, lifecycle, animation, system monitors, external drives, temperatures, CPU service protocol, peripherals, one-click update (including betas), charge limit slider and smart charging tests (runs with Command Line Tools)
```

Debug arguments:

```bash
APP=/Applications/macbookBatteryMonitor.app/Contents/MacOS/macbookBatteryMonitor
$APP --dump              # current readings as JSON
$APP --dump-hardware     # component power every second, five JSON samples
$APP --charging-plan-status # smart charging: plan, system charge limit, level, scheduled wakes and the latest log lines (read only)
$APP --snapshot <folder> # render each panel tab to PNG off screen
$APP --selftest-panel    # open the panel for 20 seconds and close it, for power measurements
$APP --selftest-hardware # expand the chip and switch to Settings to confirm sampling stops and resumes, printing the CPU reading (with admin CPU sampling status)
$APP --dump-monitors     # system monitor readings (two samples one second apart) as JSON
$APP --dump-sensors 10   # a temperature sensor and fan table every second, 10 times
$APP --dump-peripherals  # read peripheral levels once (all Bluetooth devices) with timing
$APP --notification-status # this app's notification permission (check this first if notifications don't arrive)
$APP --selftest-monitors # open the CPU and memory module panels for 10 seconds each, for power measurements
$APP --selftest-update   # check GitHub for a new version and one-click update right away (lower the version of a copy to test)
$APP --screenshots <folder> # render the README images with demo data (docs/screenshots)
```

- The macOS 12 build lives on the `legacy-macos12` branch: macOS 13/14-only APIs (Observation, Swift Charts, Grid, SMAppService and so on) are replaced with compatible code, everything else matches the main branch. Launching with `--macos12-paths` forces the macOS 12 code paths on newer systems. GitHub Actions only packages `…-macOS12.zip` when the `legacy-macos12` branch has the same version (including the beta number) as the release
- `build.sh` builds Apple silicon and Intel in one go (universal); with Command Line Tools that can't build both, it falls back to this Mac's architecture
- Releases package three zips: the universal build (`MBMEdition=universal`) and the older `battery`/`status` file names for the one-click update of v1.5.0–v1.6.2 (same content, only `MBMEdition` differs, which decides whether system monitors start on when upgrading)
- When Info.plist has `MBMPrerelease` (such as `beta.1`), the release tag is `v<version>-beta.1` and the release is marked as a pre-release, never as the latest release
- `build.sh` puts the admin service (`CPUPowerHelper`) into `Contents/Library/Helpers/` and the charging companion's animations and still images (`Resources/Companion/`) into `Contents/Resources/`; the service is only installed into the system when the user turns on admin CPU sampling or precise wake
- Command Line Tools don't include SwiftUI's macro plugins, so the code doesn't use `@State`; UI state lives in `PanelState`

The app icon is generated by `Scripts/make-icon.swift`: the cat is `Resources/icon-cat.png` (a cut-out photo), and the charging pad, waves and background are drawn in code.

```bash
swiftc -O Scripts/make-icon.swift -o build/make-icon
build/make-icon Resources/AppIcon.icns                                  # built-in mint icon
for bg in peach night sky; do build/make-icon --bg $bg --size 512 --preview Resources/AppIcons/icon-$bg.png; done
```

## Thanks

- [@melvin0kuo](https://github.com/melvin0kuo): animated power flow, layered component power, power sensor fallbacks, percentage inside the menu bar icon, stable full-charge display and admin CPU sampling (#1, #2, #4–#7), and the idea of smart charging with schedules and a daily recap (#13)
- [@liaw-boy](https://github.com/liaw-boy): external drives, fans and temperatures, menu bar icon alignment on 1x displays, the idea of merging the charge limit slider into the info card, closing the panel on outside clicks and power saving only on battery (#8–#10, #12)
