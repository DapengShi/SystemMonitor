# SystemMonitor 详情页面访问指南

## 如何打开详情页面

1. 首先，确保你已经启动了最新版本的SystemMonitor应用。

2. 在Mac屏幕顶部的菜单栏中，找到SystemMonitor图标（显示CPU、MEM和网络数据的图标）。

3. 点击该图标，会弹出一个下拉菜单。

4. 在菜单中，找到并点击「Open Detailed View」选项。
   ![菜单栏示意图](menu_illustration.png)

5. 或者，你可以使用键盘快捷键：⌘+D（按住Command键，同时按D键）。

6. 详情页面将会打开，显示系统资源使用的详细信息和进程列表。

## 如果找不到「Open Detailed View」选项

如果你在菜单中没有看到「Open Detailed View」选项，可能是因为：

1. 你正在运行的是旧版本的SystemMonitor。请确保使用本次更新提供的最新版本。

2. 应用可能需要重新启动。请尝试以下步骤：
   - 在菜单中选择「Quit」退出应用
   - 重新打开SystemMonitor.app

3. 如果问题仍然存在，请尝试以下命令重新安装应用：
   ```
   cd /Users/shidapeng/Documents/SystemMonitor
   ./package_app.sh
   open SystemMonitor.app
   ```

## 详情页面功能概览

成功打开详情页面后，你将看到：

- 左侧：CPU、内存和网络使用情况的图形化展示
- 右侧：系统进程列表，可以按不同条件排序
- 底部：进程管理控制，可以安全终止选定的进程

详情页面提供了比菜单栏更丰富的信息和更强大的功能，特别适合需要监控和管理系统资源的场景。