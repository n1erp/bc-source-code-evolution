function Run-AlTests
(
    [string] $TestSuite = $script:DefaultTestSuite,
    [string] $TestCodeunitsRange = "",
    [string] $TestProcedureRange = "",
    [string] $ExtensionId = "",
    [ValidateSet('None','Disabled','Codeunit','Function')]
    [string] $RequiredTestIsolation = "None",
    [string] $TestType,
    [ValidateSet("Disabled", "Codeunit")]
    [string] $TestIsolation = "Codeunit",
    [ValidateSet('Windows','NavUserPassword','AAD')]
    [string] $AutorizationType = $script:DefaultAuthorizationType,
    [string] $TestPage = $global:DefaultTestPage,
    [switch] $DisableSSLVerification,
    [Parameter(Mandatory=$true)]
    [string] $ServiceUrl,
    [Parameter(Mandatory=$false)]
    [pscredential] $Credential,
    [array] $DisabledTests = @(),
    [bool] $Detailed = $true,
    [ValidateSet('no','error','warning')]
    [string] $AzureDevOps = 'no',
    [bool] $SaveResultFile = $true,
    [string] $ResultsFilePath = "$PSScriptRoot\TestResults.xml",
    [ValidateSet('Disabled', 'PerRun', 'PerCodeunit', 'PerTest')]
    [string] $CodeCoverageTrackingType = 'Disabled',
    [ValidateSet('Disabled','PerCodeunit','PerTest')]
    [string] $ProduceCodeCoverageMap = 'Disabled',
    [string] $CodeCoverageOutputPath = "$PSScriptRoot\CodeCoverage",
    [string] $CodeCoverageExporterId = $script:DefaultCodeCoverageExporter,
    [switch] $CodeCoverageTrackAllSessions,
    [string] $CodeCoverageFilePrefix = ("TestCoverageMap_" + (get-date -Format 'yyyymmdd')),
    [bool] $StabilityRun
)
{
    $testRunArguments = @{
        TestSuite = $TestSuite
        TestCodeunitsRange = $TestCodeunitsRange
        TestProcedureRange = $TestProcedureRange
        ExtensionId = $ExtensionId
        RequiredTestIsolation = $RequiredTestIsolation
        TestType = $TestType
        TestRunnerId = (Get-TestRunnerId -TestIsolation $TestIsolation)
        CodeCoverageTrackingType = $CodeCoverageTrackingType
        ProduceCodeCoverageMap = $ProduceCodeCoverageMap
        CodeCoverageOutputPath = $CodeCoverageOutputPath
        CodeCoverageFilePrefix = $CodeCoverageFilePrefix
        CodeCoverageExporterId = $CodeCoverageExporterId
        AutorizationType = $AutorizationType
        TestPage = $TestPage
        DisableSSLVerification = $DisableSSLVerification
        ServiceUrl = $ServiceUrl
        Credential = $Credential
        DisabledTests = $DisabledTests
        Detailed = $Detailed
        StabilityRun = $StabilityRun
    }
    
    [array]$testRunResult = Run-AlTestsInternal @testRunArguments

    if($SaveResultFile)
    {
        Save-ResultsAsXUnitFile -TestRunResultObject $testRunResult -ResultsFilePath $ResultsFilePath
    }

    if($AzureDevOps  -ne 'no')
    {
        Report-ErrorsInAzureDevOps -AzureDevOps $AzureDevOps -TestRunResultObject $TestRunResultObject
    }
}

