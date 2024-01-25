# EC2 Hibernate Windows Agent (Deprecated)

> As of December 2023, the ec2-hibernate-windows-agent is officially deprecated. It is superseded by the new version of EC2 Spot Hibernation.
> The new version of EC2 Spot Hibernation provides significant improvements.
> For more information about the new version and to access its features, please visit | [Link](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/hibernate-spot-instances.html)

A Hibernating Agent for Windows on Amazon EC2

## License

This library is licensed under the Apache 2.0 License.

## Build

Running EC2HibernateAgentCompiler.ps1 will generate a C# executable called EC2HibernateAgent.exe.  This is a wrapper for EC2HibernateAgent.ps1.

## Install and Run

Follow the instructions [here](http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-hibernation.html "EC2 Spot hibernation user guide") to install and run the agent – i.e. place EC2HibernateAgent.exe and EC2HibernateAgent.ps1 in the directory "C:\Program Files\Amazon\Hibernate" of your Windows EC2 Spot instance, then run EC2HibernateAgent.exe from your instance user data.

