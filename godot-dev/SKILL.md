---
name: godot-dev
description: 使用 Godot 4.7 官方文档、文本资产、运行时反射与 CLI 开发和验证 Godot 项目。用于创建、修改、审查或排错 GDScript、tres、res、tscn、节点、Resource、Signal 连接、Shader、Project Settings、Input Map、AutoLoad、插件配置、UID、导入与本地化资产；也用于推导和维护内置、第三方及项目 Node/Resource 契约。技能不依赖 MCP、编辑器插件或其他技能。
---

# Godot Dev

把磁盘文本和 Godot 运行时视为权威来源。只加载当前对象需要的参考与单类型契约，不预读整个契约库。

## 开始工作

1. 读取项目 `AGENTS.md`、`project.godot` 和受影响文件；项目规则优先于本技能的通用默认值。
2. 解析 Godot：显式路径优先，其次 `GODOT_BIN`，再查找 PATH 中的 `godot` 或 `godot4`。执行 `--version`；使用契约时完整版本和构建哈希必须同时匹配。
3. 检查编辑器是否可能对目标文件有未保存修改。无法确认时，先请人保存重叠文件。
4. 读取契约清单，只选择本次涉及的 Node/Resource 契约：
   - 项目：`docs/godot-dev/manifest.json`
   - 内置：`references/contracts/godot-4.7/manifest.json`
5. 按 [contract-layout.md](references/contract-layout.md) 选择有效项目契约、精确版本第三方契约、对应 Godot 版本内置契约。不存在或过期时执行推导，不凭记忆猜序列化规则。

## 选择参考

- 不明确的 Godot 行为：读取 [official-documentation-workflow.md](references/official-documentation-workflow.md)。
- `.tres`、`.res`、`.tscn`、引用或 UID：读取 [text-resource-format.md](references/text-resource-format.md)。
- 推导 Resource：读取 [resource-contract-derivation.md](references/resource-contract-derivation.md)，运行 `derive_resource_contract.gd`。
- 推导 Node：读取 [node-contract-derivation.md](references/node-contract-derivation.md)，运行 `derive_node_contract.gd`。
- 新增、移动或选择契约：读取 [contract-layout.md](references/contract-layout.md)。
- 编写场景树、owner、实例、组或保存的 Signal：读取 [scene-authoring.md](references/scene-authoring.md)。不要创建 Scene 契约。
- 审计复杂场景、依赖闭包或质量指标：读取 [scene-validation.md](references/scene-validation.md)，运行 `audit_scene.gd` 与 `collect_dependencies.gd`。
- 使用依赖 Skeleton、Navigation、Viewport、TileMap、Multiplayer、XR 或平台服务的类型：读取 [runtime-contexts.md](references/runtime-contexts.md)。
- `.gd`、脚本类或 UID：读取 [gdscript-and-uids.md](references/gdscript-and-uids.md)。
- `project.godot`、Input Map、AutoLoad 或插件：读取 [project-settings.md](references/project-settings.md)。
- Shader、本地化、导入资产：读取 [shaders-localization-imports.md](references/shaders-localization-imports.md)。
- 人正在使用编辑器：读取 [editor-collaboration.md](references/editor-collaboration.md)。
- 准备验证：读取 [cli-validation.md](references/cli-validation.md)。
- 修改或发布内置契约库：先用 `derive_builtin_contracts.gd` 在 `user://` 完成704类型生成实验，再用 `verify_builtin_contracts.gd` 独立重建；没有 `--require-complete` 严格校验不得宣称全量完成。

## 编写约束

- `.gd`、`.tres`、`.tscn`、`.gdshader` 和 `project.godot` 使用 UTF-8 文本；不要直接编辑 `.res`、`.scn` 或导入生成物。
- 只有契约的 `authoring_mode` 为 `direct_text` 时才从零手写对应类型。
- `generated_structure` 先由 Godot 创建并保存最小骨架，再做契约允许的文本调整。
- `scene_template` 从项目认可的模板开始。
- `resource_saver_only` 必须通过 Godot API 写入。
- `reference_only` 只允许引用或继承，不直接实例化。
- 场景是 Node/Resource 契约和通用场景规则的组合结果；不创建 `<scene>.scene-contract.json`。
- 默认值可写但 Godot 再保存时可能移除；不要依赖属性行是否存在表达业务语义。
- 修改现有文件时保留 Godot 已生成的 UID、资源 ID、节点路径和与任务无关的序列化顺序。

## 固定验证门槛

1. 对契约运行 `validate_contract.gd`。
2. 对每个变更的 `.gd`、`.tres`、`.res`、`.tscn` 运行 `validate_assets.gd`；场景必须加载并实例化。
3. 运行 `godot --headless --editor --path <项目> --quit` 完成导入和编辑器扫描。
4. 执行仓库规定的结构审计、测试和主场景运行；错误、孤儿节点和 ObjectDB 泄漏均视为失败。
5. 视觉任务可在可渲染显示驱动下运行 `capture_scene.gd`；`--headless` 禁用渲染，不能截图。截图存在不等于视觉正确。
6. 直接修改后让编辑器重新扫描。涉及 AutoLoad、全局脚本类、插件、GDExtension 或导入缓存时完整重启并重新验证。
7. 复杂变更运行 `collect_dependencies.gd` 取得反向依赖闭包；交付前可用 `verify_project.gd` 输出统一 JSON 报告。`skipped` 或 `blocked` 不等于通过。

内置契约库额外要求：704 个条目不得残留 `cataloged` 或 `stale`；`direct_text` 必须同时通过生成保存/重载、代表属性独立文本和再次往返。抽象类型验证不可实例化边界及具体子类见证；依赖外部运行时上下文的类型必须保守标为 `reference_only`。`AnimationTree` 家族必须运行专项资产测试，不能用空实例替代状态、Transition、连接和动画推进。

所有脚本都使用 Godot 的用户参数：

```text
godot --headless --path <project> --script <script> -- <arguments>
```

临时样本只写入 `user://godot-dev/`。验证失败时停止交付，报告具体文件、Godot 错误和尚未完成的同步步骤。
