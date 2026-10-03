# Aaalice Pocket

<p align="center">
  <a href="README.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · English
</p>

<p align="center">
  <img src="docs/assets/pocket-icon.png" alt="Aaalice Pocket icon" width="112">
</p>

<p align="center">
  <strong>A NovelAI studio that fits in your pocket: an Android-only branch of NAI Launcher, tuned for phones.</strong>
</p>

<p align="center">
  <a href="https://github.com/CSSRS2662/Aaalice_NAI_Launcher/releases/latest"><img src="https://img.shields.io/github/v/release/CSSRS2662/Aaalice_NAI_Launcher?include_prereleases&display_name=tag" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/Android-7.0%2B%20arm64-3ddc84?logo=android&logoColor=white" alt="Android 7.0+ arm64">
  <img src="https://img.shields.io/badge/license-MIT-5b8c5a" alt="MIT License">
  <a href="https://github.com/Aaalice233/Aaalice_NAI_Launcher"><img src="https://img.shields.io/badge/upstream-NAI%20Launcher-6f7785" alt="Upstream project NAI Launcher"></a>
</p>

<p align="center">
  <a href="https://github.com/CSSRS2662/Aaalice_NAI_Launcher/releases/latest">Download</a> ·
  <a href="https://github.com/Aaalice233/Aaalice_NAI_Launcher">Upstream project</a> ·
  <a href="#-relationship-to-upstream">Relationship to upstream</a>
</p>

