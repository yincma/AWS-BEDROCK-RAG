# AWS Bedrock RAG 系统文档中心

欢迎来到 AWS Bedrock RAG 系统的文档中心。本目录包含了系统的所有技术文档、指南和参考资料。

## 📚 文档目录

### 🏗️ 架构和设计
- [**系统架构指南**](./ARCHITECTURE_GUIDE.md) - 详细的系统架构说明、组件介绍和技术决策
- [**代码架构图**](./CODE_ARCHITECTURE.md) - 代码结构和模块关系的可视化说明
- [**AI 规则**](./ai-rules/) - AI 辅助开发的规则和指南
  - [产品规则](./ai-rules/product.md)
  - [技术规则](./ai-rules/tech.md)
  - [结构规则](./ai-rules/structure.md)

### 🚀 部署和运维
- [**部署指南**](./DEPLOYMENT_GUIDE.md) - 完整的部署流程、环境配置和最佳实践
- [**Terraform 指南**](./terraform/TERRAFORM_GUIDE.md) - 基础设施即代码的详细说明
- [**故障排查指南**](./TROUBLESHOOTING_GUIDE.md) - 常见问题解决方案和调试技巧
- [**清理指南**](./CLEANUP_GUIDE.md) - 资源清理和环境重置说明
- [**资源检测指南**](./RESOURCE_DETECTION_GUIDE.md) - AWS 资源识别和管理

### 🧪 测试和质量
- [**测试指南**](./test/TEST_GUIDE.md) - 测试策略、框架使用和最佳实践

### 📋 策略和规范
- [**策略指南**](./policies/POLICIES_GUIDE.md) - 成本、性能和安全策略的综合指南

## 🎯 快速开始

### 新用户入门
1. 阅读[系统架构指南](./ARCHITECTURE_GUIDE.md)了解整体设计
2. 按照[部署指南](./DEPLOYMENT_GUIDE.md)完成首次部署
3. 参考[故障排查指南](./TROUBLESHOOTING_GUIDE.md)解决常见问题

### 开发者指南
1. 查看[代码架构图](./CODE_ARCHITECTURE.md)理解代码结构
2. 遵循[AI 规则](./ai-rules/)进行开发
3. 使用[测试指南](./test/TEST_GUIDE.md)确保代码质量

### 运维人员指南
1. 掌握[Terraform 指南](./terraform/TERRAFORM_GUIDE.md)管理基础设施
2. 熟悉[故障排查指南](./TROUBLESHOOTING_GUIDE.md)快速定位问题
3. 遵循[策略指南](./policies/POLICIES_GUIDE.md)优化系统运行

## 📖 文档规范

### 文档更新流程
1. 所有文档修改需要通过 Pull Request
2. 重大变更需要团队 Review
3. 保持文档与代码同步更新

### 文档格式要求
- 使用 Markdown 格式
- 包含清晰的目录结构
- 提供实际的代码示例
- 标注版本和更新日期

### 文档命名规范
- 使用大写字母和下划线
- 以 `_GUIDE.md` 结尾的为指南类文档
- 以 `_README.md` 结尾的为说明类文档

## 🔄 最近更新

| 文档 | 更新日期 | 主要变更 |
|------|---------|---------|
| 部署指南 | 2025-07-28 | 整合多个部署相关文档 |
| 故障排查指南 | 2025-07-28 | 合并故障排查内容 |
| Terraform 指南 | 2025-07-28 | 统一基础设施文档 |
| 测试指南 | 2025-07-28 | 整合测试相关文档 |
| 策略指南 | 2025-07-28 | 合并成本、性能、安全策略 |

## 🤝 贡献指南

欢迎对文档进行贡献！请遵循以下步骤：

1. Fork 项目仓库
2. 创建特性分支 (`git checkout -b docs/your-feature`)
3. 提交更改 (`git commit -m 'docs: 添加某某说明'`)
4. 推送到分支 (`git push origin docs/your-feature`)
5. 创建 Pull Request

## 📞 联系方式

- **技术支持**: support@example.com
- **文档反馈**: docs@example.com
- **紧急联系**: ops-team@example.com

## 📄 许可证

本文档遵循项目的开源许可证。详见项目根目录的 LICENSE 文件。

---

**文档版本**: v2.0  
**最后更新**: 2025-07-28  
**维护团队**: Documentation Team