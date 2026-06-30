#!/bin/bash

# Exit on any error
set -e

# 🛠️ جعل المسارات ديناميكية ومرنة لتعمل محلياً وسحابياً تلقائياً
KERNEL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLANG_DIR="${KERNEL_DIR}/clang-r530567"
OUT_DIR="${KERNEL_DIR}/out"
LOG_DIR="${KERNEL_DIR}/build_logs"

BUILD_LOG="${LOG_DIR}/build.log"
ERROR_LOG="${LOG_DIR}/error.log"

# Create log directory and clear previous logs
mkdir -p "${LOG_DIR}"
> "${BUILD_LOG}"
> "${ERROR_LOG}"

# Redirect stdout to tee into build.log, and stderr to tee into error.log
exec > >(tee -a "${BUILD_LOG}") 2> >(tee -a "${ERROR_LOG}" >&2)

# Verify clang directory exists
if [ ! -d "${CLANG_DIR}" ]; then
    echo "Error: Clang directory not found at ${CLANG_DIR}" >&2
    exit 1
fi

# Set architecture and subarchitecture for ARM64 (SM8550)
export ARCH=arm64
export SUBARCH=arm64

# Add the specific clang toolchain to the PATH
export PATH="${CLANG_DIR}/bin:${PATH}"

# Setup make arguments for LLVM
MAKE_ARGS=(
    "O=${OUT_DIR}"
    "ARCH=${ARCH}"
    "SUBARCH=${SUBARCH}"
    "LLVM=1"
    "LLVM_IAS=1"
    "LOCALVERSION=-VoltQ8"
    "LD=ld.lld"              # 🚀 إجبار المترجم على استخدام رابط جوجل السريع المتوافق مع Clang 19
    "KBUILD_BUILD_VERSION=1" # 📑 تنظيف ومنع استدعاء setlocalversion بشكل خاطئ أثناء التجميع الخارجي
)

# Use the generic GKI defconfig
DEFCONFIG="gki_defconfig"
DEFCONFIG_PATH="${KERNEL_DIR}/arch/arm64/configs/${DEFCONFIG}"

echo "==========================================================="
echo " 🚀 Patching defconfig LTO options to prevent cloud memory hang..."
echo "==========================================================="
# نقوم بتنظيف أي إعدادات LTO قديمة وحقن الإعداد الجديد لضمان عدم تخطي الرام المسموح به في السحاب (7GB)
if [ -f "$DEFCONFIG_PATH" ]; then
    sed -i '/CONFIG_LTO_CLANG_FULL/d' "$DEFCONFIG_PATH"
    sed -i '/CONFIG_LTO_CLANG_THIN/d' "$DEFCONFIG_PATH"
    sed -i '/CONFIG_LTO_NONE/d' "$DEFCONFIG_PATH"
    
    # خيار إيقاف الـ LTO تماماً (الأسرع والأضمن للسحاب بنسبة 100% - بناء في أقل من 10 دقائق):
    echo "CONFIG_LTO_NONE=y" >> "$DEFCONFIG_PATH"
    echo "CONFIG_LTO_CLANG_FULL=n" >> "$DEFCONFIG_PATH"
    echo "CONFIG_LTO_CLANG_THIN=n" >> "$DEFCONFIG_PATH"
    echo "✅ LTO successfully disabled in defconfig for maximum cloud speed!"
    
    # 💡 ملحوظة اختيارية: إذا أردت تفعيل نمط الـ Thin LTO بدلاً من الإيقاف الكامل، قم بحذف الأسطر الثلاثة أعلاه واستخدم هذه بدلاً منها:
    # echo "CONFIG_LTO_NONE=n" >> "$DEFCONFIG_PATH"
    # echo "CONFIG_LTO_CLANG_FULL=n" >> "$DEFCONFIG_PATH"
    # echo "CONFIG_LTO_CLANG_THIN=y" >> "$DEFCONFIG_PATH"
else
    echo "⚠️ Warning: defconfig file not found at $DEFCONFIG_PATH"
fi

# Get number of cores for parallel build
CORES=$(nproc)

echo "==========================================================="
echo " Building Kernel: $(basename "${KERNEL_DIR}")"
echo " Architecture   : ${ARCH}"
echo " Defconfig      : ${DEFCONFIG}"
echo " Clang Version  : $(clang --version | head -n 1)"
echo " Output Dir     : ${OUT_DIR}"
echo " Logs Dir       : ${LOG_DIR}"
echo " Jobs           : ${CORES}"
echo "==========================================================="

# Create the output directory
mkdir -p "${OUT_DIR}"

# 1. Generate the .config file based on the defconfig
echo "[1/2] Generating .config..."
make "${MAKE_ARGS[@]}" KBUILD_DEFCONFIG="${DEFCONFIG}" defconfig

# 2. Compile the kernel and modules
echo "[2/2] Compiling the kernel..."
# Disable "set -e" temporarily so we can gracefully handle build failure
set +e
time make "${MAKE_ARGS[@]}" -j"${CORES}"
BUILD_STATUS=$?
set -e

if [ ${BUILD_STATUS} -eq 0 ]; then
    echo "==========================================================="
    echo " Build Completed Successfully!"
    echo " The compiled kernel image and modules are in:"
    echo " ${OUT_DIR}/arch/arm64/boot/"
    echo "==========================================================="
else
    echo "===========================================================" >&2
    echo " Build Failed with exit code ${BUILD_STATUS}!" >&2
    echo " Please check the error log at: ${ERROR_LOG}" >&2
    echo "===========================================================" >&2
    exit 1
fi
