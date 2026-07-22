# 场景编写规则

场景是编写结果，不建立 Scene 契约。生成 `.tscn` 时组合通用格式、涉及的 Node/Resource 契约和业务结构要求。

## 节点与所有权

- 第一个 `[node]` 是根节点；后续节点的 `parent` 是相对根节点路径。
- `owner` 决定运行时添加节点是否被 `PackedScene.pack()` 保存。以 Godot 生成的样本确认复杂所有权关系。
- 实例场景使用 `instance=ExtResource(...)`；不要复制实例内部节点来模拟实例化。
- `NodePath`、`parent`、`owner` 和 Signal 的 `from`/`to` 都必须在最终保存树中可解析。
- 节点组使用 Godot 保存出的 `groups` 数组格式。唯一名称必须在同一 owner 范围内唯一。

## 继承、实例与局部资源

- 继承场景以根节点 `instance=ExtResource(...)` 表达；覆盖既有节点和新增节点的索引、owner 关系必须先由同版本 Godot 保存样本确认。
- 实例子树只有在 Godot 保存出 `[editable path="..."]` 后才允许持久覆盖；不要凭文本猜测可编辑边界。
- 实例内部节点仍属于被实例场景的 owner；宿主场景新增节点不得伪装成实例内部原节点。
- `resource_local_to_scene=true` 的 Resource 必须用同一 PackedScene 的两个实例证明彼此独立。
- 复杂结构修改后运行 `audit_scene.gd --strict`；只通过 `PackedScene.instantiate()` 不足以证明路径和连接语义正确。

## 保存的 Signal

- 连接放在节点段之后的 `[connection signal="..." from="..." to="..." method="..."]`。
- 信号名和参数由 Node 契约或脚本声明确认；目标方法存在性由脚本解析和实例化测试确认。
- 延迟、单次、引用计数和持久连接的 flags 必须从 Godot 保存样本推导，不猜数值。

## 校验

加载为 `PackedScene`，实例化，加入 SceneTree 至少两帧，检查错误日志后释放。业务场景还必须运行对应测试；可加载不等于行为正确。
