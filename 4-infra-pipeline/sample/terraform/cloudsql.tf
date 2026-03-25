# =============================================================================
# Cloud SQL for PostgreSQL - SFDC 移行先データベース
# =============================================================================
# このモジュールは、Salesforce からの移行先として
# Cloud SQL for PostgreSQL のインスタンスとデータベースを構築します。
# =============================================================================

# --- 必要な API の有効化 ---
resource "google_project_service" "sqladmin_api" {
  service            = "sqladmin.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "servicenetworking_api" {
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

# --- Cloud SQL インスタンス ---
resource "google_sql_database_instance" "sfdc_migration" {
  name             = var.cloudsql_instance_name
  database_version = "POSTGRES_16"
  region           = var.region
  project          = var.project_id

  # 誤操作による削除を防止 (本番環境では必ず true)
  deletion_protection = var.environment == "prod" ? true : false

  settings {
    tier              = var.cloudsql_tier
    edition           = "ENTERPRISE"
    availability_type = var.environment == "prod" ? "REGIONAL" : "ZONAL"
    disk_size         = var.cloudsql_disk_size_gb
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    # --- Private IP 接続 (推奨) ---
    ip_configuration {
      ipv4_enabled                                  = false # パブリック IP を無効化
      private_network                               = google_compute_network.migration_vpc.id
      enable_private_path_for_google_cloud_services = true

      # 初期セットアップ用に一時的にパブリック IP を有効にする場合
      # ipv4_enabled    = true
      # authorized_networks {
      #   name  = "office-network"
      #   value = "203.0.113.0/24"
      # }
    }

    # --- バックアップ設定 ---
    backup_configuration {
      enabled                        = true
      start_time                     = "02:00"  # UTC (JST 11:00)
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = 14
        retention_unit   = "COUNT"
      }
    }

    # --- メンテナンスウィンドウ ---
    maintenance_window {
      day          = 7  # 日曜日
      hour         = 18 # UTC (JST 翌 3:00)
      update_track = "stable"
    }

    # --- PostgreSQL 固有の設定フラグ ---
    database_flags {
      name  = "log_min_duration_statement"
      value = "1000" # 1秒以上かかるクエリをログに記録
    }

    database_flags {
      name  = "pg_stat_statements.track"
      value = "all"
    }

    database_flags {
      name  = "log_checkpoints"
      value = "on"
    }

    # タイムゾーンを日本標準時に設定
    database_flags {
      name  = "timezone"
      value = "Asia/Tokyo"
    }

    # --- 監査ログ (Cloud Audit Logs 連携) ---
    database_flags {
      name  = "cloudsql.enable_pgaudit"
      value = "on"
    }

    # Insights (クエリパフォーマンス分析)
    insights_config {
      query_insights_enabled  = true
      query_plans_per_minute  = 5
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }
  }

  depends_on = [
    google_project_service.sqladmin_api,
    google_service_networking_connection.private_vpc_connection,
  ]
}

# --- 移行先データベースの作成 ---
resource "google_sql_database" "sfdc_db" {
  name     = var.database_name
  instance = google_sql_database_instance.sfdc_migration.name

  # SFDC のデータ（日本語を含む）を正しく扱うための照合順序
  # ICU ロケールによる Unicode 準拠のソート
  collation = "ja_JP.utf8"
}

# --- データベースユーザー (アプリケーション用) ---
resource "random_password" "db_password" {
  length  = 32
  special = true
}

resource "google_sql_user" "app_user" {
  name     = "app_user"
  instance = google_sql_database_instance.sfdc_migration.name
  password = random_password.db_password.result
}

# --- パスワードを Secret Manager に格納 ---
resource "google_secret_manager_secret" "db_password" {
  secret_id = "cloudsql-app-password"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password_version" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

# --- 接続情報の出力 ---
output "cloudsql_connection_name" {
  value       = google_sql_database_instance.sfdc_migration.connection_name
  description = "Cloud SQL Auth Proxy で使用する接続名 (project:region:instance)"
}

output "cloudsql_private_ip" {
  value       = google_sql_database_instance.sfdc_migration.private_ip_address
  description = "Cloud SQL インスタンスのプライベート IP アドレス"
}

output "database_name" {
  value       = google_sql_database.sfdc_db.name
  description = "移行先データベース名"
}
