# LAN Sync

一个跨平台的局域网文件同步工具，支持Windows和Android设备之间的自动文件同步。

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