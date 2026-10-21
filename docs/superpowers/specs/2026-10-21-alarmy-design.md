# Alarmy (personal) — Design

Date: 2026-10-21
Status: **approved by owner 2026-10-21**

## Why this exists

The owner oversleeps. Mission alarms (like the Alarmy app) get them out of bed, but as soon as the mission is done and the alarm stops, they go straight back to bed. They want a personal iPhone alarm that:

1. makes them complete a mission to get past the alarm, and
2. **keeps ringing for X minutes after the mission is done**, so that by the time it stops they are awake enough to stay up, and
3. can't be escaped by a sleepy version of themselves: no uninstalling it, no switching it off the night before.

Success means the owner gets out of bed and stays up. The owner's own expectation: "if I set it up to keep going for 10 mins I probably won't be sleepy at that point."

## Goals

- A single mission type: **photo of a registered object**, picked at random each morning.
- **Keep ringing after the mission** for a configurable time (default 10 minutes), then stop by itself.
- **Edit lock**: alarm settings and objects can't be changed during a configurable window before the alarm.
- **Can't be uninstalled** (achieved with iOS settings plus TrollStore hardening, see below).
- Rings through the silent switch and Do Not Disturb/Focus.
- Free to build and install, from a Windows PC.

## Non-goals

- Other mission types (math, shake, steps, QR, etc.). The owner explicitly chose photo only.
- Snooze. There is no snooze.
- App Store distribution, other users, accounts, cloud sync, analytics.
- iOS 26 AlarmKit (the device is on iOS 16.5.1).
- Android, iPad, Apple Watch.

## Anti-goals (would be a failure even if it "works")

- **The alarm silently fails to ring.** That is the worst outcome. Reliability beats every other feature.
- Any "skip", "I'm awake", or "stop" button reachable while ringing or counting down.
- An easy way for a sleepy owner to defeat it: turning the alarm off the night before, setting the ring-after time to 0, deleting objects, lowering the volume, swiping the app closed, or deleting the app.
- A photo mission that can't be completed (for example, it's too dark to match), leaving the owner stuck with an endless alarm.

## Constraints

- **Device:** iPhone 13 Pro Max, **iOS 16.5.1 (c)**, with **TrollStore** installed. The owner must not update iOS, because TrollStore-installed apps likely stop launching on unsupported versions. The app should remind them of this once, during onboarding.
- **Owner's computer:** Windows only. No Mac.
- **Money:** $0. No Apple Developer Program membership.
- **Repo (owner approved):** a **public** GitHub repo under the owner's account `inverspe`, so macOS Actions minutes are free and unlimited. Each build is published as a **GitHub Release** asset so the owner can download it in Safari on the phone and open it straight into TrollStore. No personal data (photos, settings) goes in the repo. Note: the local `gh` login lacks the `workflow` scope, so pushing `.github/workflows/*` needs `gh auth refresh -s workflow` first.
- **Building:** a free cloud macOS build (GitHub Actions macOS runner) produces an unsigned/fake-signed `.ipa`/`.tipa` with the needed entitlements embedded, which the owner installs through TrollStore.
- **Testing:** there's no iOS simulator on the owner's machine, so on-device testing is done by the owner. Logic that can be unit-tested should be tested on the CI simulator.
- **Language/UI:** native Swift + SwiftUI, deployment target iOS 16.

## The experience (as decided with the owner)

Flow approved by the owner from wireframes (`.superpowers/brainstorm/.../content/morning-flow.html`):

1. **Ringing screen.** Shows the time and "Go find: <Object name>" with that object's reference photo. No snooze, no stop. The only action is **Open camera**.
2. **Camera.** Live viewfinder with the reference photo pinned in a corner, flash toggle, shutter. Camera capture only; picking from the photo library is not allowed.
3. **Miss.** "Not a match, try again." Stays on the camera, alarm keeps ringing.
4. **Countdown.** After a match: "Mission done ✓", a countdown ring showing time until it stops, and "You're up. Stay up." The alarm **keeps ringing throughout**. Nothing to tap. When the countdown ends, the alarm stops by itself.
5. **Edit alarm.** Time, repeat days, sound, mission (photo), keep-ringing-after (minutes, default 10), lock-edits-before (hours). Shows when it is locked.
6. **Your objects.** Grid of registered objects (name + reference photo). Add object = take a reference photo + name it.

### Photo mission (owner chose "register my own objects")

