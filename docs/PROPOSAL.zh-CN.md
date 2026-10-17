# WasmBudget 项目申报书

## 项目简介

WasmBudget 是用 MoonBit 编写的 Wasm 体积检查命令。它对比两次构建的 `.wasm` 文件，显示文件、章节和较大函数体的变化；也可设置总增长上限，超限时让 CI 失败。

## 解决的问题与实际意义

只看 Wasm 文件总大小，发现变大后仍不容易判断变化来自哪里。WasmBudget 在发布前比较基线与新产物，超出团队设定的上限就让 CI 失败，并列出章节和较大函数体的变化线索。这样团队能更早发现体积回退、在发布前处理；它是轻量检查工具，不替代完整分析器或验证器。

## 目标用户

维护浏览器、边缘计算或其他 WebAssembly 交付物的开发者，以及希望在 MoonBit 项目 CI 中加入产物体积门槛的团队。

## 核心功能

- 读取 Wasm 文件并统计标准章节、自定义章节和函数体的编码大小。
- 比较基线文件与候选文件，显示总大小、章节差异及较大的函数体变化。
- 接受最大增长字节数；超过门槛时返回失败状态，适用于 CI。
- 对截断文件、无效头部、越界章节长度和异常函数体边界返回错误。

## 技术实现与范围

核心扫描器用 MoonBit 实现，依据 WebAssembly 二进制模块格式检查版本头、章节边界及 code section 中的函数体长度。命令行文件读取使用 native 目标的轻量适配器。项目不执行或改写 Wasm，也不宣称是完整验证器。

## 与已有工具的区别

Wassail 可以报告章节大小，[wa-info/wa-diff](https://github.com/radekdoulik/wa-info) 可以查看并比较模块、函数大小，Twiggy 提供更深入的体积分析，[Starshine](https://github.com/jtenner/starshine-mb) 是更广的 MoonBit WebAssembly 工具包。WasmBudget 只聚焦发布 CI：设置总增长上限，超限即失败，同时给出章节和函数体变化线索。它不替代这些工具，代码也未复制它们的源码。

## MVP 与验收标准

当前 MVP 包含章节扫描、函数体大小统计、两文件差异、总增长门槛、边界错误处理和单元测试。验收以以下结果为准：

1. `moon check --target all` 与 `moon test --target all` 通过。
2. 能报告项目自身 release Wasm 文件的章节大小。
3. 两个相同文件比较结果为 0 增长；超出设置的门槛时命令返回失败状态。
4. README 提供无需额外文件的可运行示例，GitHub Actions 自动执行格式、检查、测试和 Wasm release 构建。

## 开源与后续价值

项目采用 Apache-2.0 许可证。它可以作为 MoonBit 项目接入 WebAssembly 发布流水线的基础，也可在后续版本中增加稳定符号映射、JSON 报告或更方便的 CI 集成；这些内容不计入当前已完成范围。

