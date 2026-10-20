[繁體中文](README.md) | **English**

# Battery & System Monitor (macbookBatteryMonitor)

A macOS menu bar app for battery and system information. On a MacBook the menu bar shows the charge level. Click it to see:
- time remaining, battery health and power flow (expandable down to individual components);
- a charge limit slider and smart charging;
- history charts, a daily recap and the apps using the most energy;
- the battery levels of Bluetooth keyboards, mice and headphones.

Desktop Macs (Mac mini, iMac, Mac Studio, Mac Pro) show whole-system power instead. System monitors for CPU/GPU, memory, disks and network can be turned on or off.

The app's interface is in Traditional Chinese. This README quotes the Chinese labels with an English translation in parentheses.

![Battery only: the menu bar battery icon and the battery panel, with the charging companion left of the charge limit slider and the smart charging status below it](docs/screenshots/edition-battery.png)

## Highlights

- **One app for every Mac**: Apple silicon and Intel, MacBooks and desktops use the same download, which decides by itself whether to show the battery or system power. Macs on macOS 12 or 13 have a separate build
- **Charge limit slider**: drag macOS's charge limit (80–100%) right in the panel. It is the same setting as in System Settings, kept in sync both ways, and needs no admin rights
- **Smart charging**: say "charged to X% by this time"; the Mac stays at a battery-friendly limit and macOS only charges to the target when it's time
- **Power flow**: watts between the power adapter, the system and the battery, expandable to the display backlight and CPU/GPU/ANE
- **Charging companion and desktop pet**: a breathing cat, a battery with a face, a charge bar or a photo that follows the charging state, also available as a pet on the desktop
- **Peripheral batteries**: Bluetooth keyboards, mice and trackpads (including Logitech, Razer and other Bluetooth LE devices) and the left bud, right bud and case of AirPods, each with its own low-battery notification
- **System monitors**: CPU/GPU (with fans and temperatures), memory, disks (including external drives and drive health) and network, one menu bar icon each; one switch turns them all off
- **Separate mouse and trackpad scroll directions**: for example natural scrolling on the trackpad and the traditional direction on the mouse wheel
- **Light on power**: updates every second by default and uses about 0.2% CPU with the panel closed; slower update intervals and a power saving mode are available
- **One-click updates that keep permissions**: one click in Settings downloads, verifies and installs the new version; Accessibility and Bluetooth permissions don't have to be granted again
- **Never changes charging behind your back**: the charge limit only changes when you drag the slider or set up smart charging; macOS itself stops charging at the limit
- **No Xcode needed**: the Command Line Tools are enough to build it

## Download

