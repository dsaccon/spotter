# Pass in instance ID as first arg when running script
export INST_ID=$1
RESP="x"$(aws ec2 start-instances --instance-ids $INST_ID)

if [[ $RESP == 'x' ]]; then
    exit 1
fi

echo 'Waiting for spot instance to start up. Should take approx 30s'
aws ec2 wait instance-running --instance-ids $INST_ID
sleep 10

IP_ADDR=$(aws ec2 describe-instances --region us-west-2 --instance-ids $INST_ID --query "Reservations[*].Instances[*].PublicDnsName" --output=text)

CMD="~/sharpe/sharpe/datamgmt/bt_spot_init.sh $2 $3"

ssh -t -i ~/atg_oregon.pem -o StrictHostKeyChecking=no ubuntu@$IP_ADDR $CMD

echo ''
echo 'Instance public DNS: '$IP_ADDR
echo ''
exit 0
