$ErrorActionPreference = "Stop"

<#
.SYNOPSIS
    Save variables for BC Copilot Chat Generation.
.DESCRIPTION
    This script saves credentials, urls etc. as PowerShell environment variables.
    You then don't need to specify them in the scripts every time.
.PARAMETER ProjectSubscription
    The Azure subscription ID of the AAIS project.
.PARAMETER ProjectResourceGroup
    The Azure resource group of the AAIS project.
.PARAMETER ProjectName
    The name of the AAIS project.
.PARAMETER BcTenantId
    The tenant ID
.PARAMETER BcUrl
    The target url of the BC requests
.PARAMETER BcTenantGuid
    Tenant ID used for token retrieval
.PARAMETER ChatFeatures
    The chat features to enable in Business Central
#>
function Set-BcChatGenVariables {
    param (
        [string]$ProjectSubscription,
        [string]$ProjectResourceGroup,
        [string]$ProjectName,
        [string]$BcTenantId,
        [string]$BcUrl,
        [string]$BcTenantGuid,
        [string]$ChatFeatures
    )

    Write-Host "Saving variables for BC Copilot Chat Generation:"

    foreach ($var in $MyInvocation.BoundParameters.keys) {
        if ($null -ne $MyInvocation.BoundParameters[$var]) {
            [System.Environment]::SetEnvironmentVariable($var, $MyInvocation.BoundParameters[$var])
            Write-Host "Setting new value for `$env`:$var"
        }
    }
}

<#
.SYNOPSIS
    Generate red teaming chat data for BC Copilot Chat using azure AI studio simulation.

.DESCRIPTION
    This script generates red teaming chat data for BC Copilot Chat.
    The chat data is generated from the red teaming data in the AAIS project.
.PARAMETER ProjectSubscription
    The Azure subscription ID of the AAIS project.
.PARAMETER ProjectResourceGroup
    The Azure resource group of the AAIS project.
.PARAMETER ProjectName
    The name of the AAIS project.
.PARAMETER BcTenantId
    The tenant ID
.PARAMETER BcUrl
    The target url of the BC requests
.PARAMETER Scenario
    The adversarial scenario to generate chat data. Default is "ADVERSARIAL_QA".
.PARAMETER RunDirectAttackSimulation
    If set, the script will run the direct attack simulator.
.PARAMETER RunIndirectAttackSimulation
    If set, the script will run the indirect attack simulator.
.PARAMETER MaxConversationTurns
    The maximum number of conversation turns to generate. Default is 2, maximum 5.
    Only applies to conversational scenarios.
.PARAMETER MaxSimulations
    The maximum number of simulations to run. Default is as many as scenario contains.
.PARAMETER OutputFile
    The output file to save the generated chat data. Default is "outputs[...].jsonl", where [...] is current date and time.
.PARAMETER BcTenantGuid
    Tenant ID used for token retrieval
.PARAMETER OutputFileControlSample
    The filepath to save the control sample file in direct attack simulation
.PARAMETER ChatFeatures
    The chat features to enable in Business Central
.PARAMETER UseStaging
    If set, the script will use the staging environment for authentication
