<#
.SYNOPSIS
    This script runs the Applicaiton Beanchmark Tests in different environment.
.DESCRIPTION
    This script chooses an appropriate defaults for most of the parameters if not provided.
.NOTES
    File Name      : RunBCPTTests.ps1
    Copyright 2020 - Microsof Corporation
.EXAMPLE
    RunBCPTTests.ps1  -Environment PROD -AuthorizationType AAD -Credential $Credential -SandboxName sandbox -TestRunnerPage 50010 -SuiteCode ONE -BCPTTestRunnerInternalFolderPath .\ALTestRunner\Internal
.EXAMPLE
    RunBCPTTests.ps1 -Environment OnPrem -AuthorizationType Windows -TestRunnerPage 50010 -SuiteCode THREE -BCPTTestRunnerInternalFolderPath .\ALTestRunner\Internal
#>
param
(
    [ValidateSet("PROD","OnPrem")]
    [string] $Environment,
    [ValidateSet("AAD","Windows","NavUserPassword")]
    [string] $AuthorizationType,
    [pscredential] $Credential,
    [pscredential] $Token,
    [string] $SandboxName,
    [string] $ServiceUrl,
    [int] $TestRunnerPage,
    [Parameter(Mandatory=$true)]
    [string] $SuiteCode,
    [string] $BCPTTestRunnerInternalFolderPath,
    [string] $ClientId,
    [string] $RedirectUri,
    [string] $AadTenantId,
    [switch] $SingleRun,
    [switch] $SkipDelayBeforeStart
)

