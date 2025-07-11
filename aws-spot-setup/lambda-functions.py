import json
import boto3
import os
from datetime import datetime

# Initialize AWS clients
ec2 = boto3.client('ec2')
ssm = boto3.client('ssm')

def lambda_handler(event, context):
    """
    Lambda function to launch or terminate VSS spot instances
    Triggered by EventBridge rules
    """
    
    try:
        # Determine action based on function name
        function_name = context.function_name
        
        if 'Launch' in function_name:
            return launch_spot_instance(event, context)
        elif 'Terminate' in function_name:
            return terminate_spot_instance(event, context)
        else:
            return {
                'statusCode': 400,
                'body': json.dumps('Unknown function action')
            }
            
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def launch_spot_instance(event, context):
    """Launch VSS spot instance"""
    
    print(f"Launching VSS spot instance at {datetime.now()}")
    
    # Get configuration from environment variables
    launch_template_id = os.environ.get('LAUNCH_TEMPLATE_ID')
    spot_price = os.environ.get('SPOT_PRICE', '0.25')
    openai_api_key = os.environ.get('OPENAI_API_KEY')
    
    if not launch_template_id:
        raise ValueError("LAUNCH_TEMPLATE_ID environment variable not set")
    
    if not openai_api_key:
        raise ValueError("OPENAI_API_KEY environment variable not set")
    
    # Encode startup script with OpenAI API key
    startup_script = f"""#!/bin/bash
# Set OpenAI API key
export OPENAI_API_KEY="{openai_api_key}"

# Run the main startup script
curl -s https://raw.githubusercontent.com/your-repo/video-search-and-summarization/main/aws-spot-setup/startup-script.sh | bash
"""
    
    import base64
    user_data = base64.b64encode(startup_script.encode()).decode()
    
    # Check if instance is already running
    existing_instances = ec2.describe_instances(
        Filters=[
            {'Name': 'tag:Name', 'Values': ['VSS-Spot-Instance']},
            {'Name': 'instance-state-name', 'Values': ['running', 'pending']}
        ]
    )
    
    if existing_instances['Reservations']:
        print("VSS spot instance already running")
        return {
            'statusCode': 200,
            'body': json.dumps('VSS spot instance already running')
        }
    
    # Launch spot instance
    response = ec2.run_instances(
        LaunchTemplate={
            'LaunchTemplateId': launch_template_id,
            'Version': '$Latest'
        },
        MinCount=1,
        MaxCount=1,
        InstanceMarketOptions={
            'MarketType': 'spot',
            'SpotOptions': {
                'MaxPrice': spot_price,
                'SpotInstanceType': 'one-time'
            }
        },
        UserData=user_data
    )
    
    instance_id = response['Instances'][0]['InstanceId']
    
    print(f"Launched spot instance: {instance_id}")
    
    # Add additional tags
    ec2.create_tags(
        Resources=[instance_id],
        Tags=[
            {'Key': 'LaunchedAt', 'Value': datetime.now().isoformat()},
            {'Key': 'Purpose', 'Value': 'Talentora-VSS-POC'}
        ]
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'VSS spot instance launched successfully',
            'instance_id': instance_id,
            'spot_price': spot_price
        })
    }

def terminate_spot_instance(event, context):
    """Terminate VSS spot instance"""
    
    print(f"Terminating VSS spot instance at {datetime.now()}")
    
    # Find running VSS instances
    response = ec2.describe_instances(
        Filters=[
            {'Name': 'tag:Name', 'Values': ['VSS-Spot-Instance']},
            {'Name': 'instance-state-name', 'Values': ['running', 'pending']}
        ]
    )
    
    if not response['Reservations']:
        print("No running VSS spot instances found")
        return {
            'statusCode': 200,
            'body': json.dumps('No running VSS spot instances found')
        }
    
    # Terminate instances
    instance_ids = []
    for reservation in response['Reservations']:
        for instance in reservation['Instances']:
            instance_ids.append(instance['InstanceId'])
    
    if instance_ids:
        ec2.terminate_instances(InstanceIds=instance_ids)
        print(f"Terminated instances: {instance_ids}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'VSS spot instances terminated successfully',
            'terminated_instances': instance_ids
        })
    }

# Lambda function for cost monitoring
def cost_monitor_handler(event, context):
    """Monitor daily costs and send alerts"""
    
    try:
        # Get cost data from Cost Explorer
        ce = boto3.client('ce')
        
        from datetime import datetime, timedelta
        
        end_date = datetime.now().strftime('%Y-%m-%d')
        start_date = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')
        
        response = ce.get_cost_and_usage(
            TimePeriod={
                'Start': start_date,
                'End': end_date
            },
            Granularity='DAILY',
            Metrics=['BlendedCost'],
            GroupBy=[
                {
                    'Type': 'DIMENSION',
                    'Key': 'SERVICE'
                }
            ]
        )
        
        ec2_cost = 0
        for result in response['ResultsByTime']:
            for group in result['Groups']:
                if 'EC2' in group['Keys'][0]:
                    ec2_cost += float(group['Metrics']['BlendedCost']['Amount'])
        
        # Send alert if cost exceeds threshold
        cost_threshold = float(os.environ.get('DAILY_COST_THRESHOLD', '10.0'))
        
        if ec2_cost > cost_threshold:
            # Send SNS notification
            sns = boto3.client('sns')
            topic_arn = os.environ.get('SNS_TOPIC_ARN')
            
            if topic_arn:
                sns.publish(
                    TopicArn=topic_arn,
                    Message=f"Daily EC2 cost exceeded threshold: ${ec2_cost:.2f} > ${cost_threshold:.2f}",
                    Subject="VSS Spot Instance Cost Alert"
                )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'daily_ec2_cost': ec2_cost,
                'threshold': cost_threshold,
                'alert_sent': ec2_cost > cost_threshold
            })
        }
        
    except Exception as e:
        print(f"Cost monitoring error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Cost monitoring error: {str(e)}')
        } 