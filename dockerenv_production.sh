#!/bin/bash

# include some helper function used in both training and production environment
. helpers.include

OUT=${1:-/dev/null}
REGION=${2:-eu-central-1}

check_preconditions



usage production

cat << EOF
  PRECONDITIONS:

  - have sudo write access to /etc/hosts
  - have an AWS account

  if you can meet all preconditions, press RETURN
EOF

read



# make sure there is a proper aws configuration

echo '*** please make sure all these values are set. if they are, just confirm them:'

aws configure

vpcid=$(aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)



# check if myregistry is running on amazonec2 and get its IP

docker-machine ls | grep "^myregistry" | grep amazonec2 &> /dev/null
HAS_REGISTRY=$?

# if not, create a new registry

if [ $HAS_REGISTRY -ne 0 ] ; then

  # is a localhost myregistry still running?
  docker-machine ip myregistry &> /dev/null
  
  if [ $? -eq 0 ] ; then
    # if so, shut it down
    echo "*** destroying existing local registry"
    docker-machine stop myregistry  &> /dev/null
    docker-machine rm -f myregistry &> /dev/null
  fi

  echo '*** create new VM ”myregistry" in AWS '$REGION'. this may take a few minutes.'
  
  docker-machine create --driver amazonec2 --amazonec2-region $REGION myregistry &> $OUT
fi

REGISTRY_IP=$(docker-machine ip myregistry)
eval $(docker-machine env myregistry)
  
if [ $HAS_REGISTRY -eq 0 ] ; then
  echo "*** using existing \"myregistry\" VM with ip $REGISTRY_IP"
fi
  

  
# if we had to create a new myregistry VM, put it into /etc/hosts

grep "^$REGISTRY_IP *myregistry" /etc/hosts &> /dev/null
if [ $? -ne 0 ] ; then

  echo "*** put \"myregistry\" ip $REGISTRY_IP into /etc/hosts (backup in /tmp/hosts)"

  cp /etc/hosts /tmp
  put_entry_into_etc_hosts $REGISTRY_IP  myregistry
fi



# start new registry on myregistry:5000 in a docker container

if [ $HAS_REGISTRY -ne 0 ] ; then

  echo '*** docker run private registry on new VM "myregistry"'
  
  docker run -d -p 5000:5000 --restart=always --name myregistry registry:2 &> $OUT
  
  echo '*** add security rule and group for registry port 5000'
  
  # cloudformation would have been an equal (/better?) solution here
  aws ec2 create-security-group --group-name docker-registry --vpc-id $vpcid --description "registry sg" &> $OUT
  aws ec2 authorize-security-group-ingress --group-name docker-registry --protocol tcp --port 5000 --cidr 0.0.0.0/0 &> $OUT
  GROUP1=$(aws ec2 describe-security-groups --output text --filters Name=group-name,Values=docker-machine --query 'SecurityGroups[*].GroupId')
  GROUP2=$(aws ec2 describe-security-groups --output text --filters Name=group-name,Values=docker-registry --query 'SecurityGroups[*].GroupId')
  INSTANCE=$(
    aws ec2 describe-instances --output text \
    --filters Name=key-name,Values=myregistry Name=instance-state-name,Values=running \
    --query 'Reservations[*].Instances[*].InstanceId'
  )
  aws ec2 modify-instance-attribute --instance-id $INSTANCE --groups $GROUP1 $GROUP2 &> $OUT
fi



download_static_zip



# build a custom nginx image. the nginx will serve static content 
# from "/static" (see nginx/Dockerfile) and otherwise proxy_pass to a
# jetty appication server (see below)

echo "*** build and push custom nginx image to myregistry"

docker build --no-cache -t myregistry:5000/mynginx:latest nginx &> $OUT
docker push myregistry:5000/mynginx:latest &> $OUT



download_application_war



# build custom jetty image with application from .war as ROOT application

echo "*** build and push custom jetty image to myregistry"

docker build --no-cache -t myregistry:5000/myjetty:latest jetty &> $OUT
docker push myregistry:5000/myjetty:latest &> $OUT



# create new dockerenv stack using cloud formation

echo "*** create dockerenv stack on AWS $REGION using cloudformation"

./add_user_data.sh $REGISTRY_IP dockerenv.yaml dockerenv.tmpl > dockerenv.json

aws cloudformation create-stack \
  --region $REGION \
  --stack-name dockerenv \
  --template-body file://dockerenv.json \
  --parameters ParameterKey=myVpcId,ParameterValue=$vpcid &> $OUT

echo "*** please wait for stack to complete. this may take a few minutes."
aws cloudformation wait stack-create-complete --stack-name dockerenv --output text --no-paginate &> $OUT

LOAD_BALANCER_NAME=$(aws cloudformation describe-stack-resources --stack-name dockerenv --query 'StackResources[?ResourceType==`AWS::ElasticLoadBalancing::LoadBalancer`]'.PhysicalResourceId --output text)

HOSTED_ZONE_NAME=$(aws elb describe-load-balancers --load-balancer-names $LOAD_BALANCER_NAME --query 'LoadBalancerDescriptions[0].CanonicalHostedZoneName' --output text)

cat << EOF
*** stack complete. you can now check

  http://$HOSTED_ZONE_NAME

in your browser.

NOTE
before you call the script again, make sure to detroy the
dockerenv cloudformation stack via AWS console.

if you destroy the myregistry as well, make sure to clean up
the corresponding security groups, too.
EOF
