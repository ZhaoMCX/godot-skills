# 复杂场景验证

## 读写单位

复杂场景不是一次性整文件重写对象。先读取场景头、ExtResource/SubResource、节点、连接与 editable 段，再按稳定 ID 和 NodePath 修改最小区块。写入前先计算目标场景的依赖与反向依赖；共享子场景或 Resource 的修改必须扩大到受影响闭包。

## 场景组合规则

- 继承场景的根节点通过 `instance=ExtResource(...)` 指向基场景，只保存覆盖值与新增节点。
- PackedScene 实例同样使用 `instance=ExtResource(...)`；实例内部可编辑路径使用 `[editable path="..."]`。
- 保存节点必须具有正确 owner；运行时临时节点不因父子关系自动进入 PackedScene。
- `[connection]` 必须解析源节点、目标节点、信号与方法，并在实例化后验证持久连接存在。
- `unique_name_in_owner` 在同一 owner 范围内不得重复。
- NodePath 必须按节点契约中的 `path_constraints` 分类并解析；严格模式禁止依靠猜测跳过未知路径语义。
- `resource_local_to_scene = true` 的 Resource 必须用两个独立场景实例验证不共享状态。

## 验证时机

1. 每次完成一个可加载单元后，运行 `validate_assets.gd`，尽早发现语法和引用错误。
2. 修改共享资源、继承基场景、实例场景或脚本路径后，运行 `collect_dependencies.gd`，得到完整受影响闭包。
3. 完成场景组合后，对闭包内场景运行 `audit_scene.gd --strict`。
4. 完成功能后运行对应业务测试、统一验证报告和主场景；需要视觉结果时使用非 Headless 截图。

## 审计边界

静态扫描能证明显式 `res://`、UID、ExtResource、场景继承和实例关系。运行时字符串拼接路径、网络内容、用户存档、EditorPlugin 动态行为和业务生成树必须由专项测试覆盖，并在依赖报告中保留未证明警告。
