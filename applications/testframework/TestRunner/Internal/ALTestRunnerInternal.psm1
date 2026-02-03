function Run-AlTestsInternal
(
    [string] $TestSuite = $script:DefaultTestSuite,
    [string] $TestCodeunitsRange = "",
    [string] $TestProcedureRange = "",
    [string] $ExtensionId = "",
    [ValidateSet('None','Disabled','Codeunit','Function')]
    [string] $RequiredTestIsolation = "None",
    [string] $TestType,
    [int] $TestRunnerId = $global:DefaultTestRunner,
    [ValidateSet('Windows','NavUserPassword','AAD')]
    [string] $AutorizationType = $script:DefaultAuthorizationType,
    [string] $TestPage = $global:DefaultTestPage,
    [switch] $DisableSSLVerification,
    [Parameter(Mandatory=$true)]
    [string] $ServiceUrl,
    [Parameter(Mandatory=$false)]
    [pscredential] $Credential,
    [bool] $Detailed = $true,
    [array] $DisabledTests = @(),
    [ValidateSet('Disabled', 'PerRun', 'PerCodeunit', 'PerTest')]
    [string] $CodeCoverageTrackingType = 'Disabled',
    [ValidateSet('Disabled','PerCodeunit','PerTest')]
    [string] $ProduceCodeCoverageMap = 'Disabled',
    [string] $CodeCoverageOutputPath = "$PSScriptRoot\CodeCoverage",
    [string] $CodeCoverageExporterId,
    [switch] $CodeCoverageTrackAllSessions,
    [string] $CodeCoverageFilePrefix,
    [bool] $StabilityRun
)
{
    $ErrorActionPreference = $script:DefaultErrorActionPreference
   
    Setup-TestRun -DisableSSLVerification:$DisableSSLVerification -AutorizationType $AutorizationType -Credential $Credential -ServiceUrl $ServiceUrl -TestSuite $TestSuite `
        -TestCodeunitsRange $TestCodeunitsRange -TestProcedureRange $TestProcedureRange -ExtensionId $ExtensionId -RequiredTestIsolation $RequiredTestIsolation -TestType $TestType `
        -TestRunnerId $TestRunnerId -TestPage $TestPage -DisabledTests $DisabledTests -CodeCoverageTrackingType $CodeCoverageTrackingType -CodeCoverageTrackAllSessions:$CodeCoverageTrackAllSessions -CodeCoverageOutputPath $CodeCoverageOutputPath -CodeCoverageExporterId $CodeCoverageExporterId -ProduceCodeCoverageMap $ProduceCodeCoverageMap -StabilityRun $StabilityRun
            
    $testRunResults = New-Object System.Collections.ArrayList 
    $testResult = ''
    $numberOfUnexpectedFailures = 0;

    do
    {
        try
        {
            $testStartTime = $(Get-Date)
            $testResult = Run-NextTest -DisableSSLVerification:$DisableSSLVerification -AutorizationType $AutorizationType -Credential $Credential -ServiceUrl $ServiceUrl -TestSuite $TestSuite
            if($testResult -eq $script:AllTestsExecutedResult)
            {
                return [Array]$testRunResults
            }
 
            $testRunResultObject = ConvertFrom-Json $testResult
            if($CodeCoverageTrackingType -ne 'Disabled') {
                $null = CollectCoverageResults -TrackingType $CodeCoverageTrackingType -OutputPath $CodeCoverageOutputPath -DisableSSLVerification:$DisableSSLVerification -AutorizationType $AutorizationType -Credential $Credential -ServiceUrl $ServiceUrl -CodeCoverageFilePrefix $CodeCoverageFilePrefix
            }
       }
        catch
        {
            $numberOfUnexpectedFailures++

            $stackTrace = $_.Exception.StackTrace + "Script stack trace: " + $_.ScriptStackTrace 
            $testMethodResult = @{
                method = "Unexpected Failure"
                codeUnit = "Unexpected Failure"
                startTime = $testStartTime.ToString($script:DateTimeFormat)
                finishTime = ($(Get-Date).ToString($script:DateTimeFormat))
                result = $script:FailureTestResultType
                message = $_.Exception.Message
                stackTrace = $stackTrace
            }

            $testRunResultObject = @{
                name = "Unexpected Failure"
                codeUnit = "UnexpectedFailure"
                startTime = $testStartTime.ToString($script:DateTimeFormat)
                finishTime = ($(Get-Date).ToString($script:DateTimeFormat))
                result = $script:FailureTestResultType
                testResults = @($testMethodResult)
            }
        }
        
        $testRunResults.Add($testRunResultObject) > $null
        if($Detailed)
        {
            Print-TestResults -TestRunResultObject $testRunResultObject
        }
    }
    until((!$testRunResultObject) -or ($NumberOfUnexpectedFailuresBeforeAborting -lt $numberOfUnexpectedFailures))

    throw "Expected to end the test execution, something went wrong with returning test results."      
}

