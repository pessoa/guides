#!/bin/bash
#
# Weave Nginx AWS Demo - Setup Weave and our containers
#

WEAVEDEMO_GROUPNAME=${WEAVEDEMO_GROUPNAME:-weavedemo}
WEAVEDEMO_HOSTCOUNT=${WEAVEDEMO_HOSTCOUNT:-2}
AWS_AMI=${AWS_AMI:-}
SSH_OPTS=${SSH_OPTS:-"-o StrictHostKeyChecking=no"}
DIRNAME=`dirname $0`

if [ $DIRNAME = "." ]; then
    DIRNAME=`pwd`
fi 

MY_KEY=$DIRNAME/$WEAVEDEMO_GROUPNAME-key.pem
WEAVEDEMO_ENVFILE=$DIRNAME/weavedemo.env
KEYPAIR=$WEAVEDEMO_GROUPNAME-key

MY_R_FILTER="Name=instance-state-name,Values=running"
MY_SSH="ssh -i $MY_KEY"
DNS_OFFSET=2
CONTAINER_OFFSET=2
DNS_BASE=10.2.1
APP_BASE=10.3.1

function launchWeave() {

    myHostIP=$1
    myWeaveDnsPeer=$2
    myDnsOffSet=$3

    myDnsIp=$(echo "$DNS_BASE.$myDnsOffSet")

    echo "Launching Weave and WeaveDNS on $myHostIP"

    if [ $myHostIP == $myWeaveDnsPeer ]; then
        $MY_SSH $SSH_OPTS ubuntu@$myHostIP "sudo weave launch"
    else 
        $MY_SSH $SSH_OPTS ubuntu@$myHostIP "sudo weave launch $myWeaveDnsPeer"
    fi

    $MY_SSH $SSH_OPTS ubuntu@$myHostIP "sudo weave launch-dns $myDnsIp/24"

}

function launchApacheDemo() {

    myHostIP=$1
    myContainerOffSet=$2

    myContainerIP=$(echo "$APP_BASE.$myContainerOffSet")
    myDnsName=$(echo "ws.weave.local")

    echo "Launching php app container $myDnsName on $myHostIP with $myContainerIP"

    $MY_SSH $SSH_OPTS ubuntu@$myHostIP "sudo weave run --with-dns $myContainerIP/24 -h $myDnsName pessoa/weave-gs-nginx-apache"
}

function launchNginx() {
    
    myHostIP=$1
    myContainerOffSet=$2

    myContainerIP=$(echo "$APP_BASE.$myContainerOffSet")
    myDnsName=nginx.weave.local

    echo "Launching nginx front end app container $myDnsName on $myHostIP with $myContainerIP"
    $MY_SSH $SSH_OPTS ubuntu@$myHostIP "sudo weave run --with-dns $myContainerIP/24 -ti -h $myDnsName -d -p 80:80 pessoa/weave-gs-nginx-simple"

}

echo "Launching Weave and WeaveDNS on each AWS host"

. $WEAVEDEMO_ENVFILE

TMP_HOSTCOUNT=0

while [ $TMP_HOSTCOUNT -lt $WEAVE_AWS_DEMO_HOSTCOUNT ]; do
    HOST_IP=${WEAVE_AWS_DEMO_HOSTS[$TMP_HOSTCOUNT]}  
    launchWeave $HOST_IP $WEAVE_AWS_DEMO_HOST1 $DNS_OFFSET
    DNS_OFFSET=$(expr $DNS_OFFSET + 1)
    TMP_HOSTCOUNT=$(expr $TMP_HOSTCOUNT + 1)
done

echo "Launching our Nginx front end"

launchNginx $WEAVE_AWS_DEMO_HOST1 $CONTAINER_OFFSET

echo "Launching 3 Simple PHP App Containers on each AWS host"

TMP_HOSTCOUNT=0

while [ $TMP_HOSTCOUNT -lt $WEAVE_AWS_DEMO_HOSTCOUNT ]; do
    HOST_IP=${WEAVE_AWS_DEMO_HOSTS[$TMP_HOSTCOUNT]}  

    while [ `expr $CONTAINER_OFFSET % 3` -ne 0 ]; do   
        launchApacheDemo $HOST_IP $CONTAINER_OFFSET
        CONTAINER_OFFSET=$(expr $CONTAINER_OFFSET + 1 )
    done

    if [ `expr $CONTAINER_OFFSET % 3` -eq 0 ]; then
        launchApacheDemo $HOST_IP $CONTAINER_OFFSET
    fi

    CONTAINER_OFFSET=$(expr $CONTAINER_OFFSET + 1 )
    TMP_HOSTCOUNT=$(expr $TMP_HOSTCOUNT + 1)
done


echo "Launching dnsmasq"
$MY_SSH $SSH_OPTS ubuntu@$WEAVE_AWS_DEMO_HOST1 "sudo weave run --with-dns 10.3.1.1/24 -h dns.weave.local --cap-add=NET_ADMIN andyshinn/dnsmasq"

# Auto Scaling

MIN_SIZE=1
MAX_SIZE=2
PERIOD=120
UP_THRESHOLD=10
DOWN_THRESHOLD=40
REGION=$(aws configure list | grep region | awk '{print $2}')

echo "Create launch config"
aws autoscaling create-launch-configuration --launch-configuration-name lc-auto-cli --image-id ami-b683b0ab --key-name weavedemo-key --security-groups weavedemo --user-data "`cat user-data.sh`" --instance-type t2.micro
echo "Create scaling group"
aws autoscaling create-auto-scaling-group --auto-scaling-group-name asg-auto-cli --launch-configuration-name lc-auto-cli --min-size $MIN_SIZE --max-size $MAX_SIZE --availability-zones "${REGION}a" "${REGION}b"
echo "Create scaling policies"
ARN_SCALEOUT=$(aws autoscaling put-scaling-policy --policy-name scaleout-auto-cli --auto-scaling-group-name asg-auto-cli --scaling-adjustment 1 --adjustment-type ChangeInCapacity | grep -Po '"'"PolicyARN"'"\s*:\s*"\K([^"]*)')
ARN_SCALEIN=$(aws autoscaling put-scaling-policy --policy-name scalein-auto-cli --auto-scaling-group-name asg-auto-cli --scaling-adjustment -1 --adjustment-type ChangeInCapacity | grep -Po '"'"PolicyARN"'"\s*:\s*"\K([^"]*)')
echo "Create alarms"
aws cloudwatch put-metric-alarm --alarm-name AddCapacity --metric-name CPUUtilization --namespace AWS/EC2 --statistic Average --period 120 --threshold $UP_THRESHOLD --comparison-operator GreaterThanOrEqualToThreshold --dimensions "Name=AutoScalingGroupName,Value=asg-auto-cli" --evaluation-periods 2 --alarm-actions $ARN_SCALEOUT
aws cloudwatch put-metric-alarm --alarm-name RemoveCapacity --metric-name CPUUtilization --namespace AWS/EC2 --statistic Average --period 120 --threshold $DOWN_THRESHOLD --comparison-operator LessThanOrEqualToThreshold --dimensions "Name=AutoScalingGroupName,Value=asg-auto-cli" --evaluation-periods 2 --alarm-actions $ARN_SCALEIN
