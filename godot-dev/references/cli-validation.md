# Godot CLI 验证矩阵

## 基线

```text
godot --version
godot --headless --editor --path <project> --quit
```

契约要求 Godot 完整版本与构建哈希同时匹配。编辑器扫描负责导入、全局类、插件和 UID 上下文，不能由单文件解析替代。

## 技能自身回归

修改技能后，在 `tests/fixture_project/` 隔离工程中运行：

```text
godot --headless --editor --path <fixture> --quit
godot --headless --path <fixture> --script <skill>/scripts/self_test.gd
godot --headless --path <fixture> --script res://verify_direct_text.gd
godot --headless --path <fixture> --script res://verify_animation_tree.gd -- --generate
godot --headless --path <fixture> --script res://verify_animation_tree.gd -- --verify-direct
godot --headless --path <fixture> --script res://verify_scene_audit.gd
godot --headless --path <fixture> --script res://verify_dependency_closure.gd
godot --headless --path <fixture> --script res://verify_runtime_contexts.gd
godot --headless --path <fixture> --script res://verify_project_runner.gd
```

回归必须覆盖文本与二进制 Resource/Scene、owner、持久 Signal、SceneTree 生命周期、继承场景、PackedScene 实例、`[editable]`、局部 Resource、NodePath、动态加载提示、AnimationTree、Shader、导入资源和上下文节点。

## 704 份内置契约

先写入隔离的 `user://`，再用独立验证器仅依据契约重建样本：

```text
godot --headless --path <project> --script <skill>/scripts/derive_builtin_contracts.gd -- --manifest <skill>/references/contracts/godot-4.7/manifest.json --output-root user://godot-dev/builtin-contracts
godot --headless --path <project> --script <skill>/scripts/verify_builtin_contracts.gd -- --manifest user://godot-dev/builtin-contracts/manifest.json --update
godot --headless --path <project> --script <skill>/scripts/validate_contract.gd -- --manifest user://godot-dev/builtin-contracts/manifest.json --require-complete
```

要求 704 份全部进入明确状态，零失败；`direct_text` 必须有保存、重载、独立文本重建证据。正式目录与隔离目录再次生成后，对所有契约 JSON 做内容哈希比较，必须零差异。抽象类、占位类、OpenXR 等上下文类型可以是 `reference_only`，但必须记录原因和上下文要求。

## 按资产验证

```text
godot --headless --path <project> --script <skill>/scripts/validate_assets.gd -- --file res://a.tres --file res://b.tscn --file res://c.gd --file res://image.svg --file res://shader.gdshader
```

- `.gd`：加载 Script，解析失败即失败。
- `.tres`/`.res`：绕过缓存加载；`.tres` 额外往返保存和重新加载。
- `.tscn`/`.scn`：加载 PackedScene、实例化、进入 SceneTree 两帧并释放。
- 导入资产与 Shader：先完成编辑器扫描，再由 `ResourceLoader` 加载；Shader 还须进入真实渲染场景验证。

Godot 4.7.1 保存含手工三角形的 `AnimationNodeBlendSpace2D` 时可能把 `triangles` 排在点定义之前。文本资产必须把 `triangles` 放在所有 `blend_point_*` 之后；验证器会在往返副本中规范该顺序。

## 复杂场景与依赖闭包

```text
godot --headless --path <project> --script <skill>/scripts/collect_dependencies.gd -- --changed res://changed_asset.tscn --report user://godot-dev/reports/dependencies.json
godot --headless --path <project> --script <skill>/scripts/audit_scene.gd -- --file res://scene.tscn --manifest <manifest.json> --strict --report user://godot-dev/reports/scenes.json
```

先根据静态 `res://`、UID、场景继承和实例引用计算正向/反向闭包，再验证所有受影响资产。动态 `load()`、`preload()` 或拼接路径不能静态证明完整，报告必须保留警告并由业务测试补足。

场景审计加载并实例化场景，检查 owner、唯一名称、持久信号、契约声明的 NodePath、AnimationPlayer/AnimationTree 绑定、局部资源实例隔离，并记录节点数、深度和实例化时间。严格模式下，未被契约分类的 NodePath 视为失败。

## 截图与统一报告

```text
godot --path <project> --audio-driver Dummy --script <skill>/scripts/capture_scene.gd -- --scene res://scene.tscn --output user://godot-dev/captures/scene.png --frames 3
godot --headless --path <project> --script <skill>/scripts/verify_project.gd -- --profile res://validation_profile.json --report user://godot-dev/reports/verification.json
```

Headless 显示驱动禁用渲染与窗口管理，适合契约、资源和结构验证；截图必须使用可渲染显示驱动。截图脚本会在 Headless 下立即失败，避免无限等待。无显示设备的 CI 只能把视觉验收标为 `blocked` 或 `skipped`，不能伪报通过。

统一报告使用 `passed`、`failed`、`skipped`、`blocked` 四种状态，串联依赖闭包、契约、资产、场景、预算、编辑器扫描、主场景、渲染和导出。脚本错误、资源错误、孤儿节点、ObjectDB 泄漏或新增运行日志错误均为失败；未配置的导出或无显示环境必须明确跳过或阻塞。
