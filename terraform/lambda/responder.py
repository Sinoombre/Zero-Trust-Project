import os
import json

import boto3  # AWS SDK for Python
from botocore.exceptions import ClientError

ec2 = boto3.client("ec2", region_name="us-east-2")
sns = boto3.client("sns", region_name="us-east-2")

EMPTY_SG_ID = os.environ["EMPTY_SG_ID"]
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]


def lambda_handler(event, context):
    print(json.dumps(event))  # queda en CloudWatch Logs, útil para depurar
    finding = event["detail"]
    resource = finding.get("resource", {})
    instance_id = resource.get("instanceDetails", {}).get("instanceId")

    if resource.get("resourceType") != "Instance" or not instance_id:
        estado = "No se aisló nada: el finding no corresponde a una instancia EC2."
    else:
        try:
            # Aislar las instancias comprometidas en security groups vacíos
            ec2.modify_instance_attribute(
                InstanceId=instance_id, Groups=[EMPTY_SG_ID],)
            estado = f"Instancia {instance_id} aislada."
        except ClientError as e:
            estado = f"No se pudo aislar {instance_id}: {e.response['Error']['Code']}"

    # Notificar al equipo
    sns.publish(TopicArn=SNS_TOPIC_ARN, Message=(
        f"{estado}\n" f"Tipo de finding: {finding.get('type', 'desconocido')}\n" f"Severidad: {finding.get('severity')}"), 
        Subject="GuardDuty HIGH",)
