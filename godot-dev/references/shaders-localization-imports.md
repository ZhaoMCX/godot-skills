# Shader、本地化与导入

## Shader

- `.gdshader` 可直接编辑；`shader_type`、`render_mode` 和使用它的材质/节点必须一致。
- Shader 参数保存在 ShaderMaterial Resource 中；参数名、类型和默认值同时核对 Shader 与材质。
- 编辑器扫描后用 `ResourceLoader` 加载 Shader，只能证明解析和资源引用有效。
- 渲染正确性必须在非 Headless 的真实渲染场景中运行；可截图时再由模型或人工判断图像语义。

## 本地化

- `.po`、`.csv` 等源文件按标准文本格式编辑；Godot 生成的 Translation Resource 由导入器管理。
- 保持消息 ID、上下文、复数规则和源文件编码，不直接修改 `.godot/imported/`。
- 编辑器扫描后加载生成的 Translation，并用业务语言切换测试验证键、回退和格式化参数。

## 导入

- 编辑源资产及必要的 `.import` 配置，随后运行 Headless 编辑器扫描。
- `.godot/`、导入缓存和生成 UID 映射不是人工维护的业务文件。
- 扫描后由 `ResourceLoader` 加载源路径，证明导入器已产生可消费资源；再由实际消费场景验证类型和行为。
- 移动或删除源资产后，重新计算依赖闭包并验证所有 ExtResource、UID 和脚本路径；不得复制旧缓存掩盖失效引用。

## 渲染与导出状态

- Headless 解析通过不等于真实渲染通过；渲染步骤必须单独记录。
- 没有显示设备、GPU 能力或渲染驱动时，结果为 `blocked`，不是 `passed`。
- 未配置导出预设时结果为 `skipped`；配置了预设却导出失败时结果为 `failed`。
- 导出产物还需最小启动检查；若目标平台不在当前机器上运行，明确记录未执行的目标平台验收。
