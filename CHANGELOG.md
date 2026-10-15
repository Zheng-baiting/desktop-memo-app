# 变更记录

## 1.4.1 — 2026-10-15

- 提醒页改为更圆润的纸面、浅色圆角输入框和分段提醒方式选择，快捷时间使用胶囊按钮并显示当前选项；手动改时间会清除快捷选中状态；每日模式直接显示结束日期。
- 保存按钮统一圆角并固定底部；过去时间、结束日期或保存错误直接显示在操作区上方。
- 中英文与六种整体配色保持一致，原生窗口尺寸、日期验证、提醒逻辑和便签存档规则不变。
- 验证：94 项单元/交互测试通过，静态分析无问题；中英文实字形预览及 Windows 原生提醒、跨窗口配色同步和保存退出回归通过。

## 仓库整理 — 2026-10-15

补齐统一版本入口、维护规范与历史源码标签；产品仍为 `1.4.0+8`。这次只整理 Git 记录，不改变本机程序和用户便签。

以下条目来自已有提交及 `pubspec.yaml` 的版本记录。历史标签在 2026-10-15 补登记，代表相应源码快照，不表示当时曾通过 GitHub 发布安装包。旧版存在后续修正过的保存与删除问题，实际使用以当前版本为准。

## 1.4.0

[源码标签](https://github.com/Zheng-baiting/desktop-memo-app/tree/v1.4.0) · [对应提交](https://github.com/Zheng-baiting/desktop-memo-app/commit/774f19a)

增加六套整体配色，跨便签同步并保存外观偏好。

## 1.3.0

[源码标签](https://github.com/Zheng-baiting/desktop-memo-app/tree/v1.3.0) · [对应提交](https://github.com/Zheng-baiting/desktop-memo-app/commit/4e3fa36)

圆润关闭菜单、同尺寸提醒编辑、直接输入与快捷提醒时间、中英文设置。

## 1.2.0

[源码标签](https://github.com/Zheng-baiting/desktop-memo-app/tree/v1.2.0) · [对应提交](https://github.com/Zheng-baiting/desktop-memo-app/commit/760299d)

全部便签支持搜索、显示或收起状态与单张找回。

## 1.1.3

[源码标签](https://github.com/Zheng-baiting/desktop-memo-app/tree/v1.1.3) · [对应提交](https://github.com/Zheng-baiting/desktop-memo-app/commit/c247c8f)

× 提供保存并退出单张、确认后删除两个选项。

## 1.1.2

[源码标签](https://github.com/Zheng-baiting/desktop-memo-app/tree/v1.1.2) · [对应提交](https://github.com/Zheng-baiting/desktop-memo-app/commit/9df2129)

任务栏与托盘退出先收齐全部便签待保存编辑。

## 1.1.1

[源码标签](https://github.com/Zheng-baiting/desktop-memo-app/tree/v1.1.1) · [对应提交](https://github.com/Zheng-baiting/desktop-memo-app/commit/2995c17)

确认后永久删除，读取失败和旧实例覆盖保护。

## 1.1.0

[源码标签](https://github.com/Zheng-baiting/desktop-memo-app/tree/v1.1.0) · [对应提交](https://github.com/Zheng-baiting/desktop-memo-app/commit/4d2c975)

稍后提醒及恢复、保存流程验证；其早期软删除行为已由后续版本修正。

## 1.0.0

[源码标签](https://github.com/Zheng-baiting/desktop-memo-app/tree/v1.0.0) · [对应提交](https://github.com/Zheng-baiting/desktop-memo-app/commit/5712015)

独立便签窗口、原生启动与退出优化、卡通快捷方式图标。

详细行为、平台验证范围和测试入口见 [README](README.md)。
