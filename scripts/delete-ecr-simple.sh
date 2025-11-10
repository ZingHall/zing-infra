#!/bin/bash

# 最簡單的 ECR 映像刪除腳本
# 直接使用 AWS CLI 命令

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 預設配置
REGION="ap-northeast-1"
AWS_PROFILE="jastron-prod"

# 顯示使用說明
show_help() {
    echo -e "${BLUE}=== 最簡單 ECR 映像刪除腳本 ===${NC}"
    echo ""
    echo "用法: $0 [選項]"
    echo ""
    echo "選項:"
    echo "  -r, --region REGION     指定 AWS 區域 (預設: ap-northeast-1)"
    echo "  -p, --profile PROFILE   指定 AWS Profile (預設: jastron-prod)"
    echo "  -n, --repo REPOSITORY   指定倉庫名稱"
    echo "  -a, --all               刪除所有倉庫的映像"
    echo "  -h, --help              顯示此說明"
    echo ""
    echo "範例:"
    echo "  $0 -n jastron-arb                    # 刪除 jastron-arb 倉庫的映像"
    echo "  $0 -a                                # 刪除所有倉庫的映像"
    echo "  $0 -p jastron-staging -n jastron-arb-api  # 使用 staging profile"
    echo ""
}

# 記錄訊息
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 檢查 AWS 認證
check_aws_auth() {
    log_info "檢查 AWS 認證..."
    
    # 設定環境變數
    export AWS_PROFILE="$AWS_PROFILE"
    export AWS_DEFAULT_REGION="$REGION"
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS 認證失敗，請先登入 SSO:"
        echo "  aws sso login --profile $AWS_PROFILE"
        exit 1
    fi
    
    log_success "AWS 認證成功"
}

# 刪除單個倉庫的映像
delete_repo_images() {
    local repo_name="$1"
    
    log_info "處理倉庫: $repo_name"
    
    # 檢查倉庫是否存在
    if ! aws ecr describe-repositories --repository-names "$repo_name" &> /dev/null; then
        log_warning "倉庫不存在: $repo_name"
        return 0
    fi
    
    # 獲取映像列表
    local images=$(aws ecr list-images --repository-name "$repo_name" --query 'imageIds[*]' --output json)
    
    if [ "$images" = "[]" ]; then
        log_info "倉庫 $repo_name 中沒有映像"
        return 0
    fi
    
    local image_count=$(echo "$images" | jq 'length')
    log_info "發現 $image_count 個映像"
    
    # 顯示映像信息
    echo "$images" | jq -r '.[] | "  - " + (.imageTag // "untagged") + " (digest: " + .imageDigest[0:12] + "...)"'
    
    # 使用最簡單的方法：直接刪除倉庫（會自動刪除所有映像）
    log_info "使用強制刪除倉庫方法（會自動刪除所有映像）..."
    if aws ecr delete-repository --repository-name "$repo_name" --force; then
        log_success "成功刪除倉庫 $repo_name 及其所有 $image_count 個映像"
    else
        log_error "刪除倉庫失敗"
        return 1
    fi
}

# 獲取所有倉庫
get_all_repos() {
    aws ecr describe-repositories --query 'repositories[].repositoryName' --output text | tr '\t' '\n'
}

# 主函數
main() {
    local repo_name=""
    local delete_all=false
    
    # 解析參數
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -p|--profile)
                AWS_PROFILE="$2"
                shift 2
                ;;
            -n|--repo)
                repo_name="$2"
                shift 2
                ;;
            -a|--all)
                delete_all=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知參數: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    echo ""
    log_info "=== 最簡單 ECR 映像刪除 ==="
    echo ""
    
    check_aws_auth
    
    if [ "$delete_all" = true ]; then
        log_info "刪除所有倉庫的映像..."
        local repos=($(get_all_repos))
        
        if [ ${#repos[@]} -eq 0 ]; then
            log_info "沒有找到任何倉庫"
            exit 0
        fi
        
        for repo in "${repos[@]}"; do
            delete_repo_images "$repo"
            echo ""
        done
    elif [ -n "$repo_name" ]; then
        delete_repo_images "$repo_name"
    else
        log_error "請指定倉庫名稱 (-n) 或使用 --all 選項"
        show_help
        exit 1
    fi
    
    log_success "完成！"
}

# 執行主函數
main "$@"
