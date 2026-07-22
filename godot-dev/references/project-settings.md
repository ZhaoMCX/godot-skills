# Project Settings 与扩展

- `project.godot` 是结构化文本，但官方建议通过 ProjectSettings 或编辑器修改不明显的设置。只在键和值格式明确时直接编辑。
- Input Map 位于 `[input]`，事件对象的 Variant 结构必须从相同 Godot 版本保存样本获得。
- AutoLoad 位于 `[autoload]`，前缀 `*` 表示启用。顺序、路径和全局名称都是契约的一部分。
- 插件启用列表位于 `[editor_plugins]`；安装、删除、替换或升级插件后重载插件。
- AutoLoad、全局脚本类、插件启用列表、导入缓存、删除脚本和 GDExtension 变化后完整重启编辑器。
- GDExtension、平台 SDK、导出模板和外部服务不属于纯文本契约能力；使用其官方构建或安装工具，再由 Godot 加载验证。
