function Setup-Enviroment
(
    [ValidateSet("PROD","OnPrem")]
    [string] $Environment = $script:DefaultEnvironment,
    [string] $SandboxName = $script:DefaultSandboxName,
    [pscredential] $Credential,
    [pscredential] $Token,
    [string] $ClientId,
    [string] $RedirectUri,
    [string] $AadTenantId
)
{
    switch ($Environment)
    {
        "PROD" 
        {           
            $authority = "https://login.microsoftonline.com/"
            $resource = "https://api.businesscentral.dynamics.com"
            $global:AadTokenProvider = [AadTokenProvider]::new($AadTenantId, $ClientId, $RedirectUri)
            
            if(!$global:AadTokenProvider){
                $example = @'

    $UserName = 'USERNAME'
    $Password = 'PASSWORD'
    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $UserCredential = New-Object System.Management.Automation.PSCredential($UserName, $securePassword)

    $script:AADTenantID = 'Guid like - 212415e1-054e-401b-ad32-3cdfa301b1d2'
    $script:ClientId = 'Guid like 0a576aea-5e61-4153-8639-4c5fd5e7d1f6'
    $script:RedirectUri = 'https://login.microsoftonline.com/common/oauth2/nativeclient'
    $global:AadTokenProvider = [AadTokenProvider]::new($script:AADTenantID, $script:ClientId, $scrit:RedirectUri)
'@
                throw 'You need to initialize and set the $global:AadTokenProvider. Example: ' + $example
            }
            $tenantDomain = ''
            if ($Token -ne $null)
            {
                $tenantDomain = ($Token.UserName.Substring($Token.UserName.IndexOf('@') + 1))
            }
            else
            {
                $tenantDomain = ($Credential.UserName.Substring($Credential.UserName.IndexOf('@') + 1))
            }
            $script:discoveryUrl = "https://businesscentral.dynamics.com/$tenantDomain/$SandboxName/deployment/url" #Sandbox
            $script:automationApiBaseUrl = "https://api.businesscentral.dynamics.com/v1.0/api/microsoft/automation/v1.0/companies"
        }
    }
}

function Get-SaaSServiceURL()
{
     $status = ''

     $provisioningTimeout = new-timespan -Minutes 15
     $stopWatch = [diagnostics.stopwatch]::StartNew()
     while ($stopWatch.elapsed -lt $provisioningTimeout)
     {
        $response = Invoke-RestMethod -Method Get -Uri $script:discoveryUrl
        if($response.status -eq 'Ready')
        {
            $clusterUrl = $response.data
            return $clusterUrl
        }
        else
        {
            Write-Host "Could not get Service url status - $($response.status)"
        }

        sleep -Seconds 10
     }
}

function Run-BCPTTestsInternal
(
    [ValidateSet("PROD","OnPrem")]
    [string] $Environment,
    [ValidateSet('Windows','NavUserPassword','AAD')]
    [string] $AuthorizationType,
    [pscredential] $Credential,
    [pscredential] $Token,
    [string] $SandboxName,
    [int] $TestRunnerPage,
    [switch] $DisableSSLVerification,
    [string] $ServiceUrl,
    [string] $SuiteCode,
    [int] $SessionTimeoutInMins,
    [string] $ClientId,
    [string] $RedirectUri,
    [string] $AadTenantId,
    [switch] $SingleRun
)
{
    <#
        .SYNOPSIS
        Runs the Application Beanchmark Tool(BCPT) tests.

        .DESCRIPTION
        Runs BCPT tests in different environment.

        .PARAMETER Environment
        Specifies the environment the tests will be run in. The supported values are 'PROD', 'TIE' and 'OnPrem'. Default is 'PROD'.

        .PARAMETER AuthorizationType
        Specifies the authorizatin type needed to authorize to the service. The supported values are 'Windows','NavUserPassword' and 'AAD'.

        .PARAMETER Credential
        Specifies the credential object that needs to be used to authenticate. Both 'NavUserPassword' and 'AAD' needs a valid credential objects to eb passed in.
        
        .PARAMETER Token
        Specifies the AAD token credential object that needs to be used to authenticate. The credential object should contain username and token.

        .PARAMETER SandboxName
        Specifies the sandbox name. This is necessary only when the environment is either 'PROD' or 'TIE'. Default is 'sandbox'.
        
        .PARAMETER TestRunnerPage
        Specifies the page id that is used to start the tests. Defualt is 150010.
        
        .PARAMETER DisableSSLVerification
        Specifies if the SSL verification should be disabled or not.
        
        .PARAMETER ServiceUrl
        Specifies the base url of the service. This parameter is used only in 'OnPrem' environment.
        
        .PARAMETER SuiteCode
        Specifies the code that will be used to select the test suite to be run.
        
        .PARAMETER SessionTimeoutInMins
        Specifies the timeout for the client session. This will be same the length you expect the test suite to run.

        .PARAMETER ClientId
        Specifies the guid that the BC is registered with in AAD.

        .PARAMETER SingleRun
        Specifies if it is a full run or a single iteration run.

        .INPUTS
        None. You cannot pipe objects to Add-Extension.

        .EXAMPLE
        C:\PS> Run-BCPTTestsInternal -DisableSSLVerification -Environment OnPrem -AuthorizationType Windows -ServiceUrl 'htto://localhost:48900' -TestRunnerPage 150002 -SuiteCode DEMO -SessionTimeoutInMins 20
        File.txt

        .EXAMPLE
        C:\PS> Run-BCPTTestsInternal -DisableSSLVerification -Environment PROD -AuthorizationType AAD -Credential $Credential -TestRunnerPage 150002 -SuiteCode DEMO -SessionTimeoutInMins 20 -ClientId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
    #>

    Run-NextTest -DisableSSLVerification -Environment $Environment -AuthorizationType $AuthorizationType -Credential $Credential -Token $Token -SandboxName $SandboxName -ServiceUrl $ServiceUrl -TestRunnerPage $TestRunnerPage -SuiteCode $SuiteCode -SessionTimeout $SessionTimeoutInMins -ClientId $ClientId -RedirectUri $RedirectUri -AadTenantId $AadTenantId -SingleRun:$SingleRun
}

