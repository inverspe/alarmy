# AlarmLock

A personal add-on for the owner's own copy of Alarmy, decrypted from their own App Store install. It never contains or ships Alarmy itself.

## What it does

All settings are in the button at the bottom left of the Alarms tab.

**Lock**
- While locked, the Alarms tab is covered, so alarms can't be turned off, deleted or changed. Alarmy's emergency escape is hidden too.
- Only finishing an alarm opens it: the alarm rang and its missions were done. It then stays open until the chosen hours (1–12) before the next alarm, and locks again by itself.
- Turning the lock on counts as finishing an alarm, so it first locks at the chosen hours before the next one.
- Any alarm starting to ring closes it again at once, so a snooze can't be used to get in.
- If Alarmy is closed while an alarm rings and then started again, the lock stays on until an alarm is seen to finish. Closing it can't be used to get out.
- **Safety release:** if no alarm rings for 4 days, it opens. That only happens if alarms stopped working or something in the add-on broke, so the alarms can't be locked forever.
- It also opens if no alarm is turned on, since there's nothing to protect.
- Settings can only be changed while it's open or off.

**Mission delay** (off, or 1–30 minutes)
- For that long after an alarm goes off, the ringing screen is covered with a countdown, so the missions and snooze can't start and the alarm keeps ringing.
- Alarmy's mission previews aren't affected.

The add-on reads alarm times from Alarmy's own data and never writes to it. Moving the phone's clock doesn't change any of this until the phone is restarted.

## Building

CI builds `AlarmLock.dylib` on a Mac, after testing the lock rules (`.github/workflows/build.yml`). This PC has no compiler for iPhone code.

## Adding it to your copy

On your PC, with your own decrypted IPA:

```
node tools/inject.js <your-alarmy.ipa> AlarmLock.dylib <out.ipa>
```

Then install `out.ipa` with TrollStore. Never commit an IPA here: `.gitignore` blocks them.
