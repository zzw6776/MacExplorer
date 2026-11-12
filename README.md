<p align="center">
  <img src="docs/images/app-icon.png" width="96" height="96" alt="MacExplorer folder icon">
</p>

# MacExplorer

A native macOS file manager for people who like Windows Explorer.

MacExplorer brings familiar tabs, a folder tree, drive overviews, and keyboard shortcuts to the Mac, with native Quick Look, thumbnails, and Finder color tags. Built with Swift and AppKit, with Sparkle for signed software updates.

**Early development · macOS 14+ · MIT licensed**

## Download

本 Fork 推送到 `main` 后，会在 [GitHub Actions](https://github.com/zzw6776/MacExplorer/actions/workflows/ci.yml) 的 **Build Explorer DMG** 中自动生成 Apple Silicon / Intel 通用 DMG。打开成功的运行记录，在 **Artifacts** 下载 `MacExplorer-DMG-运行编号`，解压后打开 DMG，将 Explorer 拖到 Applications 替换安装。

开发版固定使用同一份自签名证书，不需要 Apple 开发者账号；尚未经过 Apple 公证，下载后的系统打开提示仍需手动确认。已有权限能否延续取决于签名身份保持一致。

仓库需配置 Secrets `EXPLORER_DEV_P12_BASE64`、`EXPLORER_DEV_P12_PASSWORD`，以及 Variable `EXPLORER_DEV_CERT_SHA1`。证书包含私钥，必须通过 Secrets 保存，不能提交到源码；CI 只在推送或手动运行时导入证书，PR 检查使用临时签名，不上传安装包。也可在 Actions 页面通过 **Run workflow** 手动打包，产物保留 30 天。

以下是上游官方版下载：

[Download Explorer for Mac](https://explorer.bquick.io/#download) · [Release notes and checksums](https://github.com/binaryquest/MacExplorer/releases/latest)

Open the DMG and drag **Explorer** into **Applications**. The app is Developer ID signed and notarized by Apple, with one universal download for Apple Silicon and Intel. Future updates are available through **Explorer → Check for Updates…**; automatic update preferences are in **Settings → Updates**.

![This Mac with drives, storage usage bars, and cloud locations](docs/images/this-mac.png)

*All screenshots use fictional sample files, accounts, and storage figures.*

## What it can do

- **Browse your way:** tabs, tab reordering and detaching into windows, breadcrumbs, a folder tree, pinned favorites, and dual panes.
- **Manage files:** copy, cut, paste, move, rename, new folders, Trash, ZIP compression and extraction, conflict handling, and undo. Drag files between folders, tabs, and panes. Open native Get Info with **Properties**.
- **Find things:** search filenames in a folder or its subfolders, highlight matches, and click a result's folder path to open it with the file selected.
- **Choose a view:** details, content, and multiple icon sizes; sort and group independently; preview files with Quick Look.
- **See your storage:** local and external drives, mounted network shares, and locally available cloud folders, including Google Drive.
- **Make it yours:** Finder color tags, light/dark appearance, startup and browsing preferences, optional launch at login, and a configurable global shortcut (⌘E by default).
- **Use your favorite apps:** choose a registered application from **Open With**, open folders in your preferred terminal, and text/code/configuration files in your chosen editor. The context menu groups common file actions into a compact icon row.

## A closer look

Search results show the containing folder, modification date, size, and matching text.

![Search results with highlighted matches and clickable folder paths](docs/images/search.png)

Two panes make it easy to work across folders, with independent tabs and views.

![Dual panes showing color-tagged folders and image thumbnails](docs/images/dual-pane.png)

## Build and run

You need **macOS 14 or later** and a **Swift 6 toolchain** from Xcode or Xcode Command Line Tools.

GitHub Actions 固定使用 Xcode 26.3，并生成 Apple Silicon / Intel 通用 DMG。

```sh
git clone https://github.com/zzw6776/MacExplorer.git
cd MacExplorer
zsh scripts/create-local-signing-identity.sh
zsh scripts/build.sh
open build/Explorer.app
```

The build script creates `build/Explorer.app`, generates its icon, embeds Sparkle, and signs it with the fixed local development identity. Run `zsh scripts/dev-dmg.sh` to create a native-architecture development DMG in `build/dmg/`, or add `--universal` for Apple Silicon and Intel. Automatic updates are disabled in source builds.

The app appears as **Explorer** in macOS. Open **Explorer → Settings…** to change the global shortcut, appearance, startup behavior, and browsing defaults. The global shortcut works while Explorer is running, including when its last window is closed; it can be changed or disabled if it conflicts with another app.

In **Settings → Applications**, choose your terminal and text editor. The defaults are macOS Terminal and TextEdit; installed alternatives such as iTerm2, Warp, Visual Studio Code, Sublime Text, and Zed appear automatically. **Choose Application…** lets you select another app. A custom terminal must accept folder URLs through macOS’s standard Open mechanism.

Right-click a folder, sidebar location, or drive to open a terminal there; right-click empty folder space to use the current folder. For a selected file, the terminal opens its containing folder. Text files—including JSON, YAML, scripts, and dotfiles—offer **Open with [editor]**; other regular files offer **Open as Text with [editor]**. These preferences do not change macOS file associations or normal double-click behavior.

**Open With** lists applications macOS registers for the selected files, with the shared default first. For multiple files, it lists apps that handle every selected file; **Other…** lets you choose an application manually. This opens the files once without changing their default app.

**Compress to ZIP** creates `name.zip` for one item or `Archive.zip` for multiple items in the current folder. In recursive search, it uses the first selected item's containing folder and preserves relative paths so identically named files from different folders remain distinct. **Extract All…** lets you choose a parent folder, then unpacks into a folder named after the ZIP. Existing destinations offer Keep Both, Replace, Skip, or Cancel; Replace sends the old destination to Trash. Both operations support cancellation and Undo, which refuses to remove output edited since the operation. ZIPs contain standard file contents, folders, and symlinks; Finder tags, extended attributes, resource forks, and password-protected archives are not supported. Download quarantine is preserved on extracted contents.

**Properties** (⌘I) opens Finder's native Get Info window for selected items, drives, sidebar folders, or the current folder. macOS may ask you to allow Explorer to control Finder the first time. If denied, you can enable it later in **System Settings → Privacy & Security → Automation**.

## Handy shortcuts

| Action | Shortcut |
| --- | --- |
| Bring Explorer forward | ⌘E (configurable) |
| Settings | ⌘, |
| New / close tab | ⌘T / ⌘W |
| Go to a path | ⌘L |
| Search / search subfolders | ⌘F / ⇧⌘F |
| Toggle dual panes / switch pane | ⇧⌘D / F6 |
| Quick Look | Space |
| Properties / native Get Info | ⌘I |
| Rename | F2 |
| Copy / cut / paste / undo | ⌘C / ⌘X / ⌘V / ⌘Z |
| New folder | ⇧⌘N |

Windows-style Ctrl+C/X/V/Z also work when the file list has focus.

## Current scope

MacExplorer is a standalone file manager. macOS still uses Finder for system integrations. Search currently matches filenames rather than file contents. Cloud folders come from providers already installed on your Mac; MacExplorer does not sign into cloud accounts or provide its own sync engine.

This is an early project under active development. Bug reports and small, focused pull requests are welcome—please include your macOS version and steps to reproduce. Use sample data in screenshots and reports.

## Development

```sh
zsh scripts/test.sh
```

`Sources/ExplorerCore` contains navigation, search, storage models, and file operations. `Sources/ExplorerApp` contains the native interface and macOS integrations. `Tests` covers the core behavior and AppKit interactions.

To create safe screenshots of your own, see [the demo guide](docs/SCREENSHOTS.md).

## Releases and updates

The release pipeline builds universal DMGs, signs them with Developer ID, submits them for Apple notarization, and publishes signed Sparkle updates through Cloudflare R2. Official builds include **Check for Updates…** and update preferences.

Official releases are available from [GitHub Releases](https://github.com/binaryquest/MacExplorer/releases/latest) and the download link above. An end-to-end upgrade through Explorer passed before the first release. Maintainers can follow the [release setup guide](docs/RELEASING.md) and [first-release validation report](docs/RELEASE-VALIDATION-0.11.0.md).

Sparkle and its bundled components retain their [third-party licenses](Support/Licenses/Sparkle.txt).

## License

[MIT](LICENSE). Free to use, modify, and distribute, including commercially.

MacExplorer is an independent project, inspired by Windows Explorer and built for macOS. It is not affiliated with Microsoft or Apple.