function Run-NextTest
(
    [switch] $DisableSSLVerification,
    [ValidateSet("PROD","OnPrem")]
    [string] $Environment,
    [ValidateSet('Windows','NavUserPassword','AAD')]
    [string] $AuthorizationType,
    [pscredential] $Credential,
    [pscredential] $Token,
    [string] $SandboxName,
    [string] $ServiceUrl,
    [int] $TestRunnerPage,
    [string] $SuiteCode,
    [int] $SessionTimeout,
    [string] $ClientId,
    [string] $RedirectUri,
    [string] $AadTenantId,
    [switch] $SingleRun
)
{
    Setup-Enviroment -Environment $Environment -SandboxName $SandboxName -Credential $Credential -Token $Token -ClientId $ClientId -RedirectUri $RedirectUri -AadTenantId $AadTenantId
    if ($Environment -ne 'OnPrem')
    {
        $ServiceUrl = Get-SaaSServiceURL
    }
    
    try
    {
        $clientContext = Open-ClientSessionWithWait -DisableSSLVerification:$DisableSSLVerification -AuthorizationType $AuthorizationType -Credential $Credential -ServiceUrl $ServiceUrl -ClientSessionTimeout $SessionTimeout
        $form = Open-TestForm -TestPage $TestRunnerPage -DisableSSLVerification:$DisableSSLVerification -AuthorizationType $AuthorizationType -ClientContext $clientContext

        $SelectSuiteControl = $clientContext.GetControlByName($form, "Select Code")
        $clientContext.SaveValue($SelectSuiteControl, $SuiteCode);

        if ($SingleRun.IsPresent)
        {
            $StartNextAction = $clientContext.GetActionByName($form, "StartNextPRT")
        }
        else
        {
            $StartNextAction = $clientContext.GetActionByName($form, "StartNext")
        }

        $clientContext.InvokeAction($StartNextAction)
        
        $clientContext.CloseForm($form)
    }
    finally
    {
        if($clientContext)
        {
            $clientContext.Dispose()
        }
    } 
}

