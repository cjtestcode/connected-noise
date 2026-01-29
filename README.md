I was not sure how y'all preferred sumologic would communicate with lambda so I assumed a webhook set up that will trigger a lambda through an API gateway. This set up, I think, gurantees comms from a sumologic webhook to lambda. I also have to create these resources before I can test the lambda so a bit constrained with the testing part.

My recording is a bit longer than the 55 minutes stipulated in the instructions. 55 minutes was not enough for me to make good progress on the code test. There also appears to be audio issues with the recording, this may have to do with how zoom does its video cobcersion to mp4

The files in the git repo represent config that works in my AWS account so there is then VPC ID and SUBNET ID hard coded within the terraform config. Improvement here will be to parametrize these values.

I did not have enough time to make EC2 instance more robust in terms of access and security. I could have been able to set up access via ssm and use instance role for perms.
