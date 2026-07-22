# Node 契约推导

生成契约采用版本 2，并记录精确 `engine_version`、`engine_build_hash`、直接基类契约哈希、`context_requirements` 与 `path_constraints`。任一引擎身份或基类契约变化都要求重新推导，不能沿用旧验证结论。

## 固定流程

1. 确认 Node 类型、脚本路径、来源及 Godot 版本。
2. 查官方类文档；再读取项目或第三方脚本、工具脚本行为和子节点要求。
3. 反射存储属性与信号，展开继承后的实际结果。
4. 创建最小节点和代表性子树，设置正确 `owner`，用 `PackedScene.pack()` 保存到 `user://godot-dev/experiments/`。
5. 重新加载 PackedScene、实例化、加入 SceneTree 两帧，再检查类型、属性、父子关系、组和连接。
6. 无法无参实例化、依赖编辑器上下文或要求特殊子节点的类型不得标为无条件 `direct_text`。
7. 把 Godot 生成的单节点最小场景记录为 `serialization.minimal_text`，把代表值的节点属性行写入 `serialization.property_text_examples`，生成单类型契约并验证。
8. 不查看实验样本，仅依据契约手写一个新的最小 `.tscn` 节点段；加载、实例化、进入 SceneTree 并核对稳定属性成功后，才标为 `validated`。这份最小文本是 Node 序列化证据，不是业务 Scene 契约。

## 调用

```text
godot --headless --path <project> --script <skill>/scripts/derive_node_contract.gd -- --type MyNode --source res://path/my_node.gd --scope project --output <contract.json>
```

Node 契约描述单节点类型，不描述具体业务场景。保存 Signal 的 `[connection]`、实例化及节点路径语法统一由场景编写规则处理。

反射发现 NodePath 属性后，必须把用途归入 `path_constraints`，例如目标节点、动画根、spawn_path 或同步 root_path。无法从类文档、源码或最小实验确定语义时保留未知约束，并要求复杂场景审计在严格模式下失败，而不是猜测有效路径。

需要父节点、World、导航图、骨骼、视口、编辑器或平台服务的类型必须写入 `context_requirements`。单节点序列化验证与上下文夹具是两个独立证据，详见 [runtime-contexts.md](runtime-contexts.md)。
