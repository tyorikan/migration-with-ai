variable "project_id" {
  description = "The ID of the Google Cloud project"
  type        = string
}

variable "region" {
  description = "The primary region for resources"
  type        = string
  default     = "asia-northeast1"
}

variable "environment" {
  description = "The deployment environment (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "container_image" {
  description = "The container image URI to deploy to Cloud Run"
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello" # Default hello-world image for bootstrapping
}

# --- Cloud SQL for PostgreSQL (SFDC 移行先 DB) ---

variable "cloudsql_instance_name" {
  description = "Cloud SQL インスタンス名"
  type        = string
  default     = "sfdc-migration-db"
}

variable "cloudsql_tier" {
  description = "Cloud SQL のマシンタイプ (例: db-custom-2-7680)"
  type        = string
  default     = "db-custom-2-7680" # 2 vCPU, 7.5 GB RAM
}

variable "cloudsql_disk_size_gb" {
  description = "Cloud SQL のディスクサイズ (GB)"
  type        = number
  default     = 20
}

variable "database_name" {
  description = "移行先の PostgreSQL データベース名"
  type        = string
  default     = "sfdc_migration"
}

