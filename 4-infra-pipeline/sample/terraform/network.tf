# =============================================================================
# VPC ネットワーク構成 - SFDC→PostgreSQL 移行基盤
# =============================================================================
# Cloud SQL (Private IP) に安全にアクセスするための
# VPC、サブネット、Private Service Connect を構成します。
# =============================================================================

# --- VPC ネットワーク ---
resource "google_compute_network" "migration_vpc" {
  name                    = "migration-vpc"
  auto_create_subnetworks = false # カスタムモード VPC を使用
  project                 = var.project_id
}

# --- アプリケーション用サブネット ---
resource "google_compute_subnetwork" "app_subnet" {
  name          = "app-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.migration_vpc.id

  # Cloud Run の Direct VPC Egress 用
  # Cloud Run から Cloud SQL (Private IP) にアクセスするために必要
}

# --- Private Service Access (Cloud SQL Private IP 接続用) ---
# Google が管理するサービス（Cloud SQL 等）と VPC を内部接続するための IP 範囲
resource "google_compute_global_address" "private_ip_range" {
  name          = "google-managed-services-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = google_compute_network.migration_vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.migration_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]

  depends_on = [google_project_service.servicenetworking_api]
}

# --- Cloud Run 用 Direct VPC Egress サブネット ---
# Cloud Run サービスが VPC 内のリソース（Cloud SQL 等）にアクセスするための構成
# Cloud Run v2 の Direct VPC Egress では、専用のサブネットを指定可能
resource "google_compute_subnetwork" "cloudrun_egress_subnet" {
  name          = "cloudrun-egress-subnet"
  ip_cidr_range = "10.0.2.0/24"
  region        = var.region
  network       = google_compute_network.migration_vpc.id
}

# --- ファイアウォールルール ---
# Cloud Run → Cloud SQL への PostgreSQL 接続を許可
resource "google_compute_firewall" "allow_cloudrun_to_cloudsql" {
  name    = "allow-cloudrun-to-cloudsql"
  network = google_compute_network.migration_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  source_ranges = [
    google_compute_subnetwork.app_subnet.ip_cidr_range,
    google_compute_subnetwork.cloudrun_egress_subnet.ip_cidr_range,
  ]

  # Cloud SQL のプライベート IP が存在する範囲
  destination_ranges = [google_compute_global_address.private_ip_range.address]

  direction = "EGRESS"
}

# --- Cloud NAT (必要に応じて) ---
# VPC 内のリソースがインターネットに出る必要がある場合
resource "google_compute_router" "nat_router" {
  name    = "nat-router"
  region  = var.region
  network = google_compute_network.migration_vpc.id
}

resource "google_compute_router_nat" "nat_config" {
  name                               = "nat-config"
  router                             = google_compute_router.nat_router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