function Save-ResultsAsXUnitFile
(
    $TestRunResultObject,
    [string] $ResultsFilePath
)
{
    [xml]$XUnitDoc = New-Object System.Xml.XmlDocument
    $XUnitDoc.AppendChild($XUnitDoc.CreateXmlDeclaration("1.0","UTF-8",$null)) | Out-Null
    $XUnitAssemblies = $XUnitDoc.CreateElement("assemblies")
    $XUnitDoc.AppendChild($XUnitAssemblies) | Out-Null

    foreach($testResult in $TestRunResultObject)
    {
        $name = $testResult.name
        $startTime =  [datetime]($testResult.startTime)
        $finishTime = [datetime]($testResult.finishTime)
        $duration = $finishTime.Subtract($startTime)
        $durationSeconds = [Math]::Round($duration.TotalSeconds,3)

        $XUnitAssembly = $XUnitDoc.CreateElement("assembly")
        $XUnitAssemblies.AppendChild($XUnitAssembly) | Out-Null
        $XUnitAssembly.SetAttribute("name",$name)
        $XUnitAssembly.SetAttribute("x-code-unit",$testResult.codeUnit)
        $XUnitAssembly.SetAttribute("test-framework", "PS Test Runner")
        $XUnitAssembly.SetAttribute("run-date", $startTime.ToString("yyyy-MM-dd"))
        $XUnitAssembly.SetAttribute("run-time", $startTime.ToString("HH:mm:ss"))
        $XUnitAssembly.SetAttribute("total",0)
        $XUnitAssembly.SetAttribute("passed",0)
        $XUnitAssembly.SetAttribute("failed",0)
        $XUnitAssembly.SetAttribute("time", $durationSeconds.ToString([System.Globalization.CultureInfo]::InvariantCulture))
        $XUnitCollection = $XUnitDoc.CreateElement("collection")
        $XUnitAssembly.AppendChild($XUnitCollection) | Out-Null
        $XUnitCollection.SetAttribute("name",$name)
        $XUnitCollection.SetAttribute("total",0)
        $XUnitCollection.SetAttribute("passed",0)
        $XUnitCollection.SetAttribute("failed",0)
        $XUnitCollection.SetAttribute("skipped",0)
        $XUnitCollection.SetAttribute("time", $durationSeconds.ToString([System.Globalization.CultureInfo]::InvariantCulture))

        foreach($testMethod in $testResult.testResults)
        {
            $testMethodName = $testMethod.method
            $XUnitAssembly.SetAttribute("total",([int]$XUnitAssembly.GetAttribute("total") + 1))
            $XUnitCollection.SetAttribute("total",([int]$XUnitCollection.GetAttribute("total") + 1))
            $XUnitTest = $XUnitDoc.CreateElement("test")
            $XUnitCollection.AppendChild($XUnitTest) | Out-Null
            $XUnitTest.SetAttribute("name", $XUnitAssembly.GetAttribute("name") + ':' + $testMethodName)
            $XUnitTest.SetAttribute("method", $testMethodName)
            $startTime =  [datetime]($testMethod.startTime)
            $finishTime = [datetime]($testMethod.finishTime)
            $duration = $finishTime.Subtract($startTime)
            $durationSeconds = [Math]::Round($duration.TotalSeconds,3)
            $XUnitTest.SetAttribute("time", $durationSeconds.ToString([System.Globalization.CultureInfo]::InvariantCulture))

            switch($testMethod.result)
            {
                $script:SuccessTestResultType
                {
                    $XUnitAssembly.SetAttribute("passed",([int]$XUnitAssembly.GetAttribute("passed") + 1))
                    $XUnitCollection.SetAttribute("passed",([int]$XUnitCollection.GetAttribute("passed") + 1))
                    $XUnitTest.SetAttribute("result", "Pass")
                    break;
                }
                $script:FailureTestResultType
                {
                    $XUnitAssembly.SetAttribute("failed",([int]$XUnitAssembly.GetAttribute("failed") + 1))
                    $XUnitCollection.SetAttribute("failed",([int]$XUnitCollection.GetAttribute("failed") + 1))
                    $XUnitTest.SetAttribute("result", "Fail")
                    $XUnitFailure = $XUnitDoc.CreateElement("failure")
                    $XUnitMessage = $XUnitDoc.CreateElement("message")
                    $XUnitMessage.InnerText = $testMethod.message;
                    $XUnitFailure.AppendChild($XUnitMessage) | Out-Null
                    $XUnitStacktrace = $XUnitDoc.CreateElement("stack-trace")
                    $XUnitStacktrace.InnerText = $($testMethod.stackTrace).Replace(";","`n")
                    $XUnitFailure.AppendChild($XUnitStacktrace) | Out-Null
                    $XUnitTest.AppendChild($XUnitFailure) | Out-Null
                    break;
                }
                $script:SkippedTestResultType
                {
                    $XUnitCollection.SetAttribute("skipped",([int]$XUnitCollection.GetAttribute("skipped") + 1))
                    break;
                }
            }
        }
    }

    $XUnitDoc.Save($ResultsFilePath)
}

