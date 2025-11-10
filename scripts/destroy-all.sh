#!/bin/bash

# 簡單的基礎設施刪除腳本
# 支援指定 region 參數

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 預設配置
REGION="us-east-1"
ENVIRONMENT="prod"
FORCE=false
AWS_PROFILE=""

# 顯示使用說明
show_help() {
    echo -e "${BLUE}=== 基礎設施刪除腳本 ===${NC}"
    echo ""
    echo "用法: $0 [選項]"
    echo ""
    echo "選項:"
    echo "  -r, --region REGION     指定 AWS 區域 (預設: us-east-1)"
    echo "  -e, --env ENVIRONMENT   指定環境 (預設: prod)"
    echo "  -p, --profile PROFILE   指定 AWS Profile (預設: 自動檢測)"
    echo "  -f, --force             強制刪除，跳過確認"
    echo "  -h, --help              顯示此說明"
    echo ""
    echo "範例:"
    echo "  $0                                    # 使用預設設定刪除"
    echo "  $0 -r us-west-2                      # 刪除 us-west-2 區域"
    echo "  $0 -r ap-northeast-1 -e prod         # 刪除 prod 環境的 ap-northeast-1 區域"
    echo "  $0 -p jastron-prod -r ap-northeast-1 # 使用 jastron-prod profile"
    echo "  $0 -r us-east-1 -f                   # 強制刪除，不詢問確認"
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

# 檢查必要工具
check_tools() {
    log_info "檢查必要工具..."
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI 未安裝"
        exit 1
    fi
    
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform 未安裝"
        exit 1
    fi
    
    # 自動檢測 AWS Profile
    if [ -z "$AWS_PROFILE" ]; then
        if [ "$ENVIRONMENT" = "prod" ]; then
            AWS_PROFILE="jastron-prod"
        elif [ "$ENVIRONMENT" = "staging" ]; then
            AWS_PROFILE="jastron-staging"
        else
            AWS_PROFILE="default"
        fi
        log_info "自動檢測到 AWS Profile: $AWS_PROFILE"
    fi
    
    # 設定 AWS Profile
    export AWS_PROFILE="$AWS_PROFILE"
    
    # 檢查 AWS 認證
    log_info "檢查 AWS 認證..."
    if ! aws sts get-caller-identity --region "$REGION" &> /dev/null; then
        log_error "AWS 認證失敗，請檢查："
        echo "  1. 是否已登入 SSO: aws sso login --profile $AWS_PROFILE"
        echo "  2. Profile 是否正確: $AWS_PROFILE"
        echo "  3. 區域是否正確: $REGION"
        exit 1
    fi
    
    log_success "工具檢查完成"
}

# 確認刪除操作
confirm_delete() {
    if [ "$FORCE" = true ]; then
        return 0
    fi
    
    echo ""
    log_warning "即將刪除以下資源："
    echo "  環境: $ENVIRONMENT"
    echo "  區域: $REGION"
    echo ""
    echo "這將刪除所有 AWS 資源，此操作無法撤銷！"
    echo ""
    
    read -p "確定要繼續嗎？(輸入 'yes' 確認): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "操作已取消"
        exit 0
    fi
}

# 刪除 ECR 倉庫
delete_ecr() {
    log_info "刪除 ECR 倉庫..."
    
    local repos=("jastron-arb" "jastron-arb-api")
    
    for repo in "${repos[@]}"; do
        if aws ecr describe-repositories --repository-names "$repo" --region "$REGION" &> /dev/null; then
            log_info "刪除 ECR 倉庫: $repo"
            aws ecr delete-repository --repository-name "$repo" --force --region "$REGION" 2>/dev/null || true
            log_success "ECR 倉庫 $repo 已刪除"
        else
            log_info "ECR 倉庫不存在: $repo"
        fi
    done
}

# 刪除 Terraform 資源
delete_terraform() {
    local dir="$1"
    local name="$2"
    
    if [ ! -d "$dir" ]; then
        log_warning "目錄不存在: $dir"
        return 0
    fi
    
    log_info "刪除 $name..."
    cd "$dir"
    
    # 設定 AWS 區域和 Profile
    export AWS_DEFAULT_REGION="$REGION"
    export AWS_PROFILE="$AWS_PROFILE"
    
    # 初始化並刪除
    terraform init -upgrade
    terraform destroy -auto-approve
    
    log_success "$name 刪除完成"
}

# 主刪除流程
main_delete() {
    log_info "開始刪除基礎設施..."
    log_info "環境: $ENVIRONMENT"
    log_info "區域: $REGION"
    
    # 進入項目根目錄
    cd "$(dirname "$0")/.."
    
    # 刪除順序（按依賴關係）
    delete_terraform "environments/$ENVIRONMENT/jastron-arb-api" "jastron-arb-api 服務"
    delete_terraform "environments/$ENVIRONMENT/jastron-arb" "jastron-arb 服務"
    delete_terraform "environments/$ENVIRONMENT/cicd" "CICD 資源"
    delete_terraform "environments/$ENVIRONMENT/bastion-host" "堡壘機"
    delete_terraform "environments/$ENVIRONMENT/network" "網路資源"
    
    # 刪除 ECR 倉庫
    delete_ecr
    
    log_success "所有資源刪除完成！"
}

# 主函數
main() {
    # 解析參數
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -e|--env)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -p|--profile)
                AWS_PROFILE="$2"
                shift 2
                ;;
            -f|--force)
                FORCE=true
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
    log_info "=== 基礎設施刪除腳本 ==="
    echo ""
    
    check_tools
    confirm_delete
    main_delete
    
    echo ""
    log_success "=== 刪除完成 ==="
    echo ""
}

# 執行主函數
main "$@"
