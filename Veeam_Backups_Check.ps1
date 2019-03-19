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
    Last Updated: MARCH 2019
    Version: 2
  
    Requires:
    Veeam Backup & Replication v9.5 Update 3 (full or console install)
    VMware Infrastructure

#> 
#---------------------------------------------------------[Script Parameters]------------------------------------------------------

[CmdletBinding()]
param(
    [Parameter( Position = 0)]
    $name = $args[0],
    [Parameter(Position = 1)]
    $period = $args[1],
    #Location of Veeam executable (Veeam.Backup.Shell.exe)
    $veeamExecutePath = "C:\Program Files\Veeam\Backup and Replication\Backup\Veeam.Backup.Shell.exe",
    $Server = "localhost"    
)

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#region Connect
# Load required Snapins and Modules
$start = Get-Date
Write-Verbose "[00:00:00.0000000] [$((get-date).TimeOfDay.ToString())] [BEGIN  ] Starting: $($MyInvocation.Mycommand)"  
Write-Verbose "[$((New-TimeSpan -Start $start).ToString())] [$((get-date).TimeOfDay.ToString())] [BEGIN  ] Loading PSSNapins"
if ($null -eq (Get-PSSnapin -Name VeeamPSSNapin -ErrorAction SilentlyContinue)) {
    $snapin = Add-PSSnapin VeeamPSSNapin -PassThru
    Write-Verbose "[$((New-TimeSpan -Start $start).ToString()) [$((get-date).TimeOfDay.ToString())]] [BEGIN  ] Loading $($snapin)"
}
# Connect to VBR server
if ($Server -eq $null) {
    Write-Verbose "[$((New-TimeSpan -Start $start).ToString()) [$((get-date).TimeOfDay.ToString())]] [BEGIN  ] Connecting to VBR Server"
    try {
        Disconnect-VBRServer
        Connect-VBRServer -Server $server 
    }
    catch {
        Write-Error "Unable to connect to VBR server - $server"
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

function Get-ExecutionMetaData {
    [CmdletBinding()]
    param ()
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $IsAdmin = [System.Security.Principal.WindowsPrincipal]::new($id).IsInRole('administrators')
    $os = (Get-CimInstance Win32_Operatingsystem).Caption
     
    $meta = [pscustomobject]@{
        User         = "$($env:userdomain)\$($env:USERNAME)"
        IsAdmin      = $IsAdmin
        Computername = $env:COMPUTERNAME
        OS           = $os
        Host         = $($host.Name)
        PSVersion    = $($PSVersionTable.PSVersion)
        Runtime      = $(Get-Date)
        Session      = "Session"
    }
     
    $meta
}
Function Get-VeeamVersion {
    [CmdletBinding()]
    param(
        $veeamExePath
    )
    Begin {
        Write-Verbose "[$((New-TimeSpan -Start $start).ToString())] [$((get-date).TimeOfDay.ToString())] [BEGIN  ] Starting: $($MyInvocation.MyCommand)"
        Write-Verbose "[$((New-TimeSpan -Start $start).ToString())] [$((get-date).TimeOfDay.ToString())] [BEGIN  ] Getting Veeam Execute Path"
        $veeamExePath = (Get-Item $veeamExecutePath)
        Write-Verbose "[$((New-TimeSpan -Start $start).ToString())] [$((get-date).TimeOfDay.ToString())] [BEGIN  ] Veeam Execute path : $($veeamExePath)"
    }
    Process {
        Try {
            Write-Verbose "[$((New-TimeSpan -Start $start).ToString())] [$((get-date).TimeOfDay.ToString())] [PROCESS  ] Getting Veeam Version"
            $veeamVersion = $veeamExepath.VersionInfo.ProductVersion
            Write-Verbose "[$((New-TimeSpan -Start $start).ToString())] [$((get-date).TimeOfDay.ToString())] [PROCESS  ] Version : $($veeamVersion)"
            if ($Null -eq $veeamVersion) {
                throw "Unable to get veeam version"
            }
            
        }
        Catch {
            Write-Error $_
            exit  3 
        }
    }
    End {
        Write-Verbose "[$((New-TimeSpan -Start $start).ToString())] [$((get-date).TimeOfDay.ToString())] [END  ] Ending : $($MyInvocation.Mycommand)"
        Return $VeeamVersion
    }
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
        Write-Verbose "[$((New-TimeSpan -Start $start).ToString())] [$((get-date).TimeOfDay.ToString())] [BEGIN  ] Starting: $($MyInvocation.MyCommand)"
        Write-Verbose "[$((New-TimeSpan -Start $start).ToString())] [$((get-date).TimeOfDay.ToString())] [BEGIN  ] Starting: Getting Last successful Session"
        $session = Get-VBRBackupSession | Where-Object {$_.JobName -eq $jobName <#-and $_.Result -eq "Success" #> } | Sort-Object creationtime -Descending | Select-Object -First 1
        $rpo = $now.AddDays(-$period)
        #if timespan is negative == RPO is not good" 
        $timeSpan = New-TimeSpan -Start $rpo.Date  -End  $($session.EndTime).Date
       
    }
    process {
  
        Write-Verbose "[$((New-TimeSpan -Start $start).ToString())] [$((get-date).TimeOfDay.ToString())] [PROCESS  ] Starting: Current Session Info"
        $currentSessionInfo = [PSCustomObject]@{
            Result       = $session.Result;
            State        = $session.State; 
            creationtime = $session.CreationTime; 
            EndTime      = $session.EndTime; 
            RPO          = $rpo; 
            Timespan     = $timeSpan
        }
        Write-Verbose $currentSessionInfo 
        return $timespan -ge 0 -and $session.State -ne "Failed"   
    }
    end {
        Write-Verbose "[$((New-TimeSpan -Start $start).ToString())] [$((get-date).TimeOfDay.ToString())] [End  ] Ending: $($MyInvocation.Mycommand)"
    }
}

#endRegion Function

#-----------------------------------------------------------[Execution]------------------------------------------------------------

#region Report
Write-Verbose "[$((New-TimeSpan -Start $start).ToString())] [$((get-date).TimeOfDay.ToString())] [BEGIN  ] Starting: $($MyInvocation.MyCommand)"
$metadata = Get-ExecutionMetaData -Verbose:$false | Out-String
Write-Verbose "[BEGIN  ] Execution Metadata:"
Write-Verbose $metadata
$job = Get-VBRJob -Name $name
Write-Verbose "[$((New-TimeSpan -Start $start).ToString())] [$((get-date).TimeOfDay.ToString())] [BEGIN  ] Processing job state"
if ($null -eq $job) {
    Write-Error "UNKNOWN! job name is null or unknown. exiting script"
    exit 3
}
else {
    $state = $job.getLastState()
}
$VeeamVersion = Get-VeeamVersion
If ($VeeamVersion -lt 9.5) {
    Write-Error "Script requires VBR v9.5"
    Write-Error "Version detected - $VeeamVersion"
    exit 3
}
Write-Verbose "[$((New-TimeSpan -Start $start).ToString())] [$((get-date).TimeOfDay.ToString())] [BEGIN  ] job last state : $($state)"
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
            Write-Host ("CRITICAL! the last succesful session is {0} days older !." -f $period)
            exit 2
        }
    }

    Default {	    
        Write-Host "UNKNOWN! Errors were encountered during the check of the following job: $name." 
        exit 3
    }
}
Write-Verbose "[$((New-TimeSpan -Start $start).ToString())] [$((get-date).TimeOfDay.ToString())] [BEGIN  ] Starting: $($MyInvocation.MyCommand)"
#endregion Report 