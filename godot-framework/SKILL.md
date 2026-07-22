---
name: godot-framework
description: "使用 addons/godot_framework 的八类最小运行时契约设计、实现、审查、测试和迁移 Godot 4.7 GDScript。用于维护 GFGame、GFSystem、GFModel、GFEntity、GFView、GFAction、GFEvent、GFConfig，检查框架独立性与生命周期，设计 Action/Event 数据流，补齐邻近契约注释，以及验证插件或消费项目的框架接入。"
---

# Godot Framework

## 完成门槛

先满足以下硬性条件，再报告任务完成：

1. 保持 `addons/godot_framework` 独立：`core/` 与 `tests/` 只依赖 Godot 内置能力和插件自身 GF 类型；运行时内容的 `res://` 引用只能留在插件目录。
2. 为插件自有 GDScript 的类、成员字段、常量、方法、信号、枚举及每个枚举值提供邻近 `##` 契约注释。
3. 保持 GF 八类的公共签名、状态权威和生命周期语义；需要破坏兼容时先明确影响。
4. 运行静态审计、契约测试和 Godot 验证；按作用域 `AGENTS.md` 完成编辑器同步。

插件源码、注释和文档不得出现消费项目的类型、场景、AutoLoad、目录或业务术语。不要把第三方插件、项目领域对象或假想复用能力塞入框架核心。

## 固定工作流

1. 读取作用域内 `AGENTS.md`、实际 GF 基类、相关测试与真实入口；不要从目录名或 Markdown 猜测运行时结构。
2. 涉及文件、场景或运行时节点结构变化时，遵循消费项目的结构表达与验收规则；本技能只约束 GF 所有权和生命周期语义。
3. 先检查依赖边界、公共接口、状态权威、创建者、持有者、挂载点、启动顺序、失败回滚与释放责任。
4. 先写或更新契约注释，再实现行为；注释和 typed 声明必须共同表达完整契约。
5. 对消费项目的新功能，先建立独立 Action/Event、Model/Config 与契约检查，再实现 System、Entity 或 View 行为。
6. 运行 `scripts/audit_framework.py`、契约测试和受影响测试。
7. 使用 Godot 4.7 CLI 完成编辑器扫描和受影响测试，再按 `AGENTS.md` 重启编辑器、检查新日志并保持编辑器 Ready。

## 八类最小契约

| 元素 | 职责 | 不得越界 |
| --- | --- | --- |
| `GFGame` | 入口组合根，按显式顺序启停 System | 不扫描目录，不建立隐式服务，不接管其他对象生命周期 |
| `GFSystem` | 跨对象规则、运行时事实改变与外部副作用权威 | 独占 Model；只在 RUNNING 通过专属方法接收 Action、通过专属 Signal 发布 Event |
| `GFModel` | 场景保存、可共享读取的已成立运行时事实 Node | 必须是所属权威直属子节点；不接收 Action，不决定自身变化，不调用 System |
| `GFEntity` | 单个运行时对象的局部事实、不变量与生命周期 | 配置后挂载；只在 ACTIVE 通过专属方法接收 Action；不查找全局服务，不拥有具体 View |
| `GFView` | 输入、表现和临时显示状态 | 不写运行时事实，不查找接收者，只调用显式权威的 typed Action 方法 |
| `GFAction` | 尚未成立、交给权威判断的改变意图 | 只携带 typed 输入，不执行规则，不宣称结果 |
| `GFEvent` | 权威已提交并确认成立的事实快照 | 不回写状态，不隐藏命令，不在读取时触发请求 |
| `GFConfig` | Inspector 可保存、复用和替换的设计期配置 | 不保存运行时事实；在启动或激活前验证 |

保持请求与事实单向流动：

```text
GFView -- GFAction --> GFEntity / GFSystem
GFEntity / GFSystem -- GFEvent --> GFView
GFView / GFSystem / 组合方 -- read --> GFModel
```

每个具体 Action 类型只有一个接收权威和一个 public typed 方法；方法参数必须是该具体 Action。普通方法的 `bool` 只表示“请求是否被接收”，不是领域操作已经完成；System 仅在 `RUNNING`、Entity 仅在 `ACTIVE` 接收。能够同步创建跟踪对象的异步操作可以返回 `ConcreteHandle/null`，但 Action 保持纯输入，不得回填结果。

每个具体 Event 类型只有一个发布权威和一个 public typed Signal；权威必须先提交 Model，再发出携带该具体 Event 的 Signal。稍后才成立的结果通过专属 Signal 发布，异步回调发布前还必须重新检查权威生命周期，不直接返回 Event。

