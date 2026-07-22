# 官方资料取证流程

## 优先级

1. 使用与项目主次版本一致的 `https://docs.godotengine.org/en/4.7/` 类参考、教程和文件格式说明。
2. 文档没有覆盖序列化细节时，查 Godot 官方仓库相同版本标签；文本资源解析以 `scene/resources/resource_format_text.cpp` 等实际实现为准。
3. 再使用目标 Godot 可执行文件的 `ClassDB`、对象属性列表、`PROPERTY_USAGE_STORAGE` 和最小保存实验。
4. 第三方类型还必须读取插件源码、`plugin.cfg`、版本声明及相关原生扩展 API。
5. 项目类型还必须读取脚本、基类、导出属性、setter、`_validate_property()` 和工具脚本行为。

不要用非官方教程覆盖官方资料。官方文档未写明不代表可以猜测；生成最小、代表值和嵌套值样本，由 Godot 自己保存并重新加载。

## 记录证据

契约 `evidence` 按实际使用记录：

- `official_docs`：精确到 4.7 页面 URL。
- `official_source`：仓库路径和版本标签或提交。
- `reflection`：Godot 完整版本、ClassDB 类型和反射入口。
- `experiments`：样本类型、保存格式、加载结果和比较范围。

没有保存/加载实验的契约只能是 `cataloged`，不能标为 `validated`。
