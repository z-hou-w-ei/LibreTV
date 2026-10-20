# LibreTV 本地个性化修改记录（LOCAL-MODIFICATIONS.md）

> **用途**：记录 2026-10-20 在本机部署 LibreTV 时做的全部个性化修改，作为升级/更新（git pull）后重新应用补丁、排查功能丢失的对照清单。
> 项目来源：https://github.com/LibreSpark/LibreTV ｜ 本地版本：v2.19.5 ｜ 部署目录：`C:\Hack APP\LibreTV`
>
> **🌐 本机个性化修改的公开备份（GitHub fork）**：https://github.com/z-hou-w-ei/LibreTV
> 本地已配置两个远程仓库：`origin` = 上游 LibreSpark/LibreTV（拉取更新用）、`fork` = 本 fork（推送本地修改用）。同步上游的完整流程见 §5。

---

## 1. 修改总览

| 文件 | 类型 | 修改内容 | `git pull` 后状态 |
|---|---|---|---|
| `src/lib/api-guard.ts` | 源码补丁 | 无密码时 API 完全免鉴权 | ⚠️ 可能冲突，需重新应用 |
| `src/app/api/status/route.ts` | 源码补丁 | 无密码时 `verified=true` | ⚠️ 可能冲突，需重新应用 |
| `src/components/auth.tsx` | 源码补丁 | 前端永不弹登录/配置密码框 | ⚠️ 可能冲突，需重新应用 |
| `src/lib/proxy-handlers.ts` | 源码补丁 | 流代理 m3u8 读取防崩溃（客户端断开不击穿进程） | ⚠️ 可能冲突，需重新应用 |
| `src/app/api/live/probe/route.ts` | 源码补丁 | 直播测活 m3u8 读取防崩溃 | ⚠️ 可能冲突，需重新应用 |
| `src/components/live-channel-list.tsx` | 源码补丁 | 直播分组标签条由横向滑动改为自动换行（全部分组一次显示，无需左右滑动） | ⚠️ 可能冲突，需重新应用 |
| `src/components/live-player.tsx` | 源码补丁 | 直播换台复用同一 video 元素切换源、不重建播放器（保持 Edge 画中画不暂停，详见 §2.4） | ⚠️ 可能冲突，需重新应用 |
| `stress_abort_test.py` | 新增文件 | 客户端中断回归压测脚本 | ✅ 未跟踪文件，保留 |
| `.env` | 本地配置 | 免登录 + 8 点播源 + 2 直播源 + 超时参数 | ✅ 已被 `.gitignore` 排除，不受影响 |
| `public/intl.m3u` | 新增文件 | 本地国际精选直播源（6 频道） | ✅ 未跟踪文件，保留 |
| `start-LibreTV.ps1` | 新增脚本 | 自动启动服务 → 开 Edge 窗口 → 全窗关闭才停服 | ✅ 未跟踪文件，保留 |
| `LibreTV.bat` | 新增脚本 | 桌面双击入口（隐藏窗口运行 ps1） | ✅ 未跟踪文件，保留 |
| `stop-service.bat` | 新增脚本 | 手动停止服务（备用） | ✅ 未跟踪文件，保留 |
| 桌面 `LibreTV.lnk` | 系统快捷方式 | 指向 `LibreTV.bat`，图标 `public/favicon.ico` | ✅ 位于桌面，不受影响 |
| `.next/`（构建产物） | 生成 | `npm run build` 产出 | ✅ 已被 `.gitignore` 排除 |

---

## 2. 源码补丁（免登录 + 画中画保持）

### 2.1 `src/lib/api-guard.ts` — API 守卫放行

修改后 `guardRequest` 在未配置密码时直接放行：

```ts
export function guardRequest(req: Request): NextResponse | null {
  if (!isPasswordConfigured()) {
    return null;                       // ← 本地补丁：无密码完全开放
  }
  if (!sessionFromCookieHeader(req.headers.get('cookie'))) {
    return NextResponse.json({ error: '未登录' }, { status: 401 });
  }
  return null;
}
```

### 2.2 `src/app/api/status/route.ts` — 状态接口始终已验证

修改后客户端拿到的 `verified` 在无密码模式下恒为 `true`：

```ts
const passwordRequired = isPasswordConfigured();
// 本地补丁：无密码模式（PASSWORD 未设置）下视为始终已验证，前端不弹登录框
const verified = passwordRequired ? sessionFromCookieHeader(req.headers.get('cookie')) : true;
```

### 2.3 `src/components/auth.tsx` — 前端不弹登录/配置框

