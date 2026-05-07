#!/bin/bash
# ワークショップ参加者の環境セットアップ確認スクリプト

echo "=========================================="
echo "Google Cloud Migration Workshop - 環境確認"
echo "=========================================="
echo ""

# 色付き出力フォーマット
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# ツールの存在確認関数
check_command() {
    COMMAND=$1
    if command -v $COMMAND &> /dev/null; then
        echo -e "[${GREEN}OK${NC}] $COMMAND はインストールされています: $($COMMAND --version | head -n 1)"
        return 0
    else
        echo -e "[${RED}NG${NC}] $COMMAND が見つかりません。インストールしてください。"
        return 1
    fi
}

echo "--- 1. 必須ツールの確認 ---"
check_command "gcloud"
check_command "terraform"
check_command "git"

echo ""
echo "--- 2. Google Cloud 認証状況の確認 ---"
if command -v gcloud &> /dev/null; then
    ACTIVE_ACCOUNT=$(gcloud config get-value account 2>/dev/null)
    if [ -n "$ACTIVE_ACCOUNT" ]; then
        echo -e "[${GREEN}OK${NC}] ログイン中のアカウント: $ACTIVE_ACCOUNT"
    else
        echo -e "[${RED}NG${NC}] gcloud にログインしていません。'gcloud auth login' を実行してください。"
    fi

    ACTIVE_PROJECT=$(gcloud config get-value project 2>/dev/null)
    if [ -n "$ACTIVE_PROJECT" ]; then
        echo -e "[${GREEN}OK${NC}] 選択中のプロジェクト: $ACTIVE_PROJECT"
    else
        echo -e "[${RED}NG${NC}] プロジェクトが選択されていません。'gcloud config set project [PROJECT_ID]' を実行してください。"
    fi

    # Application Default Credentials (ADC) の確認 (簡易的)
    ADC_FILE="$HOME/.config/gcloud/application_default_credentials.json"
    if [ -f "$ADC_FILE" ]; then
        echo -e "[${GREEN}OK${NC}] Application Default Credentials (ADC) が設定されています。"
    else
        echo -e "[${RED}NG${NC}] ADCが見つかりません。Terraform等でエラーが出る場合は 'gcloud auth application-default login' を実行してください。"
    fi
else
    echo -e "[${RED}SKIP${NC}] gcloud がないため、認証確認をスキップします。"
fi

echo ""
echo "=========================================="
echo "[NG] が出た項目は、ワークショップ開始前にご確認をお願いします。"
echo "=========================================="
