<#
    Function to initialize the test runner with the necessary parameters. The parameters are mainly used to open the connection to the client session. The parameters are saved as script variables for further use.
    This functions needs to be called before any other functions in this module.
#>
function Initialize-TestRunner(
    [ValidateSet("PROD", "OnPrem")]
    [string] $Environment,
    [ValidateSet("AAD", "Windows", "NavUserPassword")]
    [string] $AuthorizationType,
    [switch] $DisableSSLVerification,
    [pscredential] $Credential,
    [pscredential] $Token,
    [string] $EnvironmentName,
    [string] $ServiceUrl,
    [string] $ClientId,
    [string] $RedirectUri,
    [string] $AadTenantId,
    [string] $APIHost,
    [string] $ServerInstance,
    [Nullable[guid]] $CompanyId,
    [int] $ClientSessionTimeout = $script:DefaultClientSessionTimeout,
    [int] $TransactionTimeout = $script:DefaultTransactionTimeout.TotalMinutes
) {
    Write-HostWithTimestamp "Initializing the AI Test Runner module..."

    $script:DisableSSLVerification = $DisableSSLVerification

    # Reset the script variables
    $script:Environment = ''
    $script:AuthorizationType = ''
    $script:EnvironmentName = ''
    $script:ClientId = ''
    $script:ServiceUrl = ''
    $script:APIHost = ''

    $script:CompanyId = $CompanyId
    

    # If -Environment is not specified then pick the default
    if ($Environment -eq '') {
        Write-Host "-Environment parameter is not provided. Defaulting to $script:DefaultEnvironment"

        $script:Environment = $script:DefaultEnvironment
    }
    else {
        $script:Environment = $Environment
    }

    # Depending on the Environment make sure necessary parameters are also specified
    switch ($script:Environment) {
        # PROD works only with AAD authorizatin type and OnPrem works on all 3 Authorization types
        'PROD' {
            if ($AuthorizationType -ne 'AAD') {
                throw "Only Authorization type 'AAD' can work in -Environment $Environment."
            }
            else {
                if ($AuthorizationType -eq '') {
                    Write-Host "-AuthorizationType parameter is not provided. Defaulting to $script:DefaultAuthorizationType"
                    $script:AuthorizationType = $script:DefaultAuthorizationType
                }
                else {
                    $script:AuthorizationType = $AuthorizationType
                }
            }

            if ($EnvironmentName -eq '') {
                Write-Host "-EnvironmentName parameter is not provided. Defaulting to $script:DefaultEnvironmentName"
                $script:EnvironmentName = $script:DefaultEnvironmentName
            }
            else {
                $script:EnvironmentName = $EnvironmentName
            }

            if ($ClientId -eq '') {
                Write-Error -Category InvalidArgument -Message 'ClientId is mandatory in the PROD environment'
            }
            else {
                $script:ClientId = $ClientId
            }
            if ($RedirectUri -eq '') {
                Write-Host "-RedirectUri parameter is not provided. Defaulting to $script:DefaultRedirectUri"
                $script:RedirectUri = $script:DefaultRedirectUri
            }
            else {
                $script:RedirectUri = $RedirectUri
            }
            if ($AadTenantId -eq '') {
                Write-Error -Category InvalidArgument -Message 'AadTenantId is mandatory in the PROD environment'
            }
            else {
                $script:AadTenantId = $AadTenantId
            }

            $script:AadTokenProvider = [AadTokenProvider]::new($script:AadTenantId, $script:ClientId, $script:RedirectUri)
            
            if (!$script:AadTokenProvider) {
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
            if ($Token -ne $null) {
                $tenantDomain = ($Token.UserName.Substring($Token.UserName.IndexOf('@') + 1))
            }
            else {
                $tenantDomain = ($Credential.UserName.Substring($Credential.UserName.IndexOf('@') + 1))
            }
            $script:discoveryUrl = "https://businesscentral.dynamics.com/$tenantDomain/$EnvironmentName/deployment/url"

            if ($ServiceUrl -eq '') {
                $script:ServiceUrl = Get-SaaSServiceURL
                Write-Host "ServiceUrl is not provided. Defaulting to $script:ServiceUrl"
            }
            else {
                $script:ServiceUrl = $ServiceUrl
            }

            if ($APIHost -eq '') {
                $script:APIHost = $script:DefaultSaaSAPIHost + '/' + $script:EnvironmentName
                Write-Host "APIHost is not provided. Defaulting to $script:APIHost"
            }
            else {
                $script:APIHost = $APIHost
            }
        }
        'OnPrem' {
            if ($AuthorizationType -eq '') {
                Write-Host "-AuthorizationType parameter is not provided. Defaulting to $script:DefaultAuthorizationType"
                $script:AuthorizationType = $script:DefaultAuthorizationType
            }
            else {
                $script:AuthorizationType = $AuthorizationType
            }

            # OnPrem, -ServiceUrl should be provided else default is selected. On other environments, the Service Urls are built
            if ($ServiceUrl -eq '') {
                Write-Host "Valid ServiceUrl is not provided. Defaulting to $script:DefaultServiceUrl"
                $script:ServiceUrl = $script:DefaultServiceUrl
            }
            else {
                $script:ServiceUrl = $ServiceUrl
            }

            if ($ServerInstance -eq '') {
                Write-Host "ServerInstance is not provided. Defaulting to $script:DefaultServerInstance"
                $script:ServerInstance = $script:DefaultServerInstance
            }
            else {
                $script:ServerInstance = $ServerInstance
            }

            if ($APIHost -eq '') {
                $script:APIHost = $script:DefaultOnPremAPIHost + '/' + "Navision_" + $script:ServerInstance
                Write-Host "APIHost is not provided. Defaulting to $script:APIHost"
            }
            else {
                $script:APIHost = $APIHost
            }
            
            $script:Tenant = GetTenantFromServiceUrl -Uri $script:ServiceUrl
        }
    }

    switch ($script:AuthorizationType) {
        # -Credential or -Token should be specified if authorization type is AAD.
        "AAD" {
            if ($null -eq $Credential -and $Token -eq $null) {
                throw "Parameter -Credential or -Token should be defined when selecting 'AAD' authorization type."
            }
            if ($null -ne $Credential -and $Token -ne $null) {
                throw "Specify only one parameter -Credential or -Token when selecting 'AAD' authorization type."
            }
        }
        # -Credential should be specified if authorization type is NavUserPassword.
        "NavUserPassword" {
            if ($null -eq $Credential) {
                throw "Parameter -Credential should be defined when selecting 'NavUserPassword' authorization type."
            }
        }
        "Windows" {
            if ($null -ne $Credential) {
                throw "Parameter -Credential should not be defined when selecting 'Windows' authorization type."
            }
        }
    }
    
    $script:Credential = $Credential
    $script:ClientSessionTimeout = $ClientSessionTimeout
    $script:TransactionTimeout = [timespan]::FromMinutes($TransactionTimeout);

    Test-AITestToolkitConnection
}

function GetTenantFromServiceUrl([Uri]$Uri)
{
    # Extract the query string part of the URI
    $queryString = [Uri]$Uri -replace '.*\?', ''
    $params = @{}
    
    $queryString -split '&' | ForEach-Object {  
        if ($_ -match '([^=]+)=(.*)') { 
            $params[$matches[1]] = $matches[2] 
        }  
    }

    if($params['tenant'])
    {
        return $params['tenant']
    } 
    
    return 'default'    
}

# Test the connection to the AI Test Toolkit
function Test-AITestToolkitConnection {
    try {
        Write-HostWithTimestamp "Testing the connection to the AI Test Toolkit..."

        $clientContext = Open-ClientSessionWithWait -DisableSSLVerification:$script:DisableSSLVerification -AuthorizationType $script:AuthorizationType -Credential $script:Credential -ServiceUrl $script:ServiceUrl -ClientSessionTimeout $script:ClientSessionTimeout -TransactionTimeout $script:TransactionTimeout
        
        Write-HostWithTimestamp "Opening the Test Form $script:TestRunnerPage"
        $form = Open-TestForm -TestPage $script:TestRunnerPage -DisableSSLVerification:$script:DisableSSLVerification -AuthorizationType $script:AuthorizationType -ClientContext $clientContext

        # There will be an exception if the form is not opened
        Write-HostWithTimestamp "Successfully opened the Test Form $script:TestRunnerPage" -ForegroundColor Green

        $clientContext.CloseForm($form)

        # Check API connection
        $APIEndpoint = Get-DefaultAPIEndpointForAITLogEntries

        Write-HostWithTimestamp "Testing the connection to the AI Test Toolkit Log Entries API: $APIEndpoint"
        Invoke-BCRestMethod -Uri $APIEndpoint
        Write-HostWithTimestamp "Successfully connected to the AI Test Toolkit Log Entries API" -ForegroundColor Green

        $APIEndpoint = Get-DefaultAPIEndpointForAITTestMethodLines

        Write-HostWithTimestamp "Testing the connection to the AI Test Toolkit Test Method Lines API: $APIEndpoint"
        Invoke-BCRestMethod -Uri $APIEndpoint
        Write-HostWithTimestamp "Successfully connected to the AI Test Toolkit Test Method Lines API" -ForegroundColor Green
    }
    catch {
        throw $_.Exception.Message
    }
    finally {
        if ($clientContext) {
            $clientContext.Dispose()
        }
    }     
}

# Reset the test suite pending tests
function Reset-AITTestSuite {
    param (
        [Parameter(Mandatory = $true)]
        [string] $SuiteCode,
        [int] $ClientSessionTimeout = $script:ClientSessionTimeout,
        [timespan] $TransactionTimeout = $script:TransactionTimeout
    )

    try {
        Write-HostWithTimestamp "Opening test runner page: $script:TestRunnerPage"

        $clientContext = Open-ClientSessionWithWait -DisableSSLVerification:$script:DisableSSLVerification -AuthorizationType $script:AuthorizationType -Credential $script:Credential -ServiceUrl $script:ServiceUrl -ClientSessionTimeout $ClientSessionTimeout -TransactionTimeout $TransactionTimeout        

        $form = Open-TestForm -TestPage $script:TestRunnerPage -DisableSSLVerification:$script:DisableSSLVerification -AuthorizationType $script:AuthorizationType -ClientContext $clientContext        

        $SelectSuiteControl = $clientContext.GetControlByName($form, "AIT Suite Code")        
        $clientContext.SaveValue($SelectSuiteControl, $SuiteCode);        

        Write-HostWithTimestamp "Resetting the test suite $SuiteCode"

        $ResetAction = $clientContext.GetActionByName($form, "ResetTestSuite")
        $clientContext.InvokeAction($ResetAction)
    }
    finally {
        if ($clientContext) {
            $clientContext.Dispose()
        }
    }
}

# Invoke the AI Test Suite
function Invoke-AITSuite
(
    [Parameter(Mandatory = $true)]
    [string] $SuiteCode,
    [string] $SuiteLineNo,
    [int] $ClientSessionTimeout = $script:ClientSessionTimeout,
    [timespan] $TransactionTimeout = $script:TransactionTimeout
) {
    $NoOfPendingTests = 0
    $TestResult = @()
    do {
        try {
            Write-HostWithTimestamp "Opening test runner page: $script:TestRunnerPage"

            $clientContext = Open-ClientSessionWithWait -DisableSSLVerification:$script:DisableSSLVerification -AuthorizationType $script:AuthorizationType -Credential $script:Credential -ServiceUrl $script:ServiceUrl -ClientSessionTimeout $ClientSessionTimeout -TransactionTimeout $TransactionTimeout            

            $form = Open-TestForm -TestPage $script:TestRunnerPage -DisableSSLVerification:$script:DisableSSLVerification -AuthorizationType $script:AuthorizationType -ClientContext $clientContext            

            $SelectSuiteControl = $clientContext.GetControlByName($form, "AIT Suite Code")            
            $clientContext.SaveValue($SelectSuiteControl, $SuiteCode);            

            if ($SuiteLineNo -ne '') {
                $SelectSuiteLineControl = $clientContext.GetControlByName($form, "Line No. Filter")
                $clientContext.SaveValue($SelectSuiteLineControl, $SuiteLineNo);
            }

            Invoke-NextTest -SuiteCode $SuiteCode -ClientContext $clientContext -Form $form

            # Get the results for the last run
            $TestResult += Get-AITSuiteTestResultInternal -SuiteCode $SuiteCode -TestRunVersion 0 | ConvertFrom-Json            

            $NoOfPendingTests = $clientContext.GetControlByName($form, "No. of Pending Tests")            
            $NoOfPendingTests = [int] $NoOfPendingTests.StringValue            
        }
        catch {
            $stackTraceText = $_.Exception.StackTrace + "Script stack trace: " + $_.ScriptStackTrace 
            $testResultError = @(
                @{
                    aitCode        = $SuiteCode
                    status         = "Error"
                    message        = $_.Exception.Message
                    errorCallStack = $stackTraceText
                    endTime        = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ")
                }
            )
            $TestResult += $testResultError
        }
        finally {
            if ($clientContext) {
                $clientContext.Dispose()
            }
        }
    }
    until ($NoOfPendingTests -eq 0)
    return $TestResult
}

# Run the next test in the suite
function Invoke-NextTest {
    param (
        [Parameter(Mandatory = $true)]
        [string] $SuiteCode,
        [string] $SuiteLineNo,
        [Parameter(Mandatory = $true)]
        [ClientContext] $clientContext,
        [Parameter(Mandatory = $true)]
        [ClientLogicalForm] $form
    )
    $NoOfPendingTests = [int] $clientContext.GetControlByName($form, "No. of Pending Tests").StringValue

    if ($NoOfPendingTests -gt 0) {
        $StartNextAction = $clientContext.GetActionByName($form, "RunNextTest")

        $message = "Starting the next test in the suite $SuiteCode, Number of pending tests: $NoOfPendingTests"
        if ($SuiteLineNo -ne '') {
            $message += ", Filtering the suite line number: $SuiteLineNo"
        }
        Write-HostWithTimestamp $message

        $clientContext.InvokeAction($StartNextAction)
    }
    else {
        throw "There are no tests to run. Try resetting the test suite. Number of pending tests: $NoOfPendingTests"
    }

    $NewNoOfPendingTests = [int] $clientContext.GetControlByName($form, "No. of Pending Tests").StringValue
    if ($NewNoOfPendingTests -eq $NoOfPendingTests) {
        throw "There was an error running the test. Number of pending tests: $NewNoOfPendingTests"
    }
}

# Get Suite Test Result for specified version
# If version is not provided then get the latest version
function Get-AITSuiteTestResultInternal {
    param (
        [Parameter(Mandatory = $true)]
        [string] $SuiteCode,
        [Int32] $TestRunVersion,
        [Int32] $CodeunitId,
        [string] $CodeunitName,
        [string] $TestStatus,
        [string] $ProcedureName
    )

    if ($TestRunVersion -lt 0) {
        throw "TestRunVersion should be 0 or greater"
    }
    
    $APIEndpoint = Get-DefaultAPIEndpointForAITLogEntries

    # if AIT suite version is not provided then get the latest version
    if ($TestRunVersion -eq 0) {
        # Odata to sort by version and get all the entries with highest version
        $APIQuery = Build-LogEntryAPIFilter -SuiteCode $SuiteCode -TestRunVersion $TestRunVersion -CodeunitId $CodeunitId -CodeunitName $CodeunitName -TestStatus $TestStatus -ProcedureName $ProcedureName
        $AITVersionAPI = $APIEndpoint + $APIQuery + "&`$orderby=version desc&`$top=1&`$select=version"
        
        Write-HostWithTimestamp "Getting the latest version of the AIT Suite from $AITVersionAPI"
        $AITApiResponse = Invoke-BCRestMethod -Uri $AITVersionAPI
        
        $TestRunVersion = $AITApiResponse.value[0].version
    }

    $APIQuery = Build-LogEntryAPIFilter -SuiteCode $SuiteCode -TestRunVersion $TestRunVersion -CodeunitId $CodeunitId -CodeunitName $CodeunitName -TestStatus $TestStatus -ProcedureName $ProcedureName
    $AITLogEntryAPI = $APIEndpoint + $APIQuery

    Write-HostWithTimestamp "Getting the AIT Suite Test Results from $AITLogEntryAPI"
    $AITLogEntries = Invoke-BCRestMethod -Uri $AITLogEntryAPI

    # Convert the response to JSON
    $AITLogEntriesJson = $AITLogEntries.value | ConvertTo-Json -Depth 100 -AsArray
    return $AITLogEntriesJson
}


# Get Test Method Lines for a Suite
function Get-AITSuiteTestMethodLinesInternal {
    param (
        [Parameter(Mandatory = $true)]
        [string] $SuiteCode,
        [Int32] $TestRunVersion,
        [Int32] $CodeunitId,
        [string] $CodeunitName,
        [string] $TestStatus,
        [string] $ProcedureName
    )

    if ($TestRunVersion -lt 0) {
        throw "TestRunVersion should be 0 or greater"
    }
    
    $APIEndpoint = Get-DefaultAPIEndpointForAITTestMethodLines

    $APIQuery = Build-TestMethodLineAPIFilter -SuiteCode $SuiteCode -TestRunVersion $TestRunVersion -CodeunitId $CodeunitId -CodeunitName $CodeunitName -TestStatus $TestStatus
    $AITTestMethodLinesAPI = $APIEndpoint + $APIQuery

    Write-HostWithTimestamp "Getting the Test Method Lines from $AITTestMethodLinesAPI"
    $AITTestMethodLines = Invoke-BCRestMethod -Uri $AITTestMethodLinesAPI

    # Convert the response to JSON
    $AITTestMethodLinesJson = $AITTestMethodLines.value | ConvertTo-Json
    return $AITTestMethodLinesJson
}

function Get-DefaultAPIEndpointForAITLogEntries {
    $CompanyPath = ''
    if ($script:CompanyId -ne [guid]::Empty -and $null -ne $script:CompanyId) {
        $CompanyPath = '/companies(' + $script:CompanyId + ')'
    }
    
    $TenantParam = ''
    if($script:Tenant)
    {
        $TenantParam = "tenant=$script:Tenant&"
    }
    $APIEndpoint = "$script:APIHost/api/microsoft/aiTestToolkit/v2.0$CompanyPath/aitTestLogEntries?$TenantParam"
    Write-Host "APIEndpoint: $APIEndpoint"

    return $APIEndpoint
}

function Get-DefaultAPIEndpointForAITTestMethodLines {
    $CompanyPath = ''
    if ($script:CompanyId -ne [guid]::Empty -and $null -ne $script:CompanyId) {
        $CompanyPath = '/companies(' + $script:CompanyId + ')'
    }

    $TenantParam = ''
    if($script:Tenant)
    {
        $TenantParam = "tenant=$script:Tenant&"
    }

    $APIEndpoint = "$script:APIHost/api/microsoft/aiTestToolkit/v2.0$CompanyPath/aitTestMethodLines?$TenantParam"

    return $APIEndpoint
}

function Build-LogEntryAPIFilter() {
    param (
        [Parameter(Mandatory = $true)]
        [string] $SuiteCode,
        [Int32] $TestRunVersion,
        [Int32] $CodeunitId,
        [string] $CodeunitName,
        [string] $TestStatus,
        [string] $ProcedureName
    )

    $filter = "`$filter=aitCode eq '" + $SuiteCode + "'"
    if ($TestRunVersion -ne 0) {
        $filter += " and version eq " + $TestRunVersion
    }
    if ($CodeunitId -ne 0) {
        $filter += " and codeunitId eq " + $CodeunitId
    }
    if ($CodeunitName -ne '') {
        $filter += " and codeunitName eq '" + $CodeunitName + "'"
    }
    if ($TestStatus -ne '') {
        $filter += " and status eq '" + $TestStatus + "'"
    }
    if ($ProcedureName -ne '') {
        $filter += " and procedureName eq '" + $ProcedureName + "'"
    }

    return $filter
}

function Build-TestMethodLineAPIFilter() {
    param (
        [Parameter(Mandatory = $true)]
        [string] $SuiteCode,
        [Int32] $TestRunVersion,
        [Int32] $CodeunitId,
        [string] $CodeunitName,
        [string] $TestStatus,
        [string] $ProcedureName
    )

    $filter = "`$filter=aitCode eq '" + $SuiteCode + "'"
    if ($TestRunVersion -ne 0) {
        $filter += " and version eq " + $TestRunVersion
    }
    if ($CodeunitId -ne 0) {
        $filter += " and codeunitId eq " + $CodeunitId
    }
    if ($CodeunitName -ne '') {
        $filter += " and codeunitName eq '" + $CodeunitName + "'"
    }
    if ($TestStatus -ne '') {
        $filter += " and status eq '" + $TestStatus + "'"
    }

    return $filter
}

# Upload the input dataset needed to run the AI Test Suite
function Set-InputDatasetInternal {
    param(
        [Parameter(Mandatory = $true)]
        [string] $InputDatasetFilename,
        [Parameter(Mandatory = $true)]
        [string] $InputDataset,
        [int] $ClientSessionTimeout = $script:ClientSessionTimeout,
        [timespan] $TransactionTimeout = $script:TransactionTimeout
    )
    try {
        $clientContext = Open-ClientSessionWithWait -DisableSSLVerification:$script:DisableSSLVerification -AuthorizationType $script:AuthorizationType -Credential $script:Credential -ServiceUrl $script:ServiceUrl -ClientSessionTimeout $ClientSessionTimeout -TransactionTimeout $TransactionTimeout

        $form = Open-TestForm -TestPage $script:TestRunnerPage -DisableSSLVerification:$script:DisableSSLVerification -AuthorizationType $script:AuthorizationType -ClientContext $clientContext

        $SelectSuiteControl = $clientContext.GetControlByName($form, "Input Dataset Filename")
        $clientContext.SaveValue($SelectSuiteControl, $InputDatasetFilename);
        
        Write-HostWithTimestamp "Uploading the Input Dataset $InputDatasetFilename"

        $SelectSuiteControl = $clientContext.GetControlByName($form, "Input Dataset")
        $clientContext.SaveValue($SelectSuiteControl, $InputDataset);

        $validationResultsError = Get-FormError($form)
        if ($validationResultsError.Count -gt 0) {
            Write-HostWithTimestamp "There is an error uploading the Input Dataset: $InputDatasetFilename" -ForegroundColor Red
            Write-HostWithTimestamp $validationResultsError -ForegroundColor Red
        }

        $clientContext.CloseForm($form)
    }
    finally {
        if ($clientContext) {
            $clientContext.Dispose()
        }
    }     
}

#Upload the XML test suite definition needed to setup the AI Test Suite
function  Set-SuiteDefinitionInternal {
    param (
        [Parameter(Mandatory = $true)]
        [xml] $SuiteDefinition,
        [int] $ClientSessionTimeout = $script:ClientSessionTimeout,
        [timespan] $TransactionTimeout = $script:TransactionTimeout
    )
    try {
        $clientContext = Open-ClientSessionWithWait -DisableSSLVerification:$script:DisableSSLVerification -AuthorizationType $script:AuthorizationType -Credential $script:Credential -ServiceUrl $script:ServiceUrl -ClientSessionTimeout $ClientSessionTimeout -TransactionTimeout $TransactionTimeout

        $form = Open-TestForm -TestPage $script:TestRunnerPage -DisableSSLVerification:$script:DisableSSLVerification -AuthorizationType $script:AuthorizationType -ClientContext $clientContext

        Write-HostWithTimestamp "Uploading the Suite Definition"
        $SelectSuiteControl = $clientContext.GetControlByName($form, "Suite Definition")
        $clientContext.SaveValue($SelectSuiteControl, $SuiteDefinition.OuterXml);
        
        # Check if the suite definition is set correctly
        $validationResultsError = Get-FormError($form)
        if ($validationResultsError.Count -gt 0) {
            throw $validationResultsError
        }
        $clientContext.CloseForm($form)
    }
    catch {
        Write-HostWithTimestamp "`There is an error uploading the Suite Definition. Please check the Suite Definition XML:`n $($SuiteDefinition.OuterXml)" -ForegroundColor Red
        if ($validationResultsError.Count -gt 0) {
            throw $_.Exception.Message
        }
        else {
            throw $_.Exception
        }
    }
    finally {
        if ($clientContext) {
            $clientContext.Dispose()
        }
    }
}

function Get-FormError {
    param (
        [ClientLogicalForm]
        $form
    )
    if ($form.HasValidatonResults -eq $true) {
        $validationResults = $form.ValidationResults
        $validationResultsError = @()
        foreach ($validationResult in $validationResults | Where-Object { $_.Severity -eq "Error" }) {
            $validationResultsError += "TestPage: $script:TestRunnerPage, Status: Error, Message: $($validationResult.Description), ErrorCallStack: $(Get-PSCallStack)"
        }
        return ($validationResultsError -join "`n")
    }  
}

function Invoke-BCRestMethod {
    param (
        [string]$Uri
    )
    switch ($script:AuthorizationType) {
        "Windows" {
            Invoke-RestMethod -Uri $Uri -Method Get -ContentType "application/json" -UseDefaultCredentials -AllowUnencryptedAuthentication
        }
        "NavUserPassword" {
            Invoke-RestMethod -Uri $Uri -Method Get -ContentType "application/json" -Credential $script:Credential -AllowUnencryptedAuthentication
        }
        "AAD" {
            $script:AadTokenProvider
            if ($null -ne $script:AadTokenProvider) {
                throw "You need to specify the AadTokenProvider for obtaining the token if using AAD authentication"
            }

            $token = $AadTokenProvider.GetToken($Credential)
            $headers = @{
                Authorization = "Bearer $token"
                Accept        = "application/json"
            }
            return Invoke-RestMethod -Uri $Uri -Method Get -Headers $headers
        }
        default {
            Write-Error "Invalid authentication type specified. Use 'Windows', 'UserPassword', or 'AAD'."
        }
    }
}

function Write-HostWithTimestamp {
    param (
        [string] $Message
    )
    Write-Host "[$($script:Tenant) $(Get-Date)] $Message"
}

$script:DefaultEnvironment = "OnPrem"
$script:DefaultAuthorizationType = 'Windows'
$script:DefaultEnvironmentName = "sandbox"
$script:DefaultServiceUrl = 'http://localhost:48900'
$script:DefaultRedirectUri = "https://login.microsoftonline.com/common/oauth2/nativeclient"
$script:DefaultOnPremAPIHost = "http://localhost:7047"
$script:DefaultSaaSAPIHost = "https://api.businesscentral.dynamics.com/v2.0"
$script:DefaultServerInstance = "NAV"
$script:DefaultClientSessionTimeout = 60;
$script:DefaultTransactionTimeout = [timespan]::FromMinutes(60);

$script:TestRunnerPage = '149042'
$script:ClientAssembly1 = "Microsoft.Dynamics.Framework.UI.Client.dll"
$script:ClientAssembly2 = "NewtonSoft.Json.dll"
$script:ClientAssembly3 = "Microsoft.Internal.AntiSSRF.dll"

if (!$script:TypesLoaded) {
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

$ErrorActionPreference = "Stop"
$script:AadTokenProvider = $null
$script:Credential = $null

Export-ModuleMember -Function Initialize-TestRunner, Reset-AITTestSuite, Invoke-AITSuite, Set-InputDatasetInternal, Set-SuiteDefinitionInternal, Get-AITSuiteTestResultInternal, Get-AITSuiteTestMethodLinesInternal

# SIG # Begin signature block
# MIIoKAYJKoZIhvcNAQcCoIIoGTCCKBUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDfcLyCvwDA0uaL
# NvtG3HIqjJT4JNjt4Y2ge7M3Fkgwx6CCDXYwggX0MIID3KADAgECAhMzAAAEBGx0
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
# IL7gkTzwNq56USQQQtYv85C1zskJph5Fi7wLhxyhgo6LMEIGCisGAQQBgjcCAQwx
# NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20wDQYJKoZIhvcNAQEBBQAEggEAjZWHl4Epbk6blYLeGzp4xssA5PFsrvGT
# cWDxfeO0bxvWL9N8TUiT3E3XBpTdz7XXnp5Jn7JhLFqmHBoMjbwJN6NiL+Fn3y+Z
# qUseQvNdTthBsPltBUMQtLQ+OPbWoZSm0xAkcRj4LRpIgsM1m2kMV2uTDv5HQGGx
# WXsirpxoA4F6xRKCGy9XvcDEzvJ96SNXEisx27m8HdjvlARav+BXPKXg4ec5rUg6
# w3P3CbbeVcfHm4mgk/vxETCYPfs+VAGergGngCvWx/AHaLcncEfU2/F83QjOYg+n
# l1Yp3rbids5LlAwXl+hPwOCkcP/JBQ3ONXhHmpCVWs3OdlE97S7lm6GCF7Awghes
# BgorBgEEAYI3AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCCF4kwgheFAgEDMQ8wDQYJ
# YIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYB
# BAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCAY8/3k4A3TPsmEzq4XzRRxnmJcmY7M
# HcEE3eZDnbfoPQIGZ+0t3z9FGBMyMDI1MDQyMjEyMDAwOS4xMzNaMASAAgH0oIHZ
# pIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYD
# VQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNV
# BAsTHm5TaGllbGQgVFNTIEVTTjo0MzFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEf4wggcoMIIFEKADAgECAhMzAAAB
# +vs7RNN3M8bTAAEAAAH6MA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFBDQSAyMDEwMB4XDTI0MDcyNTE4MzExMVoXDTI1MTAyMjE4MzExMVowgdMx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1p
# Y3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNo
# aWVsZCBUU1MgRVNOOjQzMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQg
# VGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKC
# AgEAyhZVBM3PZcBfEpAf7fIIhygwYVVP64USeZbSlRR3pvJebva0LQCDW45yOrtp
# wIpGyDGX+EbCbHhS5Td4J0Ylc83ztLEbbQD7M6kqR0Xj+n82cGse/QnMH0WRZLnw
# ggJdenpQ6UciM4nMYZvdQjybA4qejOe9Y073JlXv3VIbdkQH2JGyT8oB/LsvPL/k
# AnJ45oQIp7Sx57RPQ/0O6qayJ2SJrwcjA8auMdAnZKOixFlzoooh7SyycI7BENHT
# pkVKrRV5YelRvWNTg1pH4EC2KO2bxsBN23btMeTvZFieGIr+D8mf1lQQs0Ht/tMO
# Vdah14t7Yk+xl5P4Tw3xfAGgHsvsa6ugrxwmKTTX1kqXH5XCdw3TVeKCax6JV+yg
# M5i1NroJKwBCW11Pwi0z/ki90ZeO6XfEE9mCnJm76Qcxi3tnW/Y/3ZumKQ6X/iVI
# Jo7Lk0Z/pATRwAINqwdvzpdtX2hOJib4GR8is2bpKks04GurfweWPn9z6jY7GBC+
# js8pSwGewrffwgAbNKm82ZDFvqBGQQVJwIHSXpjkS+G39eyYOG2rcILBIDlzUzMF
# FJbNh5tDv3GeJ3EKvC4vNSAxtGfaG/mQhK43YjevsB72LouU78rxtNhuMXSzaHq5
# fFiG3zcsYHaa4+w+YmMrhTEzD4SAish35BjoXP1P1Ct4Va0CAwEAAaOCAUkwggFF
# MB0GA1UdDgQWBBRjjHKbL5WV6kd06KocQHphK9U/vzAfBgNVHSMEGDAWgBSfpxVd
# AF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIw
# UENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBo
# dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUy
# MFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYG
# A1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0B
# AQsFAAOCAgEAuFbCorFrvodG+ZNJH3Y+Nz5QpUytQVObOyYFrgcGrxq6MUa4yLmx
# N4xWdL1kygaW5BOZ3xBlPY7Vpuf5b5eaXP7qRq61xeOrX3f64kGiSWoRi9EJawJW
# CzJfUQRThDL4zxI2pYc1wnPp7Q695bHqwZ02eaOBudh/IfEkGe0Ofj6IS3oyZsJP
# 1yatcm4kBqIH6db1+weM4q46NhAfAf070zF6F+IpUHyhtMbQg5+QHfOuyBzrt67C
# iMJSKcJ3nMVyfNlnv6yvttYzLK3wS+0QwJUibLYJMI6FGcSuRxKlq6RjOhK9L3QO
# jh0VCM11rHM11ZmN0euJbbBCVfQEufOLNkG88MFCUNE10SSbM/Og/CbTko0M5wbV
# vQJ6CqLKjtHSoeoAGPeeX24f5cPYyTcKlbM6LoUdO2P5JSdI5s1JF/On6LiUT50a
# dpRstZajbYEeX/N7RvSbkn0djD3BvT2Of3Wf9gIeaQIHbv1J2O/P5QOPQiVo8+0A
# Km6M0TKOduihhKxAt/6Yyk17Fv3RIdjT6wiL2qRIEsgOJp3fILw4mQRPu3spRfak
# SoQe5N0e4HWFf8WW2ZL0+c83Qzh3VtEPI6Y2e2BO/eWhTYbIbHpqYDfAtAYtaYId
# e87ZymXG3MO2wUjhL9HvSQzjoquq+OoUmvfBUcB2e5L6QCHO6qTO7WowggdxMIIF
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
# BAsTHm5TaGllbGQgVFNTIEVTTjo0MzFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUA94Z+bUJn
# +nKwBvII6sg0Ny7aPDaggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDANBgkqhkiG9w0BAQsFAAIFAOuxYFAwIhgPMjAyNTA0MjIwMDI0NDhaGA8y
# MDI1MDQyMzAwMjQ0OFowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA67FgUAIBADAK
# AgEAAgIfiQIB/zAHAgEAAgITHzAKAgUA67Kx0AIBADA2BgorBgEEAYRZCgQCMSgw
# JjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3
# DQEBCwUAA4IBAQAQki2DG3WqnHa7TkNBvpU0E2AFZVokEPBA+hCzRb1SV6NFJLY3
# ra7b66rb7lUVLp377zDf3xtOMQXKQ6egcD0q/5zBlhcaduWVQkbCyi1Wv4jGmkLe
# nbLcwP9Ug5HFOXTaeI6UvDePE4feNAVFiDimBbGjHXBN1piTjIJDV4qjzQxqGPyH
# CjQyMtjwzrT6rX80UrlAyB7dH1jcuXd3ulGORk/zpPx2SYmD5+tEgoQ9XZtuHK03
# KSjnQO9gzUiiAi4id4I/sKmEhMzbDfTAXmGVdE9z8cv1gbWvgQazUD4Nu+9o2xMT
# zbr4xfEc2MX1WeSTJF1LRg1g1gNtPY5gs7cFMYIEDTCCBAkCAQEwgZMwfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAH6+ztE03czxtMAAQAAAfowDQYJ
# YIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkq
# hkiG9w0BCQQxIgQgu+8Qrml1EPG10bEXnGw53wI4RHKnve848FTWEbDQakowgfoG
# CyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCB98n8tya8+B2jjU/dpJRIwHwHHpco5
# ogNStYocbkOeVjCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# AhMzAAAB+vs7RNN3M8bTAAEAAAH6MCIEIIzwyxl/vPk60RxBERuCHgesUaPwVLZB
# +5Asc+Jm55wHMA0GCSqGSIb3DQEBCwUABIICAEcX5sx2zN+liZQb0a5nAObxNbPJ
# yWOtdd3elznOWHWCboGekHeTp49mD5iJj9j55zl7lImyA70yu4ze5NEQjRcZV/c+
# Z4xRJBH76akOnXgqofkY1YnzQtdL4NNadfjmC6CAqDWUoBBzZrVfstCc5sMlECUo
# d61f1F9dm8yT1Y4OYkXhrnSy3sCQs7w9wQpzK9uivMbnPxhaAJAJFrVsY0sz45+t
# 88xxek6+/uaI3pxmFZaOvlOOzEJB6UvbGSuFsmo2IW5ufPVMtrpqjbg8scju2xbC
# CC1EIU7z5sdcHz3om1dgI0ypVCI8sFynkvhnkPOVLBX85DfahHE65M3PVEWBe2YG
# BK08qH9NqiT1+XePt3qiw1c5V3MQ7EiP07sb3dFybRk0qc8LJ69GKk488txmcXpZ
# jSdwBSTVEhCo9z8k/5rqpwj3gDg9w8KThRX7SXdflmXGpk3FILQ7rk0xYZbisLPL
# VIgk1KqC+6tpVaJU6nTDBjXQk0tUF6V3ADHlL+DCu7X9BHXXG1QA7ldTA//Ad51x
# MfckCanXpzyu37UxUI6tDiOMP0OEYT7JoC99kwAsWA9qP1OqYjANPxXMQlbp78nt
# zz1U9d6wg19RhUKI1xI60xvFB0AWnBswfFdgCSAB2+EGeQxkVOjtX/FzPYLdCI+G
# EWrj3iKFWCFpqu4S
# SIG # End signature block