修改 `AuthProvider` 内 `/api/status` 回调：`setSetupRequired(false)` 硬编码为恒 `false`：

```tsx
.then((s) => {
  if (cancelled) return;
  setVerified(s.verified);
  // 本地补丁：无密码部署模式，不要求配置密码，也不弹登录/设置框
  setSetupRequired(false);
  setVersion(s.version);
  setChecked(true);
})
```

> 配套约定：`.env` **不设置 `PASSWORD`**。一旦将来在 `.env` 里加了 `PASSWORD`，补丁 2.1/2.2 会自动回到"需登录"模式（`isPasswordConfigured()` 变为 true），行为可预期。

### 2.4 稳定性加固（客户端中断不崩溃 + 服务自动重启）—— 2026-10-20 追加

**问题现象**：使用中操作几步后出现"网络请求失败"，再操作或返回主页提示"无法访问、拒绝连接"（服务进程消失，`server.log.err` 无任何错误）。

**根因**：直播/点播 HLS 流代理 `src/lib/proxy-handlers.ts` 的 m3u8 分支中 `await response.text()` 为**裸调用**（无 try/catch）。用户在流请求传输完成前切台/关页/返回时，服务端 abort 上游连接导致该 promise 以 rejection 结束——Node 对未捕获 rejection 默认直接终止整个进程，且不写任何日志。

**修改**：
1. `src/lib/proxy-handlers.ts` — 两处（`handleProxyRequest` 点播代理、`handleLiveStreamRequest` 直播代理）m3u8 读取包 try/catch，中断时返回 `499`（不抛出、不击穿进程）。
2. `src/app/api/live/probe/route.ts` — `fetchHeadersOnly` 的 m3u8 读取同样加 try/catch（中断按该频道本次探测失败处理）。
3. `start-LibreTV.ps1` — 守护循环重构：**窗口未出现时保持服务运行并持续检测（绝不误停）；有窗口时服务崩溃自动重启（watchdog）；仅当"窗口曾出现且全部关闭"才停服**。窗口打开改为最多重试 3 次。

**验证**（压测脚本 `stress_abort_test.py`）：
- 20 轮 m3u8 manifest 强制中断 + 10 并发流中断 → 服务全程存活；
- 杀掉 node 服务模拟崩溃 → 启动器 20 秒内自动重启；
- 全部 LibreTV 窗口关闭 → 服务正确停止。

### 2.5 画中画保持修复（Edge PiP 不暂停）—— 2026-10-20 追加

**问题现象**：直播播放中使用 Edge 画中画（小窗）后，回到 LibreTV 页面换台/操作，小窗播放会暂停。

**根因**：`src/components/live-player.tsx` 原实现把 `url` 放进播放器创建 effect 的依赖数组——换台（url 变化）时整个播放器 `art.destroy()` 并**新建 video 元素**。浏览器画中画跟随的是原 video 元素，元素被销毁后 PiP 即退出/暂停。

**修复**：直播播放器改为与点播播放器一致的设计——ArtPlayer 实例**只在挂载时创建一次**，换台只切换 HLS/FLV/原生源、复用同一 `<video>` 元素，绝不销毁重建；仅手动"重新加载"（错误恢复）允许重建实例：
1. 创建 effect 依赖数组去掉 `url`（保留 `retryNonce` / 换台回调）；
2. 新增 `switchSource(targetUrl)`：重置播放状态 → `cleanupEngines()`（只销毁 hls/mpegts 引擎）→ 按引擎分发 `setupHls/setupFlv/setupNative` 复用 `art.video`；
3. 新增 `[url]` effect 调用 `switchSourceRef.current?.(url)`（跳过首次挂载）；
4. 各引擎的"直连失败回退代理/原生"统一改用 `fallbackUrl` 参数（基于本次目标地址，而非闭包里的旧 prop）。

**验证**：浏览器实测换台（CCTV13 → CCTV15）——video 元素标记保持不变（同一 DOM 节点未重建）、新频道正常起播（paused=false）。点播播放器（player-shell.tsx）原本就是"只切源不重建"设计，无需改动。

---

## 3. `.env` 配置（已被 .gitignore 排除，pull 不影响）

当前完整内容（2026-10-20）：

