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
    [int] $TransactionTimeout = $script:DefaultTransactionTimeout.TotalMinutes,
    [string] $Culture = $script:DefaultCulture
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
    $script:Culture = $Culture;

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

        $clientContext = Open-ClientSessionWithWait -DisableSSLVerification:$script:DisableSSLVerification -AuthorizationType $script:AuthorizationType -Credential $script:Credential -ServiceUrl $script:ServiceUrl -ClientSessionTimeout $script:ClientSessionTimeout -TransactionTimeout $script:TransactionTimeout -Culture $script:Culture
        
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
        $scriptArgs = @{
            AuthorizationType    = $script:AuthorizationType
            ServiceUrl           = $script:ServiceUrl
            APIHost              = $script:APIHost
            ClientSessionTimeout = $script:ClientSessionTimeout
            TransactionTimeout   = $script:TransactionTimeout
            Culture              = $script:Culture
            TestRunnerPage       = $script:TestRunnerPage
            APIEndpoint          = $script:APIEndpoint
        }
        Write-HostWithTimestamp "Exception occurred. Script arguments: $($scriptArgs | Out-String)"
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

        $clientContext = Open-ClientSessionWithWait -DisableSSLVerification:$script:DisableSSLVerification -AuthorizationType $script:AuthorizationType -Credential $script:Credential -ServiceUrl $script:ServiceUrl -ClientSessionTimeout $ClientSessionTimeout -TransactionTimeout $TransactionTimeout -Culture $script:Culture

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

            $clientContext = Open-ClientSessionWithWait -DisableSSLVerification:$script:DisableSSLVerification -AuthorizationType $script:AuthorizationType -Credential $script:Credential -ServiceUrl $script:ServiceUrl -ClientSessionTimeout $ClientSessionTimeout -TransactionTimeout $TransactionTimeout -Culture $script:Culture

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


