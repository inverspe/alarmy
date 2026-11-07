# AlarmLock

A personal add-on for the owner's own copy of Alarmy, decrypted from their own App Store install. It never contains or ships Alarmy itself.

## What it does

- A **Lock alarms** button on the Alarms tab turns the lock on.
- While the lock is on, the Alarms tab is covered, so alarms can't be turned off, deleted or changed. Alarmy's emergency escape is hidden too.
- Three sums unlock everything for 10 minutes. While it's unlocked, the lock can be turned off or the hours changed.
- In the chosen hours before the next alarm (1 to 12, or never), not even the sums unlock it. The add-on reads the next alarm time from Alarmy's own data and never writes to it.
- Moving the phone's clock doesn't change any of this until the phone is restarted, and a restart ends an unlock.

## Building

CI builds `AlarmLock.dylib` on a Mac, after testing the lock rules (`.github/workflows/build.yml`). This PC has no compiler for iPhone code.

## Adding it to your copy

On your PC, with your own decrypted IPA:

```
node tools/inject.js <your-alarmy.ipa> AlarmLock.dylib <out.ipa>
```

Then install `out.ipa` with TrollStore. Never commit an IPA here: `.gitignore` blocks them.