<#
This funciton verifies the passed parameters and sets the defaults for the missing ones. The parameters are saved as global variables for further use
#>
function VerifyAndSetup-Parameters(
    [string] $Environment,
    [string] $AuthorizationType,
    [pscredential] $Credential,
    [pscredential] $Token,
    [string] $SandboxName,
    [string] $ServiceUrl,
    [int] $TestRunnerPage = $script:DefaultTestRunnerPage,
    [string] $SuiteCode,
    [string] $BCPTTestRunnerInternalFolderPath,
    [string] $ClientId,
    [string] $RedirectUri,
    [string] $AadTenantId
)
{
    # If -Environment is not specified then pick the default
    if ($Environment -eq '')
    {
        Write-Host "-Environment parameter is not provided. Defaulting to $script:DefaultEnvironment"

        $global:Environment = $script:DefaultEnvironment
    }
    else
    {
        $global:Environment = $Environment
    }

    # Depending on the Environment make sure necessary parameters are also specified
    switch ($global:Environment)
    {
        # PROD works only with AAD authorizatin type and OnPrem works on all 3 Authorization types
        'PROD'
        {
            if ($AuthorizationType -ne 'AAD')
            {
                throw "Only Authorization type 'AAD' can work in -Environment $Environment."
            }
            else
            {
                if ($AuthorizationType -eq '')
                {
                    Write-Host "-AuthorizationType parameter is not provided. Defaulting to $script:DefaultAuthorizationType"
                    $global:AuthorizationType = $script:DefaultAuthorizationType
                }
                else
                {
                    $global:AuthorizationType = $AuthorizationType
                }
            }

            if ($SandboxName -eq '')
            {
                Write-Host "-SandboxName parameter is not provided. Defaulting to $script:DefaultSandboxName"
                $global:SandboxName = $script:DefaultSandboxName
            }
            else
            {
                $global:SandboxName = $SandboxName
            }

            if ($ClientId -eq '')
            {
                Write-Error -Category InvalidArgument -Message 'ClientId is mandatory in the PROD environment'
            }
            else
            {
                $global:ClientId = $ClientId
            }
            if ($RedirectUri -eq '')
            {
                Write-Host "-RedirectUri parameter is not provided. Defaulting to $script:DefaultRedirectUri"
                $global:RedirectUri = $script:DefaultRedirectUri
            }
            else
            {
                $global:RedirectUri = $RedirectUri
            }
            if ($AadTenantId -eq '')
            {
                Write-Error -Category InvalidArgument -Message 'AadTenantId is mandatory in the PROD environment'
            }
            else
            {
                $global:AadTenantId = $AadTenantId
            }
        }
        'OnPrem'
        {
            if ($AuthorizationType -eq '')
            {
                Write-Host "-AuthorizationType parameter is not provided. Defaulting to $script:DefaultAuthorizationType"
                $global:AuthorizationType = $script:DefaultAuthorizationType
            }
            else
            {
                $global:AuthorizationType = $AuthorizationType
            }

            # OnPrem, -ServiceUrl should be provided else default is selected. On other environments, the Service Urls are built
            if ($ServiceUrl -eq '')
            {
                Write-Host "Valid ServiceUrl is not provided. Defaulting to $script:DefaultServiceUrl"
                $global:ServiceUrl = $script:DefaultServiceUrl
            }
            else
            {
                $global:ServiceUrl = $ServiceUrl
            }
        }
    }

    switch ($global:AuthorizationType)
    {
        # -Credential or -Token should be specified if authorization type is AAD.
        "AAD"
        {
            if ($Credential -eq $null -and $Token -eq $null)
            {
                throw "Parameter -Credential or -Token should be defined when selecting 'AAD' authorization type."
            }
            if ($Credential -ne $null -and $Token -ne $null)
            {
                throw "Specify only one parameter -Credential or -Token when selecting 'AAD' authorization type."
            }
        }
        # -Credential should be specified if authorization type is NavUserPassword.
        "NavUserPassword"
        {
            if ($Credential -eq $null)
            {
                throw "Parameter -Credential should be defined when selecting 'NavUserPassword' authorization type."
            }
        }
        "Windows"
        {
            if ($Credential -ne $null)
            {
                throw "Parameter -Credential should not be defined when selecting 'Windows' authorization type."
            }
        }
    }

    # Make sure all necessary scripts and assemblies are in the specified folder
    if ($BCPTTestRunnerInternalFolderPath -eq '')
    {
        Write-Host "Valid BCPTTestRunnerInternalFolderPath is not provided. Defaulting to $script:BCPTTestRunnerInternalFolderPath"
        $global:BCPTTestRunnerInternalFolderPath = $script:DefaultBCPTTestRunnerInternalFolderPath
    }
    else
    {
        $global:BCPTTestRunnerInternalFolderPath = $BCPTTestRunnerInternalFolderPath
    }

    if ([System.IO.Path]::IsPathRooted($global:BCPTTestRunnerInternalFolderPath) -eq $false)
    {
        Write-Host "The passed path for -BCPTTestRunnerInternalFolderPath seem to be relative path, converting to absolute."
        $global:BCPTTestRunnerInternalFolderPath = Convert-Path -Path $global:BCPTTestRunnerInternalFolderPath
        Write-Host "Absolute path is $global:BCPTTestRunnerInternalFolderPath"
    }

    if ((Test-Path -Path (Join-Path $global:BCPTTestRunnerInternalFolderPath $script:BCPTTestRunnerInternalScriptName)) -eq $false)
    {
         throw "Cannot find $script:BCPTTestRunnerInternalScriptName in location $global:BCPTTestRunnerInternalFolderPath"
    }

    if ((Test-Path -Path (Join-Path $global:BCPTTestRunnerInternalFolderPath $script:ClientAssembly1)) -eq $false)
    {
         throw "Cannot find $script:ClientAssembly1 in location $global:BCPTTestRunnerInternalFolderPath"
    }

    if ((Test-Path -Path (Join-Path $global:BCPTTestRunnerInternalFolderPath $script:ClientAssembly2)) -eq $false)
    {
         throw "Cannot find $script:ClientAssembly2 in location $global:BCPTTestRunnerInternalFolderPath"
    }

    if ((Test-Path -Path (Join-Path $global:BCPTTestRunnerInternalFolderPath $script:ClientAssembly3)) -eq $false)
    {
         throw "Cannot find $script:ClientAssembly3 in location $global:BCPTTestRunnerInternalFolderPath"
    }

    if ($TestRunnerPage -eq 0)
    {
        Write-Host "Valid TestRunnerPage is not provided. Defaulting to $script:DefaultTestRunnerPage"
        $global:TestRunnerPage = $script:DefaultTestRunnerPage
    }
    else
    {
        $global:TestRunnerPage = $TestRunnerPage
    }
}

