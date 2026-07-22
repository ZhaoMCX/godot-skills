# Godot 文本资源格式

> 本页描述文件级语法；复杂组合与验证时机见 [scene-validation.md](scene-validation.md)。

## 通用规则

- Godot 4 的 `.tres` 与 `.tscn` 使用 `format=3`；头部必须先出现。
- `.tres` 头为 `[gd_resource type="Type" ...]`，主体资源属性位于 `[resource]`。
- `.tscn` 头为 `[gd_scene ...]`，依次包含外部资源、子资源、节点和连接。
- `ExtResource` 引用磁盘资源，`SubResource` 引用同文件内资源。ID 只在当前文件内解析；不要随意重编号。
- 外部资源优先同时保留 Godot 已生成的 `uid` 与 `path`。没有可靠 UID 时使用路径，让 Godot 导入后补齐。
- Variant 文本写法以 Godot 保存的最小实验为准，尤其是 TypedArray、Dictionary、RID、Callable、PackedArray、Mesh、Animation 和曲线数据。
- 等于默认值的属性通常不会保存，Godot 再保存时可能删除手写默认值。

## 二进制边界

- `.res`、`.scn` 和 `.godot/imported/` 中的内容不能直接文本编写。
- 用 `ResourceSaver`、`PackedScene.pack()` 或导入器生成二进制资源。
- 文本资源可以通过 `ExtResource` 引用二进制资源；校验引用能被 `ResourceLoader` 加载即可。

## 自定义 Resource

- `[gd_resource]` 的基础 `type` 必须与脚本实例基础类型兼容。
- 自定义脚本通过外部资源声明，并在 `[resource]` 设置 `script = ExtResource("id")`。
- 只保存带 `PROPERTY_USAGE_STORAGE` 的属性。导出属性的类型、默认值和资源约束由脚本及契约共同决定。
- 脚本内嵌类不是可靠的独立 Resource 序列化入口；使用可加载的脚本文件和稳定全局类。

## AnimationTree 家族

- `AnimationTree` 是保存在 `.tscn` 的 Node；`tree_root` 引用 `AnimationNodeStateMachine`、`AnimationNodeBlendTree` 或 BlendSpace 等 Resource。
- 状态机节点使用 `states/<name>/node` 与 `states/<name>/position`；`transitions` 是重复的 `from`、`to`、Transition 子资源三元组。
- BlendTree 节点使用 `nodes/<name>/node` 与 `nodes/<name>/position`；`node_connections` 按目标节点、输入端口、来源节点记录。
- BlendSpace 点使用 `blend_point_<index>/node`、`pos` 和 `name`。显式名称可避免 Godot 4.7 的空名称弃用警告。
- `AnimationNodeBlendSpace2D` 的 `triangles` 必须位于所有 `blend_point_*` 行之后。Godot 4.7.1 的 `ResourceSaver` 可能输出相反顺序，重载前必须规范；以 `tests/fixture_project/animation_tree_blend_space_2d.tres` 为已验证样本。
- 结构加载不足以证明正确；还要装配 `AnimationPlayer`/`AnimationLibrary`，取得 `parameters/playback`，验证状态切换并用手动处理模式调用 `advance()` 核对轨道实际生效。

## 继承、实例与局部资源

- 继承场景与普通 PackedScene 实例都由节点的 `instance=ExtResource("id")` 表达；继承场景只保存覆盖值和新增节点，不复制基场景全文。
- 实例内部允许编辑的节点路径使用独立的 `[editable path="Instance/Child"]` 段；路径必须在实例化后解析。
- 保存节点依靠 `owner` 归属进入 PackedScene；仅调用 `add_child()` 不会自动保存该节点。
- `resource_local_to_scene = true` 影响实例化复制语义，不能仅从文本存在性判断；必须创建两个场景实例并验证资源对象与可变状态互相独立。
- ExtResource/SubResource ID 是文件内稳定引用标识。局部修改时保留未触及 ID，避免制造无意义差异和断开嵌套引用。
