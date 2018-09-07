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
    Function  that calculate timespan
    .DESCRIPTION
    This function compares two dates and returns true if [param] date1 is equal or greater than rpo  
    .EXAMPLE
    RPO([dateTime]date)
    .PARAMETER date1
    The date to compare.
    #>
    [CmdletBinding()]
    param
    (
      [Parameter(Mandatory=$True,ValidateNotnullOrEmpty, Position = 0)]
      [datetime]$date1
    )
    begin {
    write-verbose "declaring variables"
     $rpo = $now.AddDays(-$period)
     $timeSpan = New-TimeSpan -Start $date1.Date -End  $rpo.Date
    }
    process {
  
      write-verbose "Beginning process comparison between the two "
      $timeSpan -ge 0
    }
    end{}
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
$lastOkSession = Get-VBRBackupSession | Where-Object {$_.JobName -eq $job.Name -and $_.Result -eq "success" } | Sort-Object creationtime -Descending | Select-Object -First 1

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
        #Recovery Point Objective 
        $rpo
         = (Get-Date).AddDays(-$period)
        if ((get-date $lastOkSession.EndTime) -ge (get-date $rpo
        ) -and ($lastOkSession.State -ne "failed")) {
            Write-Host "OK! $name waiting for new restore points."
            exit 0
        } 
        elseif ((get-date $lastOkSession.EndTime) -lt (get-date $rpo
        ) -and ($lastOkSession.State -ne "failed")) {
            Write-Host ("CRITICAL! the last successful session is {0} day old." -f $(Get-Date $lastOkSession.EndTime))
            exit 2
        }
        else {
            Write-Host "WARNING! Job $name didn't fully succeed."
            exit 1
        }
    }
    stopped {
        #Recovery Point Objective 
        $rpo = (Get-Date).AddDays(-$period)
        if ((get-date $lastOkSession.EndTime) -gt (get-date $rpo
        ) -and ($lastOkSession.State -ne "failed")) {
            Write-Host "OK! $name waiting for new restore points."
            exit 0
        } 
        elseif ((get-date $lastOkSession.EndTime) -le (get-date $rpo
        ) -and ($lastOkSession.State -ne "failed")) {
            Write-Host ("CRITICAL! the last successful session is {0} days old." -f $((Get-Date $lastOkSession.EndTime).Day))
            exit 2
        }
        else {
            Write-Host "WARNING! Job $name didn't fully succeed."
            exit 1
        }
    }

    Default {	    
        Write-Host "UNKNOWN! Errors were encountered during the check of the following job: $name." 
        exit 3
    }
}
#endregion Report 