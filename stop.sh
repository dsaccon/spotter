# Pass in instance ID as first arg when running script
export INST_ID=$1

aws ec2 stop-instances --instance-ids $INST_ID
