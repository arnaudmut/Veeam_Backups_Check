#requires -Version 3.0
<#

    .SYNOPSIS
    Veeam_Backup_Check is a reporting script for Veeam Backup.

    .DESCRIPTION
    Veeam_backup_check is a simple script for Veeam Backup and
    Replication that check backups and backup copies. This script checks the last status and last successful backup session of the job passed as an argument.


    .PARAMETER name
    The name of the job passed as an argument.

    .PARAMETER period
    report period in days (RPO).
    
    .PARAMETER veeamExePath
    Location of Veeam executable (Veeam.Backup.Shell.exe)
    default : "C:\Program Files\Veeam\Backup and Replication\Backup\Veeam.Backup.Shell.exe"
    
    .PARAMETER server
    Veaam backup and replication server.
    default : "localhost"

    .EXAMPLE
    .\Veeam_Backup_Check.ps1 -name "name of the job to check" -period "days to check (RPO)"
    Run script from (an elevated) PowerShell console  
  
    .NOTES
    Author: Arnaud Mutana
    Last Updated: SEPTEMBER 2018
    Version: 1.1
  
    Requires:
    Veeam Backup & Replication v9.5 Update 3 (full or console install)
    VMware Infrastructure

#> 
#---------------------------------------------------------[Script Parameters]------------------------------------------------------

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    $name = $args[0],
    [Parameter(Position = 1)]
    $period = $args[1],
    #Location of Veeam executable (Veeam.Backup.Shell.exe)
    $veeamExePath = "C:\Program Files\Veeam\Backup and Replication\Backup\Veeam.Backup.Shell.exe",
    $Server = "localhost"
)

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#region Connect
# Load required Snapins and Modules
if ($null -eq (Get-PSSnapin -Name VeeamPSSNapin -ErrorAction SilentlyContinue)) {
    Add-PSSnapin VeeamPSSNapin
}
# Connect to VBR server
if ($Server -eq $null) {
    try {
        Disconnect-VBRServer
        Connect-VBRServer -Server $server 
    }
    catch {
        Write-Host "Unable to connect to VBR server - $server" -ForegroundColor Red
        exit 3
      
    }   
}
#endregion

#----------------------------------------------------------[Declarations]----------------------------------------------------------

#region variables 
#job to work with
$job
#Last state 
#$state
#last known successful session
$lastOkSession 
#get today date 
$now = (Get-Date)
#endregion variables 

#----------------------------------------------------------[Functions]----------------------------------------------------------

#region Function

Function Get-VeeamVersion {
    Begin {}
    Process {
        Try {
            $veeamExe = Get-Item $veeamExePath
            $VeeamVersion = $veeamExe.VersionInfo.ProductVersion
            Return $VeeamVersion
        }
        Catch {
            Write-Host "Unable to Locate Veeam executable, check path - $veeamExePath" -ForegroundColor Red
            exit  3 
        }
    }
    End {}
}

# Convert mode (timeframe) to hours
function IsRPOValid {
    <#
    .SYNOPSIS
    Function  that check if RPO is valid in a given timespan
    .DESCRIPTION
    This function compares two dates and returns true if [param] date1 is equal or greater than rpo and if last job session is successful.
    $rpo : rpo to compare.
    $timespan : timespn between $rpo and the last successful job session passed as param ($date1)
    for more info : https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_functions_advanced_parameters?view=powershell-6
    .EXAMPLE
    IsRPOValid $jobName
    .PARAMETER job
    The job to check
    #>
    [CmdletBinding()]
    param(
        # job name
        [Parameter(Mandatory = $true)]
        [string]$jobName
    )
    begin {
        write-verbose "Function begin. declaring variables"
        $session = Get-VBRBackupSession | Where-Object {$_.JobName -eq $jobName -and $_.Result -eq "idle" } | Sort-Object creationtime -Descending | Select-Object -First 1
        $rpo = $now.AddDays(-$period)
        #if timespan is negative == RPO is not good" 
        $timeSpan = New-TimeSpan -Start $rpo.Date  -End  $($session.EndTime).Date
        Write-Verbose "func jobname : $($jobName)"
        Write-Verbose "session date : $($session.EndTime)"
        write-verbose "declaring variables"
        Write-Verbose "RPO date : $($rpo)"
        Write-Verbose "timespan : $($timeSpan)"
    }
    process {
  
        write-verbose "Function process begin. comparison between the dates"
        Write-Verbose " return : $($timespan -ge 0 -and $session.State -ne "Failed")"
        return $timespan -ge 0 -and $session.State -ne "Failed"   
    }
    end {}
}

#endRegion Function

#-----------------------------------------------------------[Execution]------------------------------------------------------------

#region Report
$job = Get-VBRJob -Name $name
if ($null -eq $job) {
    Write-Host "UNKNOWN! job name is null or unknown. exiting script"
    exit 3
}
else {
    $state = $job.getLastState()
}
$VeeamVersion = Get-VeeamVersion
If ($VeeamVersion -lt 9.5) {
    Write-Host "Script requires VBR v9.5" -ForegroundColor Red
    Write-Host "Version detected - $VeeamVersion" -ForegroundColor Red
    exit 3
}
switch ($state) {
    Failed {	
        Write-Host "CRITICAL! Errors were encountered during the backup process of the following job: $name." 
        exit 2
    }
    Working {	
        Write-Host "OK - Job: $name is currently in progress."
        exit 0
    }
    idle {
        Write-Verbose "function IsRPOValid = '$(IsRPOValid $job.name)'." 
        #Recovery Point Objective 
        if (IsRPOValid $job.name) {
            Write-Host "OK! $name waiting for new restore points."
            exit 0
        } 
        else {
            Write-Host ("CRITICAL! the last succesful session is {0} days older !." -f $period)
            exit 2
        }
    }
    stopped {
        if (IsRPOValid $job.name) {
            Write-Host "OK! $name waiting for new restore points."
            exit 0
        } 
        else {
            Write-Host ("CRITICAL! the last successful session was on {0}." -f $period)
            exit 2
        }
    }

    Default {	    
        Write-Host "UNKNOWN! Errors were encountered during the check of the following job: $name." 
        exit 3
    }
}
#endregion Report 