# Get Suite Test Result for specified version
# If version is not provided then get the latest version
function Get-AITSuiteEvaluationResultInternal {
    param (
        [Parameter(Mandatory = $true)]
        [string] $SuiteCode,
        [Int32] $SuiteLineNo,
        [Int32] $TestRunVersion,
        [string] $TestState
    )

    if ($TestRunVersion -lt 0) {
        throw "TestRunVersion should be 0 or greater"
    }
    
    $APIEndpoint = Get-DefaultAPIEndpointForAITEvaluationLogEntries

    Write-Host "Getting the AIT Suite Evaluation Results for Suite Code: $SuiteCode, Suite Line No: $SuiteLineNo, Test Run Version: $TestRunVersion, Test State: $TestState"

    # if AIT suite version is not provided then get the latest version
    if ($TestRunVersion -eq 0) {
        # Odata to sort by version and get all the entries with highest version
        $APIQuery = Build-LogEvaluationEntryAPIFilter -SuiteCode $SuiteCode -TestRunVersion $TestRunVersion -SuiteLineNo $SuiteLineNo -TestState $TestState
        $AITVersionAPI = $APIEndpoint + $APIQuery + "&`$orderby=version desc&`$top=1&`$select=version"
        
        Write-HostWithTimestamp "Getting the latest version of the AIT Suite from $AITVersionAPI"
        $AITApiResponse = Invoke-BCRestMethod -Uri $AITVersionAPI
        
        $TestRunVersion = $AITApiResponse.value[0].version
    }

    $APIQuery = Build-LogEvaluationEntryAPIFilter -SuiteCode $SuiteCode -TestRunVersion $TestRunVersion -SuiteLineNo $SuiteLineNo -TestState $TestState
    $AITEvaluationLogEntryAPI = $APIEndpoint + $APIQuery

    Write-HostWithTimestamp "Getting the AIT Suite Evaluation Results from $AITEvaluationLogEntryAPI"
    $AITEvaluationLogEntries = Invoke-BCRestMethod -Uri $AITEvaluationLogEntryAPI

    # Convert the response to JSON
    $AITEvaluationLogEntriesJson = $AITEvaluationLogEntries.value | ConvertTo-Json -Depth 100 -AsArray
    return $AITEvaluationLogEntriesJson
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

function Get-DefaultAPIEndpointForAITEvaluationLogEntries {
    $CompanyPath = ''
    if ($script:CompanyId -ne [guid]::Empty -and $null -ne $script:CompanyId) {
        $CompanyPath = '/companies(' + $script:CompanyId + ')'
    }
    
    $TenantParam = ''
    if($script:Tenant)
    {
        $TenantParam = "tenant=$script:Tenant&"
    }
    $APIEndpoint = "$script:APIHost/api/microsoft/aiTestToolkit/v2.0$CompanyPath/aitEvaluationLogEntries?$TenantParam"
    Write-Host "APIEndpoint: $APIEndpoint"

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

function Build-LogEvaluationEntryAPIFilter() {
    param (
        [Parameter(Mandatory = $true)]
        [string] $SuiteCode,
        [Int32] $SuiteLineNo,
        [Int32] $TestRunVersion,
        [string] $TestState
    )

    $filter = "`$filter=aitCode eq '" + $SuiteCode + "'"
    if ($TestRunVersion -ne 0) {
        $filter += " and version eq " + $TestRunVersion
    }
    if ($SuiteLineNo -ne 0) {
        $filter += " and aitTestMethodLineNo eq " + $SuiteLineNo
    }
    if ($TestState -ne '') {
        $filter += " and state eq '" + $TestState + "'"
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
        $clientContext = Open-ClientSessionWithWait -DisableSSLVerification:$script:DisableSSLVerification -AuthorizationType $script:AuthorizationType -Credential $script:Credential -ServiceUrl $script:ServiceUrl -ClientSessionTimeout $ClientSessionTimeout -TransactionTimeout $TransactionTimeout -Culture $script:Culture

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
        $clientContext = Open-ClientSessionWithWait -DisableSSLVerification:$script:DisableSSLVerification -AuthorizationType $script:AuthorizationType -Credential $script:Credential -ServiceUrl $script:ServiceUrl -ClientSessionTimeout $ClientSessionTimeout -TransactionTimeout $TransactionTimeout -Culture $script:Culture

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
$script:DefaultCulture = "en-US";

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

Export-ModuleMember -Function Initialize-TestRunner, Reset-AITTestSuite, Invoke-AITSuite, Set-InputDatasetInternal, Set-SuiteDefinitionInternal, Get-AITSuiteTestResultInternal, Get-AITSuiteEvaluationResultInternal, Get-AITSuiteTestMethodLinesInternal

# SIG # Begin signature block
# MIIoDAYJKoZIhvcNAQcCoIIn/TCCJ/kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAOki8D+wwfFmip
# Q/ssbvA4EpjFU9+rxgFJDzmjf36uiKCCDXYwggX0MIID3KADAgECAhMzAAAEhV6Z
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
# /Xmfwb1tbWrJUnMTDXpQzTGCGewwghnoAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAASFXpnsDlkvzdcAAAAABIUwDQYJYIZIAWUDBAIB
# BQCggZAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwLwYJKoZIhvcNAQkEMSIE
# IKvAt9Lw5MXiUeCXGLOOKYNdOSkdSM8v2EDaOw+7FRLBMEIGCisGAQQBgjcCAQwx
# NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20wDQYJKoZIhvcNAQEBBQAEggEArpDnzXZZOHjAjGiCN90wC6ZKyCj3DfU0
# 4CoY7Xhf5WmkDAaCVAoYJtJV7+ELHigl0tBL5SflVdly6NkXRTK/GqDK0+0HITyf
# 6VKrbVtRARuL4KKqPS/0HwLmVChjYJK3/+/ZeDAVXFjqWiG8agpLAIgVRDxWtvMQ
# 7mzNkuPWDEMFuAENd9VH4vtn1590HoLnwXD3rzc1IORIBK5ZldtIZCKbRQ/FeQpN
# yE/0LrxYgMKkKUhshwaNmUtMf/ffMF7VJBA0ROAgO424GRWEjs1gxCN3NSQ0OhvH
# yGMqtKuRY/Ln3fK61QSJFaD/7fzO6V4tcgk9aDPtznfOz7lIS9I9z6GCF5QwgheQ
# BgorBgEEAYI3AwMBMYIXgDCCF3wGCSqGSIb3DQEHAqCCF20wghdpAgEDMQ8wDQYJ
# YIZIAWUDBAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYB
# BAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCAqBvUoMLWekPGHpKklmKaQ43EWdBI5
# tps4Oinf/9/TpgIGaKOmD5S1GBMyMDI1MDkxNDIyMDQ1Ny44MzhaMASAAgH0oIHR
# pIHOMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYD
# VQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hp
# ZWxkIFRTUyBFU046RjAwMi0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WgghHqMIIHIDCCBQigAwIBAgITMwAAAgU8dWyCRIfN
# /gABAAACBTANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDAeFw0yNTAxMzAxOTQyNDlaFw0yNjA0MjIxOTQyNDlaMIHLMQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQg
# QW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046RjAw
# Mi0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZp
# Y2UwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCSkvLfd7gF1r2wGdy8
# 5CFYXHUC8ywEyD4LRLv0WYEXeeZ0u5YuK7p2cXVzQmZPOHTN8TWqG2SPlUb+7Pld
# zFDDAlR3vU8piOjmhu9rHW43M2dbor9jl9gluhzwUd2SciVGa7f9t67tM3KFKRSM
# XFtHKF3KwBB7aVo+b1qy5p9DWlo2N5FGrBqHMEVlNyzreHYoDLL+m8fSsqMu/iYU
# qxzK5F4S7IY5NemAB8B+A3QgwVIi64KJIfeKZUeiWKCTf4odUgP3AQilxh48P6z7
# AT4IA0dMEtKhYLFs4W/KNDMsYr7KpQPKVCcC5E8uDHdKewubyzenkTxy4ff1N3g8
# yho5Pi9BfjR0VytrkmpDfep8JPwcb4BNOIXOo1pfdHZ8EvnR7JFZFQiqpMZFlO5C
# AuTYH8ujc5PUHlaMAJ8NEa9TFJTOSBrB7PRgeh/6NJ2xu9yxPh/kVN9BGss93MC6
# UjpoxeM4x70bwbwiK8SNHIO8D8cql7VSevUYbjN4NogFFwhBClhodE/zeGPq6y6i
# xD4z65IHY3zwFQbBVX/w+L/VHNn/BMGs2PGHnlRjO/Kk8NIpN4shkFQqA1fM08fr
# rDSNEY9VKDtpsUpAF51Y1oQ6tJhWM1d3neCXh6b/6N+XeHORCwnY83K+pFMMhg8i
# sXQb6KRl65kg8XYBd4JwkbKoVQIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFHR6Wrs2
# 7b6+yJ3bEZ9o5NdL1bLwMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1Gely
# MF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lv
# cHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNy
# bDBsBggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBD
# QSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYB
# BQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQAOuxk47b1i
# 75V81Tx6xo10xNIr4zZxYVfkF5TFq2kndPHgzVyLnssw/HKkEZRCgZVpkKEJ6Y4j
# vG5tugMi+Wjt7hUMSipk+RpB5gFQvh1xmAEL2flegzTWEsnj0wrESplI5Z3vgf2e
# GXAr/RcqGjSpouHbD2HY9Y3F0Ol6FRDCV/HEGKRHzn2M5rQpFGSjacT4DkqVYmem
# /ArOfSvVojnKEIW914UxGtuhJSr9jOo5RqTX7GIqbtvN7zhWld+i3XxdhdNcflQz
# 9YhoFqQexBenoIRgAPAtwH68xczr9LMC3l9ALEpnsvO0RiKPXF4l22/OfcFffaph
# nl/TDwkiJfxOyAMfUF3xI9+3izT1WX2CFs2RaOAq3dcohyJw+xRG0E8wkCHqkV57
# BbUBEzLX8L9lGJ1DoxYNpoDX7iQzJ9Qdkypi5fv773E3Ch8A+toxeFp6FifQZyCc
# 8IcIBlHyak6MbT6YTVQNgQ/h8FF+S5OqP7CECFvIH2Kt2P0GlOu9C0BfashnTjod
# mtZFZsptUvirk/2HOLLjBiMjDwJsQAFAzJuz4ZtTyorrvER10Gl/mbmViHqhvNAC
# fTzPiLfjDgyvp9s7/bHu/CalKmeiJULGjh/lwAj5319pggsGJqbhJ4FbFc+oU5zf
# fbm/rKjVZ8kxND3im10Qp41n2t/qpyP6ETCCB3EwggVZoAMCAQICEzMAAAAVxedr
# ngKbSZkAAAAAABUwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRp
# ZmljYXRlIEF1dGhvcml0eSAyMDEwMB4XDTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4
# MzIyNVowfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQG
# A1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggIiMA0GCSqGSIb3
# DQEBAQUAA4ICDwAwggIKAoICAQDk4aZM57RyIQt5osvXJHm9DtWC0/3unAcH0qls
# TnXIyjVX9gF/bErg4r25PhdgM/9cT8dm95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLA
# EBjoYH1qUoNEt6aORmsHFPPFdvWGUNzBRMhxXFExN6AKOG6N7dcP2CZTfDlhAnrE
# qv1yaa8dq6z2Nr41JmTamDu6GnszrYBbfowQHJ1S/rboYiXcag/PXfT+jlPP1uyF
# Vk3v3byNpOORj7I5LFGc6XBpDco2LXCOMcg1KL3jtIckw+DJj361VI/c+gVVmG1o
# O5pGve2krnopN6zL64NF50ZuyjLVwIYwXE8s4mKyzbnijYjklqwBSru+cakXW2dg
# 3viSkR4dPf0gz3N9QZpGdc3EXzTdEonW/aUgfX782Z5F37ZyL9t9X4C626p+Nuw2
# TPYrbqgSUei/BQOj0XOmTTd0lBw0gg/wEPK3Rxjtp+iZfD9M269ewvPV2HM9Q07B
# MzlMjgK8QmguEOqEUUbi0b1qGFphAXPKZ6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJ
# NmSLW6CmgyFdXzB0kZSU2LlQ+QuJYfM2BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6
# r1AFemzFER1y7435UsSFF5PAPBXbGjfHCBUYP3irRbb1Hode2o+eFnJpxq57t7c+
# auIurQIDAQABo4IB3TCCAdkwEgYJKwYBBAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3
# FQIEFgQUKqdS/mTEmr6CkTxGNSnPEP8vBO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl
# 0mWnG1M1GelyMFwGA1UdIARVMFMwUQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUH
# AgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0
# b3J5Lmh0bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMA
# dQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAW
# gBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8v
# Y3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRf
# MjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEw
# LTA2LTIzLmNydDANBgkqhkiG9w0BAQsFAAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL
# /Klv6lwUtj5OR2R4sQaTlz0xM7U518JxNj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu
# 6WZnOlNN3Zi6th542DYunKmCVgADsAW+iehp4LoJ7nvfam++Kctu2D9IdQHZGN5t
# ggz1bSNU5HhTdSRXud2f8449xvNo32X2pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfg
# QJY4rPf5KYnDvBewVIVCs/wMnosZiefwC2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8s
# CXgU6ZGyqVvfSaN0DLzskYDSPeZKPmY7T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCr
# dTDFNLB62FD+CljdQDzHVG2dY3RILLFORy3BFARxv2T5JL5zbcqOCb2zAVdJVGTZ
# c9d/HltEAY5aGZFrDZ+kKNxnGSgkujhLmm77IVRrakURR6nxt67I6IleT53S0Ex2
# tVdUCbFpAUR+fKFhbHP+CrvsQWY9af3LwUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8C
# wYKiexcdFYmNcP7ntdAoGokLjzbaukz5m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9
# JZTmdHRbatGePu1+oDEzfbzL6Xu/OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDB
# cQZqELQdVTNYs6FwZvKhggNNMIICNQIBATCB+aGB0aSBzjCByzELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFt
# ZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOkYwMDIt
# MDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNl
# oiMKAQEwBwYFKw4DAhoDFQDVsH9p1tJn+krwCMvqOhVvXrbetKCBgzCBgKR+MHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7HG6
# RTAiGA8yMDI1MDkxNDIyMDM0OVoYDzIwMjUwOTE1MjIwMzQ5WjB0MDoGCisGAQQB
# hFkKBAExLDAqMAoCBQDscbpFAgEAMAcCAQACAkGJMAcCAQACAhI8MAoCBQDscwvF
# AgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSCh
# CjAIAgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBACOmiDzRg2LE5w00muqk7txB
# 66iTWEg26LrvXnM90b2CT0HZJMVJwwnR3AVHzO5pOK38L6axiwUf9i0OSqB48vIA
# ksl0HRKeGMlDfPoN77AF6oXP7mDnz4CRJ1SssFki8eOwXmBOxXHfvrBgO3XgK1K+
# YvoDBYeu9BxCBAvtguWxkPs1l7SfK/b4S1+QZMIxbsLtd6t89nIz8ziHLCXxp+cS
# cOne8J+Fhgx/WVy1vBEHOojv2z8nUsCw8T/RlQkelzINTitOopRfv/u9hwVGicbA
# vsRYDXTjJ2AT57QNQMF5dnJSy8FH3CCP5AwyaJYQXnKzuOdhUsY/WxM7ecqLjLcx
# ggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAA
# AgU8dWyCRIfN/gABAAACBTANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkD
# MQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCBKEPeH7vTzE1J7f52+DHBA
# fCks5SpjF4yj5SusPnJ6QDCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIIAN
# Az3ceY0umhdWLR2sJpq0OPqtJDTAYRmjHVkwEW9IMIGYMIGApH4wfDELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIFPHVsgkSHzf4AAQAAAgUwIgQgcGqG
# PpCHQ7He2F75CJkh/wGP/RaqCxiD4cC9L2dglIwwDQYJKoZIhvcNAQELBQAEggIA
# DTl91IQPd02qqI0K6qNXtDGPSujF+CbE0I5nV2N/h+98U94g59OTP1URQQZ3dbKQ
# HiWU7eth1iBI+sllJuuIwv8UNkwIDsEi75Uzm82DqtOWL2SzC25fDjQXrNDh31G/
# hE4fIfNIPaIPri5vKr0jdUTU/Vtf0J9hbsEiaUvS0NwC8JkjncHNoRpdy0lQNXgp
# N9itwl9FC22wp2CgL9SN9lIfc5WLUoDbmrFaGXW6cvvHqtfizACWeeMpzaO5S6Gr
# LFDfwe1FAmGiAippiczI6YBM3BizVIAjqR3vOPanl7cjVAV4JRT+STDw9EcdWWGE
# h4y0r3aZI+pf1DC5irlY1U3SAtCFk0tF20oY+KeRkz1X3weD+j6+SceSmtckNLjR
# xpy8jl/m+VHWBYE58tCAGmHmil/uYeJI0zbPfhmvG5UkK5ybh6FyLREgIAkdtJ0+
# TsiTEmkfedkCUF8TmKlyJ+6M29+Fw8k0UcEgg7vwwgd7RMlIi5RlQgXhODUbTBaF
# FuSDhVi7PHKldb1/yrvj02TXkxyS57Vkb8sM6hKYQO0yVK9CjfTOBUxEr1ydz0ur
# 0AU2AMnirhDAdmU3pdndi7mkKBnqLGjiqqZ+t7MZjJ3JsP/CXu/hjSmtkqjeWGe0
# Z2nZppA66WKs1zcSo+1Ld1hveHu09BCw7xI3fgNaij0=
# SIG # End signature block
