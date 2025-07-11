#!/bin/bash
# VSS Engine Startup Script for AWS Spot Instance
# Runs from 8 PM EST to 3 AM EST

set -e

# Logging
exec > >(tee /var/log/vss-startup.log)
exec 2>&1

echo "Starting VSS Engine setup at $(date)"

# Update system
apt-get update -y
apt-get upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker ubuntu

# Install NVIDIA Docker
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list
apt-get update -y
apt-get install -y nvidia-docker2
systemctl restart docker

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create application directory
mkdir -p /opt/vss-engine
cd /opt/vss-engine

# Clone the repository
git clone https://github.com/NVIDIA/video-search-and-summarization.git .

# Create environment configuration
cat > deploy/docker/remote_vlm_deployment/.env << EOF
# VSS Engine Configuration for Talentora POC
BACKEND_PORT=8081
FRONTEND_PORT=8080
DISABLE_CA_RAG=false
DISABLE_FRONTEND=false
DISABLE_GUARDRAILS=false
DISABLE_CV_PIPELINE=true
MODEL_PATH=""
NGC_API_KEY=""
OPENAI_API_KEY=${OPENAI_API_KEY}
OPENAI_API_VERSION=2024-02-01
VLM_MODEL_TO_USE=openai-compat
VIA_VLM_OPENAI_MODEL_DEPLOYMENT_NAME=gpt-4o
NUM_GPUS=1
VLM_BATCH_SIZE=1
NUM_VLM_PROCS=4
ENABLE_AUDIO=true
INSTALL_PROPRIETARY_CODECS=true
MILVUS_DB_HOST=127.0.0.1
MILVUS_DB_PORT=19530
NVIDIA_VISIBLE_DEVICES=all
EOF

# Set up automatic shutdown at 3 AM EST
cat > /opt/shutdown-at-3am.sh << 'EOF'
#!/bin/bash
# Automatic shutdown script
echo "Shutting down VSS Engine at $(date)"
cd /opt/vss-engine
docker-compose -f deploy/docker/remote_vlm_deployment/compose.yaml down
echo "VSS Engine stopped. Terminating instance..."
/usr/local/bin/aws ec2 terminate-instances --instance-ids $(curl -s http://169.254.169.254/latest/meta-data/instance-id)
EOF

chmod +x /opt/shutdown-at-3am.sh

# Schedule shutdown for 3 AM EST (8 AM UTC)
echo "0 8 * * * root /opt/shutdown-at-3am.sh" >> /etc/crontab

# Create spot interruption monitor
cat > /opt/spot-monitor.sh << 'EOF'
#!/bin/bash
while true; do
    # Check for spot interruption
    if curl -s http://169.254.169.254/latest/meta-data/spot/instance-action | grep -q terminate; then
        echo "Spot interruption detected at $(date)"
        cd /opt/vss-engine
        docker-compose -f deploy/docker/remote_vlm_deployment/compose.yaml down
        # Save any important data to S3 if needed
        # aws s3 cp /tmp/logs s3://your-bucket/logs/ --recursive
        break
    fi
    sleep 30
done
EOF

chmod +x /opt/spot-monitor.sh

# Start spot monitor in background
nohup /opt/spot-monitor.sh > /var/log/spot-monitor.log 2>&1 &

# Pull Docker images
cd /opt/vss-engine
docker-compose -f deploy/docker/remote_vlm_deployment/compose.yaml pull

# Start VSS Engine
echo "Starting VSS Engine at $(date)"
docker-compose -f deploy/docker/remote_vlm_deployment/compose.yaml up -d

# Wait for services to be ready
echo "Waiting for services to start..."
sleep 60

# Health check
if curl -f http://localhost:8081/health/ready; then
    echo "VSS Engine is ready!"
    
    # Send notification (optional)
    # aws sns publish --topic-arn "arn:aws:sns:us-east-1:123456789012:vss-notifications" \
    #   --message "VSS Engine started successfully on $(hostname) at $(date)"
else
    echo "VSS Engine failed to start"
    exit 1
fi

echo "VSS Engine setup completed at $(date)" 