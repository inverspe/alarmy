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

- Missions per alarm, stacked in any order the owner chooses: **photo of a registered object** (picked at random each morning), **steps**, **squats**, **shake** and **math**. Photo is the default. (Owner changed this from photo only on 2026-11-06.)
- **Keep ringing after the mission** for a configurable time (default 10 minutes), then stop by itself.
- **Vibrates** once a second while ringing, per alarm, on by default. Not while a mission is open, as that would disturb the motion sensors.
- **Edit lock**: alarm settings and objects can't be changed during a configurable window before the alarm.
- **Can't be uninstalled** (achieved with iOS settings plus TrollStore hardening, see below).
- Rings through the silent switch and Do Not Disturb/Focus.
- Free to build and install, from a Windows PC.

## Non-goals

- Other mission types (typing, memory, QR, etc.).
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

1. **Ringing screen.** Shows the time and "Go find: <Object name>" with that object's reference photo, or the mission to do. No snooze, no stop. The only action is **Open camera** or **Start mission**.
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
- Only the centre square of each photo is compared. A photo passes below a limit that starts at 20 and rises by 2 with every miss, up to 36. A pass sets it back to 20. The miss count carries over between alarms until then.
- No skip. An alarm can't be enabled with zero registered objects.
- **Fallback when the mission can't be done (owner approved):** after about 5 failed attempts on the same object, the app switches to a different registered object (random, not the one just failed). It cycles through all objects if needed. There is never a skip, so the owner always has to get up and photograph something. If only one object is registered, it stays on that object, which is why onboarding asks for at least 3.

### Stacked missions (owner requested 2026-11-06)

- Each alarm has an ordered list, with each kind at most once. An alarm can leave photo out, and the editor warns that it could then be finished from bed.
- All of them must be done, in order. The keep-ringing countdown starts after the last one.
- **Quiet during missions (per alarm, on by default):** starting a mission stops the sound, without stopping anything else. It stays stopped from one mission to the next. There's a switch on the mission screen for that one ring, which isn't saved. Leaving the app brings the sound back straight away.
- **20 seconds of nothing:** a bar shows the time left, and any input starts it again: a key, the shutter, or a count. When it runs out the mission closes, the sound comes back and the list starts over from the first mission. Missions keep their place if the app is closed.
- **Steps:** one for each second of movement, not real footsteps, from how much the accelerometer varies. Ten sharp jolts within 3 seconds freezes the count and vibrates, then 1 second later takes off 10 steps, and 1 second after that it carries on. Standing still for 3 seconds gives a nudge at no cost.
- **Squats:** two fingers held on the screen for 2 seconds start the mission. Then each 2 seconds of movement counts once if the phone is upright with its screen facing the owner and hasn't been twisted about, and it either moved hard enough or a whole down-and-up was seen. Movement that doesn't count gives a vibration. That second way of counting is ours and may need tuning.
- **Shake:** a sharp change in the accelerometer, at most five a second, at one of five strengths per alarm. Stopping for 3 seconds vibrates and shows "paused", with nothing lost.
- **Math:** seven difficulties per alarm, from 4 + 7 up to 240 × 35 + 1200. The default is like 24 × 7 + 35. A wrong answer clears the entry and keeps the same sum.
- **Can't be completed:** if a sensor can't be used, or hasn't got any further in 2 minutes of mission time, a button swaps that mission for 5 sums. (My call: this keeps the "mission can't be completed" anti-goal out, but waiting 2 minutes in bed does get out of walking.)
- A photo mission with no usable objects is dropped from the list. If that leaves nothing, the alarm rings for the countdown.
- A missed wake-up check restarts the whole list.
- Only alarms with a photo mission need registered objects.

### Clearing early (owner approved)

- If the owner is already up, they can complete the photo mission **before** the alarm to cancel that morning's ring entirely, with no countdown.
- My call: this is only available within **30 minutes before** the alarm time, so it can't be used at 3 AM. It's configurable per alarm, and the setting is subject to the edit lock.
- Finishing an early clear cancels that occurrence's pre-scheduled backup notifications and ends the edit lock for that occurrence. Until it's finished the backups stay in place, in case the app dies partway through.

