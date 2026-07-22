# 契约存放与选择

每个 Node 或 Resource 类型使用一个独立 JSON 文件；清单只保存索引、版本、哈希和依赖，不内嵌完整契约。场景是契约组合后的产物，不创建 Scene 契约。

契约格式使用 `contract_version=2`。`engine_version` 与 `engine_build_hash` 必须和运行中的 Godot 完全一致；补丁版本或构建哈希变化即失效。`base_contract_hashes` 保存直接基类契约哈希，基类变化会使派生契约失效。

## 内置契约

随技能保存，按精确 Godot 主次版本隔离：

```text
<skill>/references/contracts/godot-4.7/
├── manifest.json
├── nodes/<type>.node-contract.json
└── resources/<type>.resource-contract.json
```

目录契约用于发现类型和选择上下文。没有单类型保存实验时只能是 `cataloged`，不能据此宣称可直接手写。

## 第三方契约

包作者提供的权威契约放在包自己的 `godot-dev/` 目录，避免与插件运行文件混杂：

```text
addons/<package>/godot-dev/<package-version>/
├── manifest.json
├── nodes/<source-mirror>.node-contract.json
└── resources/<source-mirror>.resource-contract.json
```

不要为了记录本项目的推导结果修改供应商目录。本项目推导的第三方契约覆盖层放在：

```text
docs/godot-dev/contracts/third-party/<package-id>/<package-version>/
├── nodes/<source-mirror>.node-contract.json
└── resources/<source-mirror>.resource-contract.json
```

第三方契约必须记录 `package_id`、`package_version`、源码哈希和 Godot 版本。版本或源码哈希变化即视为过期，不跨版本复用。

Node 的 `path_constraints` 区分保存树、运行时和外部上下文解析；Node/Resource 的 `context_requirements` 区分本地可构造与外部环境。外部上下文没有实际环境证据时保持 `reference_only`。

## 项目契约

项目自有类型放在：

```text
docs/godot-dev/contracts/project/
├── nodes/<source-mirror>.node-contract.json
└── resources/<source-mirror>.resource-contract.json
```

`docs/godot-dev/manifest.json` 统一索引项目契约和本地第三方覆盖层。文件名镜像源码相对路径；同一脚本包含多个可序列化类型时，在叶目录继续按类型名单独拆文件。

## 选择顺序

1. 源码哈希匹配的项目契约或本地第三方覆盖层。
2. 包内 `godot-dev/` 中包版本和源码哈希都匹配的契约。
3. 精确 Godot 4.7 版本的内置契约。
4. 没有有效契约时执行固定推导流程。

只加载清单和当前类型的契约。读取继承或嵌套类型时，再按 `base_contract_hashes` 或属性类型加载直接依赖。