依赖通过 typed `@export` 或 `configure()` 注入。Model 是所属 System/Entity 的场景直属子节点；其他对象可以注入 Model 并读取 getter-only 事实，但只有所属权威可以调用 `_commit_*`。跨 Entity 规则由 System 协调；跨领域 Event→Action 映射由持有两端依赖的明确组合方完成，不建立中心路由或全局事件总线。

## 通信规范

### 专属接口与命名

- 一个具体 Action 只有一个接收权威和一个 public typed 方法；禁止同一 Action 被多个 System/Entity 接收，也禁止按基类或运行时类型集中分派。
- Action 方法名从类型名机械生成：去掉接收权威前缀和 `Action` 后缀，再转为 `snake_case`。例如 `CapabilityRefreshAction` 只能进入 `CapabilitySystem.refresh(action: CapabilityRefreshAction)`。
- 一个具体 Event 只有一个发布权威和一个 public typed Signal；禁止多个权威发布同一 Event，也禁止通过通用 Signal 再按类型分流。
- Event Signal 名从类型名机械生成：去掉发布权威前缀和 `Event` 后缀，再转为 `snake_case`。例如 `CapabilityContentChangedEvent` 只能由 `CapabilitySystem.content_changed(event: CapabilityContentChangedEvent)` 发布。
- Action/Event 文件的邻近 `##` 注释必须分别写出唯一方法或唯一 Signal；typed 声明与注释不一致视为契约错误。

### 通信矩阵

| 方向 | 允许方式 | 禁止方式 |
| --- | --- | --- |
| View → System/Entity | 持有 typed 引用并调用专属 Action 方法 | 查找接收者、通用提交方法、字符串路由 |
| System/Entity → View | 专属 typed Signal 携带具体 Event；View 从 typed Model 读取公开快照 | 引用具体 View、直接修改表现、通用 Event Signal、System 事实转发 getter |
| System → Entity | System 持有或获注入 typed Entity 引用后协调跨对象规则 | 扫描 SceneTree、节点组或全局注册表查找 Entity |
| Entity → System | 默认不建立反向领域依赖；确有局部请求时显式注入 typed System，或交给组合方映射 | Entity 查找全局 System、隐藏 Service Locator |
| Entity → Entity | 由 System 持有两端引用并协调 | Entity 互相搜索、跨聚合直接改写事实 |
| System → System | 默认由组合方映射 Event→Action；只读事实依赖直接注入来源 Model | System 互相发现、读取对方私有字段、调用外部 Model `_commit_*`、中心事件总线 |

组合方通常是 `GFGame` 派生组合根，也可以是职责明确、持有两端 typed 依赖且具有相同生命周期范围的专用协调对象。映射回调只负责翻译 Event→Action，不取得两端 Model 的写权限。

### Model 持有、读取与写入

- 每个具体 Model 是所属 System/Entity 的场景直属子节点，由场景保存设计归属；权威通过 typed `@export` 返回同一实例。
- View、其他 System 和组合方可以持有 typed Model 引用并直接读取公开属性；不要在 System 上复制一套事实 getter。
- Model 的公开属性必须是 getter-only；数组与字典 getter 返回副本，集合中的领域值对象也必须是不可回写快照。
- `_commit_*` 只接收权威已经验证并确认的结果或完整快照，不接收 Action，也不执行领域判断或外部副作用。
- 只有 Model 的父级 System/Entity 可以调用 `_commit_*`。Action 是写入前置条件之一，但写入权仍属于接收 Action 并执行规则的权威，不转移给 Action 或调用方。
- 状态事实的 Event 必须在 `_commit_*` 后发布；纯瞬时事实可以只发 Event，但不得伪造长期可读状态。

### View 订阅时序

- View 激活时先连接本次活动期需要的全部专属 Signal，再读取权威的当前公开快照并渲染，避免连接与读取之间丢失事实。
- View 停用时对称断开由本次激活建立的全部连接；停用后的 View 不处理领域 Event。
- 激活过程中任一步失败，必须断开本次已经建立的连接并恢复未激活状态；不得把部分订阅泄漏到下一次激活。
- Signal 回调参数必须是具体 Event 类型；禁止一个通用回调接收 `GFEvent` 后再按类型分流。
- 只有调用方与权威共享完整生命周期且连接所有权无需切换时，才允许在 `_ready()` 建立固定连接；必须在邻近注释中说明该例外。

### Signal、Event 与 Handle

