# 十三水 — 最小源代码包

福建十三水游戏：Flutter UI + C++ 引擎 + ONNX AI。

## 目录结构

```
flutter/
├── lib/                          # Dart 源代码（40 个文件）
│   ├── main.dart                 # 入口
│   └── src/
│       ├── app/                  # App 壳、游戏模块
│       ├── backend/              # 设置、存储、ONNX、FFI
│       ├── games/thirteen/       # 游戏页面、AI、控制器
│       ├── i18n/                 # 字符串
│       ├── models/               # 数据模型
│       ├── theme/                # 主题
│       └── widgets/              # 通用组件
├── android/                      # Android 构建
├── windows/                      # Windows 构建
├── assets/
│   ├── models/thirteen_ranker.onnx
│   └── sounds/
├── cpp/                          # C++ 引擎（链接：../cpp/）
├── test/                         # 测试
└── tool/                         # ONNX 推理子进程
```

外部源码：`../cpp/`（C++ 引擎）、`../python/`（训练代码）。

## 编译

### 前置条件

| 工具 | 用途 |
|------|------|
| Flutter 3.4+ | Dart / UI |
| Android SDK 35 + NDK 27 | Android APK |
| Visual Studio 2022 (MSVC) | Windows 桌面版 |

### Windows 桌面版

```bash
flutter build windows --release
```

### Android APK

```bash
flutter build apk --release
```

### 运行测试

```bash
CARDS_ROOT=.. flutter test
```

## 预编译的二进制文件

`android/app/src/main/jniLibs/arm64-v8a/` 中包含：

| 文件 | 大小 | 来源 |
|------|------|------|
| `libthirteen_cards_cpp.so` | 413KB | CMake 自动编译 |
| `libonnx_thirteen.so` | 16KB | NDK 预编译 |
| `libonnxruntime.so` | 27MB | Maven AAR 提取 |

如需从源码重新编译 Android .so，参见 `cpp/CMakeLists.txt`。