function Invoke-ALTestResultVerification
(
    [string] $TestResultsFolder = $(throw "Missing argument TestResultsFolder"),
    [switch] $IgnoreErrorIfNoTestsExecuted
)
{
    $failedTestList = Get-FailedTestsFromXMLFiles -TestResultsFolder $TestResultsFolder

    if($failedTestList.Count -gt 0) 
    {
        $testsExecuted = $true;
        Write-Log "Failed tests:"
        $testsFailed = ""
        foreach($failedTest in $failedTestList)
        {
            $testsFailed += "Name: " + $failedTest.name + [environment]::NewLine
            $testsFailed += "Method: " + $failedTest.method + [environment]::NewLine
            $testsFailed += "Time: " + $failedTest.time + [environment]::NewLine
            $testsFailed += "Message: " + [environment]::NewLine + $failedTest.message + [environment]::NewLine
            $testsFailed += "StackTrace: "+ [environment]::NewLine + $failedTest.stackTrace + [environment]::NewLine  + [environment]::NewLine
        }

        Write-Log $testsFailed
        throw "Test execution failed due to the failing tests, see the list of the failed tests above."
    }

    if(-not $testsExecuted)
    {
        [array]$testResultFiles = Get-ChildItem -Path $TestResultsFolder -Filter "*.xml" | Foreach { "$($_.FullName)" }

        foreach($resultFile in $testResultFiles)
        {
            [xml]$xmlDoc = Get-Content "$resultFile"
            [array]$otherTests = $xmlDoc.assemblies.assembly.collection.ChildNodes | Where-Object {$_.result -ne 'Fail'}
            if($otherTests.Length -gt 0)
            {
                return;
            }

        }

        if (-not $IgnoreErrorIfNoTestsExecuted) {
            throw "No test codeunits were executed"
        }
    }
}

function Get-FailedTestsFromXMLFiles
(
    [string] $TestResultsFolder = $(throw "Missing argument TestResultsFolder")
)
{
    $failedTestList = New-Object System.Collections.ArrayList
    $testsExecuted = $false
    [array]$testResultFiles = Get-ChildItem -Path $TestResultsFolder -Filter "*.xml" | Foreach { "$($_.FullName)" }

    if($testResultFiles.Length -eq 0)
    {
        throw "No test results were found"
    }

    foreach($resultFile in $testResultFiles)
    {
        [xml]$xmlDoc = Get-Content "$resultFile"
        [array]$failedTests = $xmlDoc.assemblies.assembly.collection.ChildNodes | Where-Object {$_.result -eq 'Fail'}
        if($failedTests)
        {
            $testsExecuted = $true
            foreach($failedTest in $failedTests)
            {
                $failedTestObject = @{
                    codeunitID = [int]($failedTest.ParentNode.ParentNode.'x-code-unit');
                    codeunitName = $failedTest.name;
                    method = $failedTest.method;
                    time = $failedTest.time;
                    message = $failedTest.failure.message;
                    stackTrace = $failedTest.failure.'stack-trace';
                }

                $failedTestList.Add($failedTestObject) > $null
            }
        }
    }

    return $failedTestList
}

function Write-DisabledTestsJson
(
    $FailedTests,
    [string] $OutputFolder = $(throw "Missing argument OutputFolder"),
    [string] $FileName = 'DisabledTests.json'
)
{
    $testsToDisable = New-Object -TypeName "System.Collections.ArrayList"
    foreach($failedTest in $failedTests)
    {
        $test = @{
                    codeunitID = $failedTest.codeunitID;
                    codeunitName = $failedTest.name;
                    method = $failedTest.method;
                }

       $testsToDisable.Add($test)
    }

    $oututFile = Join-Path $OutputFolder $FileName
    if(-not (Test-Path $outputFolder))
    {
        New-Item -Path $outputFolder -ItemType Directory
    }

    Add-Content -Value (ConvertTo-Json $testsToDisable) -Path $oututFile
}