- Signal 是发布通道，Event 是该通道携带的不可回写事实快照；两者不是可互换概念。
- Event 发布前必须先提交 Model。订阅者收到 Event 后可以更新表现或由组合方创建下一项 Action，但 Event 自身不得隐藏命令。
- Handle 是单次异步操作的 typed 跟踪对象。权威能够同步创建跟踪对象时可返回 `ConcreteHandle/null`；Handle 用自己的 typed Signal 表达进度、完成和单次结果。
- Handle 不替代领域 Event：操作级进度与单次结果属于 Handle，权威长期成立并可被多个观察者消费的事实仍进入 Model，并由专属 Event Signal 发布。
- Action 不持有由接收者回填的 Handle、Event 或结果字段；拒绝请求时不得留下部分跟踪对象或发布 Event。

### 八项原则检查

通信设计或审查必须同时确认：接口和连接能从真实入口验证；依赖由 Scene/Inspector/typed 代码表达；创建、持有、连接和断开责任可追踪；没有为假想复用增加路由层；类型与邻近注释共同表达契约；公共命名和生命周期语义稳定；测试覆盖真实消费入口与拒绝路径；结构变化满足消费项目的可核验表达要求。

## 插件基础类型与具体元素

插件只定义八个抽象基础类型，不收纳消费项目的具体 Action、Event、Model、System、Entity、View 或 Config。

消费项目中的每种具体 Action/Event 使用独立 GDScript 和唯一顶层 `class_name`，分别放在所属能力附近的 `actions/`、`events/`，文件名以 `_action.gd`、`_event.gd` 结尾。禁止使用 `<domain>_contracts.gd`、内部类或集中仓库隐藏具体请求与事实。此文件组织规则不构成框架运行时扫描协议。

消费项目的 GF 派生类型必须用角色后缀直接暴露契约：`XxxGame`/`xxx_game.gd`、`XxxSystem`/`xxx_system.gd`、`XxxModel`/`xxx_model.gd`、`XxxEntity`/`xxx_entity.gd`、`XxxView`/`xxx_view.gd`、`XxxAction`/`xxx_action.gd`、`XxxEvent`/`xxx_event.gd`、`XxxConfig`/`xxx_config.gd`。间接继承也遵守同一规则；领域形态名称不能替代 GF 角色后缀。具体目录由消费项目的 `AGENTS.md` 决定，插件不得假设模块名称或项目层级。

### 外部 Resource 文件命名

消费项目自有的 `.tres` 与 `.res` 使用相同结构：`<业务名称 snake_case>.<最具体资源类型 snake_case>.<tres|res>`。例如 `ball_01.sphere_shape_3d.tres`、`ball_01.sphere_shape_3d.res`、`workshop.workshop_config.tres`。

- 业务名称必须是非空 `snake_case`，可以包含数字；文件名只能包含业务段、类型段和扩展名三个点分段。
- 资源绑定具有全局 `class_name` 的脚本时，类型段使用该脚本类型；否则使用 Godot 原生类型。无全局名称的自定义脚本回退到原生基类。
- 类型名机械转换为 `snake_case`，保留 `2D`/`3D` 维度后缀并正确处理连续大写缩写：`SphereShape3D` → `sphere_shape_3d`，`HTTPRequest` → `http_request`。
- 规则只约束消费项目自有 `.tres` 与 `.res`；不扩展到其他资产类型，也不用于改写第三方 `addons/`。
- `.res` 是二进制格式，不得依赖文本解析猜测类型；命名审计必须通过 Godot `ResourceLoader` 加载资源，并与 `.tres` 使用同一类型解析契约。

### Resource 格式与扩展名

- `.tres` 是通用文本 Resource 格式，`.res` 是通用二进制 Resource 格式；所有可序列化的 Godot 原生 `Resource` 派生类型以及 GDScript 自定义 `Resource` 都可以使用这两种格式。自定义资源的脚本必须能够通过保存的脚本引用加载；具有全局 `class_name` 时，文件名类型段仍使用该最具体脚本类型。
- `.mesh`、`.material`、`.tscn`、`.scn` 等是具有明确资源语义或加载器约束的专用扩展名，不支持任意 `Resource`。例如 `ArrayMesh` 可以使用 `.mesh`，自定义 `GFConfig` 派生资源不能仅通过改名变成 `.mesh`；`PackedScene` 使用 `.tscn` 或 `.scn`。
- 扩展名既是文件名的一部分，也是 Godot 选择 `ResourceFormatLoader`、`ResourceFormatSaver` 和序列化格式的依据。判断资源真实类型必须加载资源并读取其运行时类型，不能只看扩展名；同为 `ArrayMesh` 的供应商文件可能分别使用通用 `.res` 与专用 `.mesh`，但消费项目自有资源应优先使用与真实类型匹配的专用扩展名。
- 只有源格式与目标扩展名由同一资源格式加载器兼容，且真实资源类型满足目标扩展名约束时，才允许把扩展名作为路径重命名处理；仍必须同步所有引用、UID/缓存、manifest 与测试。不得假定任意 `.res` 都能改为任意专用扩展名。
- `.tres` 与 `.res` 分别是文本和二进制序列化，二者互换必须通过 `ResourceLoader` 加载后由 `ResourceSaver` 重新保存，不能只修改扩展名。自定义新扩展名默认不受支持；只有实现并注册对应 `ResourceFormatLoader`/`ResourceFormatSaver` 后才能使用。

