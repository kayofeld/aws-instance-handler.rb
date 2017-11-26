# aws-instance-handler.rb
Ruby project to handle AWS instance deployments including file pushing handling and on-instance script execution

## To install the dependencies
run
```
$>bundle install
```

This will install
* aws-sdk
* base64
* colorize

## Where files are included

To deploy files in the instance, put them in ./include, and deploy them in your script using the origin path `/root/include`