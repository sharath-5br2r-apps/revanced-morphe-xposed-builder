<div align="center"><h1>ReVanced <img src="https://raw.githubusercontent.com/nullcpy/rvb/a5af1123e55c63119c6b81be894602e2f032fe08/.github/assets/icon.png">, Morphe <img src="https://raw.githubusercontent.com/nullcpy/rvb/a5af1123e55c63119c6b81be894602e2f032fe08/.github/assets/icon1.png"> , Xposed and Eden Builder</h1></div>

<p align="center"><b>Automatically builds and publishes APKs & Magisk/KernelSU Modules whenever new patches are released.</b></p>

<p align="center"> <a href="../../Issues">Issues </a>, <a href="../../actions">GitHub Actions</a></p>

---

## Notable Changes

- Isolated config files from upstream.
- Added Support for dirctv2-dlurl and local-dlurl using aapt2 which can also be used for predl (i.e. using a unrecogonised source and preprocessing it)
- Completely removed telegram support
- Now considering both stable and prerelase patches for prerelease builds and completely removed stable patch builds.
- Added typeable manual config file trigger tk build only a particular toml manually.
- Added support for second flaresolverr compatible scraper along with cloudflarebypassforscraping.
- Moved BKS support from a apt based install into a maven+classpath based injection for local building.
- Added the entirety of [Eden-CI/Workflow](../Eden-CI) and modifed it to support this repo.
- Added the website code (nullcpy.github.io) as a [branch](../gh-pages) and significantly modifed it to support this repo.
- Added support for your own keystore with a fallback of j-hc's keystore if not available. The one in this repo is my private keystore via GitHub secrets.
- Removed Termux build wrapper, and instead you can still build manually on termux.
- Added signficant Config changes
- Improved x86 support
- Significantly improved local build support
- Actual Morphe experimental version support
- Reduced local on tree binaries and replaced tomlq with yq
- Added sign only apps for shared compatiblilty
- Added version names in apk files

For local use and modifications, see [CONFIG.md](CONFIG.md) for instructions on how to configure the builder and add your own apps and patches.

---
## 🤝 Support the Project Upstream

Building, testing, and maintaining these automated workflows takes a significant amount of time. If this builder has saved you time or made your life easier, any support is hugely appreciated!

