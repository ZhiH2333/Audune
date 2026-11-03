# Third-party notices

## mediaremote-adapter (Experimental Island Now Playing)

- Package: [ejbills/mediaremote-adapter](https://github.com/ejbills/mediaremote-adapter) (Swift Package Manager fork)
- Upstream technique: [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
- Pinned revision: `5b6afde3f501a3da567e23bf7f23d562938a1809`
- Purpose: optional system Now Playing metadata and transport via Apple’s private `MediaRemote.framework`, bridged through `/usr/bin/perl` on macOS 15.4+
- Scope in Audune: Settings → Notch Island → Show Now Playing when expanded (default off). Not part of Core MVP. Not App Store–ready. May break after OS updates.
- Audune does not claim ownership of MediaRemote; the helper is used only when the user enables the Experimental switch.