$ErrorActionPreference = "Stop"

$global:Environment = ''
$global:AuthorizationType = ''
$global:SandboxName = ''
$global:ClientId = ''
$global:ServiceUrl = ''
$global:TestRunnerPage = 0
$global:BCPTTestRunnerInternalFolderPath = ''

$script:DefaultEnvironment = "OnPrem"
$script:DefaultAuthorizationType = 'Windows'
$script:DefaultSandboxName = "sandbox"
$script:DefaultServiceUrl = 'http://localhost:48900'
$script:DefaultTestRunnerPage = '149002'
$script:DefaultBCPTTestRunnerInternalFolderPath = $PSScriptRoot
$script:DefaultRedirectUri = "https://login.microsoftonline.com/common/oauth2/nativeclient"

$script:BCPTTestRunnerInternalScriptName = "BCPTTestRunnerInternal.psm1"
$script:ClientAssembly1 = "Microsoft.Dynamics.Framework.UI.Client.dll"
$script:ClientAssembly2 = "NewtonSoft.Json.dll"
$script:ClientAssembly3 = "Microsoft.Internal.AntiSSRF.dll"

VerifyAndSetup-Parameters -Environment $Environment -AuthorizationType $AuthorizationType -Credential $Credential -Token $Token -SandboxName $SandboxName -ServiceUrl $ServiceUrl -TestRunnerPage $TestRunnerPage -SuiteCode $SuiteCode -BCPTTestRunnerInternalFolderPath $BCPTTestRunnerInternalFolderPath -ClientId $ClientId -RedirectUri $RedirectUri -AadTenantId $AadTenantId

$BCPTRTestRunnerInternalScriptPath = (Join-Path $global:BCPTTestRunnerInternalFolderPath $script:BCPTTestRunnerInternalScriptName)
Write-Host "Importing AL Test Runner from $BCPTRTestRunnerInternalScriptPath"
Import-Module $BCPTRTestRunnerInternalScriptPath -WarningAction SilentlyContinue -Force

# Fetch no. of tasks, tasks life time and no. of tests from the client
$NoOfTasks,$TaskLifeInMins,$NoOfTests = Get-NoOfIterations -DisableSSLVerification -Environment $global:Environment -AuthorizationType $global:AuthorizationType -Credential $Credential -Token $Token -SandboxName $global:SandboxName -ServiceUrl $global:ServiceUrl -TestRunnerPage $global:TestRunnerPage -SuiteCode $SuiteCode -ClientId $global:ClientId  -RedirectUri $global:RedirectUri -AadTenantId $global:AadTenantId

$TaskLifeInMins += 10;

$task = {
    param(
        [string] $Environment,
        [string] $AuthorizationType,
        [pscredential] $Credential,
        [pscredential] $Token,
        [string] $SandboxName,
        [string] $ServiceUrl,
        [int] $TestRunnerPage,
        [string] $SuiteCode,
        [string] $PathToRunnerScript,
        [int] $SessionTimeoutInMins,
        [string] $ClientId,
        [string] $RedirectUri,
        [string] $AadTenantId,
        [switch] $SingleRun
    )
        
    Write-Host "Importing AL Test Runner from $PathToRunnerScript"
    Import-Module $PathToRunnerScript -WarningAction SilentlyContinue -Force

    Run-BCPTTestsInternal -DisableSSLVerification -Environment $Environment -AuthorizationType $AuthorizationType -Credential $Credential -Token $Token -SandboxName $SandboxName -ServiceUrl $ServiceUrl -TestRunnerPage $TestRunnerPage -SuiteCode $SuiteCode -SessionTimeoutInMins $SessionTimeoutInMins -ClientId $ClientId -RedirectUri $RedirectUri -AadTenantId $AadTenantId -SingleRun:$SingleRun
}

