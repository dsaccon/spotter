# Pass in instance ID as first arg when running script
export INST_ID=$1

IP_ADDR=$(aws ec2 describe-instances --region us-west-2 --instance-ids $INST_ID --query "Reservations[*].Instances[*].PublicDnsName" --output=text)

ssh -i ~/atg_oregon.pem -o StrictHostKeyChecking=no ubuntu@$IP_ADDR
