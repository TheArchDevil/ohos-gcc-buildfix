# GCC for OpenHarmony (OHOS)

OpenHarmony 的 GCC 工具链构建脚本，支持交叉编译器和原生编译器的完整三阶段构建。

[![CI Build](https://github.com/sanchuanhehe/ohos-gcc/actions/workflows/build.yml/badge.svg)](https://github.com/sanchuanhehe/ohos-gcc/actions/workflows/build.yml)

## 项目简介

本项目提供完整的构建脚本，用于为 OpenHarmony (OHOS) 操作系统编译 GCC 工具链。支持：

- **Stage 1**: 交叉编译器（在 Linux 上运行，生成 OHOS 代码）
- **Stage 2**: 原生编译器（Canadian Cross，在 OHOS 上运行）
- **Stage 3**: 原生自举（在 OHOS 设备上重新编译自身）

### 主要特性

- ✅ GCC 15.2.0 + Binutils 2.43
- ✅ 多架构支持（AArch64、x86_64、ARM、RISC-V、MIPS）
- ✅ 使用 musl libc
- ✅ 默认启用安全特性（PIE、SSP）
- ✅ 支持 Canadian Cross 构建原生 OHOS 编译器
- ✅ 自动下载 NDK sysroot
- ✅ GitHub Actions CI/CD

## 快速开始

### 安装依赖

```bash
# Ubuntu/Debian
sudo apt-get install -y build-essential bison flex texinfo gawk zip unzip \
    libgmp-dev libmpfr-dev libmpc-dev zlib1g-dev wget git

# Fedora/RHEL
sudo dnf install -y gcc gcc-c++ bison flex texinfo gawk zip unzip \
    gmp-devel mpfr-devel libmpc-devel zlib-devel wget git
```

### Stage 1: 构建交叉编译器

```bash
# AArch64 交叉编译器（推荐）
./build.sh --target=aarch64-linux-ohos --prefix=./install all

# x86_64 交叉编译器
./build.sh --target=x86_64-linux-ohos --prefix=./install all
```

### Stage 2: 构建原生 OHOS 编译器（Canadian Cross）

```bash
# 需要先完成 Stage 1
./build.sh \
    --build=x86_64-linux-gnu \
    --host=aarch64-linux-ohos \
    --target=aarch64-linux-ohos \
    --stage1=./install \
    --prefix=./install-stage2 \
    all
```

### 测试工具链

```bash
# 测试交叉编译器
./test-toolchain.sh ./install aarch64-linux-ohos

# 简单测试
./install/bin/aarch64-linux-ohos-gcc --version
```

## 构建类型详解

### Stage 1: 交叉编译器

在 Linux 主机上运行，生成 OHOS 目标代码：

```
CBUILD = CHOST = x86_64-linux-gnu (构建机器)
CTARGET = aarch64-linux-ohos (目标平台)
```

```bash
./build.sh --target=aarch64-linux-ohos --prefix=/opt/ohos-gcc-stage1 all
```

### Stage 2: Canadian Cross（原生编译器）

使用 Stage 1 交叉编译器构建，生成在 OHOS 上运行的原生编译器：

```
CBUILD = x86_64-linux-gnu (构建机器)
CHOST = CTARGET = aarch64-linux-ohos (目标平台)
```

```bash
./build.sh \
    --build=x86_64-linux-gnu \
    --host=aarch64-linux-ohos \
    --target=aarch64-linux-ohos \
    --stage1=/opt/ohos-gcc-stage1 \
    --prefix=/opt/ohos-gcc-stage2 \
    all
```

### Stage 3: 原生自举

在 OHOS 设备上使用 Stage 2 编译器重新编译自身：

```
CBUILD = CHOST = CTARGET = aarch64-linux-ohos
```

```bash
# 在 OHOS 设备上运行
./build.sh \
    --build=aarch64-linux-ohos \
    --host=aarch64-linux-ohos \
    --target=aarch64-linux-ohos \
    --stage2=/opt/ohos-gcc-stage2 \
    --prefix=/opt/ohos-gcc \
    all
```

## 支持的目标架构

| 架构 | 目标三元组 | Stage 1 | Stage 2 | 说明 |
|------|-----------|:-------:|:-------:|------|
| AArch64 | `aarch64-linux-ohos` | ✅ | ✅ | ARM 64位（推荐） |
| x86_64 | `x86_64-linux-ohos` | ✅ | ✅ | Intel/AMD 64位 |
| ARM | `arm-linux-ohos` | ✅ | 🔄 | ARM 32位软浮点 |
| ARM HF | `armhf-linux-ohos` | ✅ | 🔄 | ARM 32位硬浮点 |
| RISC-V | `riscv64-linux-ohos` | ✅ | 🔄 | RISC-V 64位 |

## 命令参考

### 构建命令

```bash
./build.sh [选项] [命令]

命令:
  prepare_ndk      下载并设置 NDK sysroot
  prepare          准备所有源码（NDK + binutils + GCC）
  binutils         仅构建 binutils
  configure        配置 GCC
  build            编译 GCC
  install          安装 GCC
  all              完整构建流程（默认）
  clean            清理构建目录
```

### 选项

| 选项 | 说明 | 默认值 |
|------|------|--------|
| `--target=TARGET` | 目标三元组 | `aarch64-linux-ohos` |
| `--host=HOST` | 主机三元组 | 自动检测 |
| `--build=BUILD` | 构建机器三元组 | 自动检测 |
| `--prefix=PATH` | 安装路径 | `./install` |
| `--sysroot=PATH` | Sysroot 路径 | `ndk/sysroot/TARGET` |
| `--stage1=PATH` | Stage 1 安装路径（Stage 2 需要） | - |
| `--stage2=PATH` | Stage 2 安装路径（Stage 3 需要） | - |
| `--jobs=N` | 并行任务数 | `$(nproc)` |
| `--enable-languages=LIST` | 启用的语言 | `c,c++` |

## 项目结构

```
ohos-gcc/
├── build.sh                 # 主构建脚本
├── build-examples.sh        # 交互式示例脚本
├── test-toolchain.sh        # 工具链测试脚本
├── BUILD_OHOS.md           # 详细构建文档
├── CONTRIBUTING.md         # 贡献指南
├── gcc-patches/            # GCC 补丁
│   └── 0001-Add-OpenHarmony-OHOS-*.patch
├── binutils-patches/       # Binutils 补丁
├── gmp-patches/            # GMP 补丁（OHOS 支持）
├── mpfr-patches/           # MPFR 补丁
├── mpc-patches/            # MPC 补丁
├── isl-patches/            # ISL 补丁
├── gettext-patches/        # gettext 补丁
├── sysroot-patches/        # Sysroot 补丁
├── ndk/                    # NDK sysroot（自动下载）
├── gcc-15.2.0/             # GCC 源码（自动下载）
└── binutils-2.43/          # Binutils 源码（自动下载）
```

## 环境变量

| 变量 | 说明 |
|------|------|
| `CTARGET` | 目标三元组 |
| `CHOST` | 主机三元组 |
| `CBUILD` | 构建机器三元组 |
| `INSTALL_PREFIX` | 安装路径 |
| `STAGE1_PREFIX` | Stage 1 路径 |
| `STAGE2_PREFIX` | Stage 2 路径 |
| `SYSROOT` | Sysroot 路径 |
| `NDK_URL` | NDK 下载地址 |
| `JOBS` | 并行任务数 |

## 常见问题

### Q: Stage 2 构建失败，提示找不到编译器？

A: 确保：
1. Stage 1 已成功构建
2. `--stage1` 路径正确指向 Stage 1 安装目录
3. 如果重新构建，先清理目标目录：`rm -rf install-stage2 build-ohos build-binutils`

### Q: 构建需要多长时间？

| 配置 | Stage 1 | Stage 2 |
|------|---------|---------|
| 8 核 CPU | ~30-60 分钟 | ~45-90 分钟 |
| 16 核 CPU | ~15-30 分钟 | ~25-45 分钟 |

### Q: 如何使用编译好的工具链？

```bash
# Stage 1 交叉编译
export PATH=/opt/ohos-gcc-stage1/bin:$PATH
aarch64-linux-ohos-gcc -o hello hello.c

# 查看目标信息
aarch64-linux-ohos-gcc -v
```

### Q: 支持哪些语言？

默认支持 C 和 C++。可通过 `--enable-languages` 启用其他语言：
- `c,c++` (默认)
- `c,c++,fortran`
- `c,c++,go`

## CI/CD

本项目使用 GitHub Actions 进行持续集成：

- **Stage 1**: 为 aarch64 和 x86_64 构建交叉编译器
- **Stage 2**: 使用 Canadian Cross 构建原生编译器
- **Artifacts**: 构建产物可从 Actions 页面下载

## 贡献

欢迎贡献！请查看 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证

- GCC: GPL-3.0
- Binutils: GPL-3.0
- 本项目脚本: GPL-3.0

## 致谢

- [Alpine Linux](https://alpinelinux.org/) - 构建脚本参考
- [GCC Project](https://gcc.gnu.org/) - 编译器
- [OpenHarmony](https://www.openharmony.cn/) - 目标操作系统
- [musl libc](https://musl.libc.org/) - C 标准库

## 相关链接

- [OpenHarmony 官网](https://www.openharmony.cn/)
- [GCC 官方文档](https://gcc.gnu.org/onlinedocs/)
- [Binutils 文档](https://sourceware.org/binutils/docs/)

---

**注意**: 这是一个社区项目，与 OpenHarmony 官方无关。