function CollectCoverageResults {
    param (
        [ValidateSet('PerRun', 'PerCodeunit', 'PerTest')]
        [string] $TrackingType,
        [string] $OutputPath,
        [switch] $DisableSSLVerification,
        [ValidateSet('Windows','NavUserPassword','AAD')]
        [string] $AutorizationType = $script:DefaultAuthorizationType,
        [Parameter(Mandatory=$false)]
        [pscredential] $Credential,
        [Parameter(Mandatory=$true)]
        [string] $ServiceUrl,
        [string] $CodeCoverageFilePrefix
    )
    try{
        $clientContext = Open-ClientSessionWithWait -DisableSSLVerification:$DisableSSLVerification -AuthorizationType $AutorizationType -Credential $Credential -ServiceUrl $ServiceUrl
        $form = Open-TestForm -TestPage $TestPage -ClientContext $clientContext
        do {
            $clientContext.InvokeAction($clientContext.GetActionByName($form, "GetCodeCoverage"))

            $CCResultControl = $clientContext.GetControlByName($form, "CCResultsCSVText")
            $CCInfoControl = $clientContext.GetControlByName($form, "CCInfo")
            $CCResult = $CCResultControl.StringValue
            $CCInfo = $CCInfoControl.StringValue
            if($CCInfo -ne $script:CCCollectedResult){
                $CCInfo = $CCInfo -replace ",","-"
                $CCOutputFilename = $CodeCoverageFilePrefix +"_$CCInfo.dat"
                Write-Host "Storing coverage results of $CCCodeunitId in:  $OutputPath\$CCOutputFilename"
                Set-Content -Path "$OutputPath\$CCOutputFilename" -Value $CCResult
            }
        } while ($CCInfo -ne $script:CCCollectedResult)
       
        if($ProduceCodeCoverageMap -ne 'Disabled') {
            $codeCoverageMapPath = Join-Path $OutputPath "TestCoverageMap"
            SaveCodeCoverageMap -OutputPath $codeCoverageMapPath  -DisableSSLVerification:$DisableSSLVerification -AutorizationType $AutorizationType -Credential $Credential -ServiceUrl $ServiceUrl
        }

        $clientContext.CloseForm($form)
    }
    finally{
        if($clientContext){
            $clientContext.Dispose()
        }
    }
}

function SaveCodeCoverageMap {
    param (
        [string] $OutputPath,
        [switch] $DisableSSLVerification,
        [ValidateSet('Windows','NavUserPassword','AAD')]
        [string] $AutorizationType = $script:DefaultAuthorizationType,
        [Parameter(Mandatory=$false)]
        [pscredential] $Credential,
        [Parameter(Mandatory=$true)]
        [string] $ServiceUrl
    )
    try{
        $clientContext = Open-ClientSessionWithWait -DisableSSLVerification:$DisableSSLVerification -AuthorizationType $AutorizationType -Credential $Credential -ServiceUrl $ServiceUrl
        $form = Open-TestForm -TestPage $TestPage -ClientContext $clientContext

        $clientContext.InvokeAction($clientContext.GetActionByName($form, "GetCodeCoverageMap"))

        $CCResultControl = $clientContext.GetControlByName($form, "CCMapCSVText")
        $CCMap = $CCResultControl.StringValue

        if (-not (Test-Path $OutputPath))
        {
            New-Item $OutputPath -ItemType Directory
        }
        
        $codeCoverageMapFileName = Join-Path $codeCoverageMapPath "TestCoverageMap.txt"
        if (-not (Test-Path $codeCoverageMapFileName))
        {
            New-Item $codeCoverageMapFileName -ItemType File
        }

        Add-Content -Path $codeCoverageMapFileName -Value $CCMap

        $clientContext.CloseForm($form)
    }
    finally{
        if($clientContext){
            $clientContext.Dispose()
        }
    }
}