# Determine how many sessions to spawn based on single run mode
if ($SingleRun.IsPresent)
{
    $NoOfSessions = $NoOfTests
}
else
{
    $NoOfSessions = $NoOfTasks
}
    
# Spawn sessions
for ($i = 0; $i -lt $NoOfSessions; $i++)
{
    Start-Job -ScriptBlock $task -ArgumentList $global:Environment,$global:AuthorizationType,$Credential,$Token,$global:SandboxName,$global:ServiceUrl,$global:TestRunnerPage,$SuiteCode,$BCPTRTestRunnerInternalScriptPath,$TaskLifeInMins, $global:ClientId, $global:RedirectUri, $AadTenantId, $SingleRun

    if ($SkipDelayBeforeStart -eq $false)
    {sleep -Seconds 2}
}

While (@(Get-Job | Where { $_.State -eq "Running" -and $_.PSJobTypeName -eq "BackgroundJob"}).Count -ne 0) {
    Write-Verbose "Waiting for background jobs..."
    Start-Sleep -Seconds 3
}

$Data = ForEach ($Job in (Get-Job | Where { $_.PSJobTypeName -eq "BackgroundJob"}))
{  
    try {
        Receive-Job $Job
    }
    catch { 
        Write-Host $_ -ForegroundColor Red
    }
    finally {
        Remove-Job $Job
    }
}

