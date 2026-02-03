
# Initialize
function Initialize-Module {
    param (
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
        [int] $ClientSessionTimeout,
        [int] $TransactionTimeout,
        [string] $Culture = 'en-US'
    )

    $initArguments = @{
        Environment            = $Environment
        AuthorizationType      = $AuthorizationType
        DisableSSLVerification = $DisableSSLVerification
        Credential             = $Credential
        Token                  = $Token
        EnvironmentName        = $EnvironmentName
        ServiceUrl             = $ServiceUrl
        ClientId               = $ClientId
        RedirectUri            = $RedirectUri
        AadTenantId            = $AadTenantId
        APIHost                = $APIHost
        ServerInstance         = $ServerInstance
        CompanyId              = $CompanyId
        Culture                = $Culture
    }
    
    if ($PSBoundParameters.ContainsKey('ClientSessionTimeout')) {
        $initArguments.ClientSessionTimeout = $ClientSessionTimeout
    }
    if ($PSBoundParameters.ContainsKey('TransactionTimeout')) {
        $initArguments.TransactionTimeout = $TransactionTimeout
    }

    TestRunnerInternalForAIT\Initialize-TestRunner @initArguments
}

# Prerequisite: Initialize the Module
# Run the suite test lines and get the test results:
function Invoke-AITTests {
    param (
        [Parameter(Mandatory = $true)]
        [string] $SuiteCode,
        [string] $SuiteLineNo,
        [switch] $ResetTestSuite
    )

    if ($ResetTestSuite) {
        TestRunnerInternalForAIT\Reset-AITTestSuite -SuiteCode $SuiteCode
    }

    $TestRunResult = TestRunnerInternalForAIT\Invoke-AITSuite -SuiteCode $SuiteCode -SuiteLineNo $SuiteLineNo

    return $TestRunResult
}

# Prerequisite: Initialize the Module
# Upload the dataset
function Set-InputDataset {
    param (
        [Parameter(Mandatory = $true)]
        [string] $InputDatasetFilename,
        [Parameter(Mandatory = $true)]
        [string] $InputDatasetPath
    )
    $InputDatasetContent = Get-Content $InputDatasetPath -Raw
    TestRunnerInternalForAIT\Set-InputDatasetInternal -InputDatasetFilename $InputDatasetFilename -InputDataset $InputDatasetContent
}

# Prerequisite: Initialize the Module
# Upload the suite definition
function Set-SuiteDefinition {
    param (
        [Parameter(Mandatory = $true)]
        [string] $SuiteDefinitionPath
    )
    $SuiteDefinition = [xml](Get-Content $SuiteDefinitionPath)
    TestRunnerInternalForAIT\Set-SuiteDefinitionInternal -SuiteDefinition $SuiteDefinition
}

# Prerequisite: Initialize the Module
# Get the test results using the APIs
function Get-AITSuiteTestResult {
    param (
        [Parameter(Mandatory = $true)]
        [string] $SuiteCode,
        [Int32] $TestRunVersion,
        [Int32] $CodeunitId,
        [string] $CodeunitName,
        [string] $TestStatus,
        [string] $ProcedureName
    )

    return TestRunnerInternalForAIT\Get-AITSuiteTestResultInternal -SuiteCode $SuiteCode -TestRunVersion $TestRunVersion -CodeunitId $CodeunitId -CodeunitName $CodeunitName -TestStatus $TestStatus -ProcedureName $ProcedureName
}

# Prerequisite: Initialize the Module
# Get the evaluation results using the APIs
function Get-AITSuiteEvaluationResult {
    param (
        [Parameter(Mandatory = $true)]
        [string] $SuiteCode,
        [Int32] $SuiteLineNo,
        [Int32] $TestRunVersion,
        [string] $TestState
    )

    return TestRunnerInternalForAIT\Get-AITSuiteEvaluationResultInternal -SuiteCode $SuiteCode -SuiteLineNo $SuiteLineNo -TestRunVersion $TestRunVersion -TestState $TestState
}

# Prerequisite: Initialize the Module
# Get the test method lines using the APIs
function Get-AITSuiteTestMethodLines {
    param (
        [Parameter(Mandatory = $true)]
        [string] $SuiteCode,
        [Int32] $TestRunVersion,
        [Int32] $CodeunitId,
        [string] $CodeunitName,
        [string] $TestStatus
    )

    return TestRunnerInternalForAIT\Get-AITSuiteTestMethodLinesInternal -SuiteCode $SuiteCode -TestRunVersion $TestRunVersion -CodeunitId $CodeunitId -CodeunitName $CodeunitName -TestStatus $TestStatus
}

$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot 'Internal\TestRunnerInternalForAIT.psm1') -Force -Scope Local

