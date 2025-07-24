#!/bin/bash
set -e  # Exit on any error

echo "⚙️  Building Ollama Docker image with model..."

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker and try again."
    exit 1
fi

# Check for config.ini
if [ ! -f "config.ini" ]; then
    echo "❌ config.ini file not found!"
    echo "Create a config.ini file with the following content:"
    echo ""
    echo "[model]"
    echo "name = deepseek-r1:7b"
    exit 1
fi

# Read model name from config.ini
MODEL_NAME=$(grep -E "^name" config.ini | head -1 | cut -d'=' -f2 | xargs)

if [ -z "$MODEL_NAME" ]; then
    echo "❌ Failed to read model name from config.ini"
    exit 1
fi

echo "📦 Model to be used: $MODEL_NAME"

IMAGE_NAME="ollama-with-model"
CONTAINER_NAME="ollama-temp"

# Remove old container if exists
if docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
    echo "🛑 Stopping and removing old container..."
    docker stop $CONTAINER_NAME > /dev/null 2>&1 || true
    docker rm $CONTAINER_NAME > /dev/null 2>&1
fi

# Remove old image if exists
if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^$IMAGE_NAME:latest$"; then
    echo "🗑️ Removing old image: $IMAGE_NAME:latest..."
    docker rmi $IMAGE_NAME:latest || echo "⚠️ Could not remove image (possibly in use)"
fi

# Run the Ollama container
echo "🚀 Running temporary container from ollama/ollama..."
docker run -d --name $CONTAINER_NAME ollama/ollama

# Wait for Ollama API to become available
echo "⏳ Waiting for Ollama API to start..."
for i in {1..30}; do
    if docker exec $CONTAINER_NAME ollama list > /dev/null 2>&1; then
        echo "✅ Ollama is ready."
        break
    fi
    echo "⏳ Attempt $i/30: Ollama is not ready yet..."
    sleep 2
done

# Pull the model
echo "📥 Pulling model: $MODEL_NAME"
if docker exec $CONTAINER_NAME ollama pull "$MODEL_NAME"; then
    echo "✅ Model '$MODEL_NAME' downloaded successfully."
else
    echo "❌ Failed to pull model '$MODEL_NAME'"
    docker stop $CONTAINER_NAME
    docker rm $CONTAINER_NAME
    exit 1
fi

# Commit container to a new image
echo "💾 Committing container to new image: $IMAGE_NAME:latest"
docker commit $CONTAINER_NAME $IMAGE_NAME:latest

# Cleanup
echo "🧹 Stopping and removing temporary container..."
docker stop $CONTAINER_NAME > /dev/null 2>&1
docker rm $CONTAINER_NAME > /dev/null 2>&1
docker image rm ollama/ollama

# Done
echo ""
echo "🎉 Success! New Docker image created:"
echo ""
echo "   docker run -d --name ollama $IMAGE_NAME:latest"
echo ""
echo "The model '$MODEL_NAME' is now embedded and ready to use:"
echo ""
echo "   docker exec -it ollama ollama run $MODEL_NAME"