| Your Mac | Download (latest) |
|---|---|
| macOS 14 or later (Apple silicon or Intel, MacBook or desktop) | [`macbookBatteryMonitor.dmg`](https://github.com/sgeric910601/macbookBatteryMonitor/releases/latest/download/macbookBatteryMonitor.dmg) (universal) |
| macOS 12 or 13 (Apple silicon or Intel) | [`macbookBatteryMonitor-macOS12.dmg`](https://github.com/sgeric910601/macbookBatteryMonitor/releases/latest/download/macbookBatteryMonitor-macOS12.dmg) (older macOS build) |

- The file names never change, so the links above always download the latest version; other versions are on [Releases](https://github.com/sgeric910601/macbookBatteryMonitor/releases)
- The older macOS build is for Macs on macOS 12 or 13 (for example 2015–2017 MacBooks, or older Macs upgraded with OpenCore Legacy Patcher) and has the same features. After the system is upgraded to macOS 14, one-click update switches to the universal build by itself
- Already on v1.5.0 or later: no download needed, use Settings → Update → "一鍵更新" (one-click update)
- The extra zips attached to each release are for older versions' one-click updates; they contain the same app as the DMG and you don't need them

## Install

1. Download the matching DMG above and open it
2. Drag "電池與系統監控" (Battery & System Monitor) into Applications (the file is `macbookBatteryMonitor.app`)
3. macOS blocks the first launch (the app isn't signed with an Apple developer certificate). Allow it either way:
   - In System Settings → Privacy & Security, find the app near the bottom and click "Open Anyway"
   - Or run in Terminal:
     ```bash
     xattr -dr com.apple.quarantine /Applications/macbookBatteryMonitor.app
     ```
4. On the first launch, choose:
   - battery only, or battery plus system monitors (power only / power plus system monitors on desktops);
   - whether to turn on admin CPU sampling (Apple silicon);
   - whether to allow notifications and Bluetooth (Bluetooth is only used to read the battery of Logitech, Razer and similar mice and keyboards).

   The app adds itself to login items; you can turn that off in Settings.

**Permissions are kept**: every release is signed with the same dedicated certificate, so macOS treats new versions as the same app. Accessibility and Bluetooth permissions stay after one-click updates and reinstalls, with nothing to allow again. The certificate is self-made, not an Apple developer signature, so the first launch still has to be allowed as above. Updating from v1.7.3 or earlier switches signatures, so the permissions have to be allowed one last time:
- Bluetooth asks again; allow it;
- for Accessibility, follow "[If reversed scrolling stops working](#if-reversed-scrolling-stops-working)".

The app is named "電池與系統監控" (Battery & System Monitor on English systems); the bottom left of the Settings window shows the name and version.

## Using it

### Menu bar

- **Left click** the icon to open the panel; clicking anywhere else closes it. This also works while another app is in full screen (green button). **Right click**: open the panel, Settings, Quit
- **Display styles** (Settings → Display items): icon and percentage, icon only, percentage only, icon and time remaining, or percentage inside the icon plus time remaining (the charge inside the battery icon, time remaining or time to full on the right). The last one shows "—" without time data and "已充飽" (full), "接電" (plugged in) or "已達上限" (limit reached) when full, plugged in without charging, or at the charge limit
- A bolt while charging, a plug while plugged in without charging, red at low battery
- **System monitors**: one menu bar icon each. Left click opens that monitor's panel, right click opens Settings or quits; hold ⌘ and drag to reorder the icons
- **Combine into one icon** (Settings → Monitoring & power saving): when the menu bar is full, macOS hides the icons that don't fit (MacBooks with a notch are hit hardest). You can then keep just the battery icon (power on desktops). Clicking it opens a second status bar right below the menu bar with the battery and monitor icons, updated live. Click an icon there to open its panel (click again to collapse it); click anywhere else or press Esc to close the bar. The monitors only sample while the second bar is open. No screen recording or Accessibility permission is needed
- If you only see the battery icon and no CPU or other icons, check that the system monitor master switch is on in Settings → Monitoring & power saving

### Battery panel

- **Charge and time**: charge level, charging state, time remaining or time to full (to the charge limit when one is set); estimated time to 0% and to 10% (the system estimate, plus one from the 3-minute average draw); how long it has been on battery since you unplugged
- **Charge limit slider**: 80–100% in 5% steps. It writes when you let go, reads the value back to confirm the system applied it and tells you if it didn't; changes made in System Settings show up immediately. 100% means no limit. Macs whose system can't change the charge limit don't show the slider
- **Charging companion and smart charging**: the companion sits left of the slider and the smart charging status (waiting, charging, ready and so on) below it; click either to open the smart charging page (see "[Smart charging](#smart-charging)")
- **Power flow**: watts between the power adapter, the system and the battery. Click "系統" (System) to split it into display backlight, chip, and other (estimated), then click the chip for CPU/GPU/ANE; items the model doesn't have are hidden (see "[How power flow is measured](#how-power-flow-is-measured)")
- **Details**: battery voltage, current and power, system power, system estimate, battery temperature, health, computed health (full charge capacity ÷ design capacity), cycle count, battery condition, remaining, full charge and design capacity (mAh), Low Power Mode, power adapter rating, live adapter voltage and current, charge limit (shown only on the slider on Macs that have one)
- **Tabs**:
  - charge history (1 hour / 24 hours / 7 days; the first launch backfills the past few days from `pmset`);
  - today's recap: charge used and regained today, net change, plug-ins, total and longest time on battery;
  - top energy users: the top 5 apps, with child processes merged into their app;
  - peripherals.
- Every power flow item and every details field can be hidden in Settings → Display items
- When the panel is taller than the screen (small screens or zoomed display), it scrolls instead of being cut off

![Smart charging: plugged in and held at the 80% care limit, charging to the original 95% limit by 7:30 tomorrow; today's recap on the left, the smart charging page on the right](docs/screenshots/smart-charging.png)

### System monitors

Pick "battery plus system monitors" on the first launch, or turn on the master switch later in Settings → Monitoring & power saving; each of the four monitors has its own switch. With the master switch off nothing is sampled, just like battery only.

- **CPU/GPU**: the menu bar shows CPU and GPU usage. The panel has:
  - the user/system split, a 2-minute chart, per-core usage (performance and efficiency cores), GPU memory, load average and the apps using the most CPU;
  - fans and temperatures: fan speed and share of maximum speed (hidden on fanless models), and CPU/GPU/SoC/battery/storage temperatures (unreadable ones are hidden).
- **Memory**: the menu bar shows usage, turning orange and red as memory pressure rises. The panel shows the breakdown into app memory, wired, compressed, cached files and free, plus a 2-minute chart, swap and the apps using the most memory
- **Disks**: the menu bar shows how full the startup disk is. The panel lists the startup disk and mounted external disks (USB, Thunderbolt, SD cards; not disk images or network volumes), each with used/free space, file system, connection type, health, read/write speed with charts and total reads/writes
  - NVMe drives keep their own record of how much of their rated life is used and how much has been read and written since they were made. Every Apple silicon Mac's internal drive is NVMe, as are most Intel Macs from 2016 on and Thunderbolt enclosures. Health is 100% minus the life used (3% used means 97%), the totals are the drive's lifetime totals, and power-on time is listed too, with an extra line if there are media errors. When the drive reports a critical warning or its spare blocks fall below the threshold, health shows a red "異常，建議立即備份" (failing, back up now)
  - Drives without that record (internal drives that aren't NVMe, such as a 2015 MacBook Air's, and most USB enclosures) show the SMART "正常／異常" (OK / failing) status, and totals since boot (since connected for external disks)
- **Network**: the menu bar shows upload and download speed; the panel shows the current interface (Wi-Fi, Ethernet) and IP, a speed chart and totals since boot
- Child processes (such as browser tabs) are merged into their app

![Battery plus system monitors: CPU/GPU, memory, disk and network icons in the menu bar and each monitor's panel, with fans, temperatures and external disks](docs/screenshots/edition-status.png)

### Peripherals

The "周邊設備" (Peripherals) tab at the bottom of the panel lists the battery levels of connected Bluetooth keyboards, mice, trackpads and headphones:
- AirPods and similar headphones show "左" (left), "右" (right) and "盒" (case) side by side on one line;
- non-Apple Bluetooth LE mice and keyboards from Logitech, Razer and others show up too (Bluetooth permission required).

The bell to the right of each device sets its low-battery notification: off, or below 10%, 15%, 20%, 30% or 50% (20% by default). Settings → Peripherals sets them for all connected devices at once. Levels update every 60 seconds; the arrow at the bottom right refreshes them right away.

![Peripherals: AirPods, keyboard and mouse battery levels with notification settings](docs/screenshots/peripherals.png)

### Notifications

- **Low battery, fully charged**: adjustable thresholds; reaching the system charge limit notifies too. The low-battery alert still fires while plugged in if the battery is draining (adapter too weak or load too high)
- **Smart charging**: once when charged before the finish time, and once if it may not make it at the current rate
- **Peripherals**: once when a device drops below its own threshold, and again only after it has charged back above it
- **New versions**: see "[One-click update](#one-click-update)"
- When macOS has turned off notifications for the app, Settings → General → "通知" (Notifications) says so and can open the notification settings directly

### Settings window

Click the gear at the bottom right of the panel, or "設定…" (Settings…) in the menu bar icon's right-click menu. While it's open the app shows up in the Dock and ⌘Tab, so you can find it again after visiting System Settings; ⌘W closes it. The sections on the left:

| Section | Contents |
|---|---|
| 一般 (General) | App icon color, notification thresholds, launch at login |
| 顯示項目 (Display items) | Menu bar style, power flow items, details fields |
| 監控與省電 (Monitoring & power saving) | Update interval, power saving mode, system monitor master switch and each monitor, combine into one icon, admin CPU sampling |
| 充電 (Charging) | Charge limit slider, smart charging |
| 充電夥伴 (Charging companion) | Appearance, my photo, the desktop pet's position, size and moving eyes |
| 周邊設備 (Peripherals) | Each device's low-battery notification |
| 滑鼠與觸控板 (Mouse & trackpad) | Separate scroll directions |
| 更新 (Update) | One-click update, automatic checks and new-version notifications |

Desktop Macs have no Charging or Charging companion sections. The panel's gear reopens the section you last viewed, "有新版本" (new version available) opens Update, and the gear in a monitor panel opens Monitoring & power saving.

![Settings window: sections on the left, Display items on the right (menu bar style, power flow items, details fields)](docs/screenshots/settings.png)

## Smart charging

Needs a Mac whose charge limit the app can change: an Apple silicon MacBook that has "充電上限" (Charge Limit) in System Settings → Battery. Other Macs have no smart charging; the panel shows only the charging companion at the top.

**How to use it**: click the charging companion left of the slider, the status below the slider, or open Settings → Charging. You can choose:
- "1 小時後", "2 小時後" or "3 小時後" (in 1, 2 or 3 hours);
- a finish time;
- weekdays and a time, saved as a weekly schedule (for example 8:00 on workdays).

Before you pick, each option shows an estimate from the current charge and charging speed:
- in time: "可準時充到 95%：先維持 80%，約 8:07 開始充" (will reach 95% in time: hold 80%, start around 8:07);
- already close to the target: "會直接充到 95%" (will charge straight to 95%);
- not enough time: "來不及充到 100%，預計最多約 90%" (can't reach 100%, about 90% at most).

**How it works**

1. While waiting, the app sets macOS's charge limit to the care limit (80% by default). If the battery is already above the care limit, the limit isn't lowered below the current charge (macOS would drain to the care limit first and then charge back, an extra cycle for nothing); it stays at the current charge, rounded up to the next 5% step (95% at 93%)
2. The start time is worked back from the charging time needed: the current charging speed if it is charging, otherwise the median charging speed over the past seven days, otherwise 20% per hour. Charging slows above 80%, so that part takes 1.8 times longer, and 15 minutes of buffer are added
3. At the start time, the limit is raised to the target and macOS charges by itself. The target defaults to "原本的上限" (the original limit, the system charge limit when the schedule was created); choose 100% separately if needed. Once started, the limit isn't lowered again even if the estimate shrinks, so charging never stops halfway
4. A "已充到目標" (target reached) notification is sent when done. A one-time schedule restores the original charge limit after you unplug (or 2 hours after the finish time if you don't); a weekly schedule moves on to its next time
5. If it can't make the finish time at the current rate, the status shows "可能無法準時" (may be late) and notifies once; charging continues

The target and care limit are set under "目標與保養上限" (target and care limit) on the smart charging page and apply to schedules created afterwards.

- **Your own changes win**: if you drag the charge limit slider or change the limit in System Settings while a schedule is running, the app ends the schedule and neither changes it back nor restores it. "取消排程並還原" (cancel and restore) on the smart charging page restores the limit from before the schedule
- **Every write is checked**: the system limit is read back after writing and only counts as done when it matches; failed writes are retried after 1 minute, and a failed restore keeps the schedule and tries again later

**While asleep** ("睡眠時" on the smart charging page)

- **"優先準時完成"** (finish on time first, default): the app can't raise the limit on time while the Mac sleeps, so if it is still waiting before sleep, it raises the limit to the target first and lets macOS finish charging during sleep (it may be full earlier than planned). If the start time hasn't come when the Mac wakes, the limit goes back to the care limit. Sleep waits up to 5 seconds for the write
- **"精準喚醒"** (precise wake): wakes the Mac 1 minute before charging should start and raises the limit to the target right after waking; the care limit holds the whole time before that. A wake is only scheduled while waiting, so a Mac that is already charged or unplugged isn't woken for nothing. Needs admin authorization once to install the system service shared with admin CPU sampling. The wake event's identifier is always `com.kuan.batterymonitor.charging` (visible in `pmset -g sched`), and the service only accepts one time between 1 minute and 7 days ahead. If authorization is withdrawn or the service is unavailable, it switches back to finish on time first

**Limits**: macOS still does the actual charging, and system mechanisms such as temperature protection or Optimized Battery Charging can pause it (the status shows "macOS 暫停充電", macOS paused charging), so a full charge on time isn't guaranteed.

**Log**: state changes, limit writes with the read-back values, sleep and wake, and wake scheduling are written to `~/Library/Logs/macbookBatteryMonitor/charging-plan.log`, which stays on this Mac and keeps only the second half once it passes 256 KB. `macbookBatteryMonitor --charging-plan-status` prints the current schedule, system charge limit, charge level, scheduled wake events and recent log lines without changing anything.

## Charging companion

"滑桿旁顯示" (shown next to the slider) at the top of the smart charging page, or "外觀" (Appearance) in Settings → Charging companion, switches between five appearances; on Macs that can't change the charge limit it's called "面板上方顯示" (shown at the top of the panel). When plugged in but not charging (at the limit or full), every appearance turns green with a plug badge at the top right.

- **Cat (default)**: a 6-second looping animation with a transparent background. Its belly rises and falls, the tail sweeps slowly now and then, and the dangling front paw sways. While charging it lies on a glowing charging pad with charging ripples above; while waiting there's a sleep badge, a check mark when done and a plug at the charge limit. It plays while the panel is open and shows a still image when the panel is closed or in power saving mode
- **Battery buddy**: a battery with a face, filled to the current charge. Blank without a schedule, eyes closed asleep while waiting, smiling while charging, laughing when done or at the limit, frowning when it may be late or macOS paused charging; it blinks now and then while the panel is open
- **Power flow**: a charge bar with dots flowing right while charging and a green plug at the charge limit
- **Cat photo**: the built-in photo of a Ragdoll cat, cropped to a circle with a charge ring around it (colored by state) and a status badge at the top right; its eyes move when it's the desktop pet
- **My photo**: a photo you choose with "選擇照片…" (Choose photo…) in Settings → Charging companion (or "換照片…" on the smart charging page and in the desktop pet's right-click menu). Choosing one switches to this appearance; the cat photo stays available. The photo is cropped square from the center, resized to 256 pixels and saved again (no location or other photo metadata), only in `~/Library/Application Support/BatteryMonitor/` on this Mac; "移除" (Remove) deletes it

## Desktop pet

On a MacBook, turn on "在桌面顯示" (show on desktop) in Settings → Charging companion and the companion appears on the desktop (bottom right at first), about the size of the Calendar widget.

![Desktop pet: the charging cat with a thought bubble, the battery buddy and the cat photo with speech bubbles, and the cat waiting for smart charging with a bubble below](docs/screenshots/desktop-pet.png)

- **Appearance**: the same as in the panel and always animated, except in power saving mode. The cat uses a high-resolution animation, with a glowing charging pad under its feet and a charging badge above its head while charging
- **Hover**: a thought bubble shows the charge and state (for example "62%・充電中，36 分鐘後到 80%", 62%, charging, 80% in 36 minutes, or "78%・還能用 7 小時 25 分", 78%, 7 h 25 min left), plus a line for a smart charging schedule
- **Click**: a speech bubble says something different each time: its mood (almost empty, charging, full, asleep while waiting for smart charging), today's charge used and regained, battery health and cycle count, or the whole Mac's power draw; it closes after 4 seconds
- **Double-click** opens the panel; **right click** opens the panel or changes the appearance, photo, size or position, opens the companion settings or hides it
- **Drag** it anywhere on screen, including next to the menu bar or above the Dock, even partly off screen (at least one corner stays on screen so you can find it again); its position is remembered. Dragging it to the top of the screen doesn't make macOS tile it like a window or zoom it to the middle
- **Size**: 50%–200% with the slider in Settings → Charging companion or "大小" (Size) in the right-click menu (small, standard, large, extra large); its feet stay in place when the size changes
- **Moving eyes** (cat photo): the eyes follow the mouse pointer and blink now and then; while waiting for smart charging they close in sleep and open when the pointer comes near. They use the cat's own irises from the photo and only move that small patch, so there's no CPU use while the mouse is still (about 0.4% extra CPU measured on an M1 while the mouse keeps moving). With "在桌面顯示" on and the cat photo appearance, Settings → Charging companion has "眼睛跟著游標" (eyes follow the pointer; off means no mouse tracking at all) and "會眨眼、睡覺" (blink and sleep). "My photo" doesn't have moving eyes
- **Stroking**: move the mouse back and forth over the pet a few times and hearts float up while it says "呼嚕呼嚕～" (purr), "好舒服喔" (that feels nice) and the like
- **Where it sits**: "浮在視窗上方" (above windows) or "放在桌布上" (on the wallpaper, at the desktop icon level, so windows cover it). It shows on every desktop but not in full-screen apps
- The bubble is a separate window that ignores the mouse and hugs the pet (below it when there's no room above), so it never blocks what's underneath

## Mouse and trackpad scroll directions

macOS's "natural scrolling" is one setting for both mouse and trackpad: if you like natural scrolling on the trackpad, the mouse wheel flips too. Settings → Mouse & trackpad separates them:

- **"滑鼠滾輪反向"** (reverse mouse wheel): reverses regular mouse wheels and Magic Mouse
- **"觸控板反向"** (reverse trackpad): reverses only the trackpad
- **How it tells them apart**: scrolling with two or more fingers on the trackpad counts as trackpad, including the momentum after lifting your fingers; everything else (wheels, Magic Mouse one-finger scrolling) counts as mouse. Vertical and horizontal scrolling are reversed together. Turning the wheel while trackpad momentum is still gliding follows the mouse setting for the wheel and keeps the trackpad setting for the rest of the momentum
- **No bouncing back in web pages**: reversed trackpad and Magic Mouse scrolls are replaced with newly created events, so the raw deltas web pages use for momentum are reversed too
- **Permission**: needs Accessibility. Turning a switch on asks you to enable "電池與系統監控" in System Settings → Privacy & Security → Accessibility; it starts working within seconds, no relaunch needed, and stays allowed after updates and reinstalls
- **Status**: the settings page shows the real state. "運作中" (working) means scroll events are being intercepted, "啟動中…" (starting) means permission is there and it starts shortly; without permission it shows an orange note and "打開輔助使用設定" (open Accessibility settings)
- **Power and reliability**: nothing is intercepted while both switches are off; when on, events are only handled at the moment you scroll. The interception runs on its own high-priority thread and is checked every 5 seconds: re-enabled if macOS paused it, rebuilt if it became invalid

How it works in detail: [docs/design/scroll-direction.md](docs/design/scroll-direction.md) (Chinese).

### If reversed scrolling stops working

This usually happens after updating from v1.7.3 or earlier: the "電池與系統監控" entry in the list is the old version's approval, and although its switch looks on it does nothing for the new version. Allow it again:

1. Open the app's Settings → Mouse & trackpad; it shows an orange note starting with "需要允許「輔助使用」" (Accessibility needed). Click "打開輔助使用設定" (open Accessibility settings)
2. Select "電池與系統監控" in the list and click "−" below it to remove it (even if its switch still looks on)
3. Click "+", choose `macbookBatteryMonitor` in Applications, click Open and make sure its switch is on
4. Back in the app's settings the status turns to "運作中" (working) within seconds, no relaunch needed

## App icon

The icon is a Ragdoll cat lying on its back on a wireless charging pad (a cut-out photo). Settings → General offers background colors: mint (built in), peach, night blue, sky blue.

![The four app icon background colors](docs/screenshots/app-icons.png)

- It changes the icon shown in Applications, Finder, Launchpad and Spotlight, the same as pasting a custom icon in Get Info; notifications and the login items list in System Settings use the built-in mint icon
- With a color other than mint, the app gets an extra custom icon file at its top level, so `codesign --verify --strict` reports an unexpected file; the app runs normally, permissions aren't affected, and switching back to mint removes the file
- After a one-click update or replacing the app with a new version, the app reapplies your color at launch

## One-click update

Settings → Update checks GitHub for new versions; when there is one, click "一鍵更新" (one-click update):

1. It downloads the DMG (the older macOS build downloads `macbookBatteryMonitor-macOS12.dmg`, or the universal build once the system is macOS 14 or later), only from `github.com` and `githubusercontent.com`
2. It verifies the download against the release's `SHA256SUMS.txt` and checks the app's identifier, version, beta number and signature. The DMG is mounted read-only in a temporary folder and never appears in Finder or on the desktop
3. When the app quits, the new version replaces it and relaunches; if that fails, the original version is put back. Settings, charge history, smart charging schedules and the app icon color are kept; temporary files are removed if downloading or verification fails or the update is interrupted

- **Check for updates automatically** (on by default): checks at launch and every 6 hours after, but only contacts `api.github.com` if the last check was more than a day ago; it only tells you and never installs by itself. A new release is found within about a day
- **Notify about new versions** (on by default): when an automatic check finds a new stable release, you get one notification per version; the notification or "有新版本" (new version available) at the bottom of the panel opens Settings → Update
- **Betas**: betas marked as pre-releases on GitHub (for example v1.8.0-beta.1) are only listed when you click "檢查更新" (check for updates); automatic checks don't mention them or notify. "安裝 Beta…" (install beta…) first explains that betas may be unstable, and only a second click on "安裝 Beta" installs it. If a stable release newer than the beta exists, only that is listed. To go back to stable, download a stable release from GitHub and reinstall
- If the app isn't in a writable location (for example installed by an administrator), one-click update can't work and points you to GitHub instead

**Updating from older versions**:
- every release includes the files older one-click updaters look for;
- v1.5.0 and later update straight to the latest version, except the v1.7.1 older macOS build, which goes through the bridge release v1.7.2 first;
- v1.4.1 and earlier have no one-click update and need one manual download.

## Desktop Macs

Macs without a battery show a computer icon with whole-system power in the menu bar. The panel has:
- whole-system power with a 3-minute average;
- a power breakdown: chip, CPU/GPU/ANE, other;
- power history, the most energy-hungry apps and peripherals.

The Settings window has no Charging or Charging companion sections and no battery notifications.

The app checks three things to recognize a desktop:
1. the product name, for example "Mac mini (M1, 2020)";
2. whether a battery is installed;
3. whether the system's power source list has an internal battery.

Apple silicon desktops also have an empty battery entry in the system, so v1.7.3 and earlier treated the M1 Mac mini as a laptop and showed 0%.

![Desktop Mac: system power in the menu bar and the power breakdown panel](docs/screenshots/desktop.png)

## Intel Macs

The universal build needs macOS 14 or later, roughly 2018 models and newer; older ones use the older macOS build. Tested on a 2018 Mac mini (Intel Core i5-8500B, macOS 15) and a 2015 MacBook Air (macOS 13, older macOS build):

- **Battery**: charge, voltage, current, cycle count and capacity match `pmset` and `ioreg`. macOS doesn't provide health (maximum capacity) or live adapter voltage and current on the 2015 MacBook Air, so those show "—"; the capacity gives an estimate
- **Temperatures**: the CPU uses per-core SMC temperature keys (from `TC1C`; missing cores report -127 and are filtered out), falling back to PECI/die/proximity (`TCXC`, `TC0F`, `TC0P`); integrated graphics `TCGC`, discrete GPU `TG0D`/`TG0P`; SSD `TH0a`/`TH0b`; MacBook battery the `TB0T` keys
- **CPU and integrated GPU power**: SMC `PCPC`/`PCPG`, which need no admin password, so Intel Macs have no admin CPU sampling
- **GPU memory**: Intel integrated graphics report `inUseSysMemoryBytes`; the occasional overflow value under load (larger than physical memory) is dropped
- Intel Macs can't have their charge limit changed by apps, so there's no charge limit slider or smart charging; the charging companion still shows at the top of the panel, and clicking it changes the appearance
- Old Intel Macs without HEVC hardware decoding still animate the charging companion

## Admin CPU sampling

Optional, off by default. Some Apple silicon chips (such as M1 and M2 Pro) don't update their CPU energy counter, so the chip details can only show 0 W for the CPU. If you want CPU power, turn on "管理員 CPU 取樣" (admin CPU sampling) under "CPU 功耗" (CPU power) in Settings → Monitoring & power saving, which reads it with the built-in `powermetrics` instead.

- **Turning it on**: the macOS admin authorization prompt only appears when you turn it on yourself in Settings, and installs a system service; no password is stored and sudoers isn't touched. If authorization is cancelled or fails, the option turns itself off again; launching the app or the Mac never asks for a password
- **Sampling**: it only connects while the main panel is open, at the same interval as everything else. Closing the panel, switching to the smart charging page, sleep or quitting disconnects, and `powermetrics` stops at once; the service exits after 30 seconds idle and doesn't stay resident
- **Power**: measured on an M1 MacBook Air, the service plus `powermetrics` use about 1% CPU extra while the panel is open (about 0.3% in power saving mode); with the panel closed it's the same as having it off
- **Security**: the service only accepts connections from the user who installed it, and can only start/stop `powermetrics` with fixed arguments (interval 1, 2, 5 or 10 seconds), schedule or cancel one smart charging wake with a fixed identifier within a limited time range, or remove itself; it accepts no arbitrary commands, paths or PIDs
- **Turning it off**: turning the option off stops and removes the service (no password needed); while precise wake still uses it, it only disconnects, and it's removed once both are off
- **Location**: the service is in `/Library/PrivilegedHelperTools/com.kuan.batterymonitor.cpu/`, its launch configuration in `/Library/LaunchDaemons/com.kuan.batterymonitor.cpu.plist`

## How power flow is measured

- **Adapter input** reads SMC `PDTR` and **system power** SMC `PSTR`; **battery power** is the difference, so the three numbers always add up. If either is missing, the battery's voltage × current is used instead
- **Whether it's charging** follows SMC's live power: the battery chip's charging flag often sticks to an old value, so it's only consulted when the power is ambiguous
- **Stable display**: while plugged in, switching between charging, at limit and not charging only takes effect after 10 seconds, so the icon doesn't flicker when macOS pauses and resumes charging near the limit; actually plugging or unplugging updates immediately. For 30 seconds after plugging in, the battery isn't drawn as supplying power (Intel chargers take a dozen seconds to start)
- **Time estimates**: while macOS is still estimating, it shows "計算中…" (calculating) instead of a straight-line guess (which ignores the slower current above 80%); with a charge limit, both the top right and the details show the time to the limit
- **Component details**: the display backlight reads SMC `PDBR`/`PBwo`; CPU/GPU/ANE read the IOReport energy model on Apple silicon and SMC `PCPC`/`PCPG` on Intel; "other" is system power minus backlight and chip, an estimate. When details are missing or samples aren't in sync, nothing is forced: it shows "資料不完整" (incomplete) or "取樣不同步" (samples out of sync)
- The chip total only covers the CPU, GPU and ANE values available, not the whole SoC, and excludes external displays. IOReport is a private system interface whose availability varies by chip and macOS version

| Model | System power | Backlight | GPU | CPU | ANE |
|---|---|---|---|---|---|
| M2 Pro | ✓ | ✓ | ✓ | Shows 0 W (counter doesn't update); readable with admin CPU sampling | 0 W when idle |
| M1 MacBook Air | ✓ | No sensor, hidden (counted in "other, including display") | ✓ | Shows 0 W (counter doesn't update); readable with admin CPU sampling | No channel, hidden |

How the sample windows are aligned and when "other" isn't shown: [docs/design/hardware-power-flow.md](docs/design/hardware-power-flow.md) (Chinese).

## Performance and power saving

Everything live updates every second by default; Settings → Monitoring & power saving can change it to every 2, 5 or 10 seconds, and slower uses less power. **Power saving mode** draws the power flow with static icons and arrows, stops the companion and flow animations, and updates at most every 2 seconds; "只在使用電池時啟用" (only on battery) turns it off automatically while plugged in.

![Power saving mode: static power flow](docs/screenshots/power-saving.png)

CPU usage measured on an M1 MacBook Air:

| Situation | Every second | Power saving (every 2 s) |
|---|---|---|
| Panel closed, battery only | About 0.2% | About 0.15% |
| Panel closed, all four system monitors on | About 1% | About 0.5% |
| Battery panel open (top energy users tab) | About 4%, plus about 6% for `top` | About 2%, plus about 3% for `top` |
| CPU or memory monitor panel open | About 3%, plus about 6% for `top` | About 2%, plus about 3% for `top` |

- With the panel closed, only what the menu bar needs is read (charge, state, power, time remaining); plugging and unplugging update immediately through system notifications. Menu bar icons are only redrawn when a number, time or state changes
- The panel is built each time it opens and released entirely when it closes, so nothing draws in the background. Component details, SMC temperatures and the optional admin CPU sampling are only read while the panel is open
- `top` only runs while the top energy users tab or a CPU/memory panel is open
- Each SMC key's format is looked up once and remembered; only `PDTR` and `PSTR` are read every second. Adapter details are read every 30 seconds while plugged in; the system charge limit only at launch, when the panel opens and when the system announces a change
- Smart charging does nothing without a schedule and only calls the system when the limit has to change
- Flow and charge bar animations are composited by Core Animation, not redrawn frame by frame; the charging companion is a small transparent HEVC video decoded once on first display and then played frame by frame (the desktop pet animating nonstop adds about 0.2% CPU and about 16 MB of memory on an M1)
- Only enabled monitors sample; with the master switch off, no monitor icons or timers are created at all
- Disk space is read with `statfs()` every second, and the purgeable space is recalibrated every 5 minutes; the external disk list doesn't hang on offline network volumes. Drive health is only read while the disk panel is open (about 0.2 ms each time); drives without it fall back to the SMART status, which launches `diskutil` and may wake a sleeping external drive, so it runs at most every 10 minutes per drive
- Fans and temperatures are read in the background every 2 seconds, only while the CPU panel is open
- Peripherals are checked every 60 seconds; headphones need `system_profiler`, so background updates only query it while a Bluetooth audio device is connected; Bluetooth LE devices are only asked for their battery when already connected, without new connections
- Charge history records one sample a minute and writes the file every 15 minutes, before sleep and on quit; health is checked every 6 hours

> Screenshots use demo data.

## Data sources

| Item | Source |
|---|---|
| Charge, voltage, raw current, capacity, cycle count | IORegistry `AppleSmartBattery` |
| Adapter input, system power, backlight | SMC (read-only, `PDTR`, `PSTR`, `PDBR`/`PBwo`); desktops only read `PSTR` |
| Live adapter voltage and current | SMC (read-only, `VD0R`, `ID0R`); otherwise `SystemCurrentIn` in IORegistry `PowerTelemetryData` |
| Battery power | Adapter input − system power; if either is missing, IORegistry voltage × current (`PPBR` is never used) |
| CPU/GPU/ANE power | Apple silicon: IOReport energy model, with `powermetrics` for the CPU under admin CPU sampling; Intel: SMC `PCPC`/`PCPG` (read-only) |
| System time estimate, whether on power | IOKit Power Sources |
| Whether it's charging | Mainly SMC live battery power; the battery chip's charging flags when the value is ambiguous |
| Health (maximum capacity), battery condition | `system_profiler SPPowerDataType` |
| Battery temperature | `Temperature` in IORegistry `AppleSmartBattery` (`VirtualTemperature` if missing), or SMC (read-only, `TB0T`–`TB2T`) when neither exists |
| Top energy users | `top -o power` |
| History backfill, unplug time | Charge history and `pmset -g log`; an unplug time before this boot counts from the boot time |
| Whether it's a desktop Mac | The product name in IORegistry, `BatteryInstalled` in `AppleSmartBattery`, the internal battery in IOKit Power Sources |
| Charge limit (setting and changes) | macOS's charge limit service (PowerUI's `PowerUISmartChargeClient`, also used by the Battery pane in System Settings); change notification `com.apple.powerui.mclstatuschanged`. No admin rights needed |
| Charge limit (currently in effect) | `/Library/Preferences/com.apple.powerd.charging.plist` (read-only; only exists while plugged in) |
| Smart charging speed | Average current while charging; otherwise the median charging speed over the past seven days of charge history |
| Smart charging precise wake | The admin service schedules a `wake` event with IOKit `IOPMSchedulePowerEvent` |
| Writes before sleep | IOKit system power notifications (`IORegisterForSystemPower`), delaying sleep by at most 5 seconds |
| Today's recap | Charge history (one sample a minute) |
| CPU usage, per core | Tick deltas from `host_processor_info`; core types from `hw.perflevel0/1` |
| Load average | `getloadavg` |
| GPU usage, GPU memory | `PerformanceStatistics` of IORegistry `IOAccelerator` (`inUseSysMemoryBytes` for Intel integrated graphics) |
| Memory breakdown, pressure, swap | `host_statistics64`, `kern.memorystatus_vm_pressure_level`, `vm.swapusage` |
| Disk space | `statfs()`, plus periodically recalibrated purgeable space (matches Finder) |
| Disk reads/writes | Cumulative byte counters of IORegistry `IOBlockStorageDriver` |
| External disks, connection type | `getfsstat(MNT_NOWAIT)`, DiskArbitration (`DeviceInternal`, `DeviceProtocol`) |
| Drive health, lifetime reads/writes, power-on time | The NVMe SMART / health information log (the system's NVMeSMARTLib plug-in, no admin rights): 100% minus Percentage Used, Data Units Read/Written (512,000 bytes per unit), Power On Hours |
| Drive health status (when the row above isn't available) | `SMARTStatus` from `diskutil info -plist` |
| Fan speed | SMC (read-only, `F<n>Ac`, `F<n>Mn`, `F<n>Mx`) |
| CPU panel temperatures | IOHIDEventSystem temperature sensors (private interface, hidden if missing); SMC core temperature keys on M2 chips; Intel: see "Intel Macs" |
| Network speed and totals | 64-bit interface counters from `sysctl` (`NET_RT_IFLIST2`), active interface only |
| Network interface and IP | `SCDynamicStore` (default route interface), `getifaddrs` |
| Top CPU / memory apps | `top -o cpu`, `top -o mem` |
| Peripheral batteries (keyboards, mice, trackpads) | IORegistry services with `BatteryPercent` |
| Peripheral batteries (Bluetooth LE mice, keyboards) | CoreBluetooth: the Battery Level (`0x2A19`) of the standard Battery Service (`0x180F`) on connected devices, Bluetooth permission required; the IORegistry HID usage tells mice and keyboards apart when the name doesn't |
| Peripheral batteries (headphone buds, case) | `system_profiler SPBluetoothDataType`; whether Bluetooth headphones are connected comes from CoreAudio's device list |
| Scroll directions (optional) | A `CGEvent` tap (scroll and trackpad finger events), Accessibility permission required; no tap while both switches are off |
| Moving eyes | `NSEvent` mouse-moved events (pointer position only, no permission needed); only while the desktop pet shows the cat photo with "眼睛跟著游標" (eyes follow the pointer) on |
| New versions | GitHub API `releases` (the latest 20); automatic checks at most once a day; downloads verified against the release's `SHA256SUMS.txt` |

## Where data is stored

- Charge history: `~/Library/Application Support/BatteryMonitor/history.json` (kept for 7 days)
- My photo: `~/Library/Application Support/BatteryMonitor/`
- Settings and smart charging schedules: `com.kuan.batterymonitor` (UserDefaults)
- Smart charging log: `~/Library/Logs/macbookBatteryMonitor/charging-plan.log`
- Admin service (only while admin CPU sampling or precise wake is on): `/Library/PrivilegedHelperTools/com.kuan.batterymonitor.cpu/`, `/Library/LaunchDaemons/com.kuan.batterymonitor.cpu.plist`

## Uninstall

1. If smart charging is set up, click "取消排程並還原" (cancel and restore) on the smart charging page first to restore the charge limit
2. In Settings, turn off admin CPU sampling, set smart charging's "睡眠時" (while asleep) back to finish on time first (this removes the system service if it was installed) and turn off launch at login, then quit the app. If you used scroll directions, remove the app from System Settings → Privacy & Security → Accessibility
3. Delete `/Applications/macbookBatteryMonitor.app`
4. If you deleted the app first and the system service is still there, run:
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

## Older versions

Older versions stay on [Releases](https://github.com/sgeric910601/macbookBatteryMonitor/releases), but all have known bugs that the latest version fixes; each release's notes list its known issues at the top. v1.5.0 and later can update straight to the latest version. If you want to save power, use the latest version with battery only plus power saving mode or a slower update interval instead of an older version.

| Version | Main additions |
|---|---|
| [v1.7.3](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.7.3) | Desktop pet moves freely, moving eyes, separate scroll directions, drive health as a percentage |
| [v1.7.2](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.7.2) | Desktop pet, Settings window, drag-to-install DMG |
| [v1.7.1](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.7.1) | Smart charging, charging companion, Intel and desktop Macs, macOS 12 build; battery and system monitor editions merged into one app |
| [v1.6.2](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.6.2) | Logitech, Razer and other Bluetooth mouse and keyboard batteries |
| [v1.6.0](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.6.0) | Charge limit slider |
| [v1.5.3](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.5.3) | External disks, fans and temperatures |
| [v1.5.0](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.5.0) | One-click update |
| [v1.4.1](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.4.1) | New app icon with four background colors |
| [v1.4.0](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.4.0) | Peripheral batteries, adjustable update interval and display items |
| [v1.3.0](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.3.0) | Battery and system monitor editions, power saving mode |
| [v1.2.2](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.2.2) | Everything updates every second, expandable component details |
| [v1.1.0](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.1.0), [v1.0.0](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.0.0) | Animated / static power flow |

## Build from source

Only the Command Line Tools (`xcode-select --install`) are needed, not Xcode.

```bash
git clone https://github.com/sgeric910601/macbookBatteryMonitor.git
cd macbookBatteryMonitor
./build.sh             # universal (Apple silicon + Intel): creates build/macbookBatteryMonitor.app
./build.sh install     # also installs it to /Applications and launches it
```

- Without a checkout you get the latest development version; to build a release, `git checkout v1.7.3` (or another tag) first
- `build.sh` builds both architectures at once and strips local symbols from the executable (`strip -x`; global symbols stay, so crash reports still show function names); with only the Command Line Tools, when both architectures can't be built at once, it builds for this Mac's architecture
- Signing: it signs with the "macbookBatteryMonitor Signing" certificate when a trusted one is in the keychain, otherwise ad-hoc; the last line says which. Your own builds are ad-hoc signed, so allow Accessibility and the other permissions yourself once, and again after switching to a released build
- `./build.sh battery` and `./build.sh status` package the apps for older versions' one-click updates (same content, only `MBMEdition` differs)
- The older macOS build is on the `legacy-macos12` branch and builds the same way

## Development

```bash
Scripts/test-power.sh    # all self-tests: conversions, power source states, plugged-in stability, sampling lifecycle, animations, system monitors,
                         # external disks, temperatures, service protocol, peripherals, one-click update (betas and DMGs), charge limit slider,
                         # smart charging, charge history and daily recap, desktop pet (runs with the Command Line Tools)
```

Debug flags:

```bash
APP=/Applications/macbookBatteryMonitor.app/Contents/MacOS/macbookBatteryMonitor
$APP --dump              # current readings as JSON
$APP --dump-hardware     # component power every second, five JSON samples
$APP --charging-plan-status # smart charging: schedule, system charge limit, charge, scheduled wake events and recent log lines (read-only)
$APP --snapshot <folder> # render each panel tab off screen to PNG
$APP --screenshots <folder> # draw the README images from demo data (docs/screenshots, except the app icon and desktop pet images)
$APP --dump-monitors     # system monitor readings (two samples 1 s apart) as JSON
$APP --dump-sensors 10   # a table of temperature sensors and fans every second, 10 times
$APP --dump-peripherals  # read peripheral batteries once (all Bluetooth devices) and print the time taken
$APP --notification-status # print the app's notification permission (check this first when notifications don't arrive)
$APP --selftest-panel    # open the panel for 20 seconds and close it, for power measurements
$APP --selftest-hardware # expand the chip, switch to the smart charging page, check that sampling stops and resumes, print CPU readings
$APP --selftest-monitors # open the CPU and memory panels for 10 seconds each, for power measurements
$APP --selftest-strip    # open the second status bar, then the CPU and battery panels, and print window frames and levels
$APP --selftest-precise-wake <minutes> # create a precise-wake schedule to 100%, cancel and restore 2 minutes after the limit is raised
$APP --selftest-settings # open Settings from the panel, visit every section, check it shows in the Dock while open and returns to menu-bar-only after
$APP --selftest-pet      # desktop pet: resize, simulate stroking, toggle pointer tracking, move to menu bar height, then simulate 30 s of mouse movement
$APP --selftest-scroll   # create wheel, trackpad, momentum and Magic Mouse scroll events and check which get reversed (no permission needed)
$APP --selftest-update   # check GitHub for a new version and one-click update right away (lower a copy's version to test)
$APP --selftest-dmg <DMG> # take the app out of a local DMG and verify it the way one-click update does (versions must match), without installing
```

Scroll direction logs: `/usr/bin/log stream --predicate 'subsystem == "com.kuan.batterymonitor" AND category == "scroll"'` (in zsh `log` is a builtin, so use the full path). After `defaults write com.kuan.batterymonitor scrollDebug -bool true` and relaunching the app, every scroll event's classification and its values before and after rewriting are logged too.

Design documents (Chinese):
- [Power flow and component power](docs/design/hardware-power-flow.md): sampling, alignment, when "other" isn't shown
- [Separate mouse and trackpad scroll directions](docs/design/scroll-direction.md): telling devices apart, why events are rebuilt, keeping it running
- [Releases, one-click update and signing](docs/design/release-and-signing.md): the two branches, GitHub Actions, DMGs, update verification, the stable signature and certificate handling

Other notes:
- The Command Line Tools have no SwiftUI macro plug-ins, so the code doesn't use `@State`; interface state (including the selected Settings section) lives in `PanelState`
- `build.sh` puts the admin service (`CPUPowerHelper`) in the app's `Contents/Library/Helpers/`, and the companion animations, still images and cat photo (`Resources/Companion/`) in `Contents/Resources/`; the service is only installed into the system when the user turns on admin CPU sampling or precise wake

DMG and app icon:

```bash
Scripts/make-dmg.sh build/macbookBatteryMonitor.app build/macbookBatteryMonitor.dmg   # package and check the app's signature inside the DMG
swiftc -O Scripts/make-dmg-background.swift -o build/make-dmg-background && build/make-dmg-background
tiffutil -cathidpicheck build/dmg-background.png build/dmg-background@2x.png -out Resources/DMG/background.tiff
swiftc -O Scripts/make-icon.swift -o build/make-icon
build/make-icon Resources/AppIcon.icns                                  # the built-in mint icon
for bg in peach night sky; do build/make-icon --bg $bg --size 512 --preview Resources/AppIcons/icon-$bg.png; done
```

The cat in the app icon is `Resources/icon-cat.png` (a cut-out photo); the charging pad, ripples and background are drawn by `Scripts/make-icon.swift`.

## Thanks

- [@melvin0kuo](https://github.com/melvin0kuo): animated power flow, layered component power, power sensor fallbacks, percentage inside the menu bar icon, stable full-charge display and admin CPU sampling (#1, #2, #4–#7), and the ideas for smart charging, charging schedules and the daily recap (#13)
- [@liaw-boy](https://github.com/liaw-boy): external disks, fans and temperatures, menu bar icon alignment on 1x screens, the layout idea of merging the charge limit slider into the info card, closing the panel by clicking outside, and power saving only on battery (#8–#10, #12)
