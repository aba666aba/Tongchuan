# LAN Sync

一个跨平台的局域网文件同步工具，支持Windows和Android设备之间的自动文件同步。

## 免责声明与安全现状

**请务必在了解以下事实后再使用：**

1. **默认不加密、不鉴权**：传输面是裸 TCP `Socket`/`ServerSocket`，未启用 TLS。`SecurityService` 虽提供了 TLS `Context` 构造函数与 `openssl` 调用，但**没有任何代码把它们接到 socket 上**。同一网段内任何设备都可发包。
2. **配对校验形同虚设**：`requestConnection` 生成配对码后**直接 `return true`**，无"等待用户确认"的等待逻辑，配对码也从不参与校验对端。
3. **接收端未做路径净化**：写入路径由对端包头中的 `relativePath` 直接拼接（`path.join(syncPath, relativePath)`），**恶意对端可尝试写入同步目录之外**。
4. **收到即落盘**：不校验磁盘空间与文件类型，同名文件直接覆盖，无冲突处理。
5. **建议**：仅供**同一可信局域网内的个人文件同步**使用；请勿用于传输敏感、机密数据。
6. **README 原先声明 MIT 许可但仓库内并无 LICENSE 文件**（该问题已在本轮修复中处理，见仓库根 LICENSE）。

## 功能特性

- 🔄 **自动同步**: 文件夹中的文件变化会自动同步到其他设备
- 📱 **跨平台**: 支持Windows和Android
- 📊 **传输进度**: 实时显示文件传输进度和速度
- 🔍 **设备发现**: 自动发现局域网内的其他设备
- 📁 **文件夹选择**: 可以选择任意文件夹进行同步
- 🖱️ **Windows右键菜单**: 右键直接发送文件/文件夹
- 📤 **Android分享**: 从其他应用分享文件到LAN Sync
- ⚡ **大文件快传**: 优化的传输协议，支持大文件快速传输
- 🔄 **断点续传**: 支持中断后继续传输（协议已支持）

## 技术架构

- **UI框架**: Flutter + Dart
- **通信协议**: 自定义TCP协议
- **设备发现**: UDP广播
- **文件监控**: 定期扫描文件系统变化
- **传输优化**: 自适应chunk大小（64KB/1MB）

## 项目结构

```
lan_sync/
├── lib/
│   ├── main.dart                 # 应用入口和状态管理
│   ├── protocol/
│   │   └── protocol.dart         # TCP协议定义
│   ├── services/
│   │   ├── network_service.dart  # 网络服务
│   │   ├── file_watcher_service.dart  # 文件监控
│   │   ├── transfer_manager.dart     # 文件传输
│   │   └── sharing_service.dart      # Android分享
│   └── screens/
│       ├── home_screen.dart      # 主屏幕
│       ├── send_screen.dart      # 发送屏幕
│       ├── devices_screen.dart   # 设备列表
│       ├── transfers_screen.dart # 传输列表
│       └── settings_screen.dart  # 设置页面
├── windows/
│   └── shell_extension/          # Windows右键菜单
│       ├── install.bat           # 安装脚本
│       └── uninstall.bat         # 卸载脚本
└── android/
    └── app/src/main/
        └── AndroidManifest.xml   # Android配置
```

## 使用说明

### 前置条件

1. 安装Flutter SDK (版本3.44.0或更高)
2. 安装Android Studio (用于Android开发)
3. 安装Visual Studio (用于Windows开发，需要C++桌面开发工作负载)

### 构建发布版本

#### Windows
```bash
cd lan_sync
flutter build windows --release
```
生成的可执行文件位于: `build/windows/x64/runner/Release/`

#### Android
```bash
cd lan_sync
flutter build apk --release
```
生成的APK文件位于: `build/app/outputs/flutter-apk/app-release.apk`

### 安装Windows右键菜单

1. 先构建Windows版本
2. 以管理员身份运行 `windows/shell_extension/install.bat`
3. 重启资源管理器或注销重新登录

卸载右键菜单：
- 以管理员身份运行 `windows/shell_extension/uninstall.bat`

### 使用方式

#### 方式1：自动同步模式
1. 在两台设备上安装应用
2. 连接到同一WiFi网络
3. 选择同步文件夹
4. 点击"Start"开始同步
5. 添加文件到文件夹，自动同步到其他设备

#### 方式2：Windows右键菜单
1. 在文件或文件夹上点击右键
2. 选择 "Send via LAN Sync"
3. 选择目标设备
4. 文件开始传输

#### 方式3：Android分享
1. 在其他应用中点击分享
2. 选择 "LAN Sync"
3. 选择目标设备
4. 文件开始传输

## 支持的传输场景

- ✅ Windows → Windows
- ✅ Windows → Android
- ✅ Android → Windows
- ✅ Android → Android
- ✅ 文件夹传输
- ✅ 单文件传输
- ✅ 多文件传输（Android分享）

## 协议说明

### 消息类型

1. **Discovery (设备发现)**
   - UDP广播，端口8888
   - 包含设备ID、名称、平台、端口信息

2. **FileTransferRequest (文件传输请求)**
   - TCP，端口8889
   - 包含文件名、大小、相对路径

3. **FileChunk (文件数据块)**
   - 小文件: 64KB/块
   - 大文件 (>10MB): 1MB/块
   - 包含块索引和总块数

4. **FileTransferComplete (传输完成)**
   - 标记传输成功或失败

5. **FileTransferResume (断点续传)**
   - 支持从指定位置继续传输

### 传输优化

