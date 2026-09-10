# Sonexis DMG Maker

Build the final installer from a notarized Sonexis app:

```sh
./Scripts/build-sonexis-dmg.sh ~/Downloads/Sonexis.app
```

You can optionally choose another output directory:

```sh
./Scripts/build-sonexis-dmg.sh ~/Downloads/Sonexis.app ~/Desktop
```

The maker automatically:

1. Reads the version and build from the app.
2. Verifies its code signature and notarization ticket.
3. Renders the Retina light Sonexis background.
4. Adds the Applications shortcut and saves the Finder layout.
5. Signs and verifies the finished DMG.
6. Prints the final SHA-256 checksum.

It requires Xcode command-line tools and a valid `Developer ID Application`
certificate in the login Keychain.
