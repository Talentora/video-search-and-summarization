#!/bin/bash
# VSS Spot Instance Deployment Script
# Sets up automated 8 PM EST to 3 AM EST spot instance schedule

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 VSS Spot Instance Deployment Script${NC}"
echo -e "${BLUE}Setting up automated 8 PM EST to 3 AM EST schedule${NC}"
echo

# Configuration
REGION=${AWS_REGION:-us-east-1}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
KEY_PAIR_NAME=${KEY_PAIR_NAME:-""}
OPENAI_API_KEY=${OPENAI_API_KEY:-""}
SPOT_PRICE=${SPOT_PRICE:-"0.25"}
DAILY_COST_THRESHOLD=${DAILY_COST_THRESHOLD:-"10.0"}

# Validate requirements
if [ -z "$KEY_PAIR_NAME" ]; then
    echo -e "${RED}❌ KEY_PAIR_NAME environment variable is required${NC}"
    echo "Example: export KEY_PAIR_NAME=my-key-pair"
    exit 1
fi

if [ -z "$OPENAI_API_KEY" ]; then
    echo -e "${RED}❌ OPENAI_API_KEY environment variable is required${NC}"
    echo "Example: export OPENAI_API_KEY=sk-..."
    exit 1
fi

echo -e "${GREEN}✅ Configuration validated${NC}"
echo "Region: $REGION"
echo "Account ID: $ACCOUNT_ID"
echo "Key Pair: $KEY_PAIR_NAME"
echo "Spot Price: $SPOT_PRICE"
echo

# Function to wait for user confirmation
confirm() {
    read -p "$1 (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
}

# Step 1: Create IAM roles and policies
echo -e "${BLUE}📝 Step 1: Creating IAM roles and policies${NC}"

# Create EC2 instance profile
aws iam create-role --role-name EC2SpotInstanceRole --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}' --output text > /dev/null 2>&1 || echo "Role may already exist"

# Attach policies to EC2 role
aws iam attach-role-policy --role-name EC2SpotInstanceRole --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam attach-role-policy --role-name EC2SpotInstanceRole --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy

# Create custom policy for EC2 self-termination
aws iam put-role-policy --role-name EC2SpotInstanceRole --policy-name EC2SelfTerminatePolicy --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:TerminateInstances",
                "ec2:DescribeInstances"
            ],
            "Resource": "*"
        }
    ]
}'

# Create instance profile
aws iam create-instance-profile --instance-profile-name EC2SpotInstanceProfile --output text > /dev/null 2>&1 || echo "Instance profile may already exist"
aws iam add-role-to-instance-profile --instance-profile-name EC2SpotInstanceProfile --role-name EC2SpotInstanceRole > /dev/null 2>&1 || echo "Role may already be added"

# Create Lambda execution role
aws iam create-role --role-name LambdaSpotInstanceRole --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}' --output text > /dev/null 2>&1 || echo "Lambda role may already exist"

# Attach policies to Lambda role
aws iam attach-role-policy --role-name LambdaSpotInstanceRole --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# Create custom policy for Lambda
aws iam put-role-policy --role-name LambdaSpotInstanceRole --policy-name LambdaSpotInstancePolicy --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:*",
                "ce:GetCostAndUsage",
                "sns:Publish"
            ],
            "Resource": "*"
        }
    ]
}'

# Create EventBridge execution role
aws iam create-role --role-name EventBridgeExecutionRole --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "events.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}' --output text > /dev/null 2>&1 || echo "EventBridge role may already exist"

aws iam put-role-policy --role-name EventBridgeExecutionRole --policy-name EventBridgeLambdaPolicy --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "lambda:InvokeFunction"
            ],
            "Resource": "*"
        }
    ]
}'

echo -e "${GREEN}✅ IAM roles and policies created${NC}"

# Step 2: Create security group
echo -e "${BLUE}🔒 Step 2: Creating security group${NC}"

# Get default VPC
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query "Vpcs[0].VpcId" --output text)
echo "Using VPC: $VPC_ID"

# Create security group
SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --group-name vss-spot-security-group \
    --description "Security group for VSS spot instances" \
    --vpc-id $VPC_ID \
    --query "GroupId" --output text 2>/dev/null || \
    aws ec2 describe-security-groups --group-names vss-spot-security-group --query "SecurityGroups[0].GroupId" --output text)

echo "Security Group ID: $SECURITY_GROUP_ID"

# Add inbound rules
aws ec2 authorize-security-group-ingress \
    --group-id $SECURITY_GROUP_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 > /dev/null 2>&1 || echo "SSH rule may already exist"

aws ec2 authorize-security-group-ingress \
    --group-id $SECURITY_GROUP_ID \
    --protocol tcp \
    --port 8080 \
    --cidr 0.0.0.0/0 > /dev/null 2>&1 || echo "Frontend port rule may already exist"