Export-ModuleMember -Function Initialize-Module, Invoke-AITTests, Set-InputDataset, Set-SuiteDefinition, Get-AITSuiteTestResult, Get-AITSuiteEvaluationResult, Get-AITSuiteTestMethodLines
# SIG # Begin signature block
# MIIoKAYJKoZIhvcNAQcCoIIoGTCCKBUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAohQHJkJOXuLK9
# edHEmFMY/j19pBmlzGC3zUY1mlK2BqCCDXYwggX0MIID3KADAgECAhMzAAAEhV6Z
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
# IMEHHokRrv8V8V7Uay8JPrTHCvCzgiyonxP1vmcAmWIhMEIGCisGAQQBgjcCAQwx
# NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20wDQYJKoZIhvcNAQEBBQAEggEAIKeDqKmXt3c1SDD0NqSjoD00+vwHceMZ
# D3m6Xtcos4bysa2LAEIPYy0KO4hc2HUoFFWznBXFC27AfXjsIVxiTQDxlkq+yscq
# 8oO2y6xhVnZ/X6UGicqzmrTosOEi9Zh/iLlpW0HYhjrI9rPibpcOBgqluuhWC9JR
# VqSUC3PaIb5CpoZjPQW64YTz35bDEHXBexZvE9ddxsYErXQW2Eh+D8dtOy275NHw
# m+IU7cpMpDU4/kcvC1YJqTUpCUrhks0SQXELhAeoI2iYImLBwW/pp538DETMVRTj
# TMOi51WDwFZd75klN6GrIO13ZJ1EGoGaXF+3plKCfqbzZUgaQ/qY0qGCF7Awghes
# BgorBgEEAYI3AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCCF4kwgheFAgEDMQ8wDQYJ
# YIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYB
# BAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCDBJ+vsoDEt/YOojtwSv2YTlyDFynZI
# jztqr3iCJThJnwIGaKNagZGEGBMyMDI1MDkxNDIyMDUwOS4yMzdaMASAAgH0oIHZ
# pIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYD
# VQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNV
# BAsTHm5TaGllbGQgVFNTIEVTTjo2QjA1LTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEf4wggcoMIIFEKADAgECAhMzAAAB
# 9oMvJmpUXSLBAAEAAAH2MA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFBDQSAyMDEwMB4XDTI0MDcyNTE4MzEwNFoXDTI1MTAyMjE4MzEwNFowgdMx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1p
# Y3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNo
# aWVsZCBUU1MgRVNOOjZCMDUtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQg
# VGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKC
# AgEA0UJeLMR/N9WPBZhuKVFF+eWJZ68Wujdj4X6JR05cxO5CepNXo17rVazwWLkm
# 5AjaVh19ZVjDChHzimxsoaXxNu8IDggKwpXvpAAItv4Ux50e9S2uVwfKv57p9JKG
# +Q7VONShujl1NCMkcgSrPdmd/8zcsmhzcNobLomrCAIORZ8IwhYy4siVQlf1NKhl
# yAzmkWJD0N+60IiogFBzg3yISsvroOx0x1xSi2PiRIQlTXE74MggZDIDKqH/hb9F
# T2kK/nV/aXjuo9LMrrRmn44oYYADe/rO95F+SG3uuuhf+H4IriXr0h9ptA6SwHJP
# S2VmbNWCjQWq5G4YkrcqbPMax7vNXUwu7T65E8fFPd1IuE9RsG4TMAV7XkXBopmP
# NfvL0hjxg44kpQn384V46o+zdQqy5K9dDlWm/J6vZtp5yA1PyD3w+HbGubS0niEQ
# 1L6wGOrPfzIm0FdOn+xFo48ERl+Fxw/3OvXM5CY1EqnzEznPjzJc7OJwhJVR3VQD
# HjBcEFTOvS9E0diNu1eocw+ZCkz4Pu/oQv+gqU+bfxL8e7PFktfRDlM6FyOzjP4z
# uI25gD8tO9zJg6g6fRpaZc439mAbkl3zCVzTLDgchv6SxQajJtvvoQaZxQf0tRiP
# cbr2HWfMoqqd9uiQ0hTUEhG44FBSTeUPZeEenRCWadCW4G8CAwEAAaOCAUkwggFF
# MB0GA1UdDgQWBBRIwZsJuOcJfScPWcXZuBA4B89K8jAfBgNVHSMEGDAWgBSfpxVd
# AF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIw
# UENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBo
# dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUy
# MFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYG
# A1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0B
# AQsFAAOCAgEA13kBirH1cHu1WYR1ysj125omGtQ0PaQkEzwGb70xtqSoI+svQihs
# gdTYxaPfp2IVFdgjaMaBi81wB8/nu866FfFKKdhdp3wnMZ91PpP4Ooe7Ncf6qICk
# gSuwgdIdQvqE0h8VQ5QW5sDV4Q0Jnj4f7KHYx4NiM8C4jTw8SQtsuxWiTH2Hikf3
# QYB71a7dB9zgHOkW0hgUEeWO9mh2wWqYS/Q48ASjOqYw/ha54oVOff22WaoH+/Hx
# d9NTEU/4vlvsRIMWT0jsnNI71jVArT4Q9Bt6VShWzyqraE6SKUoZrEwBpVsI0LMg
# 2X3hOLblC1vxM3+wMyOh97aFOs7sFnuemtI2Mfj8qg16BZTJxXlpPurWrG+OBj4B
# oTDkC9AxXYB3yEtuwMs7pRWLyxIxw/wV9THKUGm+x+VE0POLwkrSMgjulSXkpfEL
# HWWiCVslJbFIIB/4Alv+jQJSKAJuo9CErbm2qeDk/zjJYlYaVGMyKuYZ+uSRVKB2
# qkEPcEzG1dO9zIa1Mp32J+zzW3P7suJfjw62s3hDOLk+6lMQOR04x+2o17G3LceL
# kkxJm41ErdiTjAmdClen9yl6HgMpGS4okjFCJX+CpOFX7gBA3PVxQWubisAQbL5H
# gTFBtQNEzcCdh1GYw/6nzzNNt+0GQnnobBddfOAiqkzvItqXjvGyK1QwggdxMIIF
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
# BAsTHm5TaGllbGQgVFNTIEVTTjo2QjA1LTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAFU9eSpdx
# s0a06JFIuGFHIj/I+36ggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDANBgkqhkiG9w0BAQsFAAIFAOxxbuowIhgPMjAyNTA5MTQxNjQyMThaGA8y
# MDI1MDkxNTE2NDIxOFowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA7HFu6gIBADAK
# AgEAAgIFGAIB/zAHAgEAAgIU9TAKAgUA7HLAagIBADA2BgorBgEEAYRZCgQCMSgw
# JjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3
# DQEBCwUAA4IBAQA7g/lPLY074VPCWZbHzYQkwpa2LIZwTd8OTvHCrAmaA5JnZaNI
# ofaA4e/y4hKtPigkqbf+wPTEFjLWoWHVYlMmA0eGj3yI8XMfO7BL6fItuzqeutpo
# ImZr+wsRDYD7ChJbNkEz1OAA1p41K+asx/f1mRiTJdUTjUJ6+hibhjIoFgyDVfZn
# oAYNJ3MfQmFds2SDBhTgf4pYssOdP5mORL8G/3rp/R3Qj9ypkwTQbW/jR1/0AZma
# WP6HBFEDXUES9KS50QxWjxCUcQ4pnuc/0i6Pn6tbWVs9Bafa795o2UBtwZ5C86UN
# uFb9uoEbMGpQI+h21akgucLxLfXgfWRi+GaLMYIEDTCCBAkCAQEwgZMwfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAH2gy8malRdIsEAAQAAAfYwDQYJ
# YIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkq
# hkiG9w0BCQQxIgQgIC0TKsXIiGWUqA7Zs8flGyQ5P6CPFkfyF8BAkKjKK9MwgfoG
# CyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCArYUzxlF6m5USLS4f8NXL/8aoNEVds
# CZRmF+LlQjG2ojCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# AhMzAAAB9oMvJmpUXSLBAAEAAAH2MCIEIBeHokb0CfjzIxeOnsfbIXhh5p5lmcC8
# M/oc6NJ8POUcMA0GCSqGSIb3DQEBCwUABIICACyn/KvXbDVwHUQeVrAZLAZA2es3
# /Uq9R+OEKV6Ggj1cWJEND4oODg60KJfEULoZLSSUljEOgXUgFL58Cxb0iqNrhLYC
# zy6EIH66AP5BPZwggS23wKrVQIJTEoZYJlGtuBCE05eAaDOkpGa0hwjk9+lful8p
# rKZf2RfJOvOAzBcpkOfePCnWzdoAKrkv1Mryfc3GE1kJ4whJECDax374J6jfSjyh
# STp2PyI3yD516mYvH2hf4csCT4dQmYqqpVCzCFNsAnYdeTA7b2CLLCmrhC+mF1Yp
# dVRv+HyEY/2PEziV8nirmP6+yPJ96cs0Z8TU9dX9Kpd9Tij6ATgzUL7inLKkrDUK
# 3OfXddA/BpH/lLUJNwwkd5cTHHqALTZKveWw4Q3AhvF6s09063VOoBd/oQCqasde
# NRvWhrIMkw8m0pCiljaHRu5TaH4lQ7ACad33UEIWqljUsJ8V2iwi/83ex0yCJZrx
# bDYVxLWD3jrIje4t0FbPd4dlq9uIwgM9/HcTmF8yYUylnMtqhsuROam8NIplU0mM
# w4UgMjoXgqmI/C7DfTZO72nzFmA2eHyf5iTRh7SOYLGeuNASUa0c3M5CfpbWDiJn
# oln4UAvI9R0Ifsv1v3qZ3n2GLy1/JoU8I29IZLMgeGp6BrQimuw5d3TIKHZj/ASL
# TdHENwC3073bsWOo
# SIG # End signature block
