#aws ec2 request-spot-instances --spot-price "0.0115" --instance-count 1 --type "one-time" --launch-specification file://spec.json

REQ_ID=$(aws ec2 request-spot-instances --spot-price "0.0226" --instance-count 1 --type "persistent" --launch-specification file://spec.json --output="text" --query="SpotInstanceRequests[*].SpotInstanceRequestId")

aws ec2 wait spot-instance-request-fulfilled --spot-instance-request-ids $REQ_ID

export INST_ID=`aws ec2 describe-spot-instance-requests --spot-instance-request-ids $REQ_ID --output="text" --query="SpotInstanceRequests[*].InstanceId"`

echo Waiting for spot instance to start up...
aws ec2 wait instance-running --instance-ids $INST_ID

echo Spot instance ID: $INST_ID