```ini
# 无密码模式：不设置 PASSWORD，站点免登录直接使用（已打补丁支持）
REQUEST_TIMEOUT=20000
MAX_RETRIES=2
SEARCH_SOURCE_TIMEOUT_MS=30000
SEARCH_MAX_PAGES=5
# 允许直播流代理访问内网/保留地址（自建 IPTV 源场景）
LIVE_ALLOW_PRIVATE=1

# 预置点播源（Apple CMS 采集站，8 个均实测可用）
DEFAULT_SOURCES=[{"name":"非凡资源","url":"https://cj.ffzyapi.com/api.php/provide/vod"},{"name":"暴风资源","url":"https://bfzyapi.com/api.php/provide/vod"},{"name":"量子资源","url":"https://cj.lziapi.com/api.php/provide/vod"},{"name":"光速资源","url":"https://api.guangsuapi.com/api.php/provide/vod"},{"name":"红牛资源","url":"https://www.hongniuzy2.com/api.php/provide/vod"},{"name":"极速资源","url":"https://jszyapi.com/api.php/provide/vod"},{"name":"电影天堂","url":"http://caiji.dyttzyapi.com/api.php/provide/vod"},{"name":"百度资源","url":"https://api.apibdzy.com/api.php/provide/vod"}]

# 预置直播源（M3U 订阅，已实测）
DEFAULT_LIVE_SOURCES=[{"name":"央视卫视·IPv4","url":"http://localhost:8080/cntv-v4.m3u","epg":"https://11.112114.xyz/pp.xml"},{"name":"国际新闻·精选","url":"http://localhost:8080/intl.m3u"}]
```

要点：
- 直播源 ① 央视卫视·IPv4：**本地文件** `public/cntv-v4.m3u`（peterhchina CNTV-V4 列表本地化，368 频道：CCTV 全套、CGTN 多语、各卫视）。**不用远程 GitHub 地址的原因**：FastGithub 劫持 GitHub 域后，Node 服务端 fetch 因 TLS 证书校验失败返回 502，订阅拉取报失败；本地文件不依赖任何外网域，永不 502。频道流地址失效时重新下载：`curl -sk -o public/cntv-v4.m3u https://raw.githubusercontent.com/peterhchina/iptv/master/CNTV-V4.m3u`。
- 直播源 ② 国际新闻·精选：指向**本地文件** `public/intl.m3u`（见下），URL 中的端口必须与启动端口（8080）一致。

---

## 4. 新增文件

### 4.1 `public/cntv-v4.m3u` — 央视卫视直播源（本地化，368 频道）

peterhchina 的 CNTV-V4 IPv4 列表，已下载为本地文件（原因见 §3：GitHub 远程地址在 FastGithub 环境下服务端 502）。覆盖 CCTV 全套、CGTN 多语种、各省卫视，抽样实测可播率 28/30。
**更新方法**（流地址失效时）：
```powershell
curl.exe -sk -o "C:\Hack APP\LibreTV\public\cntv-v4.m3u" "https://raw.githubusercontent.com/peterhchina/iptv/master/CNTV-V4.m3u"
```

**频道分组**：LibreTV 的 m3u 解析器优先读取 `#EXTINF` 行内的 `group-title` 属性（`#EXTGRP` 行会被忽略，属性缺失时才生效）。原列表自带 4 组（央视频道/卫视频道/电影频道/地方频道），我用 `re-group.py` 按频道名规则改写为 6 个更具体的分组（368 频道，组名不带重复的"频道"字样）：
| 分组 | 数量 | 识别规则 |
|---|---|---|
| 央视 | 16 | 频道名以 CCTV / CGTN 开头 |
| 卫视 | 26 | 频道名含"卫视" |
| 地方 | 242 | 含省市台特征词（综合/新闻/科教/经视/电视台等） |
| 电影 | 41 | 原属电影组且频道名含"电影" |
| 剧集 | 39 | 原属电影组的影视剧作品（西游记、倚天屠龙记等） |
| 专题 | 4 | 其余（兵器科技、熊猫直播、风云剧场等） |

如需重新分组，修改 `re-group.py` 的分类规则后执行 `python re-group.py`（会同步清除无效的 #EXTGRP 行，并对旧版"X频道"组名自动映射，可重复运行）。

### 4.2 `public/intl.m3u` — 国际新闻精选直播源（6 频道）

实测当前联通宽带上可直连播放；更新项目时**不要删除此文件**：

| 频道 | URL |
|---|---|
| BBC World News | `http://cdns.jp-primehome.com:8000/zhongying/live/playlist.m3u8?cid=cs15` |
| CNN International | `https://turnerlive.warnermediacdn.com/hls/live/586495/cnngo/cnn_slate/VIDEO_0_3564000.m3u8` |
| Fox News Now | `https://fox-foxnewsnow-samsungus.amagi.tv/playlist720p.m3u8` |
| CNA | `https://d2e1asnsl7br7b.cloudfront.net/7782e205e72f43aeb4a48ec97f66ebbe/index_5.m3u8` |
| RT News | `https://rt-glb.rttv.com/dvr/rtnews/playlist_4500Kb.m3u8` |
| RT Documentary | `https://rt-rtd.rttv.com/live/rtdoc/playlist_4500Kb.m3u8` |