# SIG # Begin signature block
# MIIoKAYJKoZIhvcNAQcCoIIoGTCCKBUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBGY0qSgOXhC/Ul
# 8Y1yDzbRESHJoj8lNh1B+KGJ5HdESKCCDXYwggX0MIID3KADAgECAhMzAAAEBGx0
# Bv9XKydyAAAAAAQEMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjQwOTEyMjAxMTE0WhcNMjUwOTExMjAxMTE0WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQC0KDfaY50MDqsEGdlIzDHBd6CqIMRQWW9Af1LHDDTuFjfDsvna0nEuDSYJmNyz
# NB10jpbg0lhvkT1AzfX2TLITSXwS8D+mBzGCWMM/wTpciWBV/pbjSazbzoKvRrNo
# DV/u9omOM2Eawyo5JJJdNkM2d8qzkQ0bRuRd4HarmGunSouyb9NY7egWN5E5lUc3
# a2AROzAdHdYpObpCOdeAY2P5XqtJkk79aROpzw16wCjdSn8qMzCBzR7rvH2WVkvF
# HLIxZQET1yhPb6lRmpgBQNnzidHV2Ocxjc8wNiIDzgbDkmlx54QPfw7RwQi8p1fy
# 4byhBrTjv568x8NGv3gwb0RbAgMBAAGjggFzMIIBbzAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQU8huhNbETDU+ZWllL4DNMPCijEU4w
# RQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEW
# MBQGA1UEBRMNMjMwMDEyKzUwMjkyMzAfBgNVHSMEGDAWgBRIbmTlUAXTgqoXNzci
# tW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3JsMGEG
# CCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3J0
# MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBAIjmD9IpQVvfB1QehvpC
# Ge7QeTQkKQ7j3bmDMjwSqFL4ri6ae9IFTdpywn5smmtSIyKYDn3/nHtaEn0X1NBj
# L5oP0BjAy1sqxD+uy35B+V8wv5GrxhMDJP8l2QjLtH/UglSTIhLqyt8bUAqVfyfp
# h4COMRvwwjTvChtCnUXXACuCXYHWalOoc0OU2oGN+mPJIJJxaNQc1sjBsMbGIWv3
# cmgSHkCEmrMv7yaidpePt6V+yPMik+eXw3IfZ5eNOiNgL1rZzgSJfTnvUqiaEQ0X
# dG1HbkDv9fv6CTq6m4Ty3IzLiwGSXYxRIXTxT4TYs5VxHy2uFjFXWVSL0J2ARTYL
# E4Oyl1wXDF1PX4bxg1yDMfKPHcE1Ijic5lx1KdK1SkaEJdto4hd++05J9Bf9TAmi
# u6EK6C9Oe5vRadroJCK26uCUI4zIjL/qG7mswW+qT0CW0gnR9JHkXCWNbo8ccMk1
# sJatmRoSAifbgzaYbUz8+lv+IXy5GFuAmLnNbGjacB3IMGpa+lbFgih57/fIhamq
# 5VhxgaEmn/UjWyr+cPiAFWuTVIpfsOjbEAww75wURNM1Imp9NJKye1O24EspEHmb
# DmqCUcq7NqkOKIG4PVm3hDDED/WQpzJDkvu4FrIbvyTGVU01vKsg4UfcdiZ0fQ+/
# V0hf8yrtq9CkB8iIuk5bBxuPMIIHejCCBWKgAwIBAgIKYQ6Q0gAAAAAAAzANBgkq
# hkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5
# IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEwOTA5WjB+MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQg
# Q29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+laUKq4BjgaBEm6f8MMHt03
# a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc6Whe0t+bU7IKLMOv2akr
# rnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4Ddato88tt8zpcoRb0Rrrg
# OGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+lD3v++MrWhAfTVYoonpy
# 4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nkkDstrjNYxbc+/jLTswM9
# sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6A4aN91/w0FK/jJSHvMAh
# dCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmdX4jiJV3TIUs+UsS1Vz8k
# A/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL5zmhD+kjSbwYuER8ReTB
# w3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zdsGbiwZeBe+3W7UvnSSmn
# Eyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3T8HhhUSJxAlMxdSlQy90
# lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS4NaIjAsCAwEAAaOCAe0w
# ggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRIbmTlUAXTgqoXNzcitW2o
# ynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBDuRQFTuHqp8cx0SOJNDBa
# BgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2Ny
# bC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3JsMF4GCCsG
# AQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3J0MIGfBgNV
# HSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEFBQcCARYzaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1hcnljcHMuaHRtMEAGCCsG
# AQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkAYwB5AF8AcwB0AGEAdABl
# AG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn8oalmOBUeRou09h0ZyKb
# C5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7v0epo/Np22O/IjWll11l
# hJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0bpdS1HXeUOeLpZMlEPXh6
# I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/KmtYSWMfCWluWpiW5IP0
# wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvyCInWH8MyGOLwxS3OW560
# STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBpmLJZiWhub6e3dMNABQam
# ASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJihsMdYzaXht/a8/jyFqGa
# J+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYbBL7fQccOKO7eZS/sl/ah
# XJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbSoqKfenoi+kiVH6v7RyOA
# 9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sLgOppO6/8MO0ETI7f33Vt
# Y5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtXcVZOSEXAQsmbdlsKgEhr
# /Xmfwb1tbWrJUnMTDXpQzTGCGggwghoEAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAAQEbHQG/1crJ3IAAAAABAQwDQYJYIZIAWUDBAIB
# BQCggZAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwLwYJKoZIhvcNAQkEMSIE
# IN8Y9ZhtZ6jBTRV1U2gRhUcS7ypk+lnBZ1JJvqaiPABMMEIGCisGAQQBgjcCAQwx
# NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20wDQYJKoZIhvcNAQEBBQAEggEAdhzcIQc7hyvjEuraWQzsXbBRer1tTxea
# GvXbpjQcL/rR0iE5IujUQMhf0IDpsOyQxKqiD3o7RDHCESCRsjRSnLl8g6p8Q8Qn
# RVD/YOdbJUEKH3LpjysiA/GSpY5RWGe4xKBlzcKL9/GN4vA3tIuasdvWtyoSlBk1
# tYo2ry2r0+K801DefKry+A1rLCIUVCqtPnpvApQ0m6lW3Plcy2rTkubYvTetD7CH
# APtIFYQyatTx8fxx1jUQpHaRje863PZZCotTImYwq10S/FLJzrwYLt2UYsApJXhv
# DlGhd/LzscHZUISrXks98sOlzfF8gHmI2oXNeVq92GI+LehLSOq/s6GCF7Awghes
# BgorBgEEAYI3AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCCF4kwgheFAgEDMQ8wDQYJ
# YIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYB
# BAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCCotqgH8sdFkw55aZjzp56WZlr/mx9w
# JST1XWyEAUhHXAIGZ+1OxPR8GBMyMDI1MDQxMDE2MjgwMS4yNzZaMASAAgH0oIHZ
# pIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYD
# VQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNV
# BAsTHm5TaGllbGQgVFNTIEVTTjo2NTFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEf4wggcoMIIFEKADAgECAhMzAAAB
# 9ZkJlLzxxlCMAAEAAAH1MA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFBDQSAyMDEwMB4XDTI0MDcyNTE4MzEwMVoXDTI1MTAyMjE4MzEwMVowgdMx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1p
# Y3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNo
# aWVsZCBUU1MgRVNOOjY1MUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQg
# VGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKC
# AgEAzO90cFQTWd/WP84IT7JMIW1fQL61sdfgmhlfT0nvYEb2kvkNF073ZwjveuSW
# ot387LjE0TCiG93e6I0HzIFQBnbxGP/WPBUirFq7WE5RAsuhNfYUL+PIb9jJq3Cw
# WxICfw5t/pTyIOHjKvo1lQOTWZypir/psZwEE7y2uWAPbZJTFrKen5R73x2Hbxy4
# eW1DcmXjym2wFWv10sBH40ajJfe+OkwcTdoYrY3KkpN/RQSjeycK0bhjo0CGYIYa
# +ZMAao0SNR/R1J1Y6sLkiCJO3aQrbS1Sz7l+/qJgy8fyEZMND5Ms7C0sEaOvoBHi
# WSpTM4vc0xDLCmc6PGv03CtWu2KiyqrL8BAB1EYyOShI3IT79arDIDrL+de91Ffj
# mSbBY5j+HvS0l3dXkjP3Hon8b74lWwikF0rzErF0n3khVAusx7Sm1oGG+06hz9XA
# y3Wou+T6Se6oa5LDiQgPTfWR/j9FNk8Ju06oSfTh6c03V0ulla0Iwy+HzUl+WmYx
# FLU0PiaXsmgudNwVqn51zr+Bi3XPJ85wWuy6GGT7nBDmXNzTNkzK98DBQjTOabQX
# UZ884Yb9DFNcigmeVTYkyUXZ6hscd8Nyq45A3D3bk+nXnsogK1Z7zZj6XbGft7xg
# OYvveU6p0+frthbF7MXv+i5qcD9HfFmOq4VYHevVesYb6P0CAwEAAaOCAUkwggFF
# MB0GA1UdDgQWBBRV4Hxb9Uo0oHDwJZJe22ixe2B1ATAfBgNVHSMEGDAWgBSfpxVd
# AF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIw
# UENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBo
# dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUy
# MFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYG
# A1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0B
# AQsFAAOCAgEAcwxmVPaA9xHffuom0TOSp2hspuf1G0cHW/KXHAuhnpW8/Svlq5j9
# aKI/8/G6fGIQMr0zlpau8jy83I4zclGdJjl5S02SxDlUKawtWvgf7ida06PgjeQM
# 1eX4Lut4bbPfT0FEp77G76hhysXxTJNHv5y+fwThUeiiclihZwqcZMpa46m+oV6i
# gTU6I0EnneotMqFs0Q3zHgVVr4WXjnG2Bcnkip42edyg/9iXczqTBrEkvTz0Ullt
# pFGaQnLzq+No8VEgq0UG7W1ELZGhmmxFmHABwTT6sPJFV68DfLoC0iB9Qbb9VZ8m
# vbTV5JtISBklTuVAlEkzXi9LIjNmx+kndBfKP8dxG/xbRXptQDQDaCsS6ogLkwLg
# H6zSs+ul9WmzI0F8zImbhnZhUziIHheFo4H+ZoojPYcgTK6/3bkSbOabmQFf95B8
# B6e5WqXbS5s9OdMdUlW1gTI1r5u+WAwH2KG7dxneoTbf/jYl3TUtP7AHpyck2c0n
# un/Q0Cycpa9QUH/Dy01k6tQomNXGjivg2/BGcgZJ0Hw8C6KVelEJ31xLoE21m9+N
# EgSKCRoFE1Lkma31SyIaynbdYEb8sOlZynMdm8yPldDwuF54vJiEArjrcDNXe6Bo
# bZUiTWSKvv1DJadR1SUCO/Od21GgU+hZqu+dKgjKAYdeTIvi9R2rtLYwggdxMIIF
# WaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3DQEBCwUAMIGIMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNy
# b3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAxMDAeFw0yMTA5MzAx
# ODIyMjVaFw0zMDA5MzAxODMyMjVaMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA5OGmTOe0ciELeaLL
# 1yR5vQ7VgtP97pwHB9KpbE51yMo1V/YBf2xK4OK9uT4XYDP/XE/HZveVU3Fa4n5K
# Wv64NmeFRiMMtY0Tz3cywBAY6GB9alKDRLemjkZrBxTzxXb1hlDcwUTIcVxRMTeg
# Cjhuje3XD9gmU3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7uhp7M62AW36MEBydUv62
# 6GIl3GoPz130/o5Tz9bshVZN7928jaTjkY+yOSxRnOlwaQ3KNi1wjjHINSi947SH
# JMPgyY9+tVSP3PoFVZhtaDuaRr3tpK56KTesy+uDRedGbsoy1cCGMFxPLOJiss25
# 4o2I5JasAUq7vnGpF1tnYN74kpEeHT39IM9zfUGaRnXNxF803RKJ1v2lIH1+/Nme
# Rd+2ci/bfV+AutuqfjbsNkz2K26oElHovwUDo9Fzpk03dJQcNIIP8BDyt0cY7afo
# mXw/TNuvXsLz1dhzPUNOwTM5TI4CvEJoLhDqhFFG4tG9ahhaYQFzymeiXtcodgLi
# Mxhy16cg8ML6EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5UPkLiWHzNgY1GIRH29wb
# 0f2y1BzFa/ZcUlFdEtsluq9QBXpsxREdcu+N+VLEhReTwDwV2xo3xwgVGD94q0W2
# 9R6HXtqPnhZyacaue7e3PmriLq0CAwEAAaOCAd0wggHZMBIGCSsGAQQBgjcVAQQF
# AgMBAAEwIwYJKwYBBAGCNxUCBBYEFCqnUv5kxJq+gpE8RjUpzxD/LwTuMB0GA1Ud
# DgQWBBSfpxVdAF5iXYP05dJlpxtTNRnpcjBcBgNVHSAEVTBTMFEGDCsGAQQBgjdM
# g30BATBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtp
# b3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wEwYDVR0lBAwwCgYIKwYBBQUHAwgwGQYJ
# KwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQF
# MAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8w
# TTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVj
# dHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBK
# BggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9N
# aWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZIhvcNAQELBQADggIBAJ1V
# ffwqreEsH2cBMSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9MTO1OdfCcTY/2mRsfNB1
# OW27DzHkwo/7bNGhlBgi7ulmZzpTTd2YurYeeNg2LpypglYAA7AFvonoaeC6Ce57
# 32pvvinLbtg/SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OOPcbzaN9l9qRWqveVtihV
# J9AkvUCgvxm2EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8DJ6LGYnn8AtqgcKBGUIZ
# UnWKNsIdw2FzLixre24/LAl4FOmRsqlb30mjdAy87JGA0j3mSj5mO0+7hvoyGtmW
# 9I/2kQH2zsZ0/fZMcm8Qq3UwxTSwethQ/gpY3UA8x1RtnWN0SCyxTkctwRQEcb9k
# +SS+c23Kjgm9swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjcZxkoJLo4S5pu+yFUa2pF
# EUep8beuyOiJXk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq77EFmPWn9y8FBSX5+k77L
# +DvktxW/tM4+pTFRhLy/AsGConsXHRWJjXD+57XQKBqJC4822rpM+Zv/Cuk0+CQ1
# ZyvgDbjmjJnW4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328y+l7vzhwRNGQ8cirOoo6
# CGJ/2XBjU02N7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIDWTCCAkECAQEwggEBoYHZ
# pIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYD
# VQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNV
# BAsTHm5TaGllbGQgVFNTIEVTTjo2NTFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAJsAKu48N
# bR5YRg3WSBQCyjzdkvaggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDANBgkqhkiG9w0BAQsFAAIFAOuiWMIwIhgPMjAyNTA0MTAxNDQ4MzRaGA8y
# MDI1MDQxMTE0NDgzNFowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA66JYwgIBADAK
# AgEAAgIWZAIB/zAHAgEAAgIS1TAKAgUA66OqQgIBADA2BgorBgEEAYRZCgQCMSgw
# JjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3
# DQEBCwUAA4IBAQATqM6bVoLZQ6GgTTWH2wxWrr9nIDXchnaVBXAZrDdfAmA5RiQB
# HvS5ltkXpn7rfoKJbTfBy60nGLpdUyCMOEG1ZZnpBwEdPItCOIbMIltPkAtqZ2Zp
# 7ddmp5d3OrmCGx7SsCvTBu3M84W/6KNHmY/6OExQkVt0eBzbU3xIC0Wr2uW+Kiwy
# jD+qIGhM3Djd5oUMrWZMDdgvLNnk9A5vcQbGIma++zHvoymgfERVmxMF5wcPrFqk
# Q9HzBjcBhdGUFQuLFotPmcRsu4p+ATa/FoQLEpICLNj0PSmi7a04NB9PK70qxhBe
# JIsrBsT/nQ8j6Tg65P+b73Af2kQUhlhLAH5gMYIEDTCCBAkCAQEwgZMwfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAH1mQmUvPHGUIwAAQAAAfUwDQYJ
# YIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkq
# hkiG9w0BCQQxIgQg4J3xNHCTMD11Kaq13krtCgRE8q/XcAB9sC45TK+UZ0UwgfoG
# CyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCDB1vLSFwh09ISu4kdEv4/tg9eR1Yk8
# w5x7j5GThqaPNTCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# AhMzAAAB9ZkJlLzxxlCMAAEAAAH1MCIEIEp4CZAsF/1ydrLfMyxNLy+3QqWGOiS+
# HF6cK17cxTT3MA0GCSqGSIb3DQEBCwUABIICAMMLExTGu/iTLrO5P3TZwRepVCR2
# Q5ooCYiqz1shMTw55vachfVX+7zluxsZDuuTwDwhfiA5J2YYj9TXwQ+SNPUST+Yh
# Xcoxu4lfh43EOJpU5QVDK6YQGDOecVbGhXxaxWTpD0GlSe4Ya8iaOGxK7UXIllsG
# O/vT7OQfKWumULPJ/1hPhibOK+d5/tvPzZYlW+qhQyBaNHFJGf4DgC0hrHUic2v0
# Z3K69dnOSCgDZJHC+kUv1MyG+o4nKlDihMB1vegfzJ7AkvlFPBlZ9OaCXyniebmf
# CIokEJGUzM7G+vViXaBM3rfW2tZq5JjDoJ5mkrIMgSh1qclqCgsKc8DoUJiRqMar
# NSow5fcdrszc9pwjeDjTv/iALhF3myS0w6GDxELfvtJsw+BqODixNe2OO4Z1XPyD
# /UP7G3KeVHWcsszGCD7uarCRH/Os+vueMTgVsfAtWJk+0ryLT+SlEGHIkxJkY20o
# 3ST7O/yL+11kznYSVcllBnFHmeL95gmU1gtv0+fKZ9TM1Ys3J/CzPvNtVc5A6F6S
# zPs2tnVtYgnh3wl5rp8A5DycBXpKW8HslUtPWd5Iu0TiIDHen5AQZ9NymnQ6M2xa
# dHkSe1Sywt7lFTLd2WAs/xB5yqCDHN/4uet2O5HfE4d86h92LVRIssJXIPUotgkw
# kamVBV2BytOeAzLA
# SIG # End signature block
