# HealthKit Exporter

A minimal iPhone app that reads Apple Health / Fitness history through HealthKit and exports standardized JSON for the Personal Health OS project.

## V0.1 scope

- Request read-only HealthKit access
- Historical import
- Today's sync
- Sync since the last run
- Daily aggregates:
  - steps
  - active calories
  - exercise minutes
  - walking/running distance
  - weight
  - VO₂max
  - resting heart rate
  - sleep duration
- Workout records:
  - workout type
  - start/end
  - duration
  - distance
  - active calories
  - average heart rate
  - source
- JSON saved locally in the app's Documents/HealthExports directory
- Share Sheet export

No server upload is implemented yet.

## Generate the Xcode project

This repo uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project file does not need to be maintained by hand.

On your Mac:

```bash
brew install xcodegen
git clone https://github.com/2ez4jz/healthkit-exporter.git
cd healthkit-exporter
xcodegen generate
open HealthKitExporter.xcodeproj
```

Then in Xcode:

1. Select the `HealthKitExporter` target.
2. Choose your Apple Development Team under **Signing & Capabilities**.
3. Confirm **HealthKit** capability is present.
4. Connect your iPhone and run on the physical device.
5. Tap **Grant Health Access** and allow the Health categories you want to export.

HealthKit is not available in a meaningful way on the iOS simulator for your real personal data.

## Privacy

V0.1 does not upload health data anywhere. JSON stays on the iPhone until you explicitly share/export it.

## Next

After we validate exported numbers against Apple Health, the next step is reliable incremental sync and upload to a private database used by the Health OS dashboard.
