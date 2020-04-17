# Pass in instance ID as first arg when running script
export INST_ID=$1
aws ec2 start-instances --instance-ids $INST_ID

echo Waiting for spot instance to start up...
aws ec2 wait instance-running --instance-ids $INST_ID
sleep 5

IP_ADDR=$(aws ec2 describe-instances --region us-west-2 --instance-ids $INST_ID --query "Reservations[*].Instances[*].PublicDnsName" --output=text)

ssh -i ~/atg_oregon.pem -o StrictHostKeyChecking=no ubuntu@$IP_ADDR