aws ec2 authorize-security-group-ingress \
    --group-id $SECURITY_GROUP_ID \
    --protocol tcp \
    --port 8081 \
    --cidr 0.0.0.0/0 > /dev/null 2>&1 || echo "Backend port rule may already exist"

echo -e "${GREEN}✅ Security group created${NC}"

# Step 3: Create launch template
echo -e "${BLUE}🚀 Step 3: Creating launch template${NC}"

# Get default subnet
SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[0].SubnetId" --output text)
echo "Using Subnet: $SUBNET_ID"

# Encode startup script
STARTUP_SCRIPT=$(base64 -w 0 startup-script.sh)

# Create launch template
LAUNCH_TEMPLATE_ID=$(aws ec2 create-launch-template \
    --launch-template-name vss-spot-template \
    --launch-template-data '{
        "ImageId": "ami-0c7217cdde317cfec",
        "InstanceType": "g4dn.xlarge",
        "KeyName": "'$KEY_PAIR_NAME'",
        "SecurityGroupIds": ["'$SECURITY_GROUP_ID'"],
        "IamInstanceProfile": {
            "Name": "EC2SpotInstanceProfile"
        },
        "BlockDeviceMappings": [
            {
                "DeviceName": "/dev/sda1",
                "Ebs": {
                    "VolumeSize": 100,
                    "VolumeType": "gp3",
                    "DeleteOnTermination": true
                }
            }
        ],
        "UserData": "'$STARTUP_SCRIPT'",
        "TagSpecifications": [
            {
                "ResourceType": "instance",
                "Tags": [
                    {"Key": "Name", "Value": "VSS-Spot-Instance"},
                    {"Key": "Project", "Value": "Talentora-POC"},
                    {"Key": "AutoShutdown", "Value": "3AM-EST"}
                ]
            }
        ]
    }' \
    --query "LaunchTemplate.LaunchTemplateId" --output text 2>/dev/null || \
    aws ec2 describe-launch-templates --launch-template-names vss-spot-template --query "LaunchTemplates[0].LaunchTemplateId" --output text)

echo "Launch Template ID: $LAUNCH_TEMPLATE_ID"
echo -e "${GREEN}✅ Launch template created${NC}"

# Step 4: Create Lambda functions
echo -e "${BLUE}⚡ Step 4: Creating Lambda functions${NC}"

# Create deployment package
zip -r lambda-deployment.zip lambda-functions.py > /dev/null

# Create Launch function
aws lambda create-function \
    --function-name LaunchVSSSpotInstance \
    --runtime python3.9 \
    --role arn:aws:iam::$ACCOUNT_ID:role/LambdaSpotInstanceRole \
    --handler lambda-functions.lambda_handler \
    --zip-file fileb://lambda-deployment.zip \
    --timeout 60 \
    --environment Variables="{
        LAUNCH_TEMPLATE_ID=$LAUNCH_TEMPLATE_ID,
        SPOT_PRICE=$SPOT_PRICE,
        OPENAI_API_KEY=$OPENAI_API_KEY
    }" > /dev/null 2>&1 || echo "Launch function may already exist"

# Create Terminate function
aws lambda create-function \
    --function-name TerminateVSSSpotInstance \
    --runtime python3.9 \
    --role arn:aws:iam::$ACCOUNT_ID:role/LambdaSpotInstanceRole \
    --handler lambda-functions.lambda_handler \
    --zip-file fileb://lambda-deployment.zip \
    --timeout 60 > /dev/null 2>&1 || echo "Terminate function may already exist"

# Create Cost Monitor function
aws lambda create-function \
    --function-name VSSCostMonitor \
    --runtime python3.9 \
    --role arn:aws:iam::$ACCOUNT_ID:role/LambdaSpotInstanceRole \
    --handler lambda-functions.cost_monitor_handler \
    --zip-file fileb://lambda-deployment.zip \
    --timeout 60 \
    --environment Variables="{
        DAILY_COST_THRESHOLD=$DAILY_COST_THRESHOLD
    }" > /dev/null 2>&1 || echo "Cost monitor function may already exist"

echo -e "${GREEN}✅ Lambda functions created${NC}"

# Step 5: Create EventBridge rules
echo -e "${BLUE}📅 Step 5: Creating EventBridge rules${NC}"

# Create start rule (8 PM EST = 1 AM UTC)
aws events put-rule \
    --name start-vss-spot-instance \
    --description "Start VSS spot instance at 8 PM EST daily" \
    --schedule-expression "cron(0 1 * * ? *)" \
    --state ENABLED > /dev/null

