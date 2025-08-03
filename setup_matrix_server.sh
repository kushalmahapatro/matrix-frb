#!/bin/bash

# Matrix Server Setup Script
# This script helps you set up and manage a local Matrix server for testing

set -e

echo "🚀 Matrix Server Setup Script"
echo "=============================="

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

# Check if Docker Compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

# Function to start the server
start_server() {
    echo "🔄 Starting Matrix server..."
    docker-compose up -d
    
    echo "⏳ Waiting for services to start..."
    sleep 10
    
    echo "✅ Matrix server is starting up!"
    echo ""
    echo "📋 Server URLs:"
    echo "  • Synapse homeserver: http://localhost:8008"
    echo "  • Sliding sync proxy: http://localhost:8009"
    echo "  • Element Web UI: http://localhost:8080"
    echo ""
    echo "🔧 To check server status: ./setup_matrix_server.sh status"
    echo "🛑 To stop server: ./setup_matrix_server.sh stop"
}

# Function to stop the server
stop_server() {
    echo "🛑 Stopping Matrix server..."
    docker-compose down
    echo "✅ Matrix server stopped!"
}

# Function to check server status
check_status() {
    echo "📊 Matrix Server Status"
    echo "======================="
    
    # Check if containers are running
    if docker-compose ps | grep -q "Up"; then
        echo "✅ Server is running"
        echo ""
        echo "📋 Container Status:"
        docker-compose ps
        echo ""
        echo "📋 Server URLs:"
        echo "  • Synapse homeserver: http://localhost:8008"
        echo "  • Sliding sync proxy: http://localhost:8009"
        echo "  • Element Web UI: http://localhost:8080"
    else
        echo "❌ Server is not running"
        echo "💡 Start it with: ./setup_matrix_server.sh start"
    fi
}

# Function to show logs
show_logs() {
    echo "📋 Matrix Server Logs"
    echo "===================="
    docker-compose logs -f
}

# Function to create test user
create_test_user() {
    echo "👤 Creating test user..."
    
    # Wait for Synapse to be ready
    echo "⏳ Waiting for Synapse to be ready..."
    sleep 15
    
    # Create a test user using Synapse admin API
    echo "🔧 Creating test user 'testuser' with password 'testpass'..."
    
    # Note: This requires the registration shared secret to be properly configured
    # For now, we'll just show the manual steps
    echo ""
    echo "📝 Manual User Creation Steps:"
    echo "1. Open Element Web: http://localhost:8080"
    echo "2. Click 'Create Account'"
    echo "3. Use these credentials:"
    echo "   • Username: testuser"
    echo "   • Password: testpass"
    echo "   • Homeserver: http://localhost:8008"
    echo ""
    echo "💡 Or use the registration API:"
    echo "curl -X POST http://localhost:8008/_matrix/client/r0/register \\"
    echo "  -H 'Content-Type: application/json' \\"
    echo "  -d '{\"auth\":{\"type\":\"m.login.dummy\"},\"username\":\"testuser\",\"password\":\"testpass\",\"initial_device_display_name\":\"Flutter Test\"}'"
}

# Function to show help
show_help() {
    echo "📖 Matrix Server Setup Script Help"
    echo "=================================="
    echo ""
    echo "Usage: ./setup_matrix_server.sh [command]"
    echo ""
    echo "Commands:"
    echo "  start     - Start the Matrix server"
    echo "  stop      - Stop the Matrix server"
    echo "  restart   - Restart the Matrix server"
    echo "  status    - Check server status"
    echo "  logs      - Show server logs"
    echo "  create-user - Create a test user"
    echo "  help      - Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./setup_matrix_server.sh start"
    echo "  ./setup_matrix_server.sh status"
    echo "  ./setup_matrix_server.sh stop"
}

# Main script logic
case "${1:-help}" in
    start)
        start_server
        ;;
    stop)
        stop_server
        ;;
    restart)
        stop_server
        echo ""
        start_server
        ;;
    status)
        check_status
        ;;
    logs)
        show_logs
        ;;
    create-user)
        create_test_user
        ;;
    help|*)
        show_help
        ;;
esac 