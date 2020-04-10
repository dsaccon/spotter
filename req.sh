#aws ec2 request-spot-instances --spot-price "0.0115" --instance-count 1 --type "one-time" --launch-specification file://spec.json

REQ_ID=$(aws ec2 request-spot-instances --spot-price "0.0115" --instance-count 1 --type "persistent" --launch-specification file://spec.json --output="text" --query="SpotInstanceRequests[*].SpotInstanceRequestId")

aws ec2 wait spot-instance-request-fulfilled --spot-instance-request-ids $REQ_ID