function Get-NoOfIterations
(
    [ValidateSet("PROD","OnPrem")]
    [string] $Environment,
    [ValidateSet('Windows','NavUserPassword','AAD')]
    [string] $AuthorizationType,
    [pscredential] $Credential,
    [pscredential] $Token,
    [string] $SandboxName,
    [int] $TestRunnerPage,
    [switch] $DisableSSLVerification,
    [string] $ServiceUrl,
    [string] $SuiteCode,
    [String] $ClientId,
    [string] $RedirectUri,
    [string] $AadTenantId
)
{
    <#
        .SYNOPSIS
        Opens the Application Beanchmark Tool(BCPT) test runner page and reads the number of sessions that needs to be created.

        .DESCRIPTION
        Opens the Application Beanchmark Tool(BCPT) test runner page and reads the number of sessions that needs to be created.

        .PARAMETER Environment
        Specifies the environment the tests will be run in. The supported values are 'PROD', 'TIE' and 'OnPrem'.

        .PARAMETER AuthorizationType
        Specifies the authorizatin type needed to authorize to the service. The supported values are 'Windows','NavUserPassword' and 'AAD'.

        .PARAMETER Credential
        Specifies the credential object that needs to be used to authenticate. Both 'NavUserPassword' and 'AAD' needs a valid credential objects to eb passed in.
        
        .PARAMETER Token
        Specifies the AAD token credential object that needs to be used to authenticate. The credential object should contain username and token.

        .PARAMETER SandboxName
        Specifies the sandbox name. This is necessary only when the environment is either 'PROD' or 'TIE'. Default is 'sandbox'.
        
        .PARAMETER TestRunnerPage
        Specifies the page id that is used to start the tests.
        
        .PARAMETER DisableSSLVerification
        Specifies if the SSL verification should be disabled or not.
        
        .PARAMETER ServiceUrl
        Specifies the base url of the service. This parameter is used only in 'OnPrem' environment.
        
        .PARAMETER SuiteCode
        Specifies the code that will be used to select the test suite to be run.
        
        .PARAMETER ClientId
        Specifies the guid that the BC is registered with in AAD.

        .INPUTS
        None. You cannot pipe objects to Add-Extension.

        .EXAMPLE
        C:\PS> $NoOfTasks,$TaskLifeInMins,$NoOfTests = Get-NoOfIterations -DisableSSLVerification -Environment OnPrem -AuthorizationType Windows -ServiceUrl 'htto://localhost:48900' -TestRunnerPage 150010 -SuiteCode DEMO
        File.txt

        .EXAMPLE
        C:\PS> $NoOfTasks,$TaskLifeInMins,$NoOfTests = Get-NoOfIterations -DisableSSLVerification -Environment PROD -AuthorizationType AAD -Credential $Credential -TestRunnerPage 50010 -SuiteCode DEMO -ClientId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'

    #>

    Setup-Enviroment -Environment $Environment -SandboxName $SandboxName -Credential $Credential -Token $Token -ClientId $ClientId -RedirectUri $RedirectUri -AadTenantId $AadTenantId
    if ($Environment -ne 'OnPrem')
    {
        $ServiceUrl = Get-SaaSServiceURL
    }
    
    try
    {
        $clientContext = Open-ClientSessionWithWait -DisableSSLVerification:$DisableSSLVerification -AuthorizationType $AuthorizationType -Credential $Credential -ServiceUrl $ServiceUrl
        $form = Open-TestForm -TestPage $TestRunnerPage -DisableSSLVerification:$DisableSSLVerification -AuthorizationType $AuthorizationType -ClientContext $clientContext
        $SelectSuiteControl = $clientContext.GetControlByName($form, "Select Code")
        $clientContext.SaveValue($SelectSuiteControl, $SuiteCode);

        $testResultControl = $clientContext.GetControlByName($form, "No. of Instances")
        $NoOfInstances = [int]$testResultControl.StringValue

        $testResultControl = $clientContext.GetControlByName($form, "Duration (minutes)")
        $DurationInMins = [int]$testResultControl.StringValue

        $testResultControl = $clientContext.GetControlByName($form, "No. of Tests")
        $NoOfTests = [int]$testResultControl.StringValue
        
        $clientContext.CloseForm($form)
        return $NoOfInstances,$DurationInMins,$NoOfTests
    }
    finally
    {
        if($clientContext)
        {
            $clientContext.Dispose()
        }
    } 
}

$ErrorActionPreference = "Stop"

if(!$script:TypesLoaded)
{
    Add-type -Path "$PSScriptRoot\Microsoft.Dynamics.Framework.UI.Client.dll"
    Add-type -Path "$PSScriptRoot\NewtonSoft.Json.dll"
    Add-type -Path "$PSScriptRoot\Microsoft.Internal.AntiSSRF.dll"
    
    $alTestRunnerInternalPath = Join-Path $PSScriptRoot "ALTestRunnerInternal.psm1"
    Import-Module "$alTestRunnerInternalPath"

    $clientContextScriptPath = Join-Path $PSScriptRoot "ClientContext.ps1"
    . "$clientContextScriptPath"
    
    $aadTokenProviderScriptPath = Join-Path $PSScriptRoot "AadTokenProvider.ps1"
    . "$aadTokenProviderScriptPath"
}

$script:TypesLoaded = $true;
$script:ActiveDirectoryDllsLoaded = $false;
$script:AadTokenProvider = $null