- The owner registers objects ahead of time, ideally in rooms away from the bed (the app suggests this).
- **An "object" is a fixed thing in its usual place** (kettle on the counter, bathroom sink, front door), not a portable item. Matching compares the whole scene against the reference photo(s), and onboarding tells the owner to pick things that don't move. This also stops a sleepy owner from bringing the object to bed. (My call, based on the examples the owner accepted.)
- Each morning one registered object is picked at random.
- Matching happens on-device and offline (Apple Vision image feature prints or similar). It must tolerate morning lighting; flash is available.
- There's a strictness setting (loose to strict) so the owner can tune false rejects and false accepts.
- No skip. An alarm can't be enabled with zero registered objects.
- **Fallback when the mission can't be done (owner approved):** after about 5 failed attempts on the same object, the app switches to a different registered object (random, not the one just failed). It cycles through all objects if needed. There is never a skip, so the owner always has to get up and photograph something. If only one object is registered, it stays on that object, which is why onboarding asks for at least 3.

### Clearing early (owner approved)

- If the owner is already up, they can complete the photo mission **before** the alarm to cancel that morning's ring entirely, with no countdown.
- My call: this is only available within **30 minutes before** the alarm time, so it can't be used at 3 AM. It's configurable per alarm, and the setting is subject to the edit lock.
- Clearing early cancels that occurrence's pre-scheduled backup notifications and ends the edit lock for that occurrence.

### Keep-ringing countdown

- X is configurable per alarm, defaulting to 10 minutes. It starts at the moment of a successful match.
- The alarm sound continues during the countdown. When it reaches 0, everything stops and the alarm is done for the day.

### Edit lock

- Configurable per alarm: "lock edits N hours before the alarm" (the owner said "a configurable time").
- While locked you can't edit, disable, or delete the alarm, change its X or lock settings, or add, remove or change objects. The lock ends when the alarm finishes (countdown complete) or is cleared early.
- If the alarm is never completed (for example, the phone was powered off), the lock ends at a hard cap so the app can't get stuck locked forever. My call: alarm time + 2 hours.

### Uninstall protection

- **Primary (no code):** onboarding walks the owner through iOS Settings → Screen Time → Content & Privacy Restrictions → iTunes & App Store Purchases → **Deleting Apps: Don't Allow**, with a Screen Time passcode they hand to someone else or hide.
- **TrollStore loophole:** TrollStore can uninstall apps itself and may ignore the Screen Time deletion block. Onboarding also tells the owner to put the TrollStore app behind a Screen Time limit (Always Allowed off / 1-minute app limit with passcode). The builder should verify whether Screen Time's deletion block actually covers TrollStore uninstalls on 16.5.1, and adjust the onboarding text.
- **Optional, in-app:** if TrollStore lets the app self-grant the Family Controls entitlement and individual authorization works, set `ManagedSettingsStore().application.denyAppRemoval = true`. This is a nice-to-have. If it doesn't work, drop it.

## Reliability and loophole handling

| Loophole | Handling |
|---|---|
| Silent switch / Focus | Alarm audio uses a playback audio session (ignores silent switch). Backup notifications use **critical alerts** (entitlement self-granted via TrollStore). |
| App swiped closed / killed / phone rebooted overnight | **Backup critical-alert notifications** are pre-scheduled about every 30 seconds starting at alarm time. Tapping one opens the app straight into the ringing/mission screen. After a match, backups are rescheduled to end exactly when the countdown ends. Note the iOS limit of 64 pending local notifications. |
| App suspended before alarm time | Alarmy-style keep-alive: the app keeps a background audio session running while an alarm is armed so it can play the alarm itself at full control. |
| Volume lowered | While ringing, the app pushes system volume back up. |
| Power off | **Cannot be prevented.** Accepted. |
| Changing the device clock to escape the lock or alarm | Known risk. The builder should make a reasonable effort, for example reacting to significant time-change notifications by not releasing locks. It doesn't have to be perfect. |
| Can't match in the dark | Flash, a lighting-tolerant matcher, and the strictness setting. Multiple reference shots per object are allowed (builder's call, see below). |

## Visual design

- The owner explicitly asked that the **frontend-design skill** be used to design the app's screens. The owner has given permission for that skill for this app. (Standing preference: ask before using any other skill.)
- The wireframes define layout and flow only. Look and feel (type, color, motion) is to be designed with that skill during the build.
- The ringing screens should be legible and usable half-asleep: big type, one obvious action.

## Left to the builder (calls I made, owner can override)

- Multiple alarms with repeat days are supported (a normal alarm list).
- A small set of loud built-in alarm sounds. No custom sound import in v1.
- 1–N reference photos per object, to improve matching across lighting.
- Default lock window: 8 hours before the alarm.
- Default strictness: medium. Tune on-device with the owner.
- Show a "keep the phone charging overnight" hint, since the background keep-alive uses battery.
- Exact matching technique, thresholds, notification cadence, and build/signing pipeline details (ldid vs TrollStore fakesign, `.tipa` vs `.ipa`).
- Project structure, persistence (SwiftData isn't available on iOS 16. Use Codable files, UserDefaults, or Core Data).
- Folder layout. This folder isn't a git repo yet, so the builder initializes one.