# Add target to start rule
aws events put-targets \
    --rule start-vss-spot-instance \
    --targets "Id=1,Arn=arn:aws:lambda:$REGION:$ACCOUNT_ID:function:LaunchVSSSpotInstance" > /dev/null

# Create stop rule (3 AM EST = 8 AM UTC)
aws events put-rule \
    --name stop-vss-spot-instance \
    --description "Stop VSS spot instance at 3 AM EST daily" \
    --schedule-expression "cron(0 8 * * ? *)" \
    --state ENABLED > /dev/null

# Add target to stop rule
aws events put-targets \
    --rule stop-vss-spot-instance \
    --targets "Id=1,Arn=arn:aws:lambda:$REGION:$ACCOUNT_ID:function:TerminateVSSSpotInstance" > /dev/null

# Create daily cost monitoring rule
aws events put-rule \
    --name daily-cost-monitor \
    --description "Monitor daily costs" \
    --schedule-expression "cron(0 9 * * ? *)" \
    --state ENABLED > /dev/null

aws events put-targets \
    --rule daily-cost-monitor \
    --targets "Id=1,Arn=arn:aws:lambda:$REGION:$ACCOUNT_ID:function:VSSCostMonitor" > /dev/null

# Add Lambda permissions for EventBridge
aws lambda add-permission \
    --function-name LaunchVSSSpotInstance \
    --statement-id allow-eventbridge-launch \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn arn:aws:events:$REGION:$ACCOUNT_ID:rule/start-vss-spot-instance > /dev/null 2>&1 || echo "Launch permission may already exist"

aws lambda add-permission \
    --function-name TerminateVSSSpotInstance \
    --statement-id allow-eventbridge-terminate \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn arn:aws:events:$REGION:$ACCOUNT_ID:rule/stop-vss-spot-instance > /dev/null 2>&1 || echo "Terminate permission may already exist"

aws lambda add-permission \
    --function-name VSSCostMonitor \
    --statement-id allow-eventbridge-cost-monitor \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn arn:aws:events:$REGION:$ACCOUNT_ID:rule/daily-cost-monitor > /dev/null 2>&1 || echo "Cost monitor permission may already exist"

echo -e "${GREEN}✅ EventBridge rules created${NC}"

# Step 6: Create manual launch script
echo -e "${BLUE}🎮 Step 6: Creating manual control scripts${NC}"

cat > manual-launch.sh << EOF
#!/bin/bash
echo "🚀 Manually launching VSS spot instance..."
aws lambda invoke --function-name LaunchVSSSpotInstance --payload '{}' response.json
cat response.json | jq .
rm response.json
EOF

cat > manual-terminate.sh << EOF
#!/bin/bash
echo "🛑 Manually terminating VSS spot instance..."
aws lambda invoke --function-name TerminateVSSSpotInstance --payload '{}' response.json
cat response.json | jq .
rm response.json
EOF

cat > check-status.sh << EOF
#!/bin/bash
echo "📊 Checking VSS spot instance status..."
aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=VSS-Spot-Instance" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
    --query "Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress,LaunchTime]" \
    --output table
EOF

chmod +x manual-launch.sh manual-terminate.sh check-status.sh

echo -e "${GREEN}✅ Manual control scripts created${NC}"

# Cleanup
rm -f lambda-deployment.zip

echo
echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
echo
echo -e "${BLUE}📋 Summary:${NC}"
echo "• Spot instances will launch automatically at 8 PM EST (1 AM UTC)"
echo "• Instances will terminate automatically at 3 AM EST (8 AM UTC)"
echo "• Max spot price: \$${SPOT_PRICE}/hour"
echo "• Daily cost threshold: \$${DAILY_COST_THRESHOLD}"
echo "• VSS Engine will be available at http://[instance-ip]:8080"
echo
echo -e "${BLUE}🎮 Manual Controls:${NC}"
echo "• Launch now: ./manual-launch.sh"
echo "• Terminate now: ./manual-terminate.sh"
echo "• Check status: ./check-status.sh"
echo
echo -e "${BLUE}💰 Cost Estimate:${NC}"
echo "• 7 hours/day × \$${SPOT_PRICE}/hour = \$$(echo "7 * $SPOT_PRICE" | bc)/day"
echo "• Monthly cost: ~\$$(echo "7 * $SPOT_PRICE * 30" | bc)/month"
echo
echo -e "${BLUE}📈 Next Steps:${NC}"
echo "1. Test manual launch: ./manual-launch.sh"
echo "2. Wait ~5 minutes for instance to be ready"
echo "3. Access VSS Engine at http://[instance-ip]:8080"
echo "4. Upload a test interview video"
echo "5. Verify summarization and chat functionality"
echo
echo -e "${GREEN}Happy testing! 🚀${NC}" 