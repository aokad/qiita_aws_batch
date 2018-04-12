#! /bin/bash
set -x
set -o errexit
set -o nounset

export AWS_ACCOUNTID=123456789012
export AWS_REGION=ap-northeast-1
export SUBNET1=subnet-123a456b
export SUBNET2=subnet-789c012d
export SUBNET3=subnet-345e678f
export SECURITYGROUPID=sg-11335577
export KEY_NAME=mykey
export S3_BUCKET=mybucket
export AMI_ID=ami-a99d8ad5

####################################
# クラスターの作成
####################################

aws ecs create-cluster \
    --cluster-name myCluster \
    > create-cluster.log

CLUSTER_ARN=$(jq -r '.cluster.clusterArn' create-cluster.log)

####################################
# タスク定義を作成
####################################

# ロググループを作成
LOG_GROUP_NAME=mytask-$(date "+%Y%m%d-%H%M%S%Z")
aws logs create-log-group --log-group-name ${LOG_GROUP_NAME}

# コンテナ定義を作成
ECSTASKROLE="arn:aws:iam::${AWS_ACCOUNTID}:role/AmazonECSTaskS3FullAccess"

cat << EOF > task_definition.json
{
    "containerDefinitions": [
        {
            "name": "mytask-definision",
            "image": "aokad/aws-wordcount:0.0.1",
            "cpu": 1,
            "memory": 800,
            "essential": true,
            "entryPoint": [
                "ash",
                "-c"
            ],
            "command": [
                "ash run.sh \${INPUT} \${OUTPUT}"
            ],
            "environment": [
                {
                  "name": "INPUT",
                  "value": ""
                },
                {
                  "name": "OUTPUT",
                  "value": ""
                }
            ],
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "${LOG_GROUP_NAME}",
                    "awslogs-region": "${AWS_REGION}",
                    "awslogs-stream-prefix": "ecs-test"
                }
            }
        }
    ],
    "taskRoleArn": "${ECSTASKROLE}",
    "family": "mytask"
}
EOF

# タスク定義を作成
aws ecs register-task-definition \
    --cli-input-json file://task_definition.json \
    > register-task-definition.log

TASK_DEFINITION_ARN=$(jq -r '.taskDefinition.taskDefinitionArn' register-task-definition.log)

####################################
# EC2 インスタンスを起動する
####################################

# ユーザデータを作成
cat << EOF > userdata.sh
Content-Type: multipart/mixed; boundary="==BOUNDARY=="
MIME-Version: 1.0

--==BOUNDARY==
Content-Type: text/cloud-boothook; charset="us-ascii"

# Install nfs-utils
cloud-init-per once yum_update yum update -y
cloud-init-per once install_nfs_utils yum install -y nfs-utils

cloud-init-per once docker_options echo 'OPTIONS="\${OPTIONS} --storage-opt dm.basesize=30G"' >> /etc/sysconfig/docker

#!/bin/bash
# Set any ECS agent configuration options
echo "ECS_CLUSTER=${CLUSTER_ARN}" >> /etc/ecs/ecs.config

--==BOUNDARY==--
EOF

# インスタンスを起動
aws ec2 run-instances \
  --image-id ${AMI_ID} \
  --security-group-ids ${SECURITYGROUPID} \
  --key-name ${KEY_NAME} \
  --user-data "file://userdata.sh" \
  --iam-instance-profile Name="ecsInstanceRole" \
  --instance-type t2.micro \
  --block-device-mappings "[{\"DeviceName\":\"/dev/xvdcz\",\"Ebs\":{\"VolumeSize\":30,\"DeleteOnTermination\":true}}]" \
  --count 1 \
  > run-instances.log

INSTANCE_ID=$(jq -r '.Instances[0].InstanceId' run-instances.log)

# 起動完了を待つ
aws ec2 wait instance-running --instance-ids ${INSTANCE_ID}
aws ec2 wait instance-status-ok --include-all-instances --instance-ids ${INSTANCE_ID}

# 起動したインスタンスに名前を付ける
aws ec2 create-tags --resources ${INSTANCE_ID} --tags Key=Name,Value=ecs-task-instance

####################################
# タスク実行
####################################

# サンプルを S3 にアップロード
cat << EOF > Humpty.txt
Humpty Dumpty sat on a wall,
Humpty Dumpty had a great fall.
All the king's horses and all the king's men
Couldn't put Humpty together again.
EOF

aws s3 cp Humpty.txt s3://${S3_BUCKET}/

# タスク実行
cat << EOF > containerOverrides.json
{
    "containerOverrides": [
        {
            "name": "mytask-definision",
            "environment": [
                {
                    "name": "INPUT",
                    "value": "s3://${S3_BUCKET}/Humpty.txt"
                },
                {
                    "name": "OUTPUT",
                    "value": "s3://${S3_BUCKET}/Humpty.count.ecs.txt"
                }
            ]
    }]
}
EOF

aws ecs run-task \
    --cluster ${CLUSTER_ARN} \
    --task-definition ${TASK_DEFINITION_ARN} \
    --overrides file://containerOverrides.json \
    > run-task.log

TASK_ARN=$(jq -r '.tasks[0].taskArn' run-task.log)

# タスク終了を待つ
while :
do
    aws ecs describe-tasks --tasks ${TASK_ARN} --cluster ${CLUSTER_ARN} \
        > describe-tasks.log

    TASK_STATE=$(jq -r '.tasks[0].lastStatus' describe-tasks.log)

    if test "${TASK_STATE}" = "STOPPED"; then
        break
    fi

    aws ecs wait tasks-stopped --tasks ${TASK_ARN} --cluster ${CLUSTER_ARN}
done

####################################
# 片付け
####################################

# EC2 インスタンスを削除
aws ec2 terminate-instances --instance-ids ${INSTANCE_ID}
aws ec2 wait instance-terminated --instance-ids ${INSTANCE_ID}

# タスク定義を削除
aws ecs deregister-task-definition --task-definition ${TASK_DEFINITION_ARN}

# クラスターを削除
aws ecs delete-cluster --cluster ${CLUSTER_ARN}