> 已验证不可用（无需再试）：半岛、NHK、DW、彭博、CNBC、fanmingming IPv6 列表（本机无公网 IPv6）、移动组播 2409: 段、yanggather 整列表（响应超 40s 导致代理 502）。

### 4.2 启动/停止脚本（3 个，位于项目根目录）

- **`LibreTV.bat`** —— 桌面双击入口：`cd /d "C:\Hack APP\LibreTV"` 后以隐藏窗口运行 `start-LibreTV.ps1`。
- **`start-LibreTV.ps1`** —— 核心启动器，流程：
  1. 检查 8080 端口，未监听则用 `node node_modules\next\dist\bin\next start -p 8080` 后台启动服务（日志 `server.log` / `server.log.err`），轮询 `/api/status` 直到就绪；
  2. 以 `msedge --app=http://localhost:8080` 打开 Edge 应用窗口；
  3. 用 **Win32 `EnumWindows` API 枚举所有可见顶层窗口，按标题含 `LibreTV` 收集窗口句柄**（不依赖进程数，Edge 常驻附加模式下也能正确识别多窗口）；
  4. 轮询直到 LibreTV 窗口**全部关闭**才停止服务。
  > ⚠️ 脚本必须保持 **纯 ASCII 内容**（PowerShell 5.1 对无 BOM 的 UTF-8 中文按 GBK 解析会直接报语法错误）。
- **`stop-service.bat`** —— 手动停止服务（备用）：按 8080 监听 PID `Stop-Process -Force`。

### 4.3 桌面快捷方式

`C:\Users\Administrator\Desktop\LibreTV.lnk`：
- Target：`C:\Hack APP\LibreTV\LibreTV.bat`
- WorkingDirectory：`C:\Hack APP\LibreTV`
- Icon：`C:\Hack APP\LibreTV\public\favicon.ico`

---

## 5. 同步上游更新 + 恢复本地功能（标准流程）

本机已配置双远程：`origin` = 上游（拉取更新）、`fork` = 个人 fork https://github.com/z-hou-w-ei/LibreTV（备份推送）。

```powershell
cd C:\Hack APP\LibreTV
git status                      # 确认工作区干净（有未提交改动先 commit 或 stash）
git fetch origin                # 拉取上游最新提交
git rebase origin/main          # 把本地个性化提交移到上游最新之上（有冲突会停下）
# 若提示冲突：git status 查看冲突文件 → 手动解决 → git add <文件> → git rebase --continue
git push fork main              # 备份推送个人 fork
git status                      # 确认干净；若 3 个源码补丁文件被上游改动，检查后重打
```

按顺序处理：

1. **3 个源码补丁文件**（`src/lib/api-guard.ts`、`src/app/api/status/route.ts`、`src/components/auth.tsx`）：
   - rebase 无冲突：检查 §2 中 3 处补丁是否仍生效（读文件或 `git log -p`），被上游改没就重新应用；
   - rebase 有冲突：以上游新版为准解决冲突，再按 §2 重新打补丁，`git rebase --continue` 后重新 `git push fork main`。
2. **`.env`、`intl.m3u`、3 个脚本、桌面快捷方式**：均不在版本库或未被跟踪，同步不会动它们，确认仍在即可。
3. **依赖与构建**（源码有变时）：
   ```powershell
   npm install
   npm run build
   ```
4. **回归测试**：
   - `http://localhost:8080/api/status` 应返回 `passwordRequired=false, verified=true`，`defaultSources` 8 项、`defaultLiveSources` 2 项；
   - 首页直接可用（无登录框）；搜索任一关键词有跨源结果；
   - 「直播」页两个分组可播放（央视卫视、国际新闻）；
   - 双击桌面快捷方式 → 服务启动+窗口打开；关闭全部窗口 → 服务停止；多开窗口关 1 个服务不停止。

---

## 6. 建议备份清单（防丢失）

将以下文件另存一份（如 `C:\Hack APP\backup-libretv-20261020\`）：
`.env`、`src/lib/api-guard.ts`、`src/app/api/status/route.ts`、`src/components/auth.tsx`、`public/intl.m3u`、`start-LibreTV.ps1`、`LibreTV.bat`、`stop-service.bat`

---

*记录时间：2026-10-20 ｜ 修改人：本地部署（豆包办公）*