### Keep-ringing countdown

- X is configurable per alarm, defaulting to 10 minutes. It starts at the moment of a successful match.
- The alarm sound continues during the countdown. When it reaches 0, everything stops and the alarm is done for the day.

### Wake-up check (owner requested 2026-11-06)

Off by default, set per alarm: 1, 3, 5, 7 or 10 minutes after the ring stops.

- When the keep-ringing countdown ends the sound stops, and the app shows when the check will come. Nothing can be tapped until then.
- At check time a quiet prompt appears (a normal notification sound, plus the prompt screen), with one button and **100 seconds** to answer.
- Answered: the alarm is done for the day.
- Not answered: the alarm rings again at full volume and the mission starts over with a different object if there is one. After that mission and countdown, the check comes again.
- The edit lock stays on throughout. There is no way to turn the check off once it has started (my call: a sleepy owner would use one).
- If the app is closed, the prompt and the repeat ring are pre-scheduled notifications.
- No new ring starts past the hard cap (alarm time + 2 hours).

### Gentle wake-up (owner requested 2026-11-06)

Off by default, set per alarm: 15, 30 or 60 seconds, or 5 or 10 minutes.

- The first ring starts at 5% of full level (never silent), stays low for a while, then rises quickly to full. System volume is still pushed to maximum; only the app's own level ramps. The ramp waits while a mission holds the sound back.
- The ramp is timed from the alarm time, so reopening the app doesn't restart it, and a repeat ring after a missed check is full volume at once.
- Backup notifications wait until the ramp has ended, otherwise they would blast at full volume over it, but never longer than 60 seconds if the app has been closed. **Cost:** if the app was closed, the first sound comes up to 60 seconds late, and a long ramp doesn't get to finish.

### Closing the app (owner requested 2026-11-06)

Swiping the app closed posts a notification about 2.5 seconds later saying so. The app holds on for 2 seconds while closing so iOS has time to accept it. iOS doesn't guarantee this runs every time, and the backups continue either way.

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
| Ringing with the phone locked or in another app | Ten silent banners over the first minute, which light up the lock screen. Tapping one opens the ringing screen. |
| App suspended before alarm time | Alarmy-style keep-alive: the app keeps a background audio session running while an alarm is armed so it can play the alarm itself at full control. |
| Volume lowered | While ringing, the app pushes system volume back up. |
| Earbuds or headphones connected | The ring goes to the phone's own speaker, including when they connect partway through. If iOS refuses, it rings through the current route rather than not at all. |
| Power off | **Cannot be prevented.** Accepted. |
| Changing the device clock to escape the lock or alarm | Known risk. The builder should make a reasonable effort, for example reacting to significant time-change notifications by not releasing locks. It doesn't have to be perfect. When the clock or time zone changes while the app is running, backups are rescheduled so they still fire at the real alarm time. |
| Can't match in the dark | Flash, a lighting-tolerant matcher, and a limit that rises with each miss. Multiple reference shots per object are allowed (builder's call, see below). |

## Visual design

- The owner explicitly asked that the **frontend-design skill** be used to design the app's screens. The owner has given permission for that skill for this app. (Standing preference: ask before using any other skill.)
- The wireframes define layout and flow only. Look and feel (type, color, motion) is to be designed with that skill during the build.
- The ringing screens should be legible and usable half-asleep: big type, one obvious action.

## Left to the builder (calls I made, owner can override)

- Multiple alarms with repeat days are supported (a normal alarm list).
- A small set of loud built-in alarm sounds. No custom sound import in v1.
- 1–N reference photos per object, to improve matching across lighting.
- Default lock window: 8 hours before the alarm.
- Show a "keep the phone charging overnight" hint, since the background keep-alive uses battery.
- Exact matching technique, thresholds, notification cadence, and build/signing pipeline details (ldid vs TrollStore fakesign, `.tipa` vs `.ipa`).
- Project structure, persistence (SwiftData isn't available on iOS 16. Use Codable files, UserDefaults, or Core Data).
- Folder layout. This folder isn't a git repo yet, so the builder initializes one.