function Print-TestResults
(
    $TestRunResultObject
)
{              
    $startTime = Convert-ResultStringToDateTimeSafe -DateTimeString $TestRunResultObject.startTime
    $finishTime = Convert-ResultStringToDateTimeSafe -DateTimeString $TestRunResultObject.finishTime
    $duration = $finishTime.Subtract($startTime)
    $durationSeconds = [Math]::Round($duration.TotalSeconds,3)

    switch($TestRunResultObject.result)
    {
        $script:SuccessTestResultType
        {
            Write-Host -ForegroundColor Green "Success - Codeunit $($TestRunResultObject.name) - Duration $durationSeconds seconds"
            break;
        }
        $script:FailureTestResultType
        {
            Write-Host -ForegroundColor Red "Failure - Codeunit $($TestRunResultObject.name) -  Duration $durationSeconds seconds"
            break;
        }
        default
        {
            if($codeUnitId -ne "0")
            {
                Write-Host -ForegroundColor Yellow "No tests were executed - Codeunit $"
            }
        }
    }

    if($TestRunResultObject.testResults)
    {
        foreach($testFunctionResult in $TestRunResultObject.testResults)
        {
            $durationSeconds = 0;
            $methodName = $testFunctionResult.method

            if($testFunctionResult.result -ne $script:SkippedTestResultType)
            {
                $startTime = Convert-ResultStringToDateTimeSafe -DateTimeString $testFunctionResult.startTime
                $finishTime = Convert-ResultStringToDateTimeSafe -DateTimeString $testFunctionResult.finishTime
                $duration = $finishTime.Subtract($startTime)
                $durationSeconds = [Math]::Round($duration.TotalSeconds,3)
            }

            switch($testFunctionResult.result)
            {
                $script:SuccessTestResultType
                {
                    Write-Host -ForegroundColor Green "   Success - Test method: $methodName - Duration $durationSeconds seconds)"
                    break;
                }
                $script:FailureTestResultType
                {
                    $callStack = $testFunctionResult.stackTrace
                    Write-Host -ForegroundColor Red "   Failure - Test method: $methodName - Duration $durationSeconds seconds"
                    Write-Host -ForegroundColor Red "      Error:"
                    Write-Host -ForegroundColor Red "         $($testFunctionResult.message)"
                    Write-Host -ForegroundColor Red "      Call Stack:"                    
                    if($callStack)
                    {
                        Write-Host -ForegroundColor Red "         $($callStack.Replace(';',"`n         "))"
                    }
                    break;
                }
                $script:SkippedTestResultType
                {
                    Write-Host -ForegroundColor Yellow "   Skipped - Test method: $methodName"
                    break;
                }
            }
        }
    }            
}

function Setup-TestRun
(
    [switch] $DisableSSLVerification,
    [ValidateSet('Windows','NavUserPassword','AAD')]
    [string] $AutorizationType = $script:DefaultAuthorizationType,
    [Parameter(Mandatory=$false)]
    [pscredential] $Credential,
    [Parameter(Mandatory=$true)]
    [string] $ServiceUrl,
    [string] $TestSuite = $script:DefaultTestSuite,
    [string] $TestCodeunitsRange = "",
    [string] $TestProcedureRange = "",
    [string] $ExtensionId = "",
    [ValidateSet('None','Disabled','Codeunit','Function')]
    [string] $RequiredTestIsolation = "None",
    [string] $TestType,
    [int] $TestRunnerId = $global:DefaultTestRunner,
    [string] $TestPage = $global:DefaultTestPage,
    [array] $DisabledTests = @(),
    [ValidateSet('Disabled', 'PerRun', 'PerCodeunit', 'PerTest')]
    [string] $CodeCoverageTrackingType = 'Disabled',
    [ValidateSet('Disabled','PerCodeunit','PerTest')]
    [string] $ProduceCodeCoverageMap = 'Disabled',
    [string] $CodeCoverageOutputPath = "$PSScriptRoot\CodeCoverage",
    [string] $CodeCoverageExporterId,
    [switch] $CodeCoverageTrackAllSessions,
    [bool] $StabilityRun
)
{
    Write-Log "Setting up test run: $CodeCoverageTrackingType - $CodeCoverageOutputPath"
    if($CodeCoverageTrackingType -ne 'Disabled')
    {
        if (-not (Test-Path -Path $CodeCoverageOutputPath))
        {
            $null = New-Item -Path $CodeCoverageOutputPath -ItemType Directory
        }
    }

    try
    {
        $clientContext = Open-ClientSessionWithWait -DisableSSLVerification:$DisableSSLVerification -AuthorizationType $AutorizationType -Credential $Credential -ServiceUrl $ServiceUrl 

        $form = Open-TestForm -TestPage $TestPage -DisableSSLVerification:$DisableSSLVerification -AuthorizationType $AutorizationType -ClientContext $clientContext
        Set-TestSuite -TestSuite $TestSuite -ClientContext $clientContext -Form $form
        Set-ExtensionId -ExtensionId $ExtensionId -Form $form -ClientContext $clientContext
        if (![string]::IsNullOrEmpty($TestType)) {
            Set-RequiredTestIsolation -RequiredTestIsolation $RequiredTestIsolation -Form $form -ClientContext $clientContext
            Set-TestType -TestType $TestType -Form $form -ClientContext $clientContext
        }
        Set-TestCodeunits -TestCodeunitsFilter $TestCodeunitsRange -Form $form -ClientContext $clientContext
        Set-TestProcedures -Filter $TestProcedureRange -Form $form $ClientContext $clientContext
        Set-TestRunner -TestRunnerId $TestRunnerId -Form $form -ClientContext $clientContext
        Set-RunFalseOnDisabledTests -DisabledTests $DisabledTests -Form $form -ClientContext $clientContext
        Set-StabilityRun -StabilityRun $StabilityRun -Form $form -ClientContext $clientContext
        Clear-TestResults -Form $form -ClientContext $clientContext
        if($CodeCoverageTrackingType -ne 'Disabled'){
            Set-CCTrackingType -Value $CodeCoverageTrackingType -Form $form -ClientContext $clientContext
            Set-CCTrackAllSessions -Value:$CodeCoverageTrackAllSessions -Form $form -ClientContext $clientContext
            Set-CCExporterID -Value $CodeCoverageExporterId -Form $form -ClientContext $clientContext
            Clear-CCResults -Form $form -ClientContext $clientContext
            Set-CCProduceCodeCoverageMap -Value $ProduceCodeCoverageMap -Form $form -ClientContext $clientContext
        }
        $clientContext.CloseForm($form)
    }
    finally
    {
        if($clientContext)
        {
            $clientContext.Dispose()
        }
        Write-Log "Complete Test Setup"
    }
}

function Run-NextTest
(
    [switch] $DisableSSLVerification,
    [ValidateSet('Windows','NavUserPassword','AAD')]
    [string] $AutorizationType = $script:DefaultAuthorizationType,
    [Parameter(Mandatory=$false)]
    [pscredential] $Credential,
    [Parameter(Mandatory=$true)]
    [string] $ServiceUrl,
    [string] $TestSuite = $script:DefaultTestSuite
)
{
    try
    {
        $clientContext = Open-ClientSessionWithWait -DisableSSLVerification:$DisableSSLVerification -AuthorizationType $AutorizationType -Credential $Credential -ServiceUrl $ServiceUrl
        $form = Open-TestForm -TestPage $TestPage -DisableSSLVerification:$DisableSSLVerification -AuthorizationType $AutorizationType -ClientContext $clientContext
        if($TestSuite -ne $script:DefaultTestSuite)
        {
            Set-TestSuite -TestSuite $TestSuite -ClientContext $clientContext -Form $form
        }

        $clientContext.InvokeAction($clientContext.GetActionByName($form, "RunNextTest"))
        
        $testResultControl = $clientContext.GetControlByName($form, "TestResultJson")
        $testResultJson = $testResultControl.StringValue
        $clientContext.CloseForm($form)
        return $testResultJson
    }
    finally
    {
        if($clientContext)
        {
            $clientContext.Dispose()
        }
    } 
}

function Open-ClientSessionWithWait
(
    [ValidateSet('Windows','NavUserPassword','AAD')]
    [string] $AuthorizationType = $script:DefaultAuthorizationType,
    [switch] $DisableSSLVerification,
    [string] $ServiceUrl,
    [pscredential] $Credential,
    [int] $ClientSessionTimeout = 20,
    [timespan] $TransactionTimeout = $script:DefaultTransactionTimeout,
    [string] $Culture = $script:DefaultCulture
)
{
        $lastErrorMessage = ""
        while(($ClientSessionTimeout -gt 0))
        {
            try
            {
                $clientContext = Open-ClientSession -DisableSSLVerification:$DisableSSLVerification -AuthorizationType $AuthorizationType -Credential $Credential -ServiceUrl $ServiceUrl -TransactionTimeout $TransactionTimeout -Culture $Culture
                return $clientContext
            }
            catch
            {
                Start-Sleep -Seconds 1
                $ClientSessionTimeout--
                $lastErrorMessage = $_.Exception.Message
            }
        }

        throw "Could not open the client session. Check if the web server is running and you can log in. Last error: $lastErrorMessage"
}

function Set-TestCodeunits
(
    [string] $TestCodeunitsFilter,
    [ClientContext] $ClientContext,
    $Form
)
{
    if(!$TestCodeunitsFilter)
    {
        return
    }

    $testCodeunitRangeFilterControl = $ClientContext.GetControlByName($Form, "TestCodeunitRangeFilter")
    $ClientContext.SaveValue($testCodeunitRangeFilterControl, $TestCodeunitsFilter)
}

function Set-TestRunner
(
    [int] $TestRunnerId,
    [ClientContext] $ClientContext,
    $Form
)
{
    if(!$TestRunnerId)
    {
        return
    }

    $testRunnerCodeunitIdControl = $ClientContext.GetControlByName($Form, "TestRunnerCodeunitId")
    $ClientContext.SaveValue($testRunnerCodeunitIdControl, $TestRunnerId)
}

function Clear-TestResults
(
    [ClientContext] $ClientContext,
    $Form
)
{
    $ClientContext.InvokeAction($ClientContext.GetActionByName($Form, "ClearTestResults"))
}

function Set-ExtensionId
(
    [string] $ExtensionId,
    [ClientContext] $ClientContext,
    $Form
)
{
    if(!$ExtensionId)
    {
        return
    }

    $extensionIdControl = $ClientContext.GetControlByName($Form, "ExtensionId")
    $ClientContext.SaveValue($extensionIdControl, $ExtensionId)
}

function Set-RequiredTestIsolation {
    param (
        [ValidateSet('None','Disabled','Codeunit','Function')]
        [string] $RequiredTestIsolation = "None",
        [ClientContext] $ClientContext,
        $Form
    )
    $TestIsolationValues = @{
        None = 0
        Disabled = 1
        Codeunit = 2
        Function = 3
    }
    $testIsolationControl = $ClientContext.GetControlByName($Form, "RequiredTestIsolation")
    $ClientContext.SaveValue($testIsolationControl, $TestIsolationValues[$RequiredTestIsolation])
}

function Set-TestType {
    param (
        [ValidateSet("UnitTest","IntegrationTest","Uncategorized")]
        [string] $TestType,
        [ClientContext] $ClientContext,
        $Form
    )
    $TypeValues = @{    
        UnitTest = 1
        IntegrationTest = 2
        Uncategorized = 3
    }
    $testTypeControl = $ClientContext.GetControlByName($Form, "TestType")
    $ClientContext.SaveValue($testTypeControl, $TypeValues[$TestType])
}

function Set-TestSuite
(
    [string] $TestSuite = $script:DefaultTestSuite,
    [ClientContext] $ClientContext,
    $Form
)
{
    $suiteControl = $ClientContext.GetControlByName($Form, "CurrentSuiteName")
    $ClientContext.SaveValue($suiteControl, $TestSuite)
}

function Set-CCTrackingType
{
    param (
        [ValidateSet('Disabled', 'PerRun', 'PerCodeunit', 'PerTest')]
        [string] $Value,
        [ClientContext] $ClientContext,
        $Form
    )
    $TypeValues = @{
        Disabled = 0
        PerRun = 1
        PerCodeunit=2
        PerTest=3
    }
    $suiteControl = $ClientContext.GetControlByName($Form, "CCTrackingType")
    $ClientContext.SaveValue($suiteControl, $TypeValues[$Value])
}

function Set-CCTrackAllSessions
{
    param (
        [switch] $Value,
        [ClientContext] $ClientContext,
        $Form
    )
    if($Value){
        $suiteControl = $ClientContext.GetControlByName($Form, "CCTrackAllSessions");
        $ClientContext.SaveValue($suiteControl, $Value)
    }
}

function Set-CCExporterID
{
    param (
        [string] $Value,
        [ClientContext] $ClientContext,
        $Form
    )
    if($Value){
        $suiteControl = $ClientContext.GetControlByName($Form, "CCExporterID");
        $ClientContext.SaveValue($suiteControl, $Value)
    }
}

function Set-CCProduceCodeCoverageMap
{

    param (
        [ValidateSet('Disabled', 'PerCodeunit', 'PerTest')]
        [string] $Value,
        [ClientContext] $ClientContext,
        $Form
    )
    $TypeValues = @{
        Disabled = 0
        PerCodeunit = 1
        PerTest=2
    }
    $suiteControl = $ClientContext.GetControlByName($Form, "CCMap")
    $ClientContext.SaveValue($suiteControl, $TypeValues[$Value])
}

function Set-TestProcedures
{
    param (
        [string] $Filter,
        [ClientContext] $ClientContext,
        $Form
    )
    $Control = $ClientContext.GetControlByName($Form, "TestProcedureRangeFilter")
    $ClientContext.SaveValue($Control, $Filter)
}

function Clear-CCResults
{
    param (
        [ClientContext] $ClientContext,
        $Form
    )
    $ClientContext.InvokeAction($ClientContext.GetActionByName($Form, "ClearCodeCoverage"))
}
function Set-StabilityRun
(
    [bool] $StabilityRun,
    [ClientContext] $ClientContext,
    $Form
)
{
    $stabilityRunControl = $ClientContext.GetControlByName($Form, "StabilityRun")
    $ClientContext.SaveValue($stabilityRunControl, $StabilityRun)
}

function Set-RunFalseOnDisabledTests
(
    [ClientContext] $ClientContext,
    [array] $DisabledTests,
    $Form
)
{
    if(!$DisabledTests)
    {
        return
    }

    foreach($disabledTestMethod in $DisabledTests)
    {
        $testKey = $disabledTestMethod.codeunitName + "," + $disabledTestMethod.method
        $removeTestMethodControl = $ClientContext.GetControlByName($Form, "DisableTestMethod")
        $ClientContext.SaveValue($removeTestMethodControl, $testKey)
    }
}

function Open-TestForm(
    [int] $TestPage = $global:DefaultTestPage,
    [ClientContext] $ClientContext
)
{ 
    $form = $ClientContext.OpenForm($TestPage)
    if (!$form) 
    {
        throw "Cannot open page $TestPage. Verify if the test tool and test objects are imported and can be opened manually."
    }

    return $form;
}

function Open-ClientSession
(
    [switch] $DisableSSLVerification,
    [ValidateSet('Windows','NavUserPassword','AAD')]
    [string] $AuthorizationType,
    [Parameter(Mandatory=$false)]
    [pscredential] $Credential,
    [Parameter(Mandatory=$true)]
    [string] $ServiceUrl,
    [string] $Culture = $script:DefaultCulture,
    [timespan] $TransactionTimeout = $script:DefaultTransactionTimeout,
    [timespan] $TcpKeepActive = $script:DefaultTcpKeepActive
)
{
    [System.Net.ServicePointManager]::SetTcpKeepAlive($true, [int]$TcpKeepActive.TotalMilliseconds, [int]$TcpKeepActive.TotalMilliseconds)

    if($DisableSSLVerification)
    {
        Disable-SslVerification
    }

    switch ($AuthorizationType)
    {
        "Windows" 
        {
            $clientContext = [ClientContext]::new($ServiceUrl, $TransactionTimeout, $Culture)
            break;
        }
        "NavUserPassword" 
        {
            if ($Credential -eq $null -or $Credential -eq [System.Management.Automation.PSCredential]::Empty) 
            {
                throw "You need to specify credentials if using NavUserPassword authentication"
            }
        
            $clientContext = [ClientContext]::new($ServiceUrl, $Credential, $TransactionTimeout, $Culture)
            break;
        }
        "AAD"
        {
            $AadTokenProvider = $global:AadTokenProvider
            if ($AadTokenProvider -eq $null) 
            {
                throw "You need to specify the AadTokenProvider for obtaining the token if using AAD authentication"
            }

            $token = $AadTokenProvider.GetToken($Credential)
            $tokenCredential = [Microsoft.Dynamics.Framework.UI.Client.TokenCredential]::new($token)
            $clientContext = [ClientContext]::new($ServiceUrl, $tokenCredential, $TransactionTimeout, $Culture)
        }
    }

    return $clientContext;
}

function Disable-SslVerification
{
    if (-not ([System.Management.Automation.PSTypeName]"SslVerification").Type)
    {
        Add-Type -TypeDefinition  @"
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;
public static class SslVerification
{
    private static bool ValidationCallback(object sender, X509Certificate certificate, X509Chain chain, SslPolicyErrors sslPolicyErrors) { return true; }
    public static void Disable() { System.Net.ServicePointManager.ServerCertificateValidationCallback = ValidationCallback; }
    public static void Enable()  { System.Net.ServicePointManager.ServerCertificateValidationCallback = null; }
}
"@
    }
    [SslVerification]::Disable()
}

function Enable-SslVerification
{
    if (([System.Management.Automation.PSTypeName]"SslVerification").Type)
    {
        [SslVerification]::Enable()
    }
}


function Convert-ResultStringToDateTimeSafe([string] $DateTimeString)
{
    [datetime]$parsedDateTime = New-Object DateTime
    
    try
    {
        [datetime]$parsedDateTime = [datetime]$DateTimeString
    }
    catch
    {
        Write-Host -ForegroundColor Red "Failed parsing DateTime: $DateTimeString"
    }

    return $parsedDateTime
}

if(!$script:TypesLoaded)
{
    Add-type -Path "$PSScriptRoot\Microsoft.Dynamics.Framework.UI.Client.dll"
    Add-type -Path "$PSScriptRoot\Microsoft.Internal.AntiSSRF.dll"
    Add-type -Path "$PSScriptRoot\NewtonSoft.Json.dll"
    
    $clientContextScriptPath = Join-Path $PSScriptRoot "ClientContext.ps1"
    . "$clientContextScriptPath"
}

$script:TypesLoaded = $true;

$script:ActiveDirectoryDllsLoaded = $false;
$script:DateTimeFormat = 's';

# Console test tool
$global:DefaultTestPage = 130455;
$global:AadTokenProvider = $null

# Test Isolation Disabled
$global:TestRunnerIsolationCodeunit = 130450
$global:TestRunnerIsolationDisabled = 130451
$global:DefaultTestRunner = $global:TestRunnerIsolationCodeunit
$global:TestRunnerAppId = "23de40a6-dfe8-4f80-80db-d70f83ce8caf"

$script:CodeunitLineType = '0'
$script:FunctionLineType = '1'

$script:FailureTestResultType = '1';
$script:SuccessTestResultType = '2';
$script:SkippedTestResultType = '3';

$script:NumberOfUnexpectedFailuresBeforeAborting = 50;

$script:DefaultAuthorizationType = 'NavUserPassword'
$script:DefaultTestSuite = 'DEFAULT'
$script:DefaultErrorActionPreference = 'Stop'

$script:DefaultTcpKeepActive = [timespan]::FromMinutes(2);
$script:DefaultTransactionTimeout = [timespan]::FromMinutes(10);
$script:DefaultCulture = "en-US";

$script:AllTestsExecutedResult = "All tests executed."
$script:CCCollectedResult = "Done."
Export-ModuleMember -Function Run-AlTestsInternal,Open-ClientSessionWithWait, Open-TestForm, Open-ClientSession
# SIG # Begin signature block
# MIIoKAYJKoZIhvcNAQcCoIIoGTCCKBUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBKIDSqOm9oUE5X
# OIY+HhcPvHEV7QPv41mMaq8LxValSqCCDXYwggX0MIID3KADAgECAhMzAAAEhV6Z
# 7A5ZL83XAAAAAASFMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjUwNjE5MTgyMTM3WhcNMjYwNjE3MTgyMTM3WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDASkh1cpvuUqfbqxele7LCSHEamVNBfFE4uY1FkGsAdUF/vnjpE1dnAD9vMOqy
# 5ZO49ILhP4jiP/P2Pn9ao+5TDtKmcQ+pZdzbG7t43yRXJC3nXvTGQroodPi9USQi
# 9rI+0gwuXRKBII7L+k3kMkKLmFrsWUjzgXVCLYa6ZH7BCALAcJWZTwWPoiT4HpqQ
# hJcYLB7pfetAVCeBEVZD8itKQ6QA5/LQR+9X6dlSj4Vxta4JnpxvgSrkjXCz+tlJ
# 67ABZ551lw23RWU1uyfgCfEFhBfiyPR2WSjskPl9ap6qrf8fNQ1sGYun2p4JdXxe
# UAKf1hVa/3TQXjvPTiRXCnJPAgMBAAGjggFzMIIBbzAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUuCZyGiCuLYE0aU7j5TFqY05kko0w
# RQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEW
# MBQGA1UEBRMNMjMwMDEyKzUwNTM1OTAfBgNVHSMEGDAWgBRIbmTlUAXTgqoXNzci
# tW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3JsMGEG
# CCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3J0
# MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBACjmqAp2Ci4sTHZci+qk
# tEAKsFk5HNVGKyWR2rFGXsd7cggZ04H5U4SV0fAL6fOE9dLvt4I7HBHLhpGdE5Uj
# Ly4NxLTG2bDAkeAVmxmd2uKWVGKym1aarDxXfv3GCN4mRX+Pn4c+py3S/6Kkt5eS
# DAIIsrzKw3Kh2SW1hCwXX/k1v4b+NH1Fjl+i/xPJspXCFuZB4aC5FLT5fgbRKqns
# WeAdn8DsrYQhT3QXLt6Nv3/dMzv7G/Cdpbdcoul8FYl+t3dmXM+SIClC3l2ae0wO
# lNrQ42yQEycuPU5OoqLT85jsZ7+4CaScfFINlO7l7Y7r/xauqHbSPQ1r3oIC+e71
# 5s2G3ClZa3y99aYx2lnXYe1srcrIx8NAXTViiypXVn9ZGmEkfNcfDiqGQwkml5z9
# nm3pWiBZ69adaBBbAFEjyJG4y0a76bel/4sDCVvaZzLM3TFbxVO9BQrjZRtbJZbk
# C3XArpLqZSfx53SuYdddxPX8pvcqFuEu8wcUeD05t9xNbJ4TtdAECJlEi0vvBxlm
# M5tzFXy2qZeqPMXHSQYqPgZ9jvScZ6NwznFD0+33kbzyhOSz/WuGbAu4cHZG8gKn
# lQVT4uA2Diex9DMs2WHiokNknYlLoUeWXW1QrJLpqO82TLyKTbBM/oZHAdIc0kzo
# STro9b3+vjn2809D0+SOOCVZMIIHejCCBWKgAwIBAgIKYQ6Q0gAAAAAAAzANBgkq
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
# Z25pbmcgUENBIDIwMTECEzMAAASFXpnsDlkvzdcAAAAABIUwDQYJYIZIAWUDBAIB
# BQCggZAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwLwYJKoZIhvcNAQkEMSIE
# IF9JCl9de3YPpjKa1iM5Sas6g/4bk3DvBbNHpOGZH8vkMEIGCisGAQQBgjcCAQwx
# NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20wDQYJKoZIhvcNAQEBBQAEggEATDy8vWdbVeqhS4tog7gaakNAB69DdoB7
# 30jnRDJtmnpzSsN3zV5AQqmd+/bk9zqCs2FbLaB9fc2THFE+JI0rWIDrfoizPWUZ
# ywVkcj3KNVqluUfdNmrxsQnzuyFG54BTvGjVOAF9kD9GScW5qMVyXE8enK/P+UuK
# T8t79uAsledp8xSn9xu3tm01VNhCZHMMlhR/D2SAf5NV27ltnWBdIAL0FlC54a+n
# iXkJfhQ0kLBf8y5ZQ6RMHVGGdELZqLoAEliS8KCfAtmXxpRjsigLZxKuPwfQNiI+
# 5IwfPrfNShK39MtF8hocrGkuW92UR/9IYt+lvXLu4DCH+14M9yEUoqGCF7Awghes
# BgorBgEEAYI3AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCCF4kwgheFAgEDMQ8wDQYJ
# YIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYB
# BAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCAreoIzkwxGcl63eNNZ3r/ds0tz8Wwj
# otoTmxqSyu6MLQIGaK4BFD76GBMyMDI1MDkxNjE1NDg1Ni41NjZaMASAAgH0oIHZ
# pIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYD
# VQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNV
# BAsTHm5TaGllbGQgVFNTIEVTTjozNjA1LTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEf4wggcoMIIFEKADAgECAhMzAAAB
# 91ggdQTK+8L0AAEAAAH3MA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFBDQSAyMDEwMB4XDTI0MDcyNTE4MzEwNloXDTI1MTAyMjE4MzEwNlowgdMx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1p
# Y3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNo
# aWVsZCBUU1MgRVNOOjM2MDUtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQg
# VGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKC
# AgEA0OdHTBNom6/uXKaEKP9rPITkT6QxF11tjzB0Nk1byDpPrFTHha3hxwSdTcr8
# Y0a3k6EQlwqy6ROz42e0R5eDW+dCoQapipDIFUOYp3oNuqwX/xepATEkY17MyXFx
# 6rQW2NcWUJW3Qo2AuJ0HOtblSpItQZPGmHnGqkt/DB45Fwxk6VoSvxNcQKhKETku
# zrt8U6DRccQm1FdhmPKgDzgcfDPM5o+GnzbiMu6y069A4EHmLMmkecSkVvBmcZ8V
# nzFHTDkGLdpnDV5FXjVObAgbSM0cnqYSGfRp7VGHBRqyoscvR4bcQ+CV9pDjbJ6S
# 5rZn1uA8hRhj09Hs33HRevt4oWAVYGItgEsG+BrCYbpgWMDEIVnAgPZEiPAaI8wB
# GemE4feEkuz7TAwgkRBcUzLgQ4uvPqRD1A+Jkt26+pDqWYSn0MA8j0zacQk9q/Av
# ciPXD9It2ez+mqEzgFRRsJGLtcf9HksvK8Jsd6I5zFShlqi5bpzf1Y4NOiNOh5Qw
# W1pIvA5irlal7qFhkAeeeZqmop8+uNxZXxFCQG3R3s5pXW89FiCh9rmXrVqOCwgc
# XFIJQAQkllKsI+UJqGq9rmRABJz5lHKTFYmFwcM52KWWjNx3z6odwz2h+sxaxewT
# oe9GqtDx3/aU+yqNRcB8w0tSXUf+ylN4uk5xHEpLpx+ZNNsCAwEAAaOCAUkwggFF
# MB0GA1UdDgQWBBTfRqQzP3m9PZWuLf1p8/meFfkmmDAfBgNVHSMEGDAWgBSfpxVd
# AF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIw
# UENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBo
# dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUy
# MFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYG
# A1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0B
# AQsFAAOCAgEAN0ajafILeL6SQIMIMAXM1Qd6xaoci2mOrpR8vKWyyTsL3b83A7XG
# LiAbQxTrqnXvVWWeNst5YQD8saO+UTgOLJdTdfUADhLXoK+RlwjfndimIJT9MH9t
# UYXLzJXKhZM09ouPwNsrn8YOLIpdAi5TPyN8Cl11OGZSlP9r8JnvomW00AoJ4Pl9
# rlg0G5lcQknAXqHa9nQdWp1ZxXqNd+0JsKmlR8tcANX33ClM9NnaClJExLQHiKeH
# UUWtqyLMl65TW6wRM7XlF7Y+PTnC8duNWn4uLng+ON/Z39GO6qBj7IEZxoq4o3av
# Eh9ba43UU6TgzVZaBm8VaA0wSwUe/pqpTOYFWN62XL3gl/JC2pzfIPxP66XfRLIx
# afjBVXm8KVDn2cML9IvRK02s941Y5+RR4gSAOhLiQQ6A03VNRup+spMa0k+XTPAi
# +2aMH5xa1Zjb/K8u9f9M05U0/bUMJXJDP++ysWpJbVRDiHG7szaca+r3HiUPjQJy
# Ql2NiOcYTGV/DcLrLCBK2zG503FGb04N5Kf10XgAwFaXlod5B9eKh95PnXKx2LNB
# gLwG85anlhhGxxBQ5mFsJGkBn0PZPtAzZyfr96qxzpp2pH9DJJcjKCDrMmZziXaz
# pa5VVN36CO1kDU4ABkSYTXOM8RmJXuQm7mUF3bWmj+hjAJb4pz6hT5UwggdxMIIF
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
# BAsTHm5TaGllbGQgVFNTIEVTTjozNjA1LTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAb28KDG/x
# XbNBjmM7/nqw3bgrEOaggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDANBgkqhkiG9w0BAQsFAAIFAOxzhFcwIhgPMjAyNTA5MTYwNjM4MTVaGA8y
# MDI1MDkxNzA2MzgxNVowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA7HOEVwIBADAK
# AgEAAgIcfAIB/zAHAgEAAgISgDAKAgUA7HTV1wIBADA2BgorBgEEAYRZCgQCMSgw
# JjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3
# DQEBCwUAA4IBAQBC+0z7WtRZOMQrgpmH7bRsQBnZSVggzwFvgZ42oQOcL8DYuSPM
# vI3Uenqtr3te/oI6adKNCcpxQmUqTv1RVqz5GU+8eOQ3SAEPTO9S0QxTItfA08cd
# P3X5qkmlTREwwuq/HQjsZsvE526R/L6rO4zgI8lPehu35qdRpvJtFJ7rFTcXljx0
# iLb1Hg3fx+gu9kbW57FN+0PkjkLTTLpzPQ2og7sNoL0OaUbiMCkLjkE36T2vyE8b
# 55x4+ocbwh246auP74aiFEjYfukflPyliYHAOM0zJ/2JXUxSN2AoQvSpudqMcJ5p
# dJQJoI08g4R6rRDYITy7JOV6jUl9UAUq7e3YMYIEDTCCBAkCAQEwgZMwfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAH3WCB1BMr7wvQAAQAAAfcwDQYJ
# YIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkq
# hkiG9w0BCQQxIgQgibKwVbecR+8t1IE/p4tj0xY4DMPdd4hkefsV7T55UCwwgfoG
# CyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCAh2pjaa3ca0ecYuhu60uYHP/IKnPbe
# dbVQJ5SoIH5Z4jCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# AhMzAAAB91ggdQTK+8L0AAEAAAH3MCIEINlbeS0pV+XdkjPCXoh+6LGB4L27sBvu
# O2J+5Uu4ts7iMA0GCSqGSIb3DQEBCwUABIICAJcg0dCWVHWZJA7fC7eYBIQHfvkQ
# 6/R64TaK7iVUi+pNFxbkuLWpF5KcoYIGMyQwhZWaMP1V8bF4AhYVLUxa1GJo/wFd
# GBGhTbOMSx5OfRZOG+CgH6RUHD773qrmP5z3vrYMsXJmqNH19Bz0ZmSgbArNfk3q
# QeeyQ2MrAJt98mP+xxv4AMOE8Kj0J1ak8xhD25WOdIJnO3In/oZD30SsuurDO+8V
# Em0n4OnRg6sWUViukTgxn5S6jRJqa+oSMrl9nV4EJT6b3L6JbrMdOy44AP9xETdR
# YmVzcowpApPWmaHkOi0soBj8+l91zUlUxVZrPDVZGiEFsWVq9DgjkVlrJ++K5SBE
# 8s8SGGmfLFB2HjTVqbxIImst6j1EMzN5i0nVEfcWTD4nAf80NoWgjU/miboolPn9
# 88dAIIJgRwobYAnE83WX+xDOx2ppe2kSn3geddWnG8U3pGPg3JjThEAIKtwUxpXV
# 5D07yaKi9vUwQCLGXz0KbYw9BiEGmKgWyg5enzAZQz13msTTfAD146gz4WFNNqWS
# Jz2y729BS/k9310E7Lsu6mBtmR5eH+pyWWXjc3otgTisyoN/l5kSjtaNscaeIHXK
# h1uUe1FHbnv6FwRWlF9aqlxDybVh8REaeyPfcT3RpsEy3VlWfNoTSlA6WpL9YtKH
# Tup8Yh0RgKTvCycn
# SIG # End signature block
