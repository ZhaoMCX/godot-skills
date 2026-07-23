# Godot Skills

面向 Codex 与兼容 Agent 工作流的两个独立 Godot 技能。每个技能都可以单独安装、单独升级，不依赖本仓库中的其他技能。

| 技能 | 用途 | 运行要求 |
| --- | --- | --- |
| `godot-framework` | 设计、实现、审查和测试 `addons/godot_framework` 的八类最小运行时契约 | Python 3、Godot 4.7.1 |
| `godot-change-tree` | 用严格对齐的文件树与 Godot 场景/节点树表达真实结构变化 | 无额外依赖 |

## 安装

全局安装时，分别选择需要的技能：

```powershell
python "$env:CODEX_HOME\skills\.system\skill-installer\scripts\install-skill-from-github.py" --repo ZhaoMCX/godot-skills --path godot-framework
python "$env:CODEX_HOME\skills\.system\skill-installer\scripts\install-skill-from-github.py" --repo ZhaoMCX/godot-skills --path godot-change-tree
```

项目级使用可以把仓库挂载到项目的技能目录：

```powershell
git submodule add -b main https://github.com/ZhaoMCX/godot-skills.git .agents/skills
git submodule update --init --recursive
```

克隆包含该子模块的消费项目时，使用 `git clone --recurse-submodules`，或者克隆后执行上面的 `submodule update` 命令。

## 版本

两个技能独立发布标签，格式分别为：

- `godot-framework-vX.Y.Z`
- `godot-change-tree-vX.Y.Z`

子模块默认跟随经 CI 验证的具体提交；需要升级时，在消费项目中更新子模块指针并单独提交。

## 验证

仓库级快速检查：

```powershell
python scripts/validate_skills.py
python godot-framework/scripts/test_audit_framework.py
```

`godot-framework` 的契约测试是自包含的 Godot CLI 测试，不要求 GUT；消费项目自己的测试框架不受限制。

## 许可

[MIT](LICENSE)
