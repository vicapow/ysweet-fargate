region         = "us-east-1"
app_name       = "ysweet"
container_port = 8080
image          = "ghcr.io/jamsocket/y-sweet"
bucket_name    = "y-sweet-crixet-dev-storage"
auth_key       = "your-secure-auth-key-change-this"

# SSL Configuration (optional)
# Set create_ssl_cert = true and provide domain_name to enable HTTPS
create_ssl_cert = false
domain_name     = "ysweet.crixet.com"