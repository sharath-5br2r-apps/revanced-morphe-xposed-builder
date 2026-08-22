brave-beta-morphe-dh6k-arm64-v8a (arm64-v8a): 1.95.88  
brave-beta-morphe-dh6k-arm-v7a (arm-v7a): 1.95.88  
brave-beta-morphe-dh6k-x86_64 (x86_64): 1.95.88  
brave-beta-morphe-dh6k-x86 (x86): 1.95.88  
brave-nightly-morphe-dh6k-arm64-v8a (arm64-v8a): 1.96.8  
brave-nightly-morphe-dh6k-arm-v7a (arm-v7a): 1.96.8  
brave-nightly-morphe-dh6k-x86_64 (x86_64): 1.96.8  
brave-nightly-morphe-dh6k-x86 (x86): 1.96.8  
github-morphe-hoodles-stylus (all): 1.273.0  
prime-video-morphe-hoodles (arm64-v8a): 3.0.468.1747  
prime-video-morphe-hoodles (arm-v7a): 3.0.468.1745  
prime-video-morphe-hoodles-shared (arm64-v8a): 3.0.468  
prime-video-morphe-hoodles-shared (arm-v7a): 3.0.468  
discord-npatch-revenge (all): 341.13-Stable  
bitwarden-morphe-stylus (all): 2026.8.0  

