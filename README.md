# plan-maker-manager-flutter

「知轻」—— 卡路里 / 饮食记录应用的 **Flutter 客户端**（从 uni-app 版整体迁移，数据格式与交互 1:1 兼容）。

## 快速上手

```bash
flutter pub get
flutter run                 # 真机/模拟器调试
flutter build apk --release # 产物：build/app/outputs/flutter-apk/app-release.apk
flutter test                # 注意：需先清 HTTP(S)_PROXY 代理环境变量，否则 flutter_tester 握手失败
```

## 仓库结构

| 路径 | 说明 |
|---|---|
| 仓库根目录 | Flutter 工程本体（入口 `lib/main.dart`；包名 `com.colorh.jianfei_dazi`） |
| [spec/](spec/) | 设计与规格文档库：参见 [spec/00_文档目录与导航索引.md](spec/00_文档目录与导航索引.md)。包含《产品需求规格说明书》、《系统架构与技术设计》、《开发任务拆解与里程碑》、《测试用例与验收清单》、《无计划默认三餐与一键转计划设计》等按版本编排的全套中文规格方案 |

## 相关仓库

- **plan-maker-manager**：uni-app（H5 / App）版源码与 Android 离线打包工程（历史版本，功能已全部由本仓库承接）
- 本仓库为 Flutter 版独立私库，工程代码与规格文档同仓维护，改动需保持 spec 与代码同步
