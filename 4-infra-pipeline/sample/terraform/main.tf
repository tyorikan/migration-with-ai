# Cloud Run Deployment Example

# Enable required APIs
resource "google_project_service" "run_api" {
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iam_api" {
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

# Create a dedicated service account for the Cloud Run service
resource "google_service_account" "cloudrun_sa" {
  account_id   = "cloudrun-app-sa"
  display_name = "Cloud Run Application Service Account"
}

# Grant the service account permissions to access Cloud SQL (example)
resource "google_project_iam_member" "sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.cloudrun_sa.email}"
}

# Deploy the Cloud Run service
resource "google_cloud_run_v2_service" "default" {
  name     = "modernized-app-service"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.cloudrun_sa.email
    containers {
      # Use a dummy image for initial deployment or reference an existing image in Artifact Registry
      image = var.container_image
      
      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }
      
      # Example of referencing a secret from Secret Manager
      # env {
      #   name = "DB_PASSWORD"
      #   value_source {
      #     secret_key_ref {
      #       secret  = google_secret_manager_secret.db_pass.secret_id
      #       version = "latest"
      #     }
      #   }
      # }
    }
  }

  depends_on = [google_project_service.run_api]
}

# Allow unauthenticated invocations (make it public) - adjust based on requirements
resource "google_cloud_run_v2_service_iam_member" "public_access" {
  project  = google_cloud_run_v2_service.default.project
  location = google_cloud_run_v2_service.default.location
  name     = google_cloud_run_v2_service.default.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

output "cloud_run_url" {
  value       = google_cloud_run_v2_service.default.uri
  description = "The URL on which the deployed service is available"
}