- **❤️ [Donate To Upstream](https://fahim-ahmed05.github.io/donate)** if you can.
- **📢 Share the project** with others who might find it useful.

Thank you to everyone who helps keep this project alive!

---

> [!NOTE]
>
> 🌐 **[Check Catalog Website](https://sharath-5br2r.github.io/my-patched-apks)**
>
> For the best experience, please download from the website. It features:
>
> - 📱 **The complete list of every supported app.**
> - 📦 Clear separation between **Variant** builds.
> - 🏷️ Beautifully organized version numbers and download tracking.
> - 🔄 Step-by-step instructions on how to set up automatic updates using **Obtainium** and easy **Add to Obtainium** buttons.
>
> **🤖 Fully Automated Builds**
>
> All APKs and modules in this repository are 100% automated. If you need help, please direct your feedback to the right place:
>
> - 🧩 **Patch Issues:** If a specific feature/mod is broken (e.g., ads are showing), please open an issue in the **respective patch developer's repository**.
> - 🛠️ **Builder Issues and 💬General Help:** The builder is highly unstable and is frequently modifed. If you want new features or new apps or encounter a patching related bug, **[open an Issue here on GitHub](../../issues/new/choose)**


---

### 📦 Archive

> This release [Beta](../../releases/tag/beta) acts as a permanent, continuously updated vault, ensuring downloads remain reliably available without interruption.


---

### [MicroG](https://github.com/microg/GmsCore/wiki)

`com.google.android.gms`

> [!IMPORTANT]
> Signing into Google account on APK (not Module) requires MicroG. Please install [MicroG-RE](https://github.com/MorpheApp/MicroG-RE/releases/latest)  before trying to sign in.

## Download Apps

### [DolphinCS-master](../../../DolphinCS-master) builds are published here and is available on releases here and website.

Official Dolphin Emulator builds are available on [Dolphin Emulator](https://dolphin-emu.org/download/)

`com.dolphinemu.dolphinemu`

---

### [Eden Emulator](https://eden-emu.dev) is also automatically built [here](../Eden-CI) with only two variants(Optmised/Genshin Spoof and ChromeOS/x86_64) at every 4 hours and uploaded to the releases and website.

`dev.eden.eden_emulator`

---

### [Adobe Acrobat](https://play.google.com/store/apps/details?id=com.adobe.reader)

`com.adobe.reader`

#### [Hooman's patches (Morphe)](https://github.com/arandomhooman/hoomans-morphe-patches)

<details>
<summary id="adobe-acrobat-morphe-hooman">Version: v26.6.1</summary>

<blockquote>

[Release 2026-07-21](https://github.com/sharath-5br2r/my-patched-apks/releases/tag/260001)<br>
Patches: [arandomhooman/patches-1.43.1.mpp](https://github.com/arandomhooman/hoomans-morphe-patches/releases/tag/v1.43.1)
- Unlock Pro
</blockquote>
</details>

---
### [Advanced Download Manager](https://play.google.com/store/apps/details?id=com.dv.adm)

`com.dv.adm`

#### [Hooman's patches (Morphe)](https://github.com/arandomhooman/hoomans-morphe-patches)

<details>
<summary id="adm-morphe-hooman">Version: v14.0.39</summary>

<blockquote>

[Release 2026-07-21](https://github.com/sharath-5br2r/my-patched-apks/releases/tag/260001)<br>
Patches: [arandomhooman/patches-1.43.1.mpp](https://github.com/arandomhooman/hoomans-morphe-patches/releases/tag/v1.43.1)
- Remove ads
</blockquote>
</details>

---
### [Amazon India](https://play.google.com/store/apps/details?id=in.amazon.mShop.android.shopping)

`in.amazon.mShop.android.shopping`

#### [Rushi's patches (Morphe)](https://github.com/rushiranpise/morphe-patches)

<details>
<summary id="amazon-india-morphe-rushiranpise">Version: v32.12.4.300</summary>

<blockquote>

[Release 2026-07-21](https://github.com/sharath-5br2r/my-patched-apks/releases/tag/260001)<br>
Patches: [rushiranpise/patches-1.14.0.mpp](https://github.com/rushiranpise/morphe-patches/releases/tag/v1.14.0)
- Dark mode
- Disable search suggestions tracking
- Disable video autoplay
- Fix Amazon manifest conflicts
- Open links in browser
- Remove ads
- Sanitize share links
</blockquote>
</details>

---

### [Amazon Alexa](https://play.google.com/store/apps/details?id=com.amazon.dee.app)

`com.amazon.dee.app`

#### Signed APK (required when you need to install Alexa with patched prime video or Amazon)

<details>
<summary id="amazon-alexa-signed">Version: v2.2.695641.0</summary>
<blockquote>

[Release 2026-07-21](https://github.com/sharath-5br2r/my-patched-apks/releases/tag/260002)<br>
Patches: 
</blockquote>
</details>

---

### [Discord](https://play.google.com/store/apps/details?id=com.discord)

`com.discord`

#### [Revenge (revenge-mod)](https://github.com/revenge-mod/revenge-xposed) via [Npatch](https://github.com/7723mod/NPatch)

<details>
<summary id="discord-npatch-revenge">Version: v338.13-Stable</summary>

<blockquote>

[Release 2026-07-22](https://github.com/sharath-5br2r/my-patched-apks/releases/tag/260017)<br>
Patches: [revenge-mod/app-release.apk](https://github.com/revenge-mod/revenge-xposed/releases/tag/1410)
</blockquote>
</details>



---


### [Fing - Network Tools](https://play.google.com/store/apps/details/Fing_Ferramentas_de_rede?id=com.overlook.android.fing)

`com.overlook.android.fing`

#### [Paresh patches (Morphe)](https://gitlab.com/Paresh-Maheshwari/paresh-patches)

<details>
<summary id="fing-morphe-paresh">Version: v12.12.0</summary>
  
<blockquote>

[Release 2026-07-21](https://github.com/sharath-5br2r/my-patched-apks/releases/tag/260001)<br>
Patches: [Paresh-Maheshwari/patches-1.19.0.mpp](https://gitlab.com/Paresh-Maheshwari/paresh-patches/-/releases/v1.19.0)
- Fing Premium
</blockquote>
</details>



--- 

### [GitHub](https://play.google.com/store/apps/details?id=com.github.android)

`com.github.android`

#### [hoo-dles patches (Morphe)](https://github.com/hoo-dles/morphe-patches)

<details>
<summary id="github-morphe-hoodles">Version: v1.267.0</summary>
  
<blockquote>

[Release 2026-07-23](https://github.com/sharath-5br2r/my-patched-apks/releases/tag/260030)<br>
Patches: [hoo-dles/patches-1.40.0-dev.4.mpp](https://github.com/hoo-dles/morphe-patches/releases/tag/v1.40.0-dev.4)
- AMOLED dark theme
</blockquote>
</details>

---

### [Geode Launcher](https://geode-sdk.org/)

`com.geode.launcher`

#### Spoof to PUBG:KR via [Morphe patches](https://github.com/MorpheApp/morphe-patches)
<details>
<summary id="geode-viamorphe-pubgkr">Version: v1.8.0</summary>

<blockquote>

[Release 2026-07-22](https://github.com/sharath-5br2r/my-patched-apks/releases/tag/260013)<br>
Patches: [MorpheApp/patches-1.36.0-dev.8.mpp](https://github.com/MorpheApp/morphe-patches/releases/tag/v1.36.0-dev.8)
- Change package name
</blockquote>
</details>

---

### [Google Keyboard (Gboard)](https://play.google.com/store/apps/details?id=com.google.android.inputmethod.latin)

`com.google.android.inputmethod.latin`

#### [Gboard patches for Morphe (jasonwu1994)](https://github.com/jasonwu1994/Gboard-patches) + [Rushi's GmsCore patch](https://github.com/rushiranpise/morphe-patches)

<details>
<summary id="gboard-morphe-jasonwu1994">Version: v17.0.10.880768217-release-arm64-v8a</summary>
  
<blockquote>

[Release 2026-07-21](https://github.com/sharath-5br2r/my-patched-apks/releases/tag/260004)<br>
Patches: [jasonwu1994/patches-1.14.0.mpp](https://github.com/jasonwu1994/Gboard-patches/releases/tag/v1.14.0)
- AI Writing Tools
- Add Gboard Signature Bypass
- Chinese Online Voice Input
- Clipboard Enhancements
- Clipboard Entity Extraction
- Clipboard Item Edit
- Custom Symbols
- Emojis, stickers & GIFs Tab Order
- Enable Inline Autofill Suggestions
- Enable Undo/Redo feature
- English QWERTY Up-Flick Uppercase
- Grammar Checker
- Inline Suggestions
- Key Shape Selection
- Latin Globe Key Ignore Interval
- Package Rename
- Settings Homepage Override
- Swipeable Custom Top Row
- Web Clipboard
- Zhuyin Bottom Row Key Sizes
- Zhuyin Quick Traditional/Simplified Toggle
- Zhuyin Slide Input
</blockquote>
</details>

#### [Gboard patches for Morphe (jasonwu1994) Root](https://github.com/jasonwu1994/Gboard-patches)
<details>
<summary id="gboard-morphe-jasonwu1994-root">Version: v17.0.10.880768217-release-arm64-v8a</summary>
  
<blockquote>

[Release 2026-07-16](https://github.com/sharath-5br2r/patched-apks-builder-2nd/releases/tag/260081)<br>
Patches: [jasonwu1994/patches-1.14.0.mpp](https://github.com/jasonwu1994/Gboard-patches/releases/tag/v1.14.0)
- AI Writing Tools
- Add Gboard Signature Bypass
- Chinese Online Voice Input
- Clipboard Enhancements
- Clipboard Entity Extraction
- Clipboard Item Edit
- Custom Symbols
- Emojis, stickers & GIFs Tab Order
- Enable Inline Autofill Suggestions
- Enable Undo/Redo feature
- English QWERTY Up-Flick Uppercase
- Grammar Checker
- Inline Suggestions
- Key Shape Selection
- Latin Globe Key Ignore Interval
- Settings Homepage Override
- Swipeable Custom Top Row
- Web Clipboard
- Zhuyin Bottom Row Key Sizes
- Zhuyin Quick Traditional/Simplified Toggle
- Zhuyin Slide Input
</blockquote>
</details>

---


### [Instagram](https://play.google.com/store/apps/details?id=com.instagram.android)

`com.instagram.android`


#### [Piko (Morphe)](https://github.com/crimera/piko)

<details>
<summary id="instagram-morphe-piko">Version: v435.0.0.37.76</summary>

<blockquote>

[Release 2026-07-23](https://github.com/sharath-5br2r/my-patched-apks/releases/tag/260032)<br>
Patches: [crimera/patches-3.8.0-dev.6.mpp](https://github.com/crimera/piko/releases/tag/v3.8.0-dev.6)
- Add settings
- Allow user network certificate
- Change like animation
- Change version code
- Copy comment
- Customise story ring size
- Customise story timestamp
- Disable Reels scrolling
- Disable ads
- Disable analytics
- Disable comments
- Disable discover people
- Disable double tap like
- Disable explore
- Disable highlights
- Disable screenshot detection
- Disable stories
- Disable story flipping
- Disable swipe to create
- Disable typing status
- Disable video autoplay
- Download media
- Download voice message
- External downloader
- Filter stories
- Friendship status indicator
- Hide group creation button on sharesheet
- Hide navigation buttons
- Hide notes tray
- Hide reshare button
- Hide stories tray
- Hide suggested content
- Improve image viewing
- Limit feed to following profiles
- Make ephemeral media permanent
- Mark chat as read manually
- More options on post
- More options on profile
- Open links externally
- Remove build expired popup
- Remove empty bottom space
- Sanitize share links
- Save media comment
- Stories audio autoplay
- Unlock Plus benefits
- Unlock developer options
- Unlock employee options
- Validate links
- View DMs anonymously
- View live anonymously
- View stories anonymously
- View story mentions
</blockquote>
</details>

---

### [JioHotstar](https://play.google.com/store/apps/details?id=in.startv.hotstar)

`in.startv.hotstar`

#### [Paresh patches (Morphe)](https://gitlab.com/Paresh-Maheshwari/paresh-patches)

<details>
<summary id="jiohotstar-morphe-paresh">Version: v26.04.27.10</summary>

<blockquote>

[Release 2026-07-21](https://github.com/sharath-5br2r/my-patched-apks/releases/tag/260001)<br>
Patches: [Paresh-Maheshwari/patches-1.19.0.mpp](https://gitlab.com/Paresh-Maheshwari/paresh-patches/-/releases/v1.19.0)
- Bypass signature check
- Enable all codecs
- Enable screen mirroring
- Enable screenshots
- Force HDR10
- Premium unlock
- Remove ads
</blockquote>
</details>

---

### [LeviLauncher Unlocked](https://github.com/0Sombra666/LeviLaunchroidUnlocked)
[Original](https://github.com/LiteLDev/LeviLaunchroid)

`org.levimc.launcher`

#### Spoof to BGMI via [Morphe patches](https://github.com/MorpheApp/morphe-patches)

<details>
<summary id="levilauncher-unlocked-viamorphe-bgmi">Version: v1.5.6</summary>
  
<blockquote>

[Release 2026-07-22](https://github.com/sharath-5br2r/my-patched-apks/releases/tag/260013)<br>
Patches: [MorpheApp/patches-1.36.0-dev.8.mpp](https://github.com/MorpheApp/morphe-patches/releases/tag/v1.36.0-dev.8)
- Change package name
</blockquote>
</details>

---

### [Moon+ Reader](https://play.google.com/store/apps/details?id=com.flyersoft.moonreader)

`com.flyersoft.moonreader`

#### [binarymend patches (Morphe)](https://github.com/binarymend/morphe-patches)

<details>
<summary id="moonplus-reader-morphe-binarymend">Version: v10.5</summary>
  
<blockquote>

[Release 2026-07-21](https://github.com/sharath-5br2r/my-patched-apks/releases/tag/260001)<br>
Patches: [binarymend/patches-1.3.1.mpp](https://github.com/binarymend/morphe-patches/releases/tag/v1.3.1)
- Make UI look like Pro
- Unlock Moon+ Reader Pro
</blockquote>
</details>

---

### [Prime Video](https://play.google.com/store/apps/details?id=com.amazon.avod.thirdpartyclient)

`com.amazon.avod.thirdpartyclient` 

#### [hoo-dles patches (Morphe)](https://github.com/hoo-dles/morphe-patches)

<details>
<summary id="prime-video-morphe-hoodles">Version: v3.0.463</summary>

<blockquote>

[Release 2026-07-23](https://github.com/sharath-5br2r/my-patched-apks/releases/tag/260030)<br>
Patches: [hoo-dles/patches-1.40.0-dev.4.mpp](https://github.com/hoo-dles/morphe-patches/releases/tag/v1.40.0-dev.4)
- Enable speed control
- Skip ads
</blockquote>
</details>

---

### [Proton VPN](https://play.google.com/store/apps/details?id=ch.protonvpn.android)

`ch.protonvpn.android`

#### [Paresh patches (Morphe)](https://gitlab.com/Paresh-Maheshwari/paresh-patches)

<details>
<summary id="proton-vpn-morphe-paresh">Version: v5.19.16.0</summary>
  
<blockquote>

[Release 2026-07-23](https://github.com/sharath-5br2r/my-patched-apks/releases/tag/260032)<br>
Patches: [Paresh-Maheshwari/patches-1.19.0.mpp](https://gitlab.com/Paresh-Maheshwari/paresh-patches/-/releases/v1.19.0)
- Disable telemetry
- Proton VPN Premium
</blockquote>
</details>


---



### [Speedtest](https://play.google.com/store/apps/details?id=org.zwanoo.android.speedtest)

`org.zwanoo.android.speedtest`

#### [Xtra Patches for Morphe (BholeyKaBhakt)](https://github.com/BholeyKaBhakt/revanced-patches-xtra)

<details>
<summary id="speedtest-morphe-xtra">Version: v7.0.4</summary>
  
<blockquote>

[Release 2026-07-21](https://github.com/sharath-5br2r/my-patched-apks/releases/tag/260001)<br>
Patches: [BholeyKaBhakt/patches-2.12.0.mpp](https://github.com/BholeyKaBhakt/revanced-patches-xtra/releases/tag/v2.12.0)
- AdFree Account
- Disable Logging(analytics)
</blockquote>
</details>

---

### [Symfonium](https://play.google.com/store/apps/details?id=app.symfonik.music.player)

`app.symfonik.music.player`

#### [Hooman's patches (Morphe)](https://github.com/arandomhooman/hoomans-morphe-patches)

<details>
<summary id="symfonium-morphe-hooman">Version: v14.1.0</summary>

<blockquote>

[Release 2026-07-21](https://github.com/sharath-5br2r/my-patched-apks/releases/tag/260001)<br>
Patches: [arandomhooman/patches-1.43.1.mpp](https://github.com/arandomhooman/hoomans-morphe-patches/releases/tag/v1.43.1)
- Unlock Premium
</blockquote>
</details>

---


### [TikTok](https://play.google.com/store/apps/details?id=com.zhiliaoapp.musically)

`com.zhiliaoapp.musically`

#### [TikTok Patches for Morphe (icysymmetra)](https://github.com/icysymmetra/tiktok-patches-for-morphe)

<details>
<summary id="tiktok-morphe-tiktok">Version: v43.8.3</summary>
  
<blockquote>

[Release 2026-07-26](https://github.com/sharath-5br2r/my-patched-apks/releases/tag/260068)<br>
Patches: [icysymmetra/patches-0.4.0-dev.1.mpp](https://github.com/icysymmetra/tiktok-patches-for-morphe/releases/tag/v0.4.0-dev.1)
- Always show publish date
- Copy comments without username
- Custom offline videos limit
- Disable login requirement
- Downloads
- Enable Open Debug
- Feature Gate Lab
- Feed filter
- Feed tab navigation
- Fix Google login
- Hide CAPTCHA popups
- Hide floating promotions
- Hold-and-slide 2x lock
- Open external links directly
- Playback speed
- Remember clear display
- SIM spoof
- Sanitize sharing links
- Settings
- Show seekbar
- Translate comments
- Disable screen capture detection
</blockquote>
</details>

---
### [Winlator Ludashi](https://github.com/StevenMXZ/Winlator-Ludashi)

`com.winlator.cmod`

#### Spoofed to PUBG:VN via [Morphe patches](https://github.com/MorpheApp/morphe-patches)

<details>
<summary id="winlator-viamorphe-pubgvn">Version: v3.1</summary>

<blockquote>

[Release 2026-07-22](https://github.com/sharath-5br2r/my-patched-apks/releases/tag/260013)<br>
Patches: [MorpheApp/patches-1.36.0-dev.8.mpp](https://github.com/MorpheApp/morphe-patches/releases/tag/v1.36.0-dev.8)
- Change package name
</blockquote>
</details>

---

### [X / Twitter](https://play.google.com/store/apps/details?id=com.twitter.android)

`com.twitter.android`

#### [Piko (Morphe)](https://github.com/crimera/piko) with [inotia00](https://gitlab.com/inotia00/x-shim) shim layer

<details>
<summary id="x-morphe-piko">Version: v12.11.0-release.0</summary>
  
<blockquote>

[Release 2026-07-24](https://github.com/sharath-5br2r/my-patched-apks/releases/tag/260047)<br>
Patches: [inotia00/patches-1.7.0.mpp](https://gitlab.com/inotia00/x-shim/-/releases/v1.7.0), [crimera/patches-3.8.0-dev.6.mpp](https://github.com/crimera/piko/releases/tag/v3.8.0-dev.6)
- Abstract shim layer
- Abstract shim layer for method
- Abstract shim layer for native library
- Add ability to copy media link
- Block redirecting to X Lite
- Change app icon
- Change version code
- Clear tracking params
- Control video auto scroll
- Custom download folder
- Custom emoji font
- Custom font
- Custom share menu
- Custom sharing domain
- Customise post font size
- Customize Inline action Bar items
- Customize Navigation Bar items
- Customize default reply sorting
- Customize explore tabs
- Customize notification tabs
- Customize profile tabs
- Customize search suggestions
- Customize search tab items
- Customize side bar items
- Customize timeline top bar
- Delete from database
- Disable auto timeline scroll on launch
- Disable chirp font
- Download patch
- Dynamic color
- Enable PiP mode automatically
- Enable Undo Posts
- Enable debug menu for posts
- Enable force HD videos
- Force enable translate
- Handle custom twitter links
- Hide Banner
- Hide Community Notes
- Hide FAB
- Hide FAB Menu Buttons
- Hide Live Threads
- Hide Recommended Users
- Hide badges from navigation bar icons
- Hide bookmark icon in timeline
- Hide community badges
- Hide followed by context
- Hide hidden replies
- Hide immersive player
- Hide nudge button
- Hide post metrics
- Hide promote button
- Hide recommendation items
- Hook feature flag
- Import/Export login token
- Legacy share links
- Log server response
- Native downloader
- Native reader mode
- Native translator
- No shortened URL
- Pause search suggestions
- Remove Ads
- Remove premium upsell
- Remove search suggestions
- Remove view count
- Round off numbers
- Selectable Text
- Share Tweet as Image
- Show changelogs
- Show poll results
- Show post source label
- Show sensitive media
- Support external downloader
</blockquote>
</details>

---

### [YouTube](https://play.google.com/store/apps/details?id=com.google.android.youtube)

`com.google.android.youtube`

#### [Morphe Experimental](https://github.com/MorpheApp/morphe-patches)

<details>
<summary id="youtube-morphe-exp">Version: v21.29.366</summary>
  
<blockquote>

[Release 2026-07-25](https://github.com/sharath-5br2r/my-patched-apks/releases/tag/260061)<br>
Patches: [MorpheApp/patches-1.37.0-dev.2.mpp](https://github.com/MorpheApp/morphe-patches/releases/tag/v1.37.0-dev.2)
- Add to queue
- Alternative thumbnails
- Ambient mode
- Bypass image region restrictions
- Bypass link redirects
- Captions
- Change form factor
- Change header
- Change start page
- Check watch history domain name resolution
- Copy video link
- Custom branding
- Custom player overlay opacity
- Disable DRC audio
- Disable QUIC protocol
- Disable Shorts resuming on startup
- Disable double tap actions
- Disable fullscreen gestures
- Disable haptic feedback
- Disable layout updates
- Disable player popup panels
- Disable rolling number animations
- Disable sign in to TV popup
- Disable video codecs
- Double tap to seek
- Downloads
- Enable debugging
- Exit fullscreen mode
- Force original audio
- GmsCore support
- Hide Shorts components
- Hide ads
- Hide autoplay preview
- Hide end screen cards
- Hide end screen suggested video
- Hide info cards
- Hide layout components
- Hide player flyout menu components
- Hide player overlay buttons
- Hide related video overlay
- Hide related videos
- Hide timestamp
- Hide video action buttons
- Loop video
- Media notification controls
- Miniplayer
- Navigation bar
- Network proxy
- Open Shorts in regular player
- Open channel of live avatar
- Open links externally
- Open system share sheet
- Open videos fullscreen
- Override YouTube Music buttons
- Play all
- Playback speed
- Reload video
- Remove background playback restrictions
- Remove viewer discretion dialog
- Return YouTube Dislike
- Sanitize sharing links
- Save to watch later
- Seekbar
- Settings menu filter
- Shorts autoplay
- SponsorBlock
- Spoof app version
- Spoof device dimensions
- Spoof video streams
- Swipe controls
- Theme
- Video quality
- Voice over translation
</blockquote>
</details>

#### [anddea (Morphe)](https://github.com/anddea/revanced-patches)
<details>
<summary id="youtube-morphe-anddea">Version: v20.51.39</summary>
  
<blockquote>

[Release 2026-07-24](https://github.com/sharath-5br2r/my-patched-apks/releases/tag/260052)<br>
Patches: [anddea/patches-4.2.0-dev.8.mpp](https://github.com/anddea/revanced-patches/releases/tag/v4.2.0-dev.8)
- Alternative thumbnails
- Ambient mode control
- Bypass URL redirects
- Bypass image region restrictions
- Change form factor
- Change player flyout menu toggles
- Change share sheet
- Change start page
- Custom Shorts action buttons
- Custom double tap length
- Description components
- Disable QUIC protocol
- Disable forced auto audio tracks
- Disable forced auto captions
- Disable haptic feedback
- Disable layout updates
- Disable resuming Miniplayer on startup
- Disable resuming Shorts on startup
- Disable sign in to TV popup
- Disable splash animation
- Enable debug logging
- Enable gradient loading screen
- Force player buttons background
- Fullscreen components
- GmsCore support
- Hide action buttons
- Hide ads
- Hide comments components
- Hide feed components
- Hide feed flyout menu
- Hide layout components
- Hide player buttons
- Hide player flyout menu
- Hook YouTube Music actions
- Hook download actions
- Miniplayer
- Navigation bar components
- Open links externally
- Overlay buttons
- Player components
- Remove background playback restrictions
- Remove viewer discretion dialog
- Return YouTube Dislike
- Return YouTube Username
- Sanitize sharing links
- Seekbar components
- Set transcript cookies
- Settings menu filter
- Shorts components
- Snack bar components
- SponsorBlock
- Spoof app version
- Spoof video streams
- Spoof watch history
- Swipe controls
- Theme
- Toolbar components
- Translations for YouTube
- Video playback
- Voice Over Translation
- Visual preferences icons for YouTube
- Reload video
- Settings for YouTube
</blockquote>
</details>

---


### [YouTube Music](https://play.google.com/store/apps/details?id=com.google.android.apps.youtube.music)

`com.google.android.apps.youtube.music`

#### [Morphe Experimental](https://github.com/MorpheApp/morphe-patches)

<details>
<summary id="youtube-music-morphe-exp">Version: v9.28.51</summary>
  
<blockquote>

[Release 2026-07-25](https://github.com/sharath-5br2r/my-patched-apks/releases/tag/260061)<br>
Patches: [MorpheApp/patches-1.37.0-dev.2.mpp](https://github.com/MorpheApp/morphe-patches/releases/tag/v1.37.0-dev.2)
- Bypass certificate checks
- Change header
- Change miniplayer color
- Change start page
- Check watch history domain name resolution
- Crossfade
- Custom branding
- Disable DRC audio
- Disable QUIC protocol
- Disable dislike redirection
- Downloads
- Enable debugging
- Enable exclusive audio playback
- Enable forced miniplayer
- Enable swipe to dismiss miniplayer
- Force original audio
- GmsCore support
- Hide ads
- Hide buttons
- Hide filter bar
- Hide flyout menu components
- Hide layout components
- Hide music action buttons
- Miniplayer previous and next buttons
- Navigation bar
- Network proxy
- Remember repeat state
- Remember shuffle state
- Remove background playback restrictions
- Return YouTube Dislike
- Sanitize sharing links
- Scrobbling
- Settings menu filter
- SponsorBlock
- Spoof app version
- Spoof video streams
- Theme
</blockquote>
</details>

#### [anddea (Morphe)](https://github.com/MorpheApp/morphe-patches)

<details>
<summary id="youtube-music-morphe-anddea">Version: v9.15.51</summary>
  
<blockquote>

[Release 2026-07-24](https://github.com/sharath-5br2r/my-patched-apks/releases/tag/260052)<br>
Patches: [anddea/patches-4.2.0-dev.8.mpp](https://github.com/anddea/revanced-patches/releases/tag/v4.2.0-dev.8)
- Bitrate default value
- Bypass image region restrictions
- Certificate spoof
- Change share sheet
- Change start page
- Dark theme
- Disable Cairo splash animation
- Disable QUIC protocol
- Disable dislike redirection
- Disable forced auto audio tracks
- Disable forced auto captions
- Enable debug logging
- Enable landscape mode
- Flyout menu components
- GmsCore support
- Hide account components
- Hide action bar components
- Hide ads
- Hide layout components
- Navigation bar components
- Player components
- Remove background playback restrictions
- Remove viewer discretion dialog
- Restore old style library shelf
- Return YouTube Dislike
- Return YouTube Username
- Sanitize sharing links
- Settings menu filter
- SponsorBlock
- Spoof app version for lyrics
- Spoof video streams
- Track crossfade
- Translations for YouTube Music
- Video playback
- Watch history
- Visual preferences icons for YouTube Music
- Settings for YouTube Music
</blockquote>
</details>

---

### [Zalith Launcher 2 Plus](https://github.com/Star1xr/ZalithLauncher2Plus)
[Original](https://github.com/ZalithLauncher/ZalithLauncher2)

`com.movtery.zalithlauncher.v2`

#### Spoofed to CODM via [Morphe patches](https://github.com/MorpheApp/morphe-patches)

<details>
<summary id="zalith-launcher-2-plus-viamorphe-codm">Version: v2.4.10</summary>

<blockquote>

[Release 2026-07-22](https://github.com/sharath-5br2r/my-patched-apks/releases/tag/260013)<br>
Patches: [MorpheApp/patches-1.36.0-dev.8.mpp](https://github.com/MorpheApp/morphe-patches/releases/tag/v1.36.0-dev.8)
- Change package name
</blockquote>
</details>

---

## 💖 Credits & Acknowledgements

This automated builder would not be possible without the incredible work and dedication of the open-source Android community. A massive thank you to:

- **[nullcpy/fahim-ahamed05](https://github.com/nullcpy/rvb)**,**[peternmuller](https://github.com/peternmuller)**, **[nvbangg](https://github.com/nvbangg/revanced-morphe-builder)**, and **[j-hc](https://github.com/j-hc)** for their phenomenal foundational build scripts, CI/CD pipelines, and automation logic that power the core of this repository.
- **[FiorenMas](https://github.com/FiorenMas/Revanced-and-Revanced-Extended-Non-Root)** for Cloudflare bypass logic and Xposed Module Support.
- **[MorpheApp/morphe-cli](https://github.com/MorpheApp/morphe-cli)** and **[7727mod/NPatch](https://github.com/7727mod/NPatch)** for Patching tools.
- **[REAndroid/APKEditor](https://github.com/REAndroid/APKEditor)**, **[htmlq](https://github.com/mgdm/htmlq)**, **[yq](https://github.com/mikefarah/yq)** to handle tasks like APK decompilation, HTML parsing, TOML parsing, and YAML parsing.
- **Android SDK and NDK** for providing signing tools, and compiling dynamic patches
- **[TRAWL](https://github.com/germondai/trawl)**, **[FlareSolverr](https://github.com/FlareSolverr/FlareSolverr)**, [Byparr](https://github.com/ThePhaseless/Byparr/) and **[CloudflareBypassForScraping](https://github.com/sarperavci/CloudflareBypassForScraping)** for bypassing Cloudflare protections on certain websites.
- **The Patch Maintainers:** Huge appreciation to the development teams behind **ReVanced**, **MorpheApp**, **Anddea**, **RVX**, **Piko**, **De-Vanced**, and all the other independent developers who spend countless hours reverse-engineering, updating, and keeping these patches alive for everyone.

_If you enjoy using these builds, please consider starring their upstream repositories and original apps and supporting the original patch developers!_


