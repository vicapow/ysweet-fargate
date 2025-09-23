region         = "us-east-1"
app_name       = "ysweet"
container_port = 8080
image          = "732560673613.dkr.ecr.us-east-1.amazonaws.com/y-sweet@sha256:d0ca641467973a3a30f4511f422dfa8e2d4348be782e9596b757d7f3a892818d"
bucket_name    = "y-crixet"
ysweet_auth_key_secret_arn = "arn:aws:secretsmanager:us-east-1:732560673613:secret:ysweet-auth-key-p4qg7y"

# SSL Configuration (optional)
# Set create_ssl_cert = true and provide domain_name to enable HTTPS
create_ssl_cert = true
domain_name     = "ysweet.crixet.com"

# Logging Configuration
log_level = "warn"

# Dev Server Configuration (optional)
enable_dev_server = true
dev_image         = "732560673613.dkr.ecr.us-east-1.amazonaws.com/y-sweet@sha256:d0ca641467973a3a30f4511f422dfa8e2d4348be782e9596b757d7f3a892818d"
dev_bucket_name   = "y-sweet-crixet-dev-storage"
