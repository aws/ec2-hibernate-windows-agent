# Copyright 2017 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You may not use this file except in compliance with the License. A copy of the License is located at
#
#     http://aws.amazon.com/apache2.0/
#
# or in the "license" file accompanying this file. This file is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.

# EC2 Hibernation Agent
Param ([switch]$runLoop, [switch]$allowShutdownHooks, [int]$pollingInterval = 1)

$scriptPath = "C:\Program Files\Amazon\Hibernate\EC2HibernateAgent.exe"

Function RunHibernateAgent {

    <#
    .SYNOPSIS
    Runs the EC2 Hibernate agent.
    
    .DESCRIPTION
    Detects the EC2 signal for hibernation and initiates hibernation.  It has the following steps:
    1) Configure settings to allow hibernation
    2) If the -runLoop switch is not set, schedules a task to run itself on each instance startup using the Windows Task Scheduler
    3) If the -runLoop switch is set, polls the instance metadata for the hibernation signal
    4) If the hibernation signal is detected, it calls the hibernate command
    
    .PARAMETER agentPath
    File path of the agent.
    
    .PARAMETER runLoop
    If true, polls for the hibernation signal.
    If false, it schedules itself to run on instance startup and then calls the task to start polling.
    
    .PARAMETER allowShutdownHooks
    If true, calls hibernate without the force flag so that application shutdown hooks may run (however, this risks hibernation being stalled).
    If false, does a force hibernate so that no applications can prevent the shutdown.
    
    .EXAMPLE
    RunHibernateAgent -allowShutdownHooks
    This will schedule the hibernate agent to run on each instance startup as well as immediately starting to poll.
    It will not force shutdown, allowing application shutdown hooks to run normally.
    #>
    
    Param (
         [Parameter(Mandatory=$true)]
         [ValidateNotNullOrEmpty()]
         [string]$agentPath,
    
         [Parameter(Mandatory=$false)]
         [switch]$runLoop,
         
         [Parameter(Mandatory=$false)]
         [switch]$allowShutdownHooks,
         
         [Parameter(Mandatory=$false)]
         [ValidateRange(1,60)]
         [int]$pollingInterval
    )
    
    Process {
        $startTime = Get-Date
    
        # Set up event log source
        $eventLogSource = "EC2HibernateAgent"
        if (-not [System.Diagnostics.EventLog]::SourceExists($eventLogSource)) {
            New-EventLog -LogName Application -Source $eventLogSource
        }
        
        # Enable hibernation
        powercfg.exe /hibernate on
        if (-not $?) {
            Write-EventLog –LogName Application –Source $eventLogSource –EntryType Error –EventID 6 –Message "Failed to enable hibernation using powercfg" -ErrorAction SilentlyContinue
            throw "Failed to enable hibernation using powercfg"
        }
        
        # Skip recovery screen if resume from hibernation fails, so the instance doesn't get stuck
        # waiting on user input. This is configured by default on Server 2016/Windows 10.
        $osVersion = (Get-CimInstance Win32_OperatingSystem).version.Split(".")[0]
        if ($osVersion -lt 10) {
            bcdedit /set "{current}" bootstatuspolicy ignoreallfailures
            if (-not $?) {
                Write-EventLog –LogName Application –Source $eventLogSource –EntryType Warning –EventID 7 –Message "Failed to configure bcdedit bootstatuspolicy to ignore resume failures" -ErrorAction SilentlyContinue
            }
            bcdedit /set "{resumeloadersettings}" custom:0x15000080 3
            if (-not $?) {
                Write-EventLog –LogName Application –Source $eventLogSource –EntryType Warning –EventID 10 –Message "Failed to configure bcdedit to timeout on resume failure recovery screen" -ErrorAction SilentlyContinue
            }
        }
        
        $instanceAction = $null
        $lastInstanceActionSeen = $null
        $hibernateConfigured = $null;

        if ($runLoop) {
            Write-EventLog –LogName Application –Source $eventLogSource –EntryType Information –EventID 2 –Message "Waiting for hibernation signal with pollingInterval $pollingInterval" -ErrorAction SilentlyContinue
            while ($true) {
            
                # Check how long the task has been running for - if it has been running for a day, restart it so that Task Scheduler doesn't stop it after three days
                $currentTime = Get-Date
                $timeSinceStart = New-TimeSpan -Start $startTime -End $currentTime
                if ($timeSinceStart.TotalHours -gt 23) {
                    $startTime = $currentTime
                    Write-EventLog –LogName Application –Source $eventLogSource –EntryType Information –EventID 14 –Message "Re-running EC2HibernateAgent task" -ErrorAction SilentlyContinue
                    schtasks /Run /TN "EC2HibernateAgent"
                    if (-not $?) {
                        Write-EventLog –LogName Application –Source $eventLogSource –EntryType Warning –EventID 13 –Message "Failed to run EC2HibernateAgent task" -ErrorAction SilentlyContinue
                    }
                }

                try {
                    # Check Hibernate-Option.Configured meta data 
                    $token = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token-ttl-seconds" = "21600"} -Method PUT –Uri http://169.254.169.254/latest/api/token
                    $hibernateConfigured = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = $token} -Method GET -Uri http://169.254.169.254/latest/meta-data/hibernation/configured
                }
                catch [Exception] {
                    # We expect a 404 exception if the hibernation-configured metadata is not set
                    Write-EventLog –LogName Application –Source $eventLogSource –EntryType Information –EventID 15 –Message "Failed to get the Hibernate-Option.Configured meta-data" -ErrorAction SilentlyContinue
                    $hibernateConfigured = $null;
                }

                if (($hibernateConfigured) -and ($hibernateConfigured -match $true)) {
                    Write-EventLog –LogName Application –Source $eventLogSource –EntryType Information –EventID 16 –Message "Hibernation-option.Configured = true. Exiting EC2HibernateAgent" -ErrorAction SilentlyContinue
                    Exit 0 # hibernation-option.Configured = true.  Exiting Spot window agent
                }

                try {
                    $token = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token-ttl-seconds" = "21600"} -Method PUT –Uri http://169.254.169.254/latest/api/token
                    $instanceAction = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = $token} -Method GET -Uri http://169.254.169.254/latest/meta-data/spot/instance-action
                }
                catch [Exception] {
                    # We expect a 404 exception if the instance-action metadata is not set
                    $instanceAction = $null
                }
        
                if (($instanceAction) -and ($instanceAction -match "hibernate")) {
                
                    if ($lastInstanceActionSeen -and ($lastInstanceActionSeen -eq $instanceAction)) {
                        # We have already acted on this hibernate signal (the timestamps are the same), so ignore it.
                        # This could occur if we read the metadata after calling shutdown but before this process froze.
                        Write-EventLog –LogName Application –Source $eventLogSource –EntryType Information –EventID 11 –Message "Hibernate signal already seen, ignoring" -ErrorAction SilentlyContinue
                        $instanceAction = $null
                        Start-Sleep -s $pollingInterval
                    } else {
                        Write-EventLog –LogName Application –Source $eventLogSource –EntryType Information –EventID 3 –Message "Detected hibernate signal, initiating hibernation" -ErrorAction SilentlyContinue
                        $lastInstanceActionSeen = $instanceAction
                        $instanceAction = $null
        
                        # Initiate hibernation
                        if ($allowShutdownHooks) {
                            shutdown /h
                        } else {
                            shutdown /h /f
                        }
        
                        # This process is not guaranteed to be frozen immediately after calling the hibernate command, so wait a bit to avoid triggering hibernation twice
                        Start-Sleep -s 2
                        Write-EventLog –LogName Application –Source $eventLogSource –EntryType Information –EventID 4 –Message "Hibernate agent resuming" -ErrorAction SilentlyContinue
                    }
                } else {
                    Start-Sleep -s $pollingInterval
                }
            }
        } else {
            Write-EventLog –LogName Application –Source $eventLogSource –EntryType Information –EventID 1 –Message "Scheduling agent to run on startup" -ErrorAction SilentlyContinue
        
            # Schedule the task to run on each instance startup
            if ($allowShutdownHooks) {
                schtasks /Create /SC ONSTART /TN "EC2HibernateAgent" /RU system /F /TR "'$agentPath' -runLoop -allowShutdownHooks -pollingInterval $pollingInterval"
            } else {
                schtasks /Create /SC ONSTART /TN "EC2HibernateAgent" /RU system /F /TR "'$agentPath' -runLoop -pollingInterval $pollingInterval"
            }
            if (-not $?) {
                Write-EventLog –LogName Application –Source $eventLogSource –EntryType Error –EventID 8 –Message "Failed to schedule EC2HibernateAgent task" -ErrorAction SilentlyContinue
                throw "Failed to schedule EC2HibernateAgent task"
            }
            
            schtasks /Run /TN "EC2HibernateAgent"
            if (-not $?) {
                Write-EventLog –LogName Application –Source $eventLogSource –EntryType Error –EventID 9 –Message "Failed to run EC2HibernateAgent task" -ErrorAction SilentlyContinue
                throw "Failed to run EC2HibernateAgent task"
            }
        }
    }
}
    
RunHibernateAgent -agentPath:$scriptPath -runLoop:$runLoop -allowShutdownHooks:$allowShutdownHooks -pollingInterval:$pollingInterval