#>
function Invoke-BcCopilotChatGenerationAdversarial {
    param (
        [string]$ProjectSubscription,
        [string]$ProjectResourceGroup,
        [string]$ProjectName,
        [string]$BcTenantId,
        [string]$BcUrl,
        [string]$Scenario = "ADVERSARIAL_CONVERSATION",
        [switch]$RunDirectAttackSimulation,
        [switch]$RunIndirectAttackSimulation,
        [int]$MaxConversationTurns = 2,
        [int]$MaxSimulations = 2000,
        [string]$OutputFile = "",
        [string]$BcTenantGuid,
        [string]$OutputFileControlSample = "",
        [string]$ChatFeatures,
        [switch]$UseStaging
    )

    if ($MaxConversationTurns -gt 5) {
        Write-Error "MaxConversationTurns must be 5 or less."
        return
    }

    if ($RunDirectAttackSimulation) {
        $SimulatorName = "JAILBREAK_DIRECT"
    } elseif ($RunIndirectAttackSimulation) {
        $SimulatorName = "JAILBREAK_INDIRECT"
        $Scenario = "ADVERSARIAL_INDIRECT_JAILBREAK"
    } else {
        $SimulatorName = "ADVERSARIAL"
    }

    Write-Host "Invoking BC Copilot Chat Generation, for scenario '$Scenario' and simulator '$SimulatorName'."

    if ($ProjectSubscription -eq "") {
        $ProjectSubscription = $env:ProjectSubscription
    }
    if ($ProjectResourceGroup -eq "") {
        $ProjectResourceGroup = $env:ProjectResourceGroup
    }
    if ($ProjectName -eq "") {
        $ProjectName = $env:ProjectName
    }
    if ($BcTenantId -eq "") {
        $BcTenantId = $env:BcTenantId
    }
    if ($BcUrl -eq "") {
        $BcUrl = $env:BcUrl
    }
    if ($BcTenantGuid -eq "") {
        $BcTenantGuid = $env:BcTenantGuid
    }
    if ($ChatFeatures -eq "") {
        $ChatFeatures = $env:ChatFeatures
    }
    
    if ($null -eq $BcTenantGuid -or $null -eq $BcTenantId -or $null -eq $BcUrl -or $null -eq $ProjectSubscription -or $null -eq $ProjectResourceGroup -or $null -eq $ProjectName) {
        Write-Error "Parameters: BcTenantGuid, BcTenantId, BcUrl, ProjectSubscription, ProjectResourceGroup, and ProjectName are required. Set them as parameters or use Set-BcChatGenVariables."
        return
    }

    python (Join-Path $PSScriptRoot "Python\bc_simulate_chat.py") `
        --project-subscription $ProjectSubscription `
        $($UseStaging ? "--is-staging" : $null) `
        --project-resource-group $ProjectResourceGroup `
        --project-name $ProjectName `
        --bc-tenant-id $BcTenantId `
        --bc-url $BcUrl `
        --scenario $Scenario `
        --simulator-type $SimulatorName `
        --max-conversation-turns $MaxConversationTurns `
        --max-simulation-results $MaxSimulations `
        --output-file $OutputFile `
        --control-sample-file $OutputFileControlSample `
        --tenant-guid $BcTenantGuid `
        --chat-features $ChatFeatures `
}

<#
.SYNOPSIS
    Generate Copilot Chat responses using your own prompts.
.DESCRIPTION
    This script generates responses from BC Copilot Chat from inputs provided by the user.
.PARAMETER BcTenantId
    The tenant ID for webservices requests
.PARAMETER BcUrl
    The target url of the BC requests
.PARAMETER OutputFile
    The output file to save the generated chat data. Default is "outputs[...].jsonl", where [...] is current date and time.
.PARAMETER BcTenantGuid
    Tenant ID used for token retrieval
.PARAMETER Data
    Set of queries to send to the BC Copilot Chat API
.PARAMETER ChatFeatures
    The chat features to enable in Business Central
.PARAMETER UseStaging
    If set, the script will use the staging environment for authentication
#>
function Invoke-BcCopilotChatGenerationFromPrompts {
    param (
        [string]$BcTenantId,
        [string]$BcUrl,
        [string]$OutputFile = "",
        [string]$BcTenantGuid,
        [object]$Data,
        [string]$ChatFeatures,
        [switch]$UseStaging
    )
    
    Write-Host "Invoking BC Copilot Chat Generation from prompts."

    if ($BcTenantId -eq "") {
        $BcTenantId = $env:BcTenantId
        Write-Host "Using BcTenantId from environment variable."
    }
    if ($BcUrl -eq "") {
        $BcUrl = $env:BcUrl
        Write-Host "Using BcUrl from environment variable."
    }
    if ($BcTenantGuid -eq "") {
        $BcTenantGuid = $env:BcTenantGuid
        Write-Host "Using BcTenantGuid from environment variable."
    }   
    if ($null -eq $BcTenantGuid -or $null -eq $BcTenantId -or $null -eq $BcUrl) {
        Write-Error "Parameters: BcTenantGuid, BcTenantId and BcUrl are required. Set them as parameters or use Set-BcChatGenVariables."
        return
    }

    python (Join-Path $PSScriptRoot "Python\bc_simulate_chat.py") `
        --generate-from-dataset `
        $($UseStaging ? "--is-staging" : $null) `
        --bc-tenant-id $BcTenantId `
        --bc-url $BcUrl `
        --output-file $OutputFile `
        --tenant-guid $BcTenantGuid `
        --data $Data `
        --chat-features $ChatFeatures 
        
}
# SIG # Begin signature block
# MIIoJQYJKoZIhvcNAQcCoIIoFjCCKBICAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBHU5RWd3u6f3ul
# kV4svAp0941zam+10QCnMQCcKSIJwaCCDXYwggX0MIID3KADAgECAhMzAAAEhV6Z
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
# /Xmfwb1tbWrJUnMTDXpQzTGCGgUwghoBAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAASFXpnsDlkvzdcAAAAABIUwDQYJYIZIAWUDBAIB
# BQCggZAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwLwYJKoZIhvcNAQkEMSIE
# IJVjWM1I/rB0EFUolyweuDedOcfcHljE5GKnqqaqAlg0MEIGCisGAQQBgjcCAQwx
# NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20wDQYJKoZIhvcNAQEBBQAEggEAqGTV8sesa/qwM2Nh2Xnf9Ym0bljigRyW
# W63K5/y9pfOpZDSUKKpyKg5UYAwDNJ2KwDENkmg3JUxw1ckVtWqfl0d5A+ob2sU4
# RbMhkYZOCYisScltUVqMAxvsUklGEiw/LTxPru2bgurwTON21zLel12Pn5M3A4Z3
# ++3Lp4ymfLj94K7FDE7fS9OvkbI4B8xlyeTHvbk4GZnXCNrC+lg4z+mfgQHb8057
# 15pvAXBl6ZZHSogGQ/j0csijyaHbE0OKlcRO9Kpxnh21rMGirUkWv3ug4DRyminW
# 46AbNJwyeo75Wrl3KuW/3WpPZfijzO9WJTilOvTPsTigTw3bCQo4kqGCF60wghep
# BgorBgEEAYI3AwMBMYIXmTCCF5UGCSqGSIb3DQEHAqCCF4YwgheCAgEDMQ8wDQYJ
# YIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYB
# BAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCA5s8sJr0giJrw3jFT//P+/YRMolwZK
# XKpqMRjFeCZ/5gIGaKR2ObFbGBMyMDI1MDkxMjE3MDA1Ni4zODRaMASAAgH0oIHZ
# pIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYD
# VQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNV
# BAsTHm5TaGllbGQgVFNTIEVTTjo0MzFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEfswggcoMIIFEKADAgECAhMzAAAB
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
# CGJ/2XBjU02N7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIDVjCCAj4CAQEwggEBoYHZ
# pIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYD
# VQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNV
# BAsTHm5TaGllbGQgVFNTIEVTTjo0MzFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUA94Z+bUJn
# +nKwBvII6sg0Ny7aPDaggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDANBgkqhkiG9w0BAQsFAAIFAOxulmMwIhgPMjAyNTA5MTIxMjUzNTVaGA8y
# MDI1MDkxMzEyNTM1NVowdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA7G6WYwIBADAH
# AgEAAgICLTAHAgEAAgISjzAKAgUA7G/n4wIBADA2BgorBgEEAYRZCgQCMSgwJjAM
# BgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEB
# CwUAA4IBAQBgiZHukarhaR7Lk3v5ruiFyZP3251nPgIwSoFDTfk7OpAkhaZSOtYl
# /QXblLv+GSXPkmbe05d8F+a3GSTtu0VEaSdsLpLTiMZ8g2XpKbtjoAx4aJKyIzkD
# iGjhOdraWxgZtIgybnV1mi99h8JlcUVbNb3/3qF5z/rbzrTJVhE09LYQdkFzgzqK
# fRmI4UdlYIikBvZ8sPO3awfNFukYDTZurBtsvTA2Pd6WlzoSMtzJK07Wa0d1n6IN
# 7oRPkaz8waQKT0U7QU8OAcZ074I+OvULzhfzIiuCRCBN4G2BNnBaMLf61QXwuhYs
# GGm7dCqNj0hfXyIneUrc9s7+wD5Q1N3zMYIEDTCCBAkCAQEwgZMwfDELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAH6+ztE03czxtMAAQAAAfowDQYJYIZI
# AWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG
# 9w0BCQQxIgQg5rYDFgMsvucLlAfYUV7yjNO4v/6cSedcllHinIlzHrcwgfoGCyqG
# SIb3DQEJEAIvMYHqMIHnMIHkMIG9BCB98n8tya8+B2jjU/dpJRIwHwHHpco5ogNS
# tYocbkOeVjCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMz
# AAAB+vs7RNN3M8bTAAEAAAH6MCIEIIV5KcwvadE9730cjDfnjVRSZTM3NP2z4ydB
# ZtODANm3MA0GCSqGSIb3DQEBCwUABIICAFE4GQeNvGYSij6DTDlDNzN8J085a9de
# CAI4hWGxoy2Zq20t3XLj44J8bMtTo9ThM7NnVNQiqbTnJqQoHrS97ysWZzEEPGV/
# juNJ3ovElomD7pbiV1KEBrkaYlhlG3Tc0oIn7/YQUQ4R/Iwpl3NwPyf5UPP1LklO
# uGVyYRrldJr2NBbNnnWB4hUubt49p3crG4cFL3jUGcna2IejKi80tqOo9ZNuKSIl
# 18v4u6KuRJPFiUzHzaWnJmfj6F6yaPlYymo85qe4tVjETmy3uEA+b3NQFxlu3dlh
# hpI3vPa9PoQk/eeLfMnerELu8CD7dV0/l+kBU2bTfShqS/ovpETP1/5o5+HPH+0J
# Jbj9ed3XuPyIc39DPCi5bKsliTWELiR9/lMkc+VejqXuwSxlyCtPIXOv3o/wwa4d
# RbS6QdTPvDFgVfdZgJhSYz3eEu5W4t5UePZZvCVL3h1vF4H3gUq8mKL9EwXLU83P
# HFruFIr1V7zKY3hRPHko/U9ThuQeqWmtVOsqUatMmKqY0Hs1ym3Xjg/QyURyD36q
# op+SpNMK2n3Dolf4ywRvSTNmLKQDII8J6/N4+DOWmGoOsDDiotbKm8J33o7tkzhT
# gqwvR2nPxZwp/MVuG47eTSok4W63lIAgTKTJgq22mCLB4pZGYCNv1hdLunpwlJg+
# KGvPAEvRYk/s
# SIG # End signature block
