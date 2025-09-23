#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
VERSION=${1:-"latest"}
ACCOUNT_ID="732560673613"
REGION="us-east-1"
REPO_NAME="y-sweet"
IMAGE_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}:${VERSION}"

# Helper functions
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

# Validate prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
    
    # Check if AWS CLI is installed and configured
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it and try again."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials are not configured. Please run 'aws configure' and try again."
        exit 1
    fi
    
    # Check if y-sweet directory exists
    if [ ! -d "y-sweet/crates" ]; then
        log_error "y-sweet/crates directory not found. Make sure you're in the project root and the submodule is initialized."
        log_info "Try running: git submodule update --init --recursive"
        exit 1
    fi
    
    log_success "All prerequisites met!"
}

# Create ECR repository if it doesn't exist
ensure_ecr_repo() {
    log_info "Ensuring ECR repository exists..."
    
    if aws ecr describe-repositories --repository-names ${REPO_NAME} --region ${REGION} >/dev/null 2>&1; then
        log_success "ECR repository '${REPO_NAME}' already exists"
    else
        log_info "Creating ECR repository '${REPO_NAME}'..."
        aws ecr create-repository \
            --repository-name ${REPO_NAME} \
            --region ${REGION} \
            --image-scanning-configuration scanOnPush=true >/dev/null
        log_success "ECR repository '${REPO_NAME}' created"
    fi
}

# Build the Docker image
build_image() {
    log_info "Building Y-Sweet Docker image..."
    
    cd y-sweet/crates
    
    # Build with build progress and better caching
    docker build \
        --tag y-sweet:local \
        --tag y-sweet:${VERSION} \
        --progress=plain \
        .
    
    cd ../..
    log_success "Docker image built successfully"
}

# Tag image for ECR
tag_image() {
    log_info "Tagging image for ECR..."
    docker tag y-sweet:local ${IMAGE_URI}
    log_success "Image tagged as ${IMAGE_URI}"
}

# Authenticate with ECR
authenticate_ecr() {
    log_info "Authenticating with ECR..."
    aws ecr get-login-password --region ${REGION} | \
        docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com
    log_success "ECR authentication successful"
}

# Push image to ECR
push_image() {
    log_info "Pushing image to ECR..."
    docker push ${IMAGE_URI}
    log_success "Image pushed successfully"
}

# Update terraform.tfvars if it exists
update_terraform_vars() {
    if [ -f "terraform.tfvars" ]; then
        log_info "Updating terraform.tfvars with new image..."
        
        # Create backup
        cp terraform.tfvars terraform.tfvars.backup
        
        # Update the image variable
        if grep -q "^image\s*=" terraform.tfvars; then
            sed -i.bak "s|^image\s*=.*|image = \"${IMAGE_URI}\"|" terraform.tfvars
            log_success "Updated image in terraform.tfvars"
        else
            echo "image = \"${IMAGE_URI}\"" >> terraform.tfvars
            log_success "Added image to terraform.tfvars"
        fi
        
        # Clean up sed backup file
        rm -f terraform.tfvars.bak
    else
        log_warning "terraform.tfvars not found. Please manually update the image variable:"
        echo "image = \"${IMAGE_URI}\""
    fi
}

# Show deployment instructions
show_next_steps() {
    echo
    log_success "Build and push completed successfully!"
    echo
    echo "Next steps:"
    echo "1. Review the updated terraform.tfvars file"
    echo "2. Deploy the new image:"
    echo "   terraform plan"
    echo "   terraform apply"
    echo
    echo "Image URI: ${IMAGE_URI}"
    echo
}

# Main execution
main() {
    echo "=========================================="
    echo "  Y-Sweet Build and Push Script"
    echo "=========================================="
    echo "Version: ${VERSION}"
    echo "Target:  ${IMAGE_URI}"
    echo "=========================================="
    echo
    
    check_prerequisites
    ensure_ecr_repo
    build_image
    tag_image
    authenticate_ecr
    push_image
    # update_terraform_vars
    show_next_steps
}

# Handle script arguments
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [VERSION]"
    echo
    echo "Builds Y-Sweet Docker image and pushes to ECR"
    echo
    echo "Arguments:"
    echo "  VERSION    Docker image tag (default: 'latest')"
    echo
    echo "Examples:"
    echo "  $0         # Build and push as 'latest'"
    echo "  $0 v7      # Build and push as 'v7'"
    echo "  $0 dev     # Build and push as 'dev'"
    echo
    echo "Prerequisites:"
    echo "  - Docker running"
    echo "  - AWS CLI configured"
    echo "  - y-sweet submodule initialized"
    exit 0
fi

# Run main function
main "$@"
