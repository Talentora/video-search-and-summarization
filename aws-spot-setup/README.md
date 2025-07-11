# AWS Spot Instance Deployment for VSS Engine

🚀 **Automated 8 PM EST to 3 AM EST deployment** for Talentora's interview analysis POC

## 💰 Cost Estimate
- **7 hours/day × $0.25/hour = $1.75/day**
- **Monthly cost: ~$52.50/month**
- **60-70% cheaper than on-demand instances**

## 🎯 Perfect for Interview Analysis
- **Video summarization** with OpenAI GPT-4
- **Behavioral insights** extraction
- **Key moments** identification
- **Automated transcription** 
- **Interactive chat** with video content

## 🚀 Quick Setup

### Prerequisites
1. **AWS Account** with appropriate permissions
2. **AWS CLI** installed and configured
3. **OpenAI API Key** 
4. **SSH Key Pair** created in AWS EC2

### Step 1: Set Environment Variables
```bash
export KEY_PAIR_NAME="your-key-pair-name"
export OPENAI_API_KEY="sk-your-openai-api-key"
export SPOT_PRICE="0.25"  # Optional: Max price per hour
export DAILY_COST_THRESHOLD="10.0"  # Optional: Daily cost alert threshold
```

### Step 2: Run Deployment Script
```bash
cd aws-spot-setup
chmod +x deploy.sh
./deploy.sh
```

### Step 3: Test Manual Launch
```bash
./manual-launch.sh
```

### Step 4: Check Status
```bash
./check-status.sh
```

### Step 5: Access VSS Engine
Once the instance is running:
- Frontend: `http://[instance-ip]:8080`
- Backend API: `http://[instance-ip]:8081`

## 🕐 Schedule Details

### Automatic Schedule
- **Start**: 8:00 PM EST (1:00 AM UTC) daily
- **Stop**: 3:00 AM EST (8:00 AM UTC) daily
- **Duration**: 7 hours per day
- **Days**: Every day (can be modified)

### Why This Schedule?
- **Off-peak hours** = Lower spot prices
- **Minimal interruption** risk
- **Perfect for overnight processing**
- **Ready for morning testing**

## 💡 Manual Controls

### Launch Instance Now
```bash
./manual-launch.sh
```

### Terminate Instance Now
```bash
./manual-terminate.sh
```

### Check Instance Status
```bash
./check-status.sh
```

## 📊 Monitoring & Alerts

### Cost Monitoring
- **Daily cost tracking** via CloudWatch
- **Email alerts** when threshold exceeded
- **Automatic termination** safeguards

### Instance Health
- **Spot interruption** monitoring
- **Automatic graceful shutdown**
- **Health check endpoints**

## 🔧 Configuration Options

### Modify Schedule
Edit EventBridge rules in AWS Console:
- `start-vss-spot-instance`: Change start time
- `stop-vss-spot-instance`: Change stop time

### Adjust Spot Price
Update Lambda environment variable:
```bash
aws lambda update-function-configuration \
  --function-name LaunchVSSSpotInstance \
  --environment Variables="{SPOT_PRICE=0.20}"
```

### Change Instance Type
Update launch template:
```bash
aws ec2 modify-launch-template \
  --launch-template-name vss-spot-template \
  --launch-template-data '{"InstanceType":"g4dn.2xlarge"}'
```

## 🎮 Usage for Interview Analysis

### 1. Upload Interview Video
- Access frontend at `http://[instance-ip]:8080`
- Upload MP4/MOV interview file
- Wait for processing (2-5 minutes)

### 2. Get Behavioral Insights
- Review automated summary
- Focus on:
  - Communication style
  - Confidence indicators
  - Key responses
  - Engagement metrics

### 3. Interactive Analysis
- Use chat interface to ask:
  - "What soft skills did the candidate demonstrate?"
  - "How did they handle behavioral questions?"
  - "What are their key strengths?"

### 4. Export Results
- Save summaries and insights
- Export for further analysis

## 🔒 Security Features

### Network Security
- **Security groups** restrict access
- **VPC isolation** for resources
- **IAM roles** with minimal permissions

### Data Protection
- **Automatic cleanup** on termination
- **No persistent storage** of sensitive data
- **Encrypted communications**

### Cost Protection
- **Spot price limits** prevent overruns
- **Daily cost monitoring**
- **Automatic termination** safeguards

## 🚨 Troubleshooting

### Instance Won't Start
1. Check spot price availability
2. Verify IAM permissions
3. Check security group rules
4. Review CloudWatch logs

### VSS Engine Not Accessible
1. Ensure ports 8080/8081 are open
2. Check instance public IP
3. Verify Docker containers are running
4. Check startup logs: `/var/log/vss-startup.log`

### High Costs
1. Check daily cost reports
2. Verify termination schedule
3. Monitor spot price fluctuations
4. Adjust instance type if needed

## 📈 Optimization Tips

### Reduce Costs
- **Lower spot price** bid during testing
- **Shorter schedules** for limited testing
- **Smaller instance types** for basic testing

### Improve Performance
- **Preload Docker images** for faster startup
- **Use larger instances** for heavy processing
- **Multiple availability zones** for better availability

### Enhanced Features
- **S3 integration** for video storage
- **SNS notifications** for status updates
- **CloudWatch dashboards** for monitoring

## 🎯 Next Steps

1. **Test with sample videos** to validate functionality
2. **Customize prompts** for specific interview types
3. **Integrate with hiring workflows**
4. **Scale to multiple instances** if needed
5. **Add custom analytics** for deeper insights

## 🆘 Support

### AWS Resources
- [EC2 Spot Instances Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-spot-instances.html)
- [EventBridge Scheduling](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-schedule-expressions.html)
- [Lambda Functions](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html)

### VSS Engine Resources
- [NVIDIA VSS Documentation](https://docs.nvidia.com/nim/video-search-summarization/)
- [OpenAI API Documentation](https://platform.openai.com/docs)

---

**Happy testing! 🚀 Your automated VSS deployment is ready for Talentora's interview analysis needs.** 