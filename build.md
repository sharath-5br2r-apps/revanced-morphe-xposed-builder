amazon-alexa-signed (arm64-v8a): 2.2.704787.0  
amazon-alexa-signed (arm-v7a): 2.2.704787.0  
amazon-alexa-signed (x86_64): 2.2.704787.0  
amazon-alexa-signed (x86): 2.2.704787.0  
bitwarden-morphe-stylus (all): 2026.8.0  
tiktok-morphe-icysymmetra (all): 46.2.3  
tiktok-morphe-hxreborn (all): 46.2.3  

**Notes:**  
• Install [MicroG-RE](https://github.com/MorpheApp/MicroG-RE/releases/latest) or [MicroG](https://github.com/ReVanced/GmsCore/releases/latest), required for Google APKs.  
• Use [Zygisk Detach](https://github.com/j-hc/zygisk-detach) to stop Play Store from updating Modules.  

[GitHub](https://github.com/sharath-5br2r-apps/revanced-morphe-xposed-builder) | [Website](https://sharath-5br2r-apps.github.io)
  
CLI: MorpheApp/morphe-desktop-1.13.2-all.jar  
Patches: ch3thanhs/patches-1.4.0.mpp  
[Changelog](https://github.com/ch3thanhs/stylus/releases/tag/v1.4.0)

<details>
<summary>v1.4.0</summary>

## [1.4.0](https://github.com/ch3thanhs/stylus/compare/v1.3.0...v1.4.0) (2026-08-05)

### ✨ New Features

* **github:** add force system font webview css override and ui-monospace patch ([993c3a3](https://github.com/ch3thanhs/stylus/commit/993c3a3bd2139d7ee8f3093959631672cc325931))

</details>

Patches: hxreborn/patches-0.11.4.mpp  
[Changelog](https://github.com/hxreborn/hxreborn-tiktok-patches/releases/tag/v0.11.4)

<details>
<summary>v0.11.4</summary>

## What's Changed


### Bug Fixes

- **build:** Complete feed model stubs by @icysymmetra ([`053ce6c`](https://github.com/hxreborn/hxreborn-tiktok-patches/commit/053ce6cd064c16c1a06e87e10b76896da7c00a83))

- **TikTok - Captcha:** Stop suppressing risk-control puzzles by default by @hxreborn ([`bb48b71`](https://github.com/hxreborn/hxreborn-tiktok-patches/commit/bb48b71b8aa09d6447528bb7cba26d8685e6e286))

- **TikTok - Feed filter:** Filter cached feed insertions by @icysymmetra ([`d30a6dd`](https://github.com/hxreborn/hxreborn-tiktok-patches/commit/d30a6dd37f9eaa1c1faecdf2b30b047707170860))

- **TikTok - Feed filter:** Hide every inserted feed card instead of only bulletin-board ones by @hxreborn ([`85d3a55`](https://github.com/hxreborn/hxreborn-tiktok-patches/commit/85d3a5579a8036ccf4c9bf514787ce97349860c9))

</details>

Patches: icysymmetra/patches-0.7.0.mpp  
[Changelog](https://github.com/icysymmetra/tiktok-patches-for-morphe/releases/tag/v0.7.0)

<details>
<summary>v0.7.0</summary>

# [0.7.0](https://github.com/icysymmetra/tiktok-patches-for-morphe/compare/v0.6.1...v0.7.0) (2026-08-23)


### Bug Fixes

* **build:** complete feed model stubs ([053ce6c](https://github.com/icysymmetra/tiktok-patches-for-morphe/commit/053ce6cd064c16c1a06e87e10b76896da7c00a83))
* **clear-display:** preserve state across feed transitions ([a433fe0](https://github.com/icysymmetra/tiktok-patches-for-morphe/commit/a433fe03b98ecee8814a83f94aaef760222e538f))
* Merge branch `dev` to `main` ([#95](https://github.com/icysymmetra/tiktok-patches-for-morphe/issues/95)) ([1ba91a3](https://github.com/icysymmetra/tiktok-patches-for-morphe/commit/1ba91a3d45ffdd8ee237105b8dd3ad8853a7b7fe))
* merge dev into main ([3c81835](https://github.com/icysymmetra/tiktok-patches-for-morphe/commit/3c8183512dfb9dbe7b7e93979e5a419e428ff605))
* **playback:** persist explicit speed selections ([0f785fc](https://github.com/icysymmetra/tiktok-patches-for-morphe/commit/0f785fc8685c30793bf7ffea028d1223613f52c9))
* **settings:** make custom dialogs fit device screens ([7592339](https://github.com/icysymmetra/tiktok-patches-for-morphe/commit/75923397520ff45fde1b5f618c1de2010de422e0))
* **tiktok:** consume download filename mappings ([864fc15](https://github.com/icysymmetra/tiktok-patches-for-morphe/commit/864fc1526d51f819daea8e0730716d62a4c6b662))
* **tiktok:** cover direct Turing CAPTCHA dialogs ([27b2639](https://github.com/icysymmetra/tiktok-patches-for-morphe/commit/27b263920ffadaf2e27777c703c225f2e4f3ce40))
* **tiktok:** expand startup and runtime hook coverage ([bac0ba8](https://github.com/icysymmetra/tiktok-patches-for-morphe/commit/bac0ba8d2697a60d2c66d723fba75e211ca48a49))
* **tiktok:** filter cached feed insertions ([d30a6dd](https://github.com/icysymmetra/tiktok-patches-for-morphe/commit/d30a6dd37f9eaa1c1faecdf2b30b047707170860))
* **tiktok:** harden bytecode hook resolution ([95e0a3f](https://github.com/icysymmetra/tiktok-patches-for-morphe/commit/95e0a3f8d6c45e97eb44c3066bd201e2d9ab1843))
* **tiktok:** preserve swipe-lock playback speed ([dfbe2a5](https://github.com/icysymmetra/tiktok-patches-for-morphe/commit/dfbe2a55aaced183f97a457b494893c31cebf596))
* **tiktok:** prevent settings crash and expand crash reports ([08186e7](https://github.com/icysymmetra/tiktok-patches-for-morphe/commit/08186e77ba89d92debfcd319fe8fcc745e2a363b))


### Features

* **downloads:** support separate media destinations ([f4580c9](https://github.com/icysymmetra/tiktok-patches-for-morphe/commit/f4580c94b3b2c0d2d79c2bb0bfa6a544abeaedb3))
* **tiktok:** add repost and cached feed controls ([446ee90](https://github.com/icysymmetra/tiktok-patches-for-morphe/commit/446ee90123b118642fe3c50f5da9221d984667c2))
* **tiktok:** expand offline video limits ([35eff0e](https://github.com/icysymmetra/tiktok-patches-for-morphe/commit/35eff0e4f84ea69925bbddc71eb04c6d0bf5e66d))





## 0.7.0

</details>  
