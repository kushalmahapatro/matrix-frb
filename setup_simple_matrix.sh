#!/bin/bash

# Simple Matrix Server Setup Script
# This script sets up a basic Matrix server without complex configuration

set -e

echo "🚀 Simple Matrix Server Setup"
echo "============================="

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

# Function to start the simple server
start_simple_server() {
    echo "🔄 Starting simple Matrix server..."
    docker-compose -f docker-compose-simple.yml up -d
    
    echo "⏳ Waiting for services to start..."
    sleep 20
    
    echo "✅ Simple Matrix server is starting up!"
    echo ""
    echo "📋 Server URLs:"
    echo "  • Synapse homeserver: http://localhost:8008"
    echo "  • Element Web UI: http://localhost:8080"
    echo ""
    echo "🔧 To check server status: ./setup_simple_matrix.sh status"
    echo "🛑 To stop server: ./setup_simple_matrix.sh stop"
}

# Function to stop the server
stop_simple_server() {
    echo "🛑 Stopping simple Matrix server..."
    docker-compose -f docker-compose-simple.yml down
    echo "✅ Simple Matrix server stopped!"
}

# Function to check server status
check_simple_status() {
    echo "📊 Simple Matrix Server Status"
    echo "=============================="
    
    # Check if containers are running
    if docker-compose -f docker-compose-simple.yml ps | grep -q "Up"; then
        echo "✅ Server is running"
        echo ""
        echo "📋 Container Status:"
        docker-compose -f docker-compose-simple.yml ps
        echo ""
        echo "📋 Server URLs:"
        echo "  • Synapse homeserver: http://localhost:8008"
        echo "  • Element Web UI: http://localhost:8080"
    else
        echo "❌ Server is not running"
        echo "💡 Start it with: ./setup_simple_matrix.sh start"
    fi
}

# Function to show logs
show_simple_logs() {
    echo "📋 Simple Matrix Server Logs"
    echo "============================"
    docker-compose -f docker-compose-simple.yml logs -f
}

# Function to show help
show_simple_help() {
    echo "📖 Simple Matrix Server Setup Script Help"
    echo "========================================="
    echo ""
    echo "Usage: ./setup_simple_matrix.sh [command]"
    echo ""
    echo "Commands:"
    echo "  start     - Start the simple Matrix server"
    echo "  stop      - Stop the simple Matrix server"
    echo "  restart   - Restart the simple Matrix server"
    echo "  status    - Check server status"
    echo "  logs      - Show server logs"
    echo "  help      - Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./setup_simple_matrix.sh start"
    echo "  ./setup_simple_matrix.sh status"
    echo "  ./setup_simple_matrix.sh stop"
}

# Main script logic
case "${1:-help}" in
    start)
        start_simple_server
        ;;
    stop)
        stop_simple_server
        ;;
    restart)
        stop_simple_server
        echo ""
        start_simple_server
        ;;
    status)
        check_simple_status
        ;;
    logs)
        show_simple_logs
        ;;
    help|*)
        show_simple_help
        ;;
esac 