- **自适应chunk大小**: 小文件使用64KB，大文件使用1MB
- **并行传输**: 支持同时传输多个文件
- **进度实时更新**: 显示传输速度和进度

## 开发进度与已知不足

### 已实现（代码可验证）

- 自研 TCP + UDP 协议：4 字节头长 + JSON 头 + payload 的消息帧；另一套二进制协议（magic `0x4C53594E`、文件头/数据块/完成/进度四类包、CRC32 表）
- UDP 设备发现（8888 广播、按 deviceId 去重）；按网卡子网逐一计算广播地址并兜底 `255.255.255.255`
- TCP 传输端口 8889，`shared: true` 多实例绑定，`tcpNoDelay`
- 自适应传输：chunk 大小与并行度下传、拥塞窗口与慢启动/拥塞避免、四种速度模式（保守/均衡/极速/极限）与设置 UI
- 网络探测与 `NetworkProfile` 质量分级
- 接收端 CRC32 校验；临时文件接收完成后改名落盘并建目录
- 定期扫描式文件监控（1 秒轮询，含隐藏/临时/系统文件过滤）；防回环（接收后 5 秒内忽略同名事件）
- 离线设备清理（30 秒无广播移除）
- 6 位配对码生成 + 受信设备白名单持久化（`trusted_devices.json`）+ 受信设备管理 UI
- Windows 右键菜单（注册 `*\shell`、`Directory\shell`、`Directory\Background\shell` 三条注册表项 + 卸载脚本）；Android 分享 intent-filter 声明
- 四页 Material 3 UI（首页 / 设备 / 传输 / 设置），含进度条与速度格式化

### 未实现 / 已知不足（**其中第 1 条为阻断性问题**）

1. **收发两端包格式不一致，接收路径实际不可用**：
   - 发送端文件头含 `chunkSize` / `parallelChunks` 各 4 字节，解析端按**不含**这两字段的布局读取 → 之后所有字段错位
   - 发送端数据块含 4 字节 transferId 长度 + id，解析端按"24 字节头 + 数据"读 → `dataLength` 读到的是 CRC
   - 完成标记含 transferId，`_parseComplete` 只读 12 字节且**不回填 `transferId`**，而 `_handleComplete` 依赖它查状态 → 恒为 null
   - **结论：端到端传输尚未验证成功**。README 原先声称"Windows↔Android 四种场景全部 ✅"是不实描述
2. **无 TCP 粘包/拆包处理**：`socket.listen` 每次回调被当作"恰好一个完整包"
3. **断点续传未实现**：`FileTransferResume` / `FileTransferResumeRequest` 只有数据类，无任何发送/接收代码
4. **`fast_transfer_service.dart` 是死代码**：无文件 import，且其 `_processReceivedData` 定义与调用处参数个数不匹配，接收路径为空壳
5. **Android 分享收不到文件**：`sharing_service.dart` 的 `startListening()`/`stopListening()` 是空函数，注释称"实现在原生代码中"，但 `MainActivity.kt` 只有一行空类
6. **不支持文件删除/重命名同步**：watcher 会产出 delete 事件，但主流程只处理 create/modify
7. 中间进度速度恒定不更新；未信任设备被静默跳过（UI 无提示）
8. **设备信任在重启后失效**：白名单按 deviceId 持久化，而 deviceId 是每次启动新生成的 v4 UUID
9. 安全目录用 `Directory.current`，Android 上也走同一路径
10. 右键菜单路径下 `networkService` 为 null 会抛异常（`send_screen.dart` 用 `appState.networkService!`，而该路径下 `startSync()` 从未被调用）
11. `send_screen` 构建的 `NetworkService` 未传 `securityService` → 该路径不做信任校验
12. 接收端无磁盘空间检查、无同名冲突处理；失败/中断后临时文件残留无清理
13. 自适应参数实际被固定：探测函数是"简化实现"，`medianLatency` 恒为约 50ms、吞吐量恒为 1.28MB/s；探测包发出后无人解析
14. 大文件存在数据竞争风险（`Uint8List buffer` 复用且不等待分块完成）
15. 无任何有意义的测试（唯一测试是模板计数器冒烟测试，对本 App 必然失败）；`pairing_verify_dialog.dart` 为死代码
16. iOS/macOS/Linux 分支仅在设备名里写了判断，无对应 runner 目录
17. `pubspec.yaml` 描述仍是模板 "A new Flutter project."

## 注意事项

1. **防火墙设置**
   - 确保防火墙允许应用访问网络
   - Windows需要允许8888和8889端口

2. **网络权限**
   - Android需要网络权限
   - 已在AndroidManifest.xml中配置

3. **文件冲突**
   - 当前版本不处理文件冲突
   - 后来的文件会覆盖之前的文件

## 已知限制

1. 不支持文件删除同步
2. 不支持文件重命名同步
3. 断点续传功能需要进一步完善
4. 不支持加密传输

## 未来改进

- [ ] 支持文件删除同步
- [ ] 支持文件重命名同步
- [ ] 完善断点续传功能
- [ ] 添加加密传输选项
- [ ] 添加文件冲突处理
- [ ] 添加传输历史记录
- [ ] 添加设备配对功能
- [ ] 添加iOS支持

## 开发说明

### 添加新功能

1. 在`protocol/protocol.dart`中定义新的消息类型
2. 在`services/`中实现相应的服务
3. 在`screens/`中添加UI界面

### 调试

- 使用`flutter logs`查看日志
- 使用`flutter analyze`检查代码质量

## 许可证

MIT License

## 联系方式

如有问题或建议，请提交Issue或Pull Request。