$script:DefaultEnvironment = "OnPrem"
$script:DefaultAuthorizationType = 'Windows'
$script:DefaultSandboxName = "sandbox"
$script:DefaultTestPage = 150002;
$script:DefaultTestSuite = 'DEFAULT'
$script:DefaultErrorActionPreference = 'Stop'

$script:DefaultTcpKeepActive = [timespan]::FromMinutes(2);
$script:DefaultTransactionTimeout = [timespan]::FromMinutes(30);
$script:DefaultCulture = "en-US";

Export-ModuleMember -Function Run-BCPTTestsInternal,Get-NoOfIterations

# SIG # Begin signature block
# MIIoKAYJKoZIhvcNAQcCoIIoGTCCKBUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCicbavk73W/qRx
# 9RJOvG5ONWB+skuaJLtfeHAwO0ANgaCCDXYwggX0MIID3KADAgECAhMzAAAEBGx0
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
# IPhVCTF5ZLZGumMFldiC/Wo+Dwas40zHnYANRc74wYQJMEIGCisGAQQBgjcCAQwx
# NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20wDQYJKoZIhvcNAQEBBQAEggEAAf/P7SnBsDp0DSazPZiRLU/RmXuQ6Muv
# /y/RyjXEZcc5bog6CG50jGOIyRY2rMexPju+tIjaeHZWOOBpJg25aRkHaX9w93vb
# EgunBJi1mBizYjFDxR5e8KwoyEU+4jnT99oIXtBoaS3HclzpleYYf8/gyruGBwYz
# drN/DcqFLJuT0mTBzd5i6nq68eFn7ab9uVG6xtxH3/vsEcWsu+1HSEfDil6rNj+w
# Iiw80LdsNkoOUvXS7z7Ac8TCJOzUZSHmHUXqRgGBp74hOfglhLR2ggM+AAx1lur7
# DBuePvsv+SS6Fd8j1jjAAL8TCXe2bytIoz9avEIjAUSDbpj9MyYeP6GCF7Awghes
# BgorBgEEAYI3AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCCF4kwgheFAgEDMQ8wDQYJ
# YIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYB
# BAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCBZ1NjD3yiHMVP4CEgonxreKMNTY+Fw
# mhYxAf4+8wT5NwIGZ+1OxPK3GBMyMDI1MDQxMDE2MjczNi43MzNaMASAAgH0oIHZ
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
# hkiG9w0BCQQxIgQg00nKmE2XHtWQ4B4IA+19xkGN0tEnxSbtpjom7W31tkQwgfoG
# CyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCDB1vLSFwh09ISu4kdEv4/tg9eR1Yk8
# w5x7j5GThqaPNTCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# AhMzAAAB9ZkJlLzxxlCMAAEAAAH1MCIEIEp4CZAsF/1ydrLfMyxNLy+3QqWGOiS+
# HF6cK17cxTT3MA0GCSqGSIb3DQEBCwUABIICAIq40XVc79PgZu9ISzKkR18wqHAx
# qyp/IMCx7MSCrK33Kt8siSYnP2AiHqaOGuLQBVHhpRBd7F+TgDiUBIaB3zfzMdSP
# 1YY3r3D4EruG02S+VE39HKM6oHhNy3GqJFiFq/9SIRO63TVVGCMHzNdB0Ul41n/8
# H4CcLb4KsXKvCHY4b0qAQ8e6NubcVr9t22kyTn2OZbCRitPVkj4fM9Y0q2H/AioK
# NgXLAw7/+L+Hoz4M+dMFvAp4k/jlx4UBiMA5s2NNau1knLLHilZhcg+50tGi6hzq
# a1RojyhhUNbxoCW0gAzaIn/put7/iHJgmQzmSrTbJUoSBWBIuBOHmlCp8gC/kVKH
# +hDWbgKbQ/V15dV/c9WFpx2Iz5wOGMunbED2gh/HH3RkJV8VjtEjjKPfxz4AZ2g7
# hDC8k3rvux9dDzVsjI8Ljgx4Morkv7ZHqwf4HXz+t90s5e6fNg9KZ7OQweYahJPa
# ZJ9zf/akrktYNmIE2OyJbFPPh9mvlAoUL9PIUElmys3VYks0AUff3OEZhQHvBNcW
# YclvI6t6XXc2nb9L0N8b+048BBR2Xse/KyMddd7802N52MEpB0eexvlZ+0LTPIVy
# UdXq+MVfBwBArmhEkPbtqkmT7kJi+AaCnQ2YYg3OXivs42mkoJoh89yq76kdX72b
# U1eUt77K0eTgzPNN
# SIG # End signature block
