# 🔌 涂鸦智能插座控制 App (Plug App)

![Flutter](https://img.shields.io/badge/Flutter-3.x-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Android-green.svg)
![Build](https://img.shields.io/badge/Build-GitHub_Actions-success.svg)

这是一个**极简、直观、纯本地**的涂鸦（Tuya）WiFi 智能插座控制 App。旨在为作者自己家人日常使用设计，作者什么也不会，就连这个md文件也是DeepSeek生成的。最后竟然真的弄成了，反正我自己是能用的，发到这里来分享一下。文件数量很少，可以发给AI让她们分析一下，以便实现你自己的需求。

> 👤 **作者**：shgvge
> 🤖 **代码生成**：本项目 100% 由 DeepSeek 协助生成与优化
> 🔗 **B站主页**：[https://space.bilibili.com/1539184586](https://space.bilibili.com/1539184586)

---

## 📸 界面预览

<div style="display: flex; flex-wrap: wrap; justify-content: center; gap: 10px;">
  <a href="https://cdn.jsdelivr.net/gh/alhdfailfi/plug_app_public@main/screenshots/1.jpg" target="_blank">
    <img src="https://cdn.jsdelivr.net/gh/alhdfailfi/plug_app_public@main/screenshots/1.jpg" width="45%" alt="主界面" style="border-radius: 12px; box-shadow: 0 4px 8px rgba(0,0,0,0.1);" />
  </a>
  <a href="https://cdn.jsdelivr.net/gh/alhdfailfi/plug_app_public@main/screenshots/2.jpg" target="_blank">
    <img src="https://cdn.jsdelivr.net/gh/alhdfailfi/plug_app_public@main/screenshots/2.jpg" width="45%" alt="手动控制" style="border-radius: 12px; box-shadow: 0 4px 8px rgba(0,0,0,0.1);" />
  </a>
  <a href="https://cdn.jsdelivr.net/gh/alhdfailfi/plug_app_public@main/screenshots/3.jpg" target="_blank">
    <img src="https://cdn.jsdelivr.net/gh/alhdfailfi/plug_app_public@main/screenshots/3.jpg" width="45%" alt="定时与阈值" style="border-radius: 12px; box-shadow: 0 4px 8px rgba(0,0,0,0.1);" />
  </a>
  <a href="https://cdn.jsdelivr.net/gh/alhdfailfi/plug_app_public@main/screenshots/4.jpg" target="_blank">
    <img src="https://cdn.jsdelivr.net/gh/alhdfailfi/plug_app_public@main/screenshots/4.jpg" width="45%" alt="设置页面" style="border-radius: 12px; box-shadow: 0 4px 8px rgba(0,0,0,0.1);" />
  </a>
</div>

---

## ✨ 核心特性

* **🚀 纯本地局域网直连**：不经过任何云端服务器，基于 `tinytuya` 协议，极低延迟，保护隐私。
* **🔋 手机电量自动保护**：可设置上下限与多种运算符（`>`、`>=`、`==` 等），低于下限自动开插座，高于上限自动关，防止手机过充。
* **⏱️ 快捷倒计时**：设定时间后自动开启或关闭插座。
* **🔔 系统级通知震动**：触发阈值或倒计时结束时，弹出系统通知并伴随震动（静音设计，不打扰）。
* **🎵 自定义提示音**：支持调用手机本地音频（.mp3, .wav, .ogg 等），内置默认音效兜底。
* **🟢 全局状态指示**：顶部实时显示插座开关状态、连接状态（绿=在线，红=离线，黄=刷新中）。

---

## 🛠️ 技术栈 & 架构

* **前端框架**：Flutter (Dart)
* **底层通讯**：`tinytuya` (TCP 直连，带 3 秒强制超时防卡死)
* **状态与本地存储**：`shared_preferences`
* **通知与音频**：`flutter_local_notifications`、`audioplayers`
* **编译流水线**：**100% 全云端**（GitHub Actions），本地无需搭建任何环境，甚至不需要下载 Android Studio 即可一键打包签名 APK。

---

## ⚠️ 开源与安全须知（非常重要！）

如果你要将此项目设为 **Public（公开）**，请务必阅读以下安全铁律：

1. **切勿泄露设备密钥**：涂鸦插座的 `Local Key` 等同于插座的控制密码。在 `config.json` 中，`device` 字段的三个值**必须留空**。
2. **切勿上传签名文件**：`release-key.jks` 签名文件绝对不能提交到代码仓库！请在 `.gitignore` 中忽略它。
3. **推荐做法**：GitHub 仓库保持 Public 供大家学习；如果你自己要用，Fork 一份设为 Private（私有），在私有分支的 `config.json` 里填上你的设备信息，生成的 App 家人装上就能直接用。

---

## 📦 如何编译（无需本地环境）

本项目借助 GitHub Actions 实现了“一键云编译”，并且**完全不需要在本地下载 Android Studio**。如果你 Fork 了本项目并想自己编译出 APK，请按照以下教程操作：

### 第一步：生成自己的签名文件（Secrets）
因为安全限制，你 Fork 的仓库是无法直接使用本项目的 Secrets 的，你必须生成自己的签名。

1. **生成 `.jks` 签名文件**：
   确保你的电脑安装了 Java（在终端输入 `java -version` 测试）。然后在终端运行以下命令（会自动生成在电脑当前目录）：
   ```bash
   keytool -genkey -v -keystore my-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias plug_app
   ```
   *(过程中会让你设置密码，并填写一些姓名/国家等信息，随便填即可，**但请务必记住你设置的密码和别名 alias**)*

2. **将 `.jks` 转换为 Base64 字符串**：
   * **Windows (PowerShell)**：
     `[Convert]::ToBase64String([IO.File]::ReadAllBytes("你的jks文件绝对路径")) | Set-Clipboard`（执行后直接复制到了剪贴板）
   * **Mac / Linux**：
     `base64 -i my-release-key.jks | pbcopy`（或直接输出）
   *(把复制出来的这一大串文本保存好)*

3. **配置到 GitHub Actions**：
   进入你 Fork 后的仓库，点击 `Settings` -> `Secrets and variables` -> `Actions`，点击 `New repository secret`，添加以下 4 个变量：
   * `KEYSTORE_BASE64`：填入你刚刚生成的 Base64 长串。
   * `KEYSTORE_PASSWORD`：填入你设置的 keystore 密码。
   * `KEY_ALIAS`：填入你设置的别名（如 `plug_app`）。
   * `KEY_PASSWORD`：填入你设置的 key 密码（通常与上面一致）。

### 第二步：修改配置文件 `config.json`
项目根目录下的 `config.json` 用于给 App 注入默认的插座信息（如果你的家人朋友要用，可以直接打包进去，省去手动输入的麻烦）：
```json
{
  "device": {
    "devId": "你的设备ID",
    "ip": "插座局域网IP",
    "localKey": "你的设备密钥"
  }
}
```
*(⚠️ 开源安全警告：如果你要公开你的代码，请务必把这三个值留空 `""`，否则别人会控制你家插座！)*

### 第三步：一键编译
1. 进入仓库的 `Actions` 页面。
2. 点击左侧的 `智能插座 APK 打包`，然后在右侧点击 `Run workflow`。
3. 在弹出的选项里：
   * `build_arm64` 选 `true`（适合现代手机）
   * `build_arm32` 选 `false`（适合老旧手机）
   * 填入描述后，点击绿色的 `Run workflow`。
4. 等待约 5~8 分钟，在运行记录底部的 **Artifacts** 中下载编译好的 APK。

---
*如果这个项目对你有帮助，欢迎来我的 B站主页 支持一下！*