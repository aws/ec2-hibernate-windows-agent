# Copyright 2017 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# 
# Licensed under the Apache License, Version 2.0 (the "License"). You may not use this file except in compliance with the License. A copy of the License is located at
#
#     http://aws.amazon.com/apache2.0/
#
# or in the "license" file accompanying this file. This file is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.

#Start PS1 file
$source = @"
  using System;
  using System.Management.Automation;
  class EC2HibernateAgent {

    static void Main(string[] args) {

      bool runLoop = false;
      bool allowShutdownHooks = false;
      int pollingInterval = 1;

      for (var i = 0; i < args.Length; i++) {
      
          switch (args[i].Trim().ToUpper()) {

            case "-RUNLOOP":
              runLoop = true;
              break;
            case "-ALLOWSHUTDOWNHOOKS":
              allowShutdownHooks = true;
              break;
            case "-POLLINGINTERVAL":
              if (i == args.Length - 1) {
                throw new System.ArgumentException("No value provided for pollingInterval");
              }
              
              int pollingIntervalVal = 1;
              bool parseSuccess = Int32.TryParse(args[i + 1], out pollingIntervalVal);
              if (!parseSuccess || pollingIntervalVal < 1 || pollingIntervalVal > 60) {
                throw new System.ArgumentException("pollingInterval must be between 1 and 60 seconds");
              }
              pollingInterval = pollingIntervalVal;
              i++;
              break;
            default:
              throw new System.ArgumentException("Invalid parameter name: " + args[i].Trim());
          }      
      }

      using (PowerShell PowerShellInstance = PowerShell.Create()) {
         var content=System.IO.File.ReadAllText("C:\\Program Files\\Amazon\\Hibernate\\EC2HibernateAgent.ps1");
         PowerShellInstance.AddScript(content);
         PowerShellInstance.AddParameter("runLoop", runLoop);
         PowerShellInstance.AddParameter("allowShutdownHooks", allowShutdownHooks);
         PowerShellInstance.AddParameter("pollingInterval", pollingInterval);
         PowerShellInstance.Invoke();
      }
     }
   
  }
"@
Add-Type -TypeDefinition $source -Language CSharp -OutputAssembly "C:\Program Files\Amazon\Hibernate\EC2HibernateAgent.exe" -OutputType WindowsApplication
#End PS1 file