function Report-ErrorsInAzureDevOps
(
    [ValidateSet('no','error','warning')]
    [string] $AzureDevOps = 'no',
    $TestRunResultObject
)
{
    if ($AzureDevOps -eq 'no')
    {
        return
    }

    $failedCodeunits = $TestRunResultObject | Where-Object { $_.result -eq $script:FailureTestResultType }
    $failedTests = $failedCodeunits.testResults | Where-Object { $_.result -eq $script:FailureTestResultType }

    foreach($failedTest in $failedTests)
    {
        $methodName = $failedTest.method;
        $errorMessage = $failedTests.message
        Write-Host "##vso[task.logissue type=$AzureDevOps;sourcepath=$methodName;]$errorMessage"
    }
}

function Get-DisabledAlTests
(
    [string] $DisabledTestsPath
)
{
    $DisabledTests = @()
    if(Test-Path $DisabledTestsPath)
    {
        $DisabledTests = Get-Content $DisabledTestsPath | ConvertFrom-Json
    }

    return $DisabledTests
}

function Get-TestRunnerId
(
    [ValidateSet("Disabled", "Codeunit")]
    [string] $TestIsolation = "Codeunit"
)
{
    switch($TestIsolation)
    {
        "Codeunit" 
        {
            return Get-CodeunitTestIsolationTestRunnerId
        }
        "Disabled"
        {
            return Get-DisabledTestIsolationTestRunnerId
        }
    }
}

function Get-DisabledTestIsolationTestRunnerId()
{
    return $global:TestRunnerIsolationDisabled
}

function Get-CodeunitTestIsolationTestRunnerId()
{
    return $global:TestRunnerIsolationCodeunit
}

$script:CodeunitLineType = '0'
$script:FunctionLineType = '1'

$script:FailureTestResultType = '1';
$script:SuccessTestResultType = '2';
$script:SkippedTestResultType = '3';

