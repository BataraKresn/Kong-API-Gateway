#!/bin/bash

# Kong Gateway API Installation Script
# This script sets up the required directories and starts Kong with Konga

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if Docker is installed and running
check_docker() {
    print_info "Checking Docker installation..."
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        print_error "Docker is not running. Please start Docker first."
        exit 1
    fi
    
    print_success "Docker is installed and running"
}

# Function to check if Docker Compose is installed
check_docker_compose() {
    print_info "Checking Docker Compose installation..."
    
    if ! command -v docker compose &> /dev/null; then
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    print_success "Docker Compose is available"
}

# Function to create required directories
create_directories() {
    print_info "Creating required directories..."
    
    # Create data directory for PostgreSQL
    mkdir -p data/postgres
    print_info "Created directory: data/postgres"
    
    # Create log directories
    mkdir -p logs/kong
    mkdir -p logs/konga
    mkdir -p logs/postgres
    mkdir -p logs/pgbouncer
    mkdir -p logs/nginx
    print_info "Created log directories: logs/{kong,konga,postgres,pgbouncer,nginx}"
    
    # Create nginx configuration directory
    mkdir -p nginx
    print_info "Created nginx configuration directory"
    
    # Set proper permissions
    chmod 755 data/postgres
    chmod 755 logs/kong logs/konga logs/postgres
    
    print_success "All directories created successfully"
}

# Function to check if .env file exists and create if needed
check_env_file() {
    if [ ! -f ".env" ]; then
        print_warning ".env file not found. Creating default .env file..."
        create_env_file
        print_success "Default .env file created"
    else
        print_success ".env file already exists"
        validate_env_file
    fi
}

# Function to create .env file with all required variables
create_env_file() {
    cat > .env << 'EOF'
# PostgreSQL Database Configuration
# Required by docker-compose.yml for postgres service
POSTGRES_USER=postgres
POSTGRES_PASSWORD=kong_password_2024

# Konga Environment Configuration  
# Required by docker-compose.yml for konga service
NODE_ENV=production

# Kong Performance Configuration
KONG_NGINX_WORKER_PROCESSES=auto
KONG_NGINX_WORKER_CONNECTIONS=1024
KONG_MEM_CACHE_SIZE=128m
KONG_LOG_LEVEL=notice

# PgBouncer Configuration (Connection Pooling)
PGBOUNCER_POOL_MODE=transaction
PGBOUNCER_MAX_CLIENT_CONN=100
PGBOUNCER_DEFAULT_POOL_SIZE=20
PGBOUNCER_MIN_POOL_SIZE=5
PGBOUNCER_RESERVE_POOL_SIZE=3
PGBOUNCER_AUTH_TYPE=md5

# Kong Database Connection (set to pgbouncer to use connection pooling)
KONG_USE_PGBOUNCER=postgres
KONG_PG_PORT=5432
# To use PgBouncer, change to: KONG_USE_PGBOUNCER=pgbouncer

# Optional: Custom database names (uncomment if needed)
# KONG_DB_NAME=kong
# KONGA_DB_NAME=konga

# Optional: Custom PostgreSQL settings
# POSTGRES_DB=postgres

# Optional: Kong specific environment variables
# KONG_ADMIN_GUI_URL=http://localhost:8002
EOF
}

# Function to validate existing .env file has required variables
validate_env_file() {
    local missing_vars=()
    
    # Check for required variables
    if ! grep -q "^POSTGRES_USER=" .env; then
        missing_vars+=("POSTGRES_USER")
    fi
    
    if ! grep -q "^POSTGRES_PASSWORD=" .env; then
        missing_vars+=("POSTGRES_PASSWORD")
    fi
    
    if ! grep -q "^NODE_ENV=" .env; then
        missing_vars+=("NODE_ENV")
    fi
    
    # If any required variables are missing, add them
    if [ ${#missing_vars[@]} -gt 0 ]; then
        print_warning "Missing required environment variables: ${missing_vars[*]}"
        print_info "Adding missing variables to .env file..."
        
        # Backup existing .env
        cp .env .env.backup
        
        # Add missing variables
        for var in "${missing_vars[@]}"; do
            case $var in
                "POSTGRES_USER")
                    echo "" >> .env
                    echo "# Added by install.sh" >> .env
                    echo "POSTGRES_USER=postgres" >> .env
                    ;;
                "POSTGRES_PASSWORD")
                    echo "POSTGRES_PASSWORD=kong_password_2024" >> .env
                    ;;
                "NODE_ENV")
                    echo "NODE_ENV=production" >> .env
                    ;;
            esac
        done
        
        print_success "Added missing variables to .env (backup saved as .env.backup)"
    fi
}

# Function to check required files exist
check_required_files() {
    print_info "Checking required files..."

    local required_files=("docker-compose.yml" "init-db.sql")
    local missing_files=()
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            missing_files+=("$file")
        fi
    done
    
    # Check nginx configuration
    if [ ! -f "nginx/kong.conf" ]; then
        print_warning "NGINX configuration not found. Load balancer will not work."
        print_info "Run the install script again to create nginx/kong.conf"
    fi
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        print_error "Missing required files: ${missing_files[*]}"
        print_error "Make sure you're in the correct directory with all Kong setup files."
        exit 1
    fi
    
    print_success "All required files present"
}

# Function to stop existing containers
stop_existing() {
    print_info "Stopping existing Kong containers if any..."
    docker compose down --remove-orphans 2>/dev/null || true
    print_success "Stopped any existing containers"
}

