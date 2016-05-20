#!/bin/bash



registry_in_hosts() {
  grep " *myregistry" /etc/hosts &> /dev/null
}



registry_ip_in_hosts() {
  local registry_ip=$1
  grep "^$registry_ip *myregistry" /etc/hosts &> /dev/null
}



registry_in_docker_machine() {
  docker-machine ls | grep "^myregistry" | grep amazonec2 &> /dev/null
}



# check if myregistry is running on amazonec2 and get its IP

HAS_REGISTRY=$(registry_in_docker_machine)

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

if [ $(registry_ip_in_hosts) -ne 0 ] ; then

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



