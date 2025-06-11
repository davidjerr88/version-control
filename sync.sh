#!/bin/bash

# 启用严格模式
# -e: 任何命令失败立即退出
# -u: 遇到未定义变量报错
# -x: 打印执行的命令（便于调试）
set -eux

# 配置文件路径
IMAGES_FILE="images.txt"

# 检查配置文件是否存在
if [ ! -f "$IMAGES_FILE" ]; then
    echo "错误: 文件 $IMAGES_FILE 不存在！请创建该文件并列出需要同步的镜像。"
    exit 1
fi

# 检查必要环境变量是否已设置
if [ -z "${ACR_REGISTRY+x}" ] || [ -z "${ACR_NAMESPACE+x}" ]; then
    echo "错误: ACR_REGISTRY 或 ACR_NAMESPACE 未设置！请在 GitHub Secrets 中配置。"
    exit 1
fi

# 打印同步信息
echo "开始同步 Docker 镜像到阿里云 ACR..."
echo "目标 Registry: ${ACR_REGISTRY}"
echo "目标 Namespace: ${ACR_NAMESPACE}"
echo "-----------------------------------"

# 同步镜像函数
sync_image() {
    local image="$1"
    local original_repo
    local original_tag
    local target_full_image_path

    # 分割镜像名称和标签
    original_repo=$(echo "$image" | cut -d ':' -f1)
    original_tag=${image##*:}  # 使用后缀匹配，处理无标签的情况

    # 默认标签处理
    if [[ "$original_tag" == "$image" ]]; then
        original_tag="latest"
    fi

    # 构造目标镜像路径
    target_full_image_path="${ACR_REGISTRY}/${ACR_NAMESPACE}/${original_repo}:${original_tag}"

    echo "--- 处理镜像: ${image} ---"
    echo "原始镜像路径: ${image}"
    echo "目标 ACR 路径: ${target_full_image_path}"
    echo "-----------------------------------"

    # 检查目标镜像是否已存在
    if docker manifest inspect "${target_full_image_path}" > /dev/null 2>&1; then
        echo "${target_full_image_path} 已存在于 ACR，跳过同步。"
        echo "-----------------------------------"
        return 0
    fi

    echo "镜像 ${target_full_image_path} 不存在，开始同步..."

    # 拉取原始镜像
    docker pull "${image}"

    # 打上阿里云 ACR 标签
    docker tag "${image}" "${target_full_image_path}"

    # 推送到阿里云 ACR
    docker push "${target_full_image_path}"

    # 清理本地镜像
    echo "清理本地镜像..."
    docker rmi "${image}" || true
    docker rmi "${target_full_image_path}" || true

    echo "成功同步: ${image} -> ${target_full_image_path}"
    echo "-----------------------------------"
}

# 读取 images.txt 并处理每个镜像
while IFS= read -r line; do
    # 跳过空行和注释行
    if [[ -z "$line" || "$line" =~ ^# ]]; then
        continue
    fi

    sync_image "$line"
done < "$IMAGES_FILE"

echo "所有镜像同步完成！"
echo "同步过程结束。"