$script:DefaultAuthorizationType = 'NavUserPassword'
$script:DefaultTestSuite = 'DEFAULT'
$global:TestRunnerAppId = "23de40a6-dfe8-4f80-80db-d70f83ce8caf"
$script:DefaultCodeCoverageExporter = 130470;
Import-Module "$PSScriptRoot\Internal\ALTestRunnerInternal.psm1"
# SIG # Begin signature block
# MIIoHgYJKoZIhvcNAQcCoIIoDzCCKAsCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCASiPHx0XSFVzUd
# bfnLIjMNfYmTWwDYFg5nO7Qt2qOfsaCCDYUwggYDMIID66ADAgECAhMzAAAEhJji
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
# LwYJKoZIhvcNAQkEMSIEIDjVfbVqGuSfNyI+XDw88xpcnq4yL/6R9Zhv8Q6CX6a8
# MEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAzqvNH3cKtXRS
# 9Adh59Ly2cczPuH/aKLHXYHXxPy8ul/CwKvS01UpGGMvmof0nk4+I8OuYeFe5wKb
# g5YbVXKfwUkqnqYCF00kIxVcjD+vZsC/DUSIYiqsv4+mEaNRl9pzewYXIbueLGEz
# CCkR04uKHpvSYU+X/8q/knmvRRuKlkKs2pTwLhZiclkKA98QbaKznUtLSxAtc17m
# ThdXXVdsiieEoBK5OpVlHnn93gM8PsmcPblB09QVGqXwQHa7xEcCPgXO8FrjDKiM
# 4vkFDS/xcjUxe0ncpdOrqHnobfeK04TDplVZYFSa+eaL9OfUWILLGedbtXR+hAgD
# vQyF/iNpsKGCF5cwgheTBgorBgEEAYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCC
# F3AwghdsAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEE
# ggE9MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCBrhmsBoBkg
# rAwNrdVksVkyyTunF/JO8EafihLTXTSb+AIGaMmDdTLoGBMyMDI1MDkyNDE4MjIz
# OC41ODdaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25z
# MScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046ODYwMy0wNUUwLUQ5NDcxJTAjBgNV
# BAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghHtMIIHIDCCBQigAwIB
# AgITMwAAAgcsETmJzYX7xQABAAACBzANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yNTAxMzAxOTQyNTJaFw0yNjA0MjIxOTQy
# NTJaMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYD
# VQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hp
# ZWxkIFRTUyBFU046ODYwMy0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoIC
# AQDFP/96dPmcfgODe3/nuFveuBst/JmSxSkOn89ZFytHQm344iLoPqkVws+CiUej
# QabKf+/c7KU1nqwAmmtiPnG8zm4Sl9+RJZaQ4Dx3qtA9mdQdS7Chf6YUbP4Z++8l
# aNbTQigJoXCmzlV34vmC4zpFrET4KAATjXSPK0sQuFhKr7ltNaMFGclXSnIhcnSc
# j9QUDVLQpAsJtsKHyHN7cN74aEXLpFGc1I+WYFRxaTgqSPqGRfEfuQ2yGrAbWjJY
# OXueeTA1MVKhW8zzSEpfjKeK/t2XuKykpCUaKn5s8sqNbI3bHt/rE/pNzwWnAKz+
# POBRbJxIkmL+n/EMVir5u8uyWPl1t88MK551AGVh+2H4ziR14YDxzyCG924gaonK
# jicYnWUBOtXrnPK6AS/LN6Y+8Kxh26a6vKbFbzaqWXAjzEiQ8EY9K9pYI/KCygix
# jDwHfUgVSWCyT8Kw7mGByUZmRPPxXONluMe/P8CtBJMpuh8CBWyjvFfFmOSNRK8E
# TkUmlTUAR1CIOaeBqLGwscShFfyvDQrbChmhXib4nRMX5U9Yr9d7VcYHn6eZJsgy
# zh5QKlIbCQC/YvhFK42ceCBDMbc+Ot5R6T/Mwce5jVyVCmqXVxWOaQc4rA2nV7on
# MOZC6UvCG8LGFSZBnj1loDDLWo/I+RuRok2j/Q4zcMnwkQIDAQABo4IBSTCCAUUw
# HQYDVR0OBBYEFHK1UmLCvXrQCvR98JBq18/4zo0eMB8GA1UdIwQYMBaAFJ+nFV0A
# XmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWlj
# cm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQ
# Q0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
# VGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYD
# VR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEB
# CwUAA4ICAQDju0quPbnix0slEjD7j2224pYOPGTmdDvO0+bNRCNkZqUv07P04nf1
# If3Y/iJEmUaU7w12Fm582ImpD/Kw2ClXrNKLPTBO6nfxvOPGtalpAl4wqoGgZxvp
# xb2yEunG4yZQ6EQOpg1dE9uOXoze3gD4Hjtcc75kca8yivowEI+rhXuVUWB7vog4
# TGUxKdnDvpk5GSGXnOhPDhdId+g6hRyXdZiwgEa+q9M9Xctz4TGhDgOKFsYxFhXN
# JZo9KRuGq6evhtyNduYrkzjDtWS6gW8akR59UhuLGsVq+4AgqEY8WlXjQGM2OTky
# BnlQLpB8qD7x9jRpY2Cq0OWWlK0wfH/1zefrWN5+be87Sw2TPcIudIJn39bbDG7a
# wKMVYDHfsPJ8ZvxgWkZuf6ZZAkph0eYGh3IV845taLkdLOCvw49Wxqha5Dmi2Ojh
# 8Gja5v9kyY3KTFyX3T4C2scxfgp/6xRd+DGOhNVPvVPa/3yRUqY5s5UYpy8Dnbpp
# V7nQO2se3HvCSbrb+yPyeob1kUfMYa9fE2bEsoMbOaHRgGji8ZPt/Jd2bPfdQoBH
# cUOqPwjHBUIcSc7xdJZYjRb4m81qxjma3DLjuOFljMZTYovRiGvEML9xZj2pHRUy
# v+s5v7VGwcM6rjNYM4qzZQM6A2RGYJGU780GQG0QO98w+sucuTVrfTCCB3EwggVZ
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
# ZCBUU1MgRVNOOjg2MDMtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQDTvVU/Yj9lUSyeDCaiJ2Da
# 5hUiS6CBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
# SIb3DQEBCwUAAgUA7H6M9DAiGA8yMDI1MDkyNDE1Mjk1NloYDzIwMjUwOTI1MTUy
# OTU2WjB3MD0GCisGAQQBhFkKBAExLzAtMAoCBQDsfoz0AgEAMAoCAQACAghdAgH/
# MAcCAQACAhViMAoCBQDsf950AgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQB
# hFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEB
# ABbM+qFcB+Yahh3F1yPpxyYDLrAPYCulMw2qMzbUnAp+Yo3Ddy97D2t0JKdckUHH
# rHfO2K6INQLMKoiUTjuPCZpg+zUfVKYlwMRltyr6nsnuntHb/rdj5chmDdGIaCnt
# lpn/qQX3fjW6q0TnyYvNdQuOH2ZqzGeaRfOg5uiREpuZU6aeLJ2UQ00DJBNPP/ZI
# 1R8UReP7YoDevk1QNkJFxmrawEcj/Jy0C5TP5+l1IBLgI2muPqAGfAymygZfWb4z
# KXlUI7Zy+E5DpPe/qbMJPIrgmJr7nCcEYPHMs60rRgHuvSFThE2KAR/PraEK2vxE
# +5lpJUlV8Onw+TDN2lrX3rYxggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMAITMwAAAgcsETmJzYX7xQABAAACBzANBglghkgBZQMEAgEF
# AKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEi
# BCCCV/siayJfoWwx+aL+Y/fyT2H47xZjTOsmYXOOq3/XQjCB+gYLKoZIhvcNAQkQ
# Ai8xgeowgecwgeQwgb0EIC/31NHQds1IZ5sPnv59p+v6BjBDgoDPIwiAmn0PHqez
# MIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAO
# BgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEm
# MCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIHLBE5
# ic2F+8UAAQAAAgcwIgQg9WuUOwt6htaq9NTBXwjHPA6rInIONbOIb7w8ALV9kb8w
# DQYJKoZIhvcNAQELBQAEggIATJSBkQb4Zc+Dg0WCesmtygENewlSY8z2e/t4eEfI
# WBgbRWJNnMeENXPeAR6OeASAO8Ka7vVpWkOq/s0QG/k4AZcifwI+B26MHhUKBcTR
# 2XEQ7sQOn5xMwzDv/j8+/aTWTAhUhGXj4/OSf/pOHkG6h8TIfUmk3Mkd1mKlXpu+
# tctYnRWieVDnEsQpS3Wr4qBJncxmkLXL164AK5TpJ4ffwKzwpwebSls5XLTacyhj
# PU33SCON0IcMelmk6Mp2m3PXRvQTks0r0FD/LQ1s6W5O5dqPzrEBa/7OfnzD5Mun
# UFoXEhi62Lu4myV1avORqQUcJWeENizVH9Z696EQADYWuC1pKxWPijSYUVPPw1Nm
# xjUQQ1ukdFEloGfRYZsvaOO3oAyUKQhU5y+T/pVDJlwlcPttcnZR6V24P/GA1ma1
# rqsT5kF3j2PVbxdSPJOMLgmThWsz6HfPybBxl0c/mU0kladPqcz2ONAs2NxLcaJZ
# LyJ6dtkPagPqS7VL4G7tM0fG81Y81e7YOslsu8sWCmTRps99W3c0KVkNDKipuvOe
# pPwxLJ5l5ngeiESunvSMKvyjC9Chrv14TO5KIDBFRvxX6rUcOtkilgSrRcLirX+W
# qIdIyMdmrm5iZOyIdqubwwcmFXk8d9+LHS0/ieINHgnr3sk/jjVP9zON4nLSJOuD
# q1Q=
# SIG # End signature block
