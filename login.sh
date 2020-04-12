# Pass in instance ID as first arg when running script

if [ -z "$1" ]
then
    echo "No arg passed in. You need to passed in one arg for instance-ID, eg './login i-0c24488afbcf2dd2f'"
    exit 1
fi

export INST_ID=$1

IP_ADDR=$(aws ec2 describe-instances --region us-west-2 --instance-ids $INST_ID --query "Reservations[*].Instances[*].PublicDnsName" --output=text)

ssh -i ~/atg_oregon.pem -o StrictHostKeyChecking=no ubuntu@$IP_ADDR
