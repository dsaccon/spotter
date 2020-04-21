# Pass in instance ID as first arg when running script
export INST_ID=$1
aws ec2 start-instances --instance-ids $INST_ID

echo Waiting for spot instance to start up...
aws ec2 wait instance-running --instance-ids $INST_ID
sleep 10

IP_ADDR=$(aws ec2 describe-instances --region us-west-2 --instance-ids $INST_ID --query "Reservations[*].Instances[*].PublicDnsName" --output=text)

#OS=`uname`
#KEYFILE='keys.txt'
#if [ "$OS" == 'Darwin' ]; then
#    KB_PATH='/Volumes/Keybase/team/atg_and_obt/'
#elif [ "$OS" == 'Linux' ]; then
#    KB_PATH='/keybase/team/atg_and_obt/'
#fi
#_KEY=$(grep -A2 '# OBT AWS' "$KB_PATH$KEYFILE" | tail -1)
#_SECRET=$(grep -A3 '# OBT AWS' "$KB_PATH$KEYFILE" | tail -1)
#KEY="${_KEY#*=}"
#SECRET="${_SECRET#*=}"

CMD="sleep 2;
    tmux send-keys -t '=system:0.left' 'pipenv shell' Enter; \
    sleep 2; \
    tmux send-keys -t '=system:0.left' 'sudo docker start influxdb' Enter; \
    sleep 5; \
    tmux send-keys -t '=system:0.left' 'cd sharpe/datamgmt' Enter; \
    tmux send-keys -t '=system:0.left' 'export AWS_S3_KEY='$2 Enter; \
    tmux send-keys -t '=system:0.left' 'export AWS_S3_SECRET='$3 Enter; \
    tmux send-keys -t '=system:0.left' 'python backtest_server.py' Enter; \
    tmux send-keys -t '=system:0.right' 'pipenv shell' Enter; \
    sleep 2; \
    tmux send-keys -t '=backtesting:0.left' 'pipenv shell' Enter; \
    sleep 2; \
    tmux send-keys -t '=backtesting:0.right' 'pipenv shell' Enter"

ssh -i ~/atg_oregon.pem -o StrictHostKeyChecking=no ubuntu@$IP_ADDR $CMD
