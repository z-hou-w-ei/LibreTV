# LibreTV 本地个性化修改记录（LOCAL-MODIFICATIONS.md）

> **用途**：记录 2026-10-20 在本机部署 LibreTV 时做的全部个性化修改，作为升级/更新（git pull）后重新应用补丁、排查功能丢失的对照清单。
> 项目来源：https://github.com/LibreSpark/LibreTV ｜ 本地版本：v2.19.5 ｜ 部署目录：`C:\Hack APP\LibreTV`

---

## 1. 修改总览

| 文件 | 类型 | 修改内容 | `git pull` 后状态 |
|---|---|---|---|
| `src/lib/api-guard.ts` | 源码补丁 | 无密码时 API 完全免鉴权 | ⚠️ 可能冲突，需重新应用 |
| `src/app/api/status/route.ts` | 源码补丁 | 无密码时 `verified=true` | ⚠️ 可能冲突，需重新应用 |
| `src/components/auth.tsx` | 源码补丁 | 前端永不弹登录/配置密码框 | ⚠️ 可能冲突，需重新应用 |
| `.env` | 本地配置 | 免登录 + 8 点播源 + 2 直播源 + 超时参数 | ✅ 已被 `.gitignore` 排除，不受影响 |
| `public/intl.m3u` | 新增文件 | 本地国际精选直播源（6 频道） | ✅ 未跟踪文件，保留 |
| `start-LibreTV.ps1` | 新增脚本 | 自动启动服务 → 开 Edge 窗口 → 全窗关闭才停服 | ✅ 未跟踪文件，保留 |
| `LibreTV.bat` | 新增脚本 | 桌面双击入口（隐藏窗口运行 ps1） | ✅ 未跟踪文件，保留 |
| `stop-service.bat` | 新增脚本 | 手动停止服务（备用） | ✅ 未跟踪文件，保留 |
| 桌面 `LibreTV.lnk` | 系统快捷方式 | 指向 `LibreTV.bat`，图标 `public/favicon.ico` | ✅ 位于桌面，不受影响 |
| `.next/`（构建产物） | 生成 | `npm run build` 产出 | ✅ 已被 `.gitignore` 排除 |

---

## 2. 免登录补丁（3 处源码，核心功能）

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
DEFAULT_LIVE_SOURCES=[{"name":"央视卫视·IPv4","url":"https://peterhchina.github.io/iptv/CNTV-V4.m3u","epg":"https://11.112114.xyz/pp.xml"},{"name":"国际新闻·精选","url":"http://localhost:8080/intl.m3u"}]
```

要点：
- 直播源 ① 央视卫视·IPv4：368 频道（CCTV 全套、CGTN 多语、各卫视），依赖公网 IPv4；若源失效可换同类 IPv4 列表。
- 直播源 ② 国际新闻·精选：指向**本地文件** `public/intl.m3u`（见下），URL 中的端口必须与启动端口（8080）一致。

---

## 4. 新增文件

### 4.1 `public/intl.m3u` — 国际新闻精选直播源（6 频道）

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

## 5. 更新项目（git pull）后的恢复流程

```powershell
cd C:\Hack APP\LibreTV
git status                    # 查看本地修改/冲突
git stash                     # （可选）暂存本地补丁，再 pull 后恢复
git pull origin main
git status                    # 若 3 个源码文件报 conflict，逐个解决
```

按顺序处理：

1. **3 个源码补丁文件**（`src/lib/api-guard.ts`、`src/app/api/status/route.ts`、`src/components/auth.tsx`）：
   - 无冲突：直接检查 §2 中 3 处补丁是否仍存在（`git diff` 或直接读文件），被上游改没就重新应用；
   - 有冲突：以上游新版为准解决冲突，再按 §2 重新打补丁。
2. **`.env`、`intl.m3u`、3 个脚本、桌面快捷方式**：均不在版本库或未被跟踪，`git pull` 不会动它们，确认仍在即可。
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
