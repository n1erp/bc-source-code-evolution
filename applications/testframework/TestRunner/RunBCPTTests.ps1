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
# MIIoHgYJKoZIhvcNAQcCoIIoDzCCKAsCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBGY0qSgOXhC/Ul
# 8Y1yDzbRESHJoj8lNh1B+KGJ5HdESKCCDYUwggYDMIID66ADAgECAhMzAAAEhJji
# EuB4ozFdAAAAAASEMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjUwNjE5MTgyMTM1WhcNMjYwNjE3MTgyMTM1WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDtekqMKDnzfsyc1T1QpHfFtr+rkir8ldzLPKmMXbRDouVXAsvBfd6E82tPj4Yz
# aSluGDQoX3NpMKooKeVFjjNRq37yyT/h1QTLMB8dpmsZ/70UM+U/sYxvt1PWWxLj
# MNIXqzB8PjG6i7H2YFgk4YOhfGSekvnzW13dLAtfjD0wiwREPvCNlilRz7XoFde5
# KO01eFiWeteh48qUOqUaAkIznC4XB3sFd1LWUmupXHK05QfJSmnei9qZJBYTt8Zh
# ArGDh7nQn+Y1jOA3oBiCUJ4n1CMaWdDhrgdMuu026oWAbfC3prqkUn8LWp28H+2S
# LetNG5KQZZwvy3Zcn7+PQGl5AgMBAAGjggGCMIIBfjAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUBN/0b6Fh6nMdE4FAxYG9kWCpbYUw
# VAYDVR0RBE0wS6RJMEcxLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJh
# dGlvbnMgTGltaXRlZDEWMBQGA1UEBRMNMjMwMDEyKzUwNTM2MjAfBgNVHSMEGDAW
# gBRIbmTlUAXTgqoXNzcitW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIw
# MTEtMDctMDguY3JsMGEGCCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDEx
# XzIwMTEtMDctMDguY3J0MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIB
# AGLQps1XU4RTcoDIDLP6QG3NnRE3p/WSMp61Cs8Z+JUv3xJWGtBzYmCINmHVFv6i
# 8pYF/e79FNK6P1oKjduxqHSicBdg8Mj0k8kDFA/0eU26bPBRQUIaiWrhsDOrXWdL
# m7Zmu516oQoUWcINs4jBfjDEVV4bmgQYfe+4/MUJwQJ9h6mfE+kcCP4HlP4ChIQB
# UHoSymakcTBvZw+Qst7sbdt5KnQKkSEN01CzPG1awClCI6zLKf/vKIwnqHw/+Wvc
# Ar7gwKlWNmLwTNi807r9rWsXQep1Q8YMkIuGmZ0a1qCd3GuOkSRznz2/0ojeZVYh
# ZyohCQi1Bs+xfRkv/fy0HfV3mNyO22dFUvHzBZgqE5FbGjmUnrSr1x8lCrK+s4A+
# bOGp2IejOphWoZEPGOco/HEznZ5Lk6w6W+E2Jy3PHoFE0Y8TtkSE4/80Y2lBJhLj
# 27d8ueJ8IdQhSpL/WzTjjnuYH7Dx5o9pWdIGSaFNYuSqOYxrVW7N4AEQVRDZeqDc
# fqPG3O6r5SNsxXbd71DCIQURtUKss53ON+vrlV0rjiKBIdwvMNLQ9zK0jy77owDy
# XXoYkQxakN2uFIBO1UNAvCYXjs4rw3SRmBX9qiZ5ENxcn/pLMkiyb68QdwHUXz+1
# fI6ea3/jjpNPz6Dlc/RMcXIWeMMkhup/XEbwu73U+uz/MIIHejCCBWKgAwIBAgIK
# YQ6Q0gAAAAAAAzANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlm
# aWNhdGUgQXV0aG9yaXR5IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEw
# OTA5WjB+MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYD
# VQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG
# 9w0BAQEFAAOCAg8AMIICCgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+la
# UKq4BjgaBEm6f8MMHt03a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc
# 6Whe0t+bU7IKLMOv2akrrnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4D
# dato88tt8zpcoRb0RrrgOGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+
# lD3v++MrWhAfTVYoonpy4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nk
# kDstrjNYxbc+/jLTswM9sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6
# A4aN91/w0FK/jJSHvMAhdCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmd
# X4jiJV3TIUs+UsS1Vz8kA/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL
# 5zmhD+kjSbwYuER8ReTBw3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zd
# sGbiwZeBe+3W7UvnSSmnEyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3
# T8HhhUSJxAlMxdSlQy90lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS
# 4NaIjAsCAwEAAaOCAe0wggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRI
# bmTlUAXTgqoXNzcitW2oynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTAL
# BgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBD
# uRQFTuHqp8cx0SOJNDBaBgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jv
# c29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFf
# MDNfMjIuY3JsMF4GCCsGAQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFf
# MDNfMjIuY3J0MIGfBgNVHSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEF
# BQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1h
# cnljcHMuaHRtMEAGCCsGAQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkA
# YwB5AF8AcwB0AGEAdABlAG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn
# 8oalmOBUeRou09h0ZyKbC5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7
# v0epo/Np22O/IjWll11lhJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0b
# pdS1HXeUOeLpZMlEPXh6I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/
# KmtYSWMfCWluWpiW5IP0wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvy
# CInWH8MyGOLwxS3OW560STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBp
# mLJZiWhub6e3dMNABQamASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJi
# hsMdYzaXht/a8/jyFqGaJ+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYb
# BL7fQccOKO7eZS/sl/ahXJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbS
# oqKfenoi+kiVH6v7RyOA9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sL
# gOppO6/8MO0ETI7f33VtY5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtX
# cVZOSEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGe8wghnrAgEBMIGVMH4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01p
# Y3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAASEmOIS4HijMV0AAAAA
# BIQwDQYJYIZIAWUDBAIBBQCggZAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# LwYJKoZIhvcNAQkEMSIEIN8Y9ZhtZ6jBTRV1U2gRhUcS7ypk+lnBZ1JJvqaiPABM
# MEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAhinRzCJh6j6m
# AqBk6eWUeJvesYDzSjCf5oLpLORtA/MHFEH4twna8JE3rwMM0t6+iOFo5dl3uhhB
# Bm6UnV1IZnoAfUTq84XKcGl4S40+XV3nQo95hS3+vRmsD1t7jfdjZ+715o9WyTl3
# xVf4jqRzrCiR7s7PQydLKsmeJ0QdDqM201Xz3jWWhbwf0FhV8rkAZaZpzG+E5yz7
# n/b3dyvKbnlOa4PnLRvUu6jpC7Sg2G92i7BC4g/VuVyVeXogICmkVB591myIBbxq
# vH4RJV2I2psLZVVjKaTOYdSnmubVh9sYTYwrLfrZpISeVY0wZdfPBqVBJGgzWzx2
# ne9zDuqek6GCF5cwgheTBgorBgEEAYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCC
# F3AwghdsAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEE
# ggE9MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCAJsxXQRcWB
# r3hCXgwaWWm6UtPeAAaxiXF7woy+fsQTmgIGaKOkwoI+GBMyMDI1MDkxMjE3MDEy
# MC45MDJaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25z
# MScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046OTYwMC0wNUUwLUQ5NDcxJTAjBgNV
# BAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghHtMIIHIDCCBQigAwIB
# AgITMwAAAgTY4A4HlzJYmAABAAACBDANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yNTAxMzAxOTQyNDdaFw0yNjA0MjIxOTQy
# NDdaMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYD
# VQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hp
# ZWxkIFRTUyBFU046OTYwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoIC
# AQDw3Sbcee2d66vkWGTIXhfGqqgQGxQXTnq44XlUvNzFSt7ELtO4B939jwZFX7Dr
# Rt/4fpzGNkFdGpc7EL5S86qKYv360eXjW+fIv1lAqDD31d/p8Ai9/AZz8M95zo0r
# DpK2csz9WAyR9FtUDx52VOs9qP3/pgpHvgUvD8s6/3KNITzms8QC1tJ3TMw1cRn9
# CZgVIYzw2iD/ZvOW0sbF/DRdgM8UdtxjFIKTXTaI/bJhsQge3TwayKQ2j85RafFF
# VCR5/ChapkrBQWGwNFaPzpmYN46mPiOvUxriISC9nQ/GrDXUJWzLDmchrmr2baAB
# Jevvw31UYlTlLZY6zUmjkgaRfpozd+Glq9TY2E3Dglr6PtTEKgPu2hM6v8NiU5nT
# vxhDnxdmcf8UN7goeVlELXbOm7j8yw1xM9IyyQuUMWkorBaN/5r9g4lvYkMohRXE
# YB0tMaOPt0FmZmQMLBFpNRVnXBTa4haXvn1adKrvTz8VlfnHxkH6riA/h2AlqYWh
# v0YULsEcHnaDWgqA29ry+jH097MpJ/FHGHxk+d9kH2L5aJPpAYuNmMNPB7FDTPWA
# x7Apjr/J5MhUx0i07gV2brAZ9J9RHi+fMPbS+Qm4AonC5iOTj+dKCttVRs+jKKuO
# 63CLwqlljvnUCmuSavOX54IXOtKcFZkfDdOZ7cE4DioP1QIDAQABo4IBSTCCAUUw
# HQYDVR0OBBYEFBp1dktAcGpW/Km6qm+vu4M1GaJfMB8GA1UdIwQYMBaAFJ+nFV0A
# XmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWlj
# cm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQ
# Q0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
# VGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYD
# VR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEB
# CwUAA4ICAQBecv6sRw2HTLMyUC1WJJ+FR+DgA9Jkv0lGsIt4y69CmOj8R63oFbhS
# mcdpakxqNbr8v9dyTb4RDyNqtohiiXbtrXmQK5X7y/Q++F0zMotTtTpTPvG3elty
# V/LvO15mrLoNQ7W4VH58aLt030tORxs8VnAQQF5BmQQMOua+EQgH4f1F4uF6rl3E
# C17JBSJ0wjHSea/n0WYiHPR0qkz/NRAf8lSUUV0gbIMawGIjn7+RKyCr+8l1xdNk
# K/F0UYuX3hG0nE+9Wc0L4A/enluUN7Pa9vOV6Vi3BOJST0RY/ax7iZ45leM8kqCw
# 7BFPcTIkWzxpjr2nCtirnkw7OBQ6FNgwIuAvYNTU7r60W421YFOL5pTsMZcNDOOs
# A01xv7ymCF6zknMGpRHuw0Rb2BAJC9quU7CXWbMbAJLdZ6XINKariSmCX3/MLdzc
# W5XOycK0QhoRNRf4WqXRshEBaY2ymJvHO48oSSY/kpuYvBS3ljAAuLN7Rp8jWS7t
# 916paGeE7prmrP9FJsoy1LFKmFnW+vg43ANhByuAEXq9Cay5o7K2H5NFnR5wj/SL
# RKwK1iyUX926i1TEviEiAh/PVyJbAD4koipig28p/6HDuiYOZ0wUkm/a5W8orIjo
# OdU3XsJ4i08CfNp5I73CsvB5QPYMcLpF9NO/1LvoQAw3UPdL55M5HTCCB3EwggVZ
# oAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcNAQELBQAwgYgxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jv
# c29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEwMB4XDTIxMDkzMDE4
# MjIyNVoXDTMwMDkzMDE4MzIyNVowfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIw
# MTAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDk4aZM57RyIQt5osvX
# JHm9DtWC0/3unAcH0qlsTnXIyjVX9gF/bErg4r25PhdgM/9cT8dm95VTcVrifkpa
# /rg2Z4VGIwy1jRPPdzLAEBjoYH1qUoNEt6aORmsHFPPFdvWGUNzBRMhxXFExN6AK
# OG6N7dcP2CZTfDlhAnrEqv1yaa8dq6z2Nr41JmTamDu6GnszrYBbfowQHJ1S/rbo
# YiXcag/PXfT+jlPP1uyFVk3v3byNpOORj7I5LFGc6XBpDco2LXCOMcg1KL3jtIck
# w+DJj361VI/c+gVVmG1oO5pGve2krnopN6zL64NF50ZuyjLVwIYwXE8s4mKyzbni
# jYjklqwBSru+cakXW2dg3viSkR4dPf0gz3N9QZpGdc3EXzTdEonW/aUgfX782Z5F
# 37ZyL9t9X4C626p+Nuw2TPYrbqgSUei/BQOj0XOmTTd0lBw0gg/wEPK3Rxjtp+iZ
# fD9M269ewvPV2HM9Q07BMzlMjgK8QmguEOqEUUbi0b1qGFphAXPKZ6Je1yh2AuIz
# GHLXpyDwwvoSCtdjbwzJNmSLW6CmgyFdXzB0kZSU2LlQ+QuJYfM2BjUYhEfb3BvR
# /bLUHMVr9lxSUV0S2yW6r1AFemzFER1y7435UsSFF5PAPBXbGjfHCBUYP3irRbb1
# Hode2o+eFnJpxq57t7c+auIurQIDAQABo4IB3TCCAdkwEgYJKwYBBAGCNxUBBAUC
# AwEAATAjBgkrBgEEAYI3FQIEFgQUKqdS/mTEmr6CkTxGNSnPEP8vBO4wHQYDVR0O
# BBYEFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMFwGA1UdIARVMFMwUQYMKwYBBAGCN0yD
# fQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lv
# cHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkr
# BgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUw
# AwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBN
# MEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0
# cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoG
# CCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01p
# Y1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDANBgkqhkiG9w0BAQsFAAOCAgEAnVV9
# /Cqt4SwfZwExJFvhnnJL/Klv6lwUtj5OR2R4sQaTlz0xM7U518JxNj/aZGx80HU5
# bbsPMeTCj/ts0aGUGCLu6WZnOlNN3Zi6th542DYunKmCVgADsAW+iehp4LoJ7nvf
# am++Kctu2D9IdQHZGN5tggz1bSNU5HhTdSRXud2f8449xvNo32X2pFaq95W2KFUn
# 0CS9QKC/GbYSEhFdPSfgQJY4rPf5KYnDvBewVIVCs/wMnosZiefwC2qBwoEZQhlS
# dYo2wh3DYXMuLGt7bj8sCXgU6ZGyqVvfSaN0DLzskYDSPeZKPmY7T7uG+jIa2Zb0
# j/aRAfbOxnT99kxybxCrdTDFNLB62FD+CljdQDzHVG2dY3RILLFORy3BFARxv2T5
# JL5zbcqOCb2zAVdJVGTZc9d/HltEAY5aGZFrDZ+kKNxnGSgkujhLmm77IVRrakUR
# R6nxt67I6IleT53S0Ex2tVdUCbFpAUR+fKFhbHP+CrvsQWY9af3LwUFJfn6Tvsv4
# O+S3Fb+0zj6lMVGEvL8CwYKiexcdFYmNcP7ntdAoGokLjzbaukz5m/8K6TT4JDVn
# K+ANuOaMmdbhIurwJ0I9JZTmdHRbatGePu1+oDEzfbzL6Xu/OHBE0ZDxyKs6ijoI
# Yn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggNQMIICOAIBATCB+aGB0aSB
# zjCByzELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UE
# CxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVs
# ZCBUU1MgRVNOOjk2MDAtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQC6PYHRw9+9SH+1pwy6qzVG
# 3k9lbqCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
# SIb3DQEBCwUAAgUA7G5tZzAiGA8yMDI1MDkxMjA5NTkwM1oYDzIwMjUwOTEzMDk1
# OTAzWjB3MD0GCisGAQQBhFkKBAExLzAtMAoCBQDsbm1nAgEAMAoCAQACAhyLAgH/
# MAcCAQACAhNfMAoCBQDsb77nAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQB
# hFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEB
# ACTdkjP7NZ0b4sgOGX8KGyp0CqrfFfI3sQRS76hHucdTdVscEr/K8XDvDmAJOhun
# LHywPepvu/+3gNdi18vtkFlGswMbujSY1r6xGDpl/m45sHD1hkn4y7k9RTty9Qjt
# OT1ZTtXnK7gQ72CrVjzU4eOAo0oqP3errYA0j5McGxE/lrPHnI2AzLM0NKUBp/V8
# DphfjPMgNYj5KUHeo55zqWw611jeXHWH8ZhnN6WKCw6Af2/wjRzoodareSXJAxzQ
# 8UvWSKDCYlzl5F41IBTaVp8uJ06BqdCfn5NR6LnVdEXy5zlBqXAjH4osmd17m6/k
# r15gHYDHwCP9UPgdrsno4XAxggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMAITMwAAAgTY4A4HlzJYmAABAAACBDANBglghkgBZQMEAgEF
# AKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEi
# BCCHKqb/zlk9fW+eBuwM0wopPHRaTuAgnsA+aU8y6scnnTCB+gYLKoZIhvcNAQkQ
# Ai8xgeowgecwgeQwgb0EIPnteGX9Wwq8VdJM6mjfx1GEJsu7/6kU6l0SS5rcebn+
# MIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAO
# BgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEm
# MCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIE2OAO
# B5cyWJgAAQAAAgQwIgQgb2gg9tcZL6ZEWTXx87VkGdShV4Go8GUuRjW7iJhmHHQw
# DQYJKoZIhvcNAQELBQAEggIACshmtT/8eqYTVX/GnFVB7ij1khjqnGXX9mR/cSI+
# 4Lkz+xi4V8U5JIwA0lmFbSDyNmIY1r5EoCHVEjDoM4hKOreA8sTqWvBUMG/5ZH+Y
# iRX/vppl1ikM8/Q2Dfr6cjchwKTSzk5DSzu7AA5lLSTCC83vn9SxNE/O4ft7+m51
# goaCEAkjD+Ucc43LEZJaSh39iS6wq9ZUca9tGnh6HUEWPYtnsX4A5URGkAVg8W93
# Wk8GXvt30ZU0jIL6pjYL4cdEgITPZK3AFNopPKG2OWD+Uiue0XwxCLQ9ttToiXeO
# bfae/iCsBCSRD30ivchBQoadzWhS7m2Oa9OuEBucEvgRamIPNEb23zmyhDXPEzW7
# DwOCw+o1JuFbDJPrKhZfMz+55B0+wO906a63FLxOdQmRh9m34AMwZlS/zjLX5rIj
# 81hOc+gO9lGQfdl9RBBqlc0fzRoQlhMm4i5oNr+BBzB9lmw/vPw6L9RzlwTJyMR4
# LkzKdL2wnXAh1Iv/0by/+x4fqyiXyyoCPLTqf4nyjqAr+MPtCNjWPhjnOpc8C4oi
# 8nDHH1kyFf0At252LPQenXzt5w5kA40GKiHrzjBXS49x0P/qH59W6HidQG60QUt1
# cuPBFs294jFEOT7keSaLaFMiLYZkXsHnQRvG+CbG+hmZOWk79jH0MsQXodyu0AP0
# 4D4=
# SIG # End signature block