> Aaalice Pocket is an unofficial Android branch of [NAI Launcher](https://github.com/Aaalice233/Aaalice_NAI_Launcher), maintained by [CSSRS2662](https://github.com/CSSRS2662). It is not affiliated with or endorsed by the upstream author or by NovelAI (Anlatan); "Aaalice" in the name comes from the upstream project name to show where it comes from. Online features need your own NovelAI account; follow the applicable terms of service, content rules, and local laws.

## 📱 Android only

Upstream NAI Launcher targets Windows, macOS, and Android. Aaalice Pocket targets Android alone. It treats the phone as the main creative device: reachable with one hand, natural to drive with gestures, smooth on real hardware, rather than a shrunken desktop layout.

- **Android packages only.** Desktop code stays in the tree so upstream merges stay easy, but this branch publishes no Windows or macOS builds.
- **Own package name and signature.** The package is `com.cssrs2662.aaalicepocket`, signed with this branch's own key. It installs side by side with upstream builds and keeps its data separate.
- **Regular upstream merges.** Upstream features and fixes are merged as needed, then reworked for phones.
- **No in-app updater.** Download new versions from this repository's Releases and install over the existing app.

## ✨ Reworked for phones

| What you'll notice | What Aaalice Pocket does |
| --- | --- |
| **Generation workbench** | The top bar holds just two pills, model and size, with V5 stamina and Anlas balance on the right. The Image / Prompt / Parameters / References / History tabs below switch with a horizontal swipe. One bottom row holds the gacha toggle, add to queue, agent, queue, and the Generate button, which shows progress inside itself. |
| **Prompt sections** | Split a prompt into sections you edit, enable, and reorder separately. Reusing parameters restores the original sections instead of putting every tag into one box. |
| **Tag mode** | Switch between text and tag views at any time; each tag shows its Chinese translation underneath, and a long press adjusts weight, copies, or temporarily disables it. |
| **Tag search without AI** | Chinese, full pinyin, Ziranma double pinyin, and initials all find English tags, with homophone and spelling correction and splitting of Chinese phrases. A bundled semantic completion model also runs fully on the device. |
| **V5 stamina and balance** | The top bar shows Opus stamina and Anlas balance; tap it for the remaining amount, estimated images, and refill time. |
| **Pocket theme** | Neutral white or charcoal backgrounds with 8 preset accent colors or a custom one; light, dark, or follow the system. |
| **Smoothness** | On high refresh rate screens, scrolling and other touch interaction run at the panel's top rate (for example 120Hz; turn off in Settings → Appearance → High refresh rate). Finishing an image no longer causes a stall. |

## 🎨 The full NovelAI workflow

Aaalice Pocket keeps the upstream capabilities that work on phones:

- **Generation and editing**: text-to-image, image-to-image, inpainting, Focused Inpaint, outpainting, variations, and enhancement. Supports NovelAI V5 Curated / Full, V4.5, V4, and V3, with parameters adjusted to each model's capabilities.
- **Characters and references**: per-character prompts and positions. Vibe Transfer and Precise Reference have their own libraries for sorting, searching, and sending straight into the current task.
- **Fixed tags and libraries**: positive and negative fixed tags, a custom tag library, and random tag libraries, with categories, search, and quick insertion.
- **Gallery and history**: the local gallery and generation history use a masonry layout. Every image menu offers save, reuse parameters, and favorite, and NovelAI image metadata can be read and selectively restored.
- **Share to import**: share an image or a direct image link from Discord or other apps to Aaalice Pocket to extract metadata or use it as an img2img source or reference.
- **Online galleries**: Danbooru, Safebooru, Gelbooru, AI TAG, and the QuickTagCloud codex, with original prompts you can send back to the generation page.
- **Queue and agent**: pause, resume, reorder, and retry batch tasks. The agent can look up tags, tidy prompts, and prepare tasks; paid and destructive actions still need your confirmation.
- **Backup and restore**: cloud backup to GitHub and WebDAV; you start every push, pull, and restore. OneDrive and Google Drive need OAuth settings at build time, which this branch's release packages do not include.

## 🖼️ Screenshots

<table>
  <tr>
    <td width="33%" align="center">
      <img src="docs/screenshots/pocket/pocket-generate.png" alt="Generation workbench" width="100%"><br>
      <sub>Workbench: model, size, and balance in the top bar</sub>
    </td>
    <td width="33%" align="center">
      <img src="docs/screenshots/pocket/pocket-streaming.png" alt="Streaming preview" width="100%"><br>
      <sub>Streaming preview with progress in the Generate button</sub>
    </td>
    <td width="33%" align="center">
      <img src="docs/screenshots/pocket/pocket-prompt-tags.png" alt="Prompt tag mode" width="100%"><br>
      <sub>Tag mode with Chinese translations</sub>
    </td>
  </tr>
  <tr>
    <td width="33%" align="center">
      <img src="docs/screenshots/pocket/pocket-params.png" alt="Parameters" width="100%"><br>
      <sub>Parameters: size, sampler, and steps</sub>
    </td>
    <td width="33%" align="center">
      <img src="docs/screenshots/pocket/pocket-appearance.png" alt="Appearance settings" width="100%"><br>
      <sub>Appearance: accent color and theme</sub>
    </td>
    <td width="33%"></td>
  </tr>
</table>

All images in the screenshots were generated with NovelAI V5 Curated from random prompts; the UI is shown in Simplified Chinese.

## ⚡ Download and install

1. Download `Aaalice_Pocket_<version>_arm64.apk` from [Releases](https://github.com/CSSRS2662/Aaalice_NAI_Launcher/releases/latest), and check its SHA-256 against `checksums.txt` on the same page.
2. On first install, allow the current app to install unknown apps when Android asks.
3. Requires Android 7.0 or later on a 64-bit ARM (arm64-v8a) device. The package bundles the offline tag database and the semantic completion model, so it is about 290MB.
4. To upgrade, install the new package over the old one; your data stays. This branch and upstream use different signatures, so neither can install over the other.

Sign in with your NovelAI email and password or a **Persistent API Token**. If the website's security check makes password sign-in fail, use a Persistent API Token instead; it is kept only in the device's secure storage.

## 🔒 Data and privacy

Aaalice Pocket has no server of its own and collects no usage data. Data leaves the device only when you use a feature that needs a service:

| Feature | Where data goes |
| --- | --- |
| Generation, img2img, inpainting, Vibe encoding | NovelAI, including the prompt, parameters, and source or reference images the request needs. |
| Online gallery search and downloads | The third-party gallery you choose; each site sets its own availability, rate limits, and content rules. |
| AI translation or the agent | The model service you configure, which may charge fees. |
| Cloud backup | The GitHub or WebDAV target you choose; only the items you select are uploaded. |

- Your NovelAI token, GitHub token, and WebDAV password stay in the device's secure storage and are never written to backups.
- Prompts, the gallery index, tags, libraries, and agent sessions stay on the device by default; image files in the local gallery are never uploaded.
- Online galleries may contain third-party content, and rating filters do not replace your own judgment.

## 🔗 Relationship to upstream

- This branch is based on [Aaalice233/Aaalice_NAI_Launcher](https://github.com/Aaalice233/Aaalice_NAI_Launcher), uses the same [MIT License](LICENSE), and keeps the upstream copyright notice.
- Credit for upstream features and fixes goes to the upstream author and contributors; this branch maintains the Android-specific interface and changes.
- Report problems with Aaalice Pocket to this branch, not to the upstream repository. Before reporting, you can save troubleshooting data with Settings → About → Export diagnostic logs.
- For Windows or macOS builds, or upstream's full feature set, use upstream [NAI Launcher](https://github.com/Aaalice233/Aaalice_NAI_Launcher/releases/latest).

## 🙏 Acknowledgements

Thanks to the author and all contributors of [NAI Launcher](https://github.com/Aaalice233/Aaalice_NAI_Launcher), and to [NovelAI](https://novelai.net/), [QuickTagCloud](https://novelai.quicktagcloud.com/), [AgIzT/NovelAI-Tag](https://github.com/AgIzT/NovelAI-Tag), the [ffdkj Chinese-English tag table](https://github.com/ffdkj/ffdkj-Danbooru_Tag-Chinese-English-Translation-Table), [amenorira/danbooru-tags-data-zh](https://github.com/amenorira/danbooru-tags-data-zh), [mozillazg/pinyin-data](https://github.com/mozillazg/pinyin-data), [ECDICT](https://github.com/skywind3000/ECDICT), [multilingual-e5-small](https://huggingface.co/intfloat/multilingual-e5-small), [Flutter](https://flutter.dev/), and [Riverpod](https://riverpod.dev/). License details for bundled data and assets are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## 📄 License

This project is open source under the [MIT License](LICENSE). NovelAI and its logo are trademarks of Anlatan; this project claims no rights to them.
