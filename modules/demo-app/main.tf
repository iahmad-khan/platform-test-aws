locals {
  app_labels = merge(var.tags, {
    app                          = "demo-app"
    "app.kubernetes.io/name"     = "demo-app"
    "app.kubernetes.io/instance" = var.namespace
  })

  # Python HTTP server that exercises S3 and Translate via Pod Identity credentials.
  # boto3 picks up credentials automatically from the token file injected by the
  # eks-pod-identity-agent DaemonSet — no imagePullSecrets or annotations needed.
  app_script = <<-PYTHON
    import boto3, json, os
    from http.server import HTTPServer, BaseHTTPRequestHandler

    BUCKET  = os.environ["S3_BUCKET_NAME"]
    REGION  = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            pass  # suppress access log noise

        def _json(self, code, body):
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(body, indent=2).encode())

        def do_GET(self):
            if self.path == "/health":
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"OK")

            elif self.path == "/s3":
                try:
                    s3  = boto3.client("s3", region_name=REGION)
                    res = s3.list_objects_v2(Bucket=BUCKET, MaxKeys=10)
                    keys = [o["Key"] for o in res.get("Contents", [])]
                    self._json(200, {"bucket": BUCKET, "object_count": res["KeyCount"], "sample_keys": keys})
                except Exception as e:
                    self._json(500, {"error": str(e)})

            elif self.path == "/translate":
                try:
                    tr  = boto3.client("translate", region_name=REGION)
                    res = tr.translate_text(
                        Text="Hello from EKS Pod Identity! AWS Translate is working.",
                        SourceLanguageCode="en",
                        TargetLanguageCode="es"
                    )
                    self._json(200, {
                        "source": res["SourceLanguageCode"],
                        "target": res["TargetLanguageCode"],
                        "original": "Hello from EKS Pod Identity! AWS Translate is working.",
                        "translated": res["TranslatedText"]
                    })
                except Exception as e:
                    self._json(500, {"error": str(e)})

            else:
                self._json(404, {"endpoints": ["/health", "/s3", "/translate"]})

    print(f"Demo app listening on :8080  bucket={BUCKET}  region={REGION}")
    HTTPServer(("", 8080), Handler).serve_forever()
  PYTHON
}

resource "kubernetes_namespace" "this" {
  metadata {
    name   = var.namespace
    labels = local.app_labels
  }
}

# Service account — plain, no annotations.
# Pod Identity association (in modules/pod-identity) binds the IAM role to this SA.
resource "kubernetes_service_account" "this" {
  metadata {
    name      = var.service_account_name
    namespace = kubernetes_namespace.this.metadata[0].name
    labels    = local.app_labels
  }
}

resource "kubernetes_config_map" "app_script" {
  metadata {
    name      = "demo-app-script"
    namespace = kubernetes_namespace.this.metadata[0].name
    labels    = local.app_labels
  }
  data = {
    "app.py" = local.app_script
  }
}

resource "kubernetes_deployment" "this" {
  metadata {
    name      = "demo-app"
    namespace = kubernetes_namespace.this.metadata[0].name
    labels    = local.app_labels
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = { app = "demo-app" }
    }

    template {
      metadata {
        labels = local.app_labels
      }

      spec {
        service_account_name            = kubernetes_service_account.this.metadata[0].name
        automount_service_account_token = true

        # Install boto3 into a shared volume before the main container starts
        init_container {
          name    = "install-deps"
          image   = "python:3.12-slim"
          command = ["pip", "install", "boto3", "--quiet", "--target", "/deps"]
          volume_mount {
            name       = "deps"
            mount_path = "/deps"
          }
        }

        container {
          name  = "demo-app"
          image = "python:3.12-slim"
          command = ["python", "/app/app.py"]

          env {
            name  = "PYTHONPATH"
            value = "/deps"
          }
          env {
            name  = "S3_BUCKET_NAME"
            value = var.s3_bucket_name
          }
          env {
            name  = "AWS_DEFAULT_REGION"
            value = var.aws_region
          }

          port {
            name           = "http"
            container_port = 8080
            protocol       = "TCP"
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 15
            period_seconds        = 20
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          resources {
            requests = { cpu = "50m", memory = "128Mi" }
            limits   = { memory = "256Mi" }
          }

          volume_mount {
            name       = "app"
            mount_path = "/app"
            read_only  = true
          }
          volume_mount {
            name       = "deps"
            mount_path = "/deps"
          }
        }

        volume {
          name = "app"
          config_map {
            name = kubernetes_config_map.app_script.metadata[0].name
          }
        }
        volume {
          name = "deps"
          empty_dir {}
        }
      }
    }
  }

  depends_on = [kubernetes_service_account.this]
}

resource "kubernetes_service" "this" {
  metadata {
    name      = "demo-app"
    namespace = kubernetes_namespace.this.metadata[0].name
    labels    = local.app_labels
  }

  spec {
    selector = { app = "demo-app" }
    port {
      name        = "http"
      port        = 80
      target_port = 8080
      protocol    = "TCP"
    }
    type = "ClusterIP"
  }
}
