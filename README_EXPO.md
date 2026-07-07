This branch contains an Expo-managed React Native scaffold to migrate the existing iOS app to cross-platform.

Quick start
1. Install Expo CLI (optional):
   npm install -g expo-cli
2. Install dependencies:
   npm install
3. Start Metro / Expo:
   npm run start
4. Run on device/emulator:
   npm run ios   # macOS + Xcode required for simulator
   npm run android

Notes
- I initialized Firebase using values extracted from GoogleService-Info.plist. If you have a Firebase Web configuration (preferred), replace the values in src/firebaseConfig.js with your web config.
- App icons and splash images are referenced at ./assets/icon.png and ./assets/splash.png — add appropriate images to the assets/ folder before building.

Publishing to stores
- For quick publishing with Expo EAS (recommended):
  1) Install EAS CLI: npm install -g eas-cli
  2) expo login (or create an Expo account)
  3) eas build --platform ios
  4) eas submit --platform ios
  5) For Android: eas build --platform android && eas submit --platform android

If your app uses iOS-only native features (ARKit, SceneKit, CoreML, etc.) we may need to eject to the bare workflow. I inspected the repository and did not yet analyze Swift files; after you test this scaffold, I can continue porting UI and logic.