# Function to start services
start_services() {
    print_info "Starting Kong Gateway services..."
    
    # Pull latest images
    print_info "Pulling Docker images..."
    docker compose pull
    
    # Start services
    print_info "Starting containers..."
    docker compose up -d
    
    # Wait for services to be ready
    print_info "Waiting for services to be ready..."
    sleep 10
    
    # Check service status
    print_info "Checking service status..."
    docker compose ps
}

# Function to verify installation
verify_installation() {
    print_info "Verifying installation..."
    
    # Check PostgreSQL
    if docker compose exec -T postgres pg_isready -U postgres &> /dev/null; then
        print_success "PostgreSQL is ready"
    else
        print_warning "PostgreSQL might still be starting up"
    fi
    
    # Check Kong Admin API
    sleep 5
    if curl -s http://localhost:8001/ &> /dev/null; then
        print_success "Kong Admin API is accessible"
    else
        print_warning "Kong Admin API might still be starting up"
    fi
    
    # Check Kong Proxy
    if curl -s http://localhost:8000/ &> /dev/null; then
        print_success "Kong Proxy is accessible"
    else
        print_warning "Kong Proxy might still be starting up"
    fi
    
    # Check Konga
    if curl -s http://localhost:1337/ &> /dev/null; then
        print_success "Konga GUI is accessible"
    else
        print_warning "Konga GUI might still be starting up"
    fi
}

# Function to display final information
display_info() {
    echo ""
    echo "=========================================="
    echo -e "${GREEN}Kong Gateway Installation Complete!${NC}"
    echo "=========================================="
    echo ""
    echo "Services are accessible at:"
    echo "• NGINX Load Balancer: http://localhost:80"
    echo "• NGINX -> Kong Admin:  http://localhost:8080"
    echo "• Kong Proxy:          http://localhost:8000"
    echo "• Kong Admin API:      http://localhost:8001"
    echo "• Kong HTTPS:          https://localhost:8443"
    echo "• Kong Admin SSL:      https://localhost:8444"
    echo "• Konga GUI:           http://localhost:1337"
    echo "• PostgreSQL:          localhost:5432"
    echo "• PgBouncer:           localhost:6432"
    echo ""
    echo "Directories created:"
    echo "• ./data/postgres/     - PostgreSQL persistent data (mounted)"
    echo "• ./logs/kong/         - Kong API Gateway logs (mounted)"
    echo "• ./logs/konga/        - Konga GUI logs (mounted)"
    echo "• ./logs/postgres/     - PostgreSQL logs (reserved)"
    echo ""
    echo "Configuration files:"
    echo "• .env                 - Environment variables (auto-created/validated)"
    echo "• docker-compose.yml   - Docker services configuration"
    echo "• init-db.sql          - Database initialization script"
    echo "• install.sh           - This installation script"
    echo ""
    echo "Useful commands:"
    echo "• docker-compose logs -f          - View all logs"
    echo "• docker-compose logs -f kong     - View Kong logs"
    echo "• docker-compose logs -f konga    - View Konga logs"
    echo "• docker-compose ps               - Check service status"
    echo "• docker-compose down             - Stop all services"
    echo "• docker-compose restart          - Restart all services"
    echo "• ./clean-logs.sh --stats         - View log files statistics"
    echo "• ./clean-logs.sh --dry-run       - Preview log cleanup"
    echo "• ./clean-logs.sh --force         - Clean logs without confirmation"
    echo ""
    echo "First time setup for Konga:"
    echo "1. Open http://localhost:1337"
    echo "2. Create admin account"
    echo "3. Add Kong connection with URL: http://kong:8001"
    echo ""
    echo "Environment Configuration:"
    echo "• .env file contains database credentials and settings"
    echo "• Modify .env file to customize database passwords"
    echo "• Required variables: POSTGRES_USER, POSTGRES_PASSWORD, NODE_ENV"
    echo "• Backup created (.env.backup) when missing variables are added"
    echo ""
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --no-start    Create directories only, don't start services"
    echo "  --stop        Stop all services"
    echo "  --restart     Restart all services"
    echo "  --logs        Show logs from all services"
    echo "  --status      Show status of all services"
    echo "  --clean       Stop services and remove data (BE CAREFUL!)"
    echo "  --help        Show this help message"
    echo ""
}

# Main execution
main() {
    echo ""
    echo "=========================================="
    echo "Kong Gateway API Installation Script"
    echo "=========================================="
    echo ""
    
    case "${1:-}" in
        --no-start)
            check_docker
            check_docker_compose
            check_required_files
            create_directories
            check_env_file
            print_success "Setup complete. Run 'docker compose up -d' to start services."
            ;;
        --stop)
            print_info "Stopping all services..."
            docker compose down
            print_success "All services stopped"
            ;;
        --restart)
            print_info "Restarting all services..."
            docker compose restart
            print_success "All services restarted"
            ;;
        --logs)
            docker compose logs -f
            ;;
        --status)
            docker compose ps
            ;;
        --clean)
            read -p "This will remove all data including PostgreSQL data. Are you sure? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                print_warning "Stopping services and removing data..."
                docker compose down -v
                rm -rf data logs
                print_success "Clean complete"
            else
                print_info "Clean cancelled"
            fi
            ;;
        --help)
            show_usage
            ;;
        "")
            check_docker
            check_docker_compose
            check_required_files
            create_directories
            check_env_file
            stop_existing
            start_services
            verify_installation
            display_info
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