**Notes:**  
• Install [MicroG-RE](https://github.com/MorpheApp/MicroG-RE/releases/latest) or [MicroG](https://github.com/ReVanced/GmsCore/releases/latest), required for Google APKs.  
• Use [Zygisk Detach](https://github.com/j-hc/zygisk-detach) to stop Play Store from updating Modules.  

[GitHub](https://github.com/sharath-5br2r-apps/revanced-morphe-xposed-builder) | [Website](https://sharath-5br2r-apps.github.io)
  
CLI: MorpheApp/morphe-desktop-1.13.1-all.jar  
Patches: arandomhooman/patches-1.50.3.mpp  
[Changelog](https://github.com/arandomhooman/hoomans-morphe-patches/releases/tag/v1.50.3)

<details>
<summary>v1.50.3</summary>

## [1.50.3](https://github.com/arandomhooman/hoomans-morphe-patches/compare/v1.50.2...v1.50.3) (2026-08-19)

### 🐛 Bug Fixes

* drop server-inserted sponsored timeline cards in Tumblr Remove ads ([9e872d0](https://github.com/arandomhooman/hoomans-morphe-patches/commit/9e872d037671e4edb3580c6eb5714ac7de2f169e))

</details>

Patches: crimera/patches-3.8.0.mpp  
[Changelog](https://github.com/crimera/piko/releases/tag/v3.8.0)

<details>
<summary>v3.8.0</summary>

## [3.8.0](https://github.com/crimera/piko/compare/v3.7.0...v3.8.0) (2026-07-24)

### 🐛 Bug Fixes

* **Instagram:** Fix app crash on comment media download([#1568](https://github.com/crimera/piko/issues/1568)) ([b3b01f7](https://github.com/crimera/piko/commit/b3b01f7f5a9f8f01b66a32299cec06a3748e23b3))
* **Instagram:** Fix chat action bar function name ([1401808](https://github.com/crimera/piko/commit/140180878895841fc8437dc21a39ab7941f79540))
* **Instagram:** Fix opening links ([ba9b4c4](https://github.com/crimera/piko/commit/ba9b4c43af6e4a42ce0654d11aa26a3d28496247))
* **Instagram:** Fix Piko settings color issues ([f1f278a](https://github.com/crimera/piko/commit/f1f278a87665be59218dcc54af983b411802fe0f))
* **Instagram:** match piko settings background to amoled patch ([#1543](https://github.com/crimera/piko/issues/1543)) ([56003dc](https://github.com/crimera/piko/commit/56003dc4b68e6969e208570c45b583bcf709ceb3))
* **Instagram:** Match piko settings highlight to theme ([#1548](https://github.com/crimera/piko/issues/1548)) ([c428e7e](https://github.com/crimera/piko/commit/c428e7ea762cf2ec94e5e9a9f17ea207a976176f))
* **Instagram:** Match story mention dialog to Instagram theme ([#1554](https://github.com/crimera/piko/issues/1554)) ([08563ca](https://github.com/crimera/piko/commit/08563ca54d486585e5fc4bc7c432d6f5f19e6d28))
* **instagram:** preserve settings fragment on recreation ([#1546](https://github.com/crimera/piko/issues/1546)) ([f57ddcc](https://github.com/crimera/piko/commit/f57ddcc555dd487f57d959e5adc625f0f15ed80c))
* **instagram:** Refine piko settings title styling ([#1534](https://github.com/crimera/piko/issues/1534)) ([ce69be6](https://github.com/crimera/piko/commit/ce69be69e8aea7aee04bdf00db5a413bbb849b2f))
* **Instagram:** Refresh localized download folder path ([#1537](https://github.com/crimera/piko/issues/1537)) ([72ce666](https://github.com/crimera/piko/commit/72ce66602c601a2e1b600367bd04430419dadc59))
* **Instagram:** Restore and sync ghost action bar icons ([#1545](https://github.com/crimera/piko/issues/1545)) ([1240faf](https://github.com/crimera/piko/commit/1240faf55fa68867e9517bbd017e1cd1978cfa72))
* **instagram:** restore native off switch colors ([#1533](https://github.com/crimera/piko/issues/1533)) ([71b0b00](https://github.com/crimera/piko/commit/71b0b007096756e1c801c14a1e8c21e2f7cada4a))
* **Twitter - Native Downloader:** Add missing downloadAll method and fix null checks ([ba9d036](https://github.com/crimera/piko/commit/ba9d036e7e01a2455e291504ec4984c9b94cda94))
* **Twitter - Native Downloader:** Clean stale temp file before download and auto-retry legacy resolution if orig fails ([a9d9bd1](https://github.com/crimera/piko/commit/a9d9bd15f9895d723a3bb9eea1ea2d56cd6aa3e4))
* **Twitter - Settings:** Guard native downloader preferences and category by patch status ([d2ac7a0](https://github.com/crimera/piko/commit/d2ac7a08f9ac2679e7b3a1cb999f79e11fae2e76))
* **Twitter:** Apply custom sharing domain to copied links ([#1555](https://github.com/crimera/piko/issues/1555)) ([8e9bec8](https://github.com/crimera/piko/commit/8e9bec895638b5de3c585647496676915b610040))
* **Twitter:** Create category only if the patch is patched ([f3538a3](https://github.com/crimera/piko/commit/f3538a30d2c1d98a3c56e1fe0a7b5222b1ba35ae))
* **Twitter:** Fix `Custom share menu` crash on image view ([f4d2e53](https://github.com/crimera/piko/commit/f4d2e53171621d02f2b04c0a0d4ff220e2e4c799))
* **Twitter:** Fix high resolution image url ([5d07767](https://github.com/crimera/piko/commit/5d07767458b387c85448801851ab4d2de01caf12))
* **Twitter:** Fix inverted number round off ([c0a04aa](https://github.com/crimera/piko/commit/c0a04aac74604e690cacd8925c8bd9f4d13a4664))
* **Twitter:** Fix open supported links activity ([8a1db76](https://github.com/crimera/piko/commit/8a1db76b9c9109db02ee4278b5a6891e5cc2b246))
* **twitter:** Handle bad response during tweet info API ([#1410](https://github.com/crimera/piko/issues/1410)) ([522f7d1](https://github.com/crimera/piko/commit/522f7d13e9f29bae854073a74c1d82cfe1874950))
* **Twitter:** Tweet link pattern ([d2500ea](https://github.com/crimera/piko/commit/d2500ead98dd5bd77ba97f1ef2ac8388f7b559f0))

### ✨ New Features

* **Instagram:** Added `Filter stories` patch ([c62d02a](https://github.com/crimera/piko/commit/c62d02adf1f0160f8bc72c4eb4e521e06b89c0be))
* **Instagram:** Added `Mark chat as read manually` patch ([1d267c8](https://github.com/crimera/piko/commit/1d267c8f67d1f7153e50a0166d327056e1643603))
* **Instagram:** Added ability to remove Piko preference ([3e29d69](https://github.com/crimera/piko/commit/3e29d69e0af53df4c0814bbd5e057ced196633c6))
* **instagram:** Disable swipe to create ([#1539](https://github.com/crimera/piko/issues/1539)) ([eaea2e9](https://github.com/crimera/piko/commit/eaea2e9db2db929409247c4a8b0ec865f13e087b))
* **Instagram:** Include debug option on thread long press ([c9df942](https://github.com/crimera/piko/commit/c9df9426377f62225c8ee63e0872563f99fd7d50))
* **instagram:** Material You theme ([#1509](https://github.com/crimera/piko/issues/1509)) ([9d97f59](https://github.com/crimera/piko/commit/9d97f590cd17e79c66a39deeedcb12a2f9f510f8))
* **Twitter - Native Downloader:** Add long-press to download all inline button ([f3d11e6](https://github.com/crimera/piko/commit/f3d11e653fd90176cdb2edc21d375447f63a4c39))
* **Twitter:** Add piko settings to the app icon long-press shortcut ([#1412](https://github.com/crimera/piko/issues/1412)) ([2eb970b](https://github.com/crimera/piko/commit/2eb970bfc7160256438fa854e5be0a0513c86877))
* **Twitter:** Add Search Piko settings ([#1516](https://github.com/crimera/piko/issues/1516)) ([fed4f51](https://github.com/crimera/piko/commit/fed4f51e3b88b4f7349af8c13a3ea61ecebb4c7c))
* **Twitter:** Added `Custom share menu` patch ([23f0a32](https://github.com/crimera/piko/commit/23f0a3237b57eea75443062ade78fc3be093fb33))
* **Twitter:** Added `External downloader` patch ([0e9a9f7](https://github.com/crimera/piko/commit/0e9a9f743364d1132d18d289a21e7e86c929f998))
* **Twitter:** Added `More information on profile` patch ([1167728](https://github.com/crimera/piko/commit/116772873059fe2b66b0708524a89cd90acac6e1))
* **Twitter:** Added new download dialog box ([9fca347](https://github.com/crimera/piko/commit/9fca347fc14da4d95c8c8a1a74fc691f1481077a))

### 🚀 Updated App Support

* **Twitter:** Bump support to `12.7.1-release.0` ([1d31338](https://github.com/crimera/piko/commit/1d313381d08afb0ba2f40f9f01673fa5cf5b6cce))

### 🔧 Improvements

* **Instagram:** Added inbox action bar customization ([7f0a219](https://github.com/crimera/piko/commit/7f0a219676976a8832744d889fe563129ea479bb))
* **Instagram:** Added more flags to improve the user experience ([#1443](https://github.com/crimera/piko/issues/1443)) ([d4835d2](https://github.com/crimera/piko/commit/d4835d26a358136777c6beccf299ab2268ecf709))
* **Instagram:** Added more story filters ([bab0fc6](https://github.com/crimera/piko/commit/bab0fc653d2ec9642ee608a0d57cd76380af944b))
* **Instagram:** Adjust DM section position on piko settings ([4646c7d](https://github.com/crimera/piko/commit/4646c7d24823f31ab530d2b2b85bfe74bae41db3))
* **Instagram:** Enhance story mention dialog box ([8d77056](https://github.com/crimera/piko/commit/8d7705684809cfa279ca0b517cecfc0911bcc54a))
* **Instagram:** Handle edge cases of comment button interaction ([fe847cb](https://github.com/crimera/piko/commit/fe847cbce8bc1fac1b324af9ac494b6d17a3ca19))
* **Instagram:** Improve action bar icon selection options ([a3b2b73](https://github.com/crimera/piko/commit/a3b2b7338659a978adba480595f9e96fc2b0d21f))
* **Instagram:** Include color friendship indicator ([48f5850](https://github.com/crimera/piko/commit/48f5850322a04c7dce982a1b4c61a9869d3635a2))
* **Instagram:** Include verification tick on story mention ([92b043b](https://github.com/crimera/piko/commit/92b043bb9a5d708f375bbaf4fe897407311d5bb5))
* **Instagram:** Move DM long press button check to java ([b2e4e71](https://github.com/crimera/piko/commit/b2e4e71e1e64fdeb06e0130271e8366d2fc4d200))
* **Instagram:** Remove unused preference ([232b4d6](https://github.com/crimera/piko/commit/232b4d6584750510088e4fe4e216534b8ce1ed86))
* **Instagram:** Story mention dialog width ([68b3c94](https://github.com/crimera/piko/commit/68b3c94f9efa7d6a7868dd63357e5c5a579d11c5))
* **Instagram:** Update download path handling and permissions ([#1500](https://github.com/crimera/piko/issues/1500)) ([76cdcb3](https://github.com/crimera/piko/commit/76cdcb3cfd62fa19cd79cdead1a3a2dd082585b2))
* **Twitter:** Introduce debug option and streamline About section buttons ([e64a7e0](https://github.com/crimera/piko/commit/e64a7e0a1978757b8c949971f3b0da1e5e4879ed))
* **Twitter:** Make the tweet-shots have rounded edges ([020589e](https://github.com/crimera/piko/commit/020589e5b1c3681396c7654f9d34604fbbc8f391))
* **Twitter:** Standardise share menu on click handling ([9aecb6b](https://github.com/crimera/piko/commit/9aecb6b68e71c70d3e4075afe2d311efd254f22c))

</details>

Patches: dh6k/patches-1.3.0.mpp  
[Changelog](https://github.com/dh6k/morphe-patches/releases/tag/v1.3.0)

<details>
<summary>v1.3.0</summary>

## [1.3.0](https://github.com/dh6k/morphe-patches/compare/v1.2.0...v1.3.0) (2026-08-21)

### 🐛 Bug Fixes

* **brave:** support Origin 1.94.114 ([6c5dfcd](https://github.com/dh6k/morphe-patches/commit/6c5dfcd4d62f42695c6e56e6b3faad50ba871bf9))
* **brave:** tolerate optional Origin hooks ([326af9d](https://github.com/dh6k/morphe-patches/commit/326af9d2f7dbd643d620bbc5efc358ff924c0dd0))
* **brave:** unpin stable compatibility ([ad21d01](https://github.com/dh6k/morphe-patches/commit/ad21d01975d3fe06e12699daad2557f863562342))

### ✨ New Features

* **universal:** disable common analytics SDKs ([5f8e982](https://github.com/dh6k/morphe-patches/commit/5f8e982cfd1e44585a3ee9802518bc4c0f0dd731))

</details>

Patches: hoo-dles/patches-1.41.0.mpp  
[Changelog](https://github.com/hoo-dles/morphe-patches/releases/tag/v1.41.0)

<details>
<summary>v1.41.0</summary>

# [1.41.0](https://github.com/hoo-dles/morphe-patches/compare/v1.40.0...v1.41.0) (2026-08-18)


### Bug Fixes

* **Duolingo:** Force max energy ([969359c](https://github.com/hoo-dles/morphe-patches/commit/969359c24d2d3ac6d75e06eb052c0f3cc7911b62))


### Features

* **Duolingo:** Update patches to support `6.92.5` ([dca61c3](https://github.com/hoo-dles/morphe-patches/commit/dca61c3c602aecb8c0b6fcc79a4368c4bb59cf67))
* **MyFitnessPal:** Update patches to support `26.31.0` ([4d50bf9](https://github.com/hoo-dles/morphe-patches/commit/4d50bf9db7d4bd1ac32f393036683090429232c2))
* **Smart Launcher:** Update patches to support `6.6 build 016` ([1218a1d](https://github.com/hoo-dles/morphe-patches/commit/1218a1d902fd28e90528765c8e6396df28d8981e))
* **Windy:** Update patches to support `51.0.1` ([634ad8a](https://github.com/hoo-dles/morphe-patches/commit/634ad8aa627ce3f35ecc023d0e0df0f015b4c53c))

</details>

Patches: ch3thanhs/patches-1.4.0.mpp  
[Changelog](https://github.com/ch3thanhs/stylus/releases/tag/v1.4.0)

<details>
<summary>v1.4.0</summary>

## [1.4.0](https://github.com/ch3thanhs/stylus/compare/v1.3.0...v1.4.0) (2026-08-05)

### ✨ New Features

* **github:** add force system font webview css override and ui-monospace patch ([993c3a3](https://github.com/ch3thanhs/stylus/commit/993c3a3bd2139d7ee8f3093959631672cc325931))

</details>

Patches: Paresh-Maheshwari/patches-1.19.0.mpp  
[Changelog](https://gitlab.com/Paresh-Maheshwari/paresh-patches/-/releases/v1.19.0)

<details>
<summary>v1.19.0</summary>

# [1.19.0](https://gitlab.com/Paresh-Maheshwari/paresh-patches/compare/v1.18.0...v1.19.0) (2026-07-07)


### Bug Fixes

* handle missing dev branch in CI backmerge ([6fd1f76](https://gitlab.com/Paresh-Maheshwari/paresh-patches/commit/6fd1f764cf39688643b57e79054b3aa6bd9a3a85))
* update Alarmo recommended version to 1.3.8 ([024e785](https://gitlab.com/Paresh-Maheshwari/paresh-patches/commit/024e785a840b7d01df0b5dab15eedad46483d520))
* update Proton VPN recommended version to 5.19.16.0 ([5f4994d](https://gitlab.com/Paresh-Maheshwari/paresh-patches/commit/5f4994d909b1ec8457162fadbb8f388df7576ebc))
* update Telegram recommended version to 12.8.3 ([2ace333](https://gitlab.com/Paresh-Maheshwari/paresh-patches/commit/2ace333510d95ec80580ef8a31dfb8ac8f5f1653))


### Features

* add MX Player Pro license bypass patch ([0800707](https://gitlab.com/Paresh-Maheshwari/paresh-patches/commit/0800707a0f4d97efbd86c51ee522969b24bb10e1))
* add Task Manager pro patch ([2e50d4a](https://gitlab.com/Paresh-Maheshwari/paresh-patches/commit/2e50d4af749db18f6412e28952624f6dace5112c))

</details>

CLI: 7723mod/jar-v1.0.7-741-release.jar  
Patches: revenge-mod/app-release.apk  
[Changelog](https://github.com/revenge-mod/revenge-xposed/releases/tag/1602)

<details>
<summary>1602</summary>

**Full Changelog**: https://github.com/revenge-mod/revenge-xposed/compare/1601...1602

</details>  