## 契约注释

让类型说明“如何连接”，让邻近 `##` 注释说明“为什么存在、谁负责、何时有效、失败后保持什么”。

- 类：职责、创建与持有者、生命周期、明确不负责的内容。
- 字段与常量：业务或契约含义、写入权威、有效期、单位或范围（如适用）。
- 方法：意图、前置条件、状态变化、副作用、返回与失败语义、重复调用语义（如适用）。
- Signal/RPC：发布权威、触发时机、方向、可靠性与订阅者应如何解释。
- Enum：状态机整体含义；每个值分别说明进入条件和后续约束。
- Action：改变意图、唯一接收权威及专属 typed 方法、负载语义与拒绝条件。
- Event：已成立事实、唯一发布权威及专属 typed Signal、触发时机与快照语义。
- 测试：业务场景、初始状态和所证明的不变量；局部变量无需机械补注释。

使用消费代码既有的文档语言。拒绝逐句翻译代码、只复述类型名、TODO、占位语句或只在类头写一段泛化说明。

## 依赖与生命周期

- 对编辑期已知且稳定的 Node/Resource 依赖首选 typed `@export` 并在 Inspector 保存绑定。
- 对动态对象使用 typed 参数或 `configure()`，在 `add_child()` 前完成注入。
- 只对单个场景内部私有子节点使用 `@onready`、UniqueName 或固定 NodePath。
- `GFGame` 只回滚已成功启动的 System，并按相反顺序停止。
- `GFSystem`/`GFEntity` 通过 `_get_model()` 返回场景保存的唯一直属 Model；Model 不随启动/停止临时创建或销毁。
- 所属 System/Entity 在 Action、外部 callback 或生命周期结果通过校验后调用具体 `_commit_*`；静态审计必须拒绝 View、组合根和其他领域 System 写入该 Model。
- `GFEntity` 的创建、配置、挂载、激活、停用和释放责任必须可追踪。
- `GFView` 按“连接 Signal → 读取快照”激活，并在停用或激活失败时对称清理本次连接。
- 不用祖先搜索、节点组、字符串服务名、AutoLoad 或 Service Locator 补齐未声明依赖。

## 静态审计

修改插件后运行：

```powershell
python <godot-framework 技能目录>/scripts/audit_framework.py addons/godot_framework --resource-prefix res://addons/godot_framework/ --test-root tests
```

审计器检查插件资源引用、分层外部类型依赖、脚本类契约注释、顶层成员声明和枚举值。测试目录声明的类型只对测试有效，不得满足 `core/` 的运行时依赖。技能目录从当前 `SKILL.md` 的真实位置解析，不假定安装在消费项目目录内。发现问题时必须逐项修复；不要用排除规则隐藏插件自有代码。自动检查不能判断全部语义，仍需人工确认 README 与注释只使用 Godot/GF 通用概念。

## 验证

至少完成：

1. 运行审计器自身测试与技能结构校验。
2. 用 Godot Headless 直接执行 `addons/godot_framework/tests/test_framework_contracts.gd`，确认八类生命周期、失败回滚、专属 Action 方法拒绝语义、错误 Action 的 typed 编译拒绝、旧通用接口消失与专属 typed Signal 的 Event 发布时间；测试运行器不得依赖第三方测试插件。
3. 执行 Godot 4.7 脚本解析和受影响的 Headless 测试。
4. 通过 Godot 4.7 CLI 扫描磁盘改动，按 `AGENTS.md` 重启编辑器并检查 Output、Debugger、插件状态、编辑器日志和游戏日志。
5. 停止验证运行并保持编辑器 Ready；明确报告已验证项、未验证项和非本次引入的问题。
