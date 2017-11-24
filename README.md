# EC2 Hibernate Windows Agent

A Hibernating Agent for Windows on Amazon EC2

## License

This library is licensed under the Apache 2.0 License.

## Build

Running EC2HibernateAgentCompiler.ps1 will generate a C# executable called EC2HibernateAgent.exe.  This is a wrapper for EC2HibernateAgent.ps1.

## Install and Run

Follow the instructions [here](http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-hibernation.html "EC2 Spot hibernation user guide") to install and run the agent – i.e. place EC2HibernateAgent.exe and EC2HibernateAgent.ps1 in the directory "C:\Program Files\Amazon\Hibernate" of your Windows EC2 Spot instance, then run EC2HibernateAgent.exe from your instance user data.

