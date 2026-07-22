# 运行时上下文节点

节点契约只证明单节点的可存储属性和最小文本，不自动证明它在业务上下文中可工作。下列类型必须构造最小上下文夹具，并同时保留契约的 `context_requirements`。

## 骨骼与动画

- Bone2D：置于 Skeleton2D 层级，设置非退化 rest，验证层级和变换传播。
- AnimationPlayer：提供 AnimationLibrary、动画与有效轨道根路径，推进时间并核对目标属性。
- AnimationTree：绑定 AnimationPlayer，设置 tree_root、激活状态与参数，推进后核对状态和轨道效果。

## 导航

- NavigationRegion2D/3D：提供可用导航数据和所属 World。
- NavigationAgent2D/3D：进入 SceneTree，等待导航同步，再验证路径请求；只设置 target_position 不足以证明可导航。

## 视口与相机

- SubViewport：设置有效尺寸和更新模式，挂接 Camera2D/Camera3D 与可渲染内容。
- ViewportTexture 或消费材质：验证纹理能被实际消费者读取；Headless 只做结构验证。

## TileMap

- TileMapLayer：绑定 TileSet、有效图块源和单元格；空 TileSet 只证明引用语法。
- 导入纹理必须先完成编辑器扫描，并验证 TileSet 实际引用的导入资源。

## 多人同步

- MultiplayerSpawner：配置 spawn_path 与可生成场景，使用最小 MultiplayerAPI 上下文验证生成路径。
- MultiplayerSynchronizer：设置 root_path 与 SceneReplicationConfig；需要对端语义时使用本地双 peer 或专项集成测试。

## 编辑器与平台上下文

EditorPlugin、EditorInspectorPlugin、OpenXR、原生扩展和平台服务不能在普通 Headless SceneTree 中完整证明。契约应保持 `reference_only` 或声明上下文要求；真正验收必须在相应编辑器、XR runtime、原生库或目标平台环境中执行，缺少环境时标为 `blocked`。
