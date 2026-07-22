# Resource 契约推导

生成契约采用版本 2，并记录精确 `engine_version`、`engine_build_hash`、直接基类契约哈希与 `context_requirements`。引擎构建、脚本源码、插件版本或基类契约哈希变化后，旧契约必须判为过期并重新推导。

## 固定流程

1. 确认 Godot 版本、类型名、脚本路径、来源范围和输出位置。
2. 查官方类文档；项目或第三方类同时读脚本、基类和插件版本。
3. 反射实例的 `get_property_list()`，只收集 `usage & PROPERTY_USAGE_STORAGE != 0` 的属性。
4. 记录每个属性的 Variant 类型、class_name、hint、hint_string、usage 和默认值文本；默认值文本只是诊断信息，不等同于 `.tres` 语法。
5. 创建空值、最小值、代表值与嵌套 Resource 样本。无法安全构造时将模式降为 `generated_structure` 或 `resource_saver_only`。
6. 用 `ResourceSaver.save()` 保存到 `user://godot-dev/experiments/`，使用 `CACHE_MODE_IGNORE_DEEP` 重新加载。
7. 比较运行时类型和全部稳定存储属性；将不可稳定比较字段写入限制，不得静默忽略。
8. 把 Godot 保存的最小文本写入 `serialization.minimal_text`，把每个非默认代表值的完整属性行写入 `serialization.property_text_examples`，生成单类型契约并运行校验。
9. 在不查看实验样本文件的独立步骤中，仅依据契约重新编写一个新 `.tres`，再加载、比较稳定属性并往返保存。通过后才标为 `validated`、`direct_text` 和 `validation.independent_text=true`。

## 调用

```text
godot --headless --path <project> --script <skill>/scripts/derive_resource_contract.gd -- --type MyResource --source res://path/my_resource.gd --scope project --output <contract.json>
```

内置类型省略 `--source`。第三方必须增加 `--package-id` 和 `--package-version`。输出位置遵循 [contract-layout.md](contract-layout.md)；项目契约与本地第三方覆盖层更新 `docs/godot-dev/manifest.json`。

对于嵌套 Resource，契约必须保存可构造的非默认代表值、完整属性文本示例与独立文本重建证据。只能由 ResourceSaver 生成、需要外部运行时或无法安全构造的类型，应明确降级验证模式并写入上下文要求，不能伪装成可直接手写。
