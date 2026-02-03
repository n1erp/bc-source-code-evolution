$ErrorActionPreference = "Stop"
$DefaultBaseUri = "http://127.0.0.1:8000"

<#
.SYNOPSIS
    Install prerequisites for BC Copilot Evaluation.

.DESCRIPTION
    This script installs the Python prerequisites for BC Copilot Evaluation in a virtual Python environment.
    If Python3 is not installed, the user will be prompted to install it.
    You may have to restart the terminal to run Enable-BcCopilotEvaluationPrerequisites afterwards.

.PARAMETER VenvName
    The name of the Python virtual environment that will be created.
    
.EXAMPLE
    Install-BcCopilotEvaluationPrerequisites -VenvName "venv"
    This example installs the prerequisites for BC Copilot Evaluation in a Python virtual environment named "venv".
#>
function Install-BcCopilotEvaluationPrerequisites {
    param (
        [string]$VenvName = "venv"
    )
    Write-Host "Installing Python virtual environment for BC Copilot Evaluation in '$VenvName'."

    . python3 -m venv $VenvName
    . $VenvName\Scripts\Activate.ps1

    . pip install azure-ai-evaluation
    . pip install promptflow-azure
    . pip install setuptools
    . pip install simplejson
}

<#
.SYNOPSIS
    Enable the Python virtual environment for BC Copilot simulation and evaluation.
.DESCRIPTION
    This script enables the Python virtual environment for BC Copilot simulation and evaluation.

    To run use Azure AI Studio (AAIS), the following environment variables must be defined:
    - AZURE_AI_SUBSCRIPTION_ID: the subscription for AAIS
    - AZURE_AI_RESOURCE_GROUP: the resource group for AAIS
    - AZURE_AI_PROJECT: the project for AAIS

    To use non-Responsible AI service-based metrics, a model is needed. To use a model set the following environment variables:
    - MODEL_ENDPOINT: the endpoint for the model
    - MODEL_DEPLOYMENT_NAME: the deployment name for the model
#>
function Enable-BcCopilotEvaluationPrerequisites {
    param (
        [string]$VenvName = "venv"
    )

    Write-Host "Enabling Python virtual environment for BC Copilot Evaluation in '$VenvName'."
    . (Join-Path $PSScriptRoot $VenvName\Scripts\Activate.ps1)

    Write-Host "Checking environment variables."
    if (!$env:AZURE_AI_PROJECT -or !$env:AZURE_AI_RESOURCE_GROUP -or !$env:AZURE_AI_SUBSCRIPTION_ID) {
        Write-Error "The environment variables AZURE_AI_PROJECT, AZURE_AI_RESOURCE_GROUP, and AZURE_AI_SUBSCRIPTION_ID must be set."
        return
    }

    if (!$env:MODEL_ENDPOINT -or !$env:MODEL_DEPLOYMENT_NAME) {
        Write-Host -ForegroundColor Blue "The environment variables MODEL_ENDPOINT and MODEL_DEPLOYMENT_NAME are not set so non-RAI metrics cannot be used."
    }
}

<#
.SYNOPSIS
    Starts the BC Copilot simulation API.
    To run simulations, the API must be running.

.DESCRIPTION
    This runs a web server that provides an API for BC Copilot simulation.
    The default URI is http://localhost:8000.

.PARAMETER VenvName
    The name of the Python virtual environment that will be used (default is `venv`).
    
.PARAMETER HostName
    The host name for the API (default is `http://localhost`).

.PARAMETER Port
    The port for the API (default is `8000`).
    
.EXAMPLE
    Start-BcCopilotSimulationApi
    This example start the BC Copilot Evaluation API server in a Python virtual environment named "venv".
#>
function Start-BcCopilotSimulationApi {
    param (
        [string]$VenvName = "venv",
        [string]$HostName = "http://localhost",
        [int]$Port = 8000
    )
    Set-Variable -Name "DefaultBaseUri" -Value "$($HostName):$($Port)"

    Enable-BcCopilotEvaluationPrerequisites -VenvName $VenvName

    Write-Host "Starting Python API server for BC Copilot Evaluation on port $Port."
    python (Join-Path $PSScriptRoot "Python\bc_api.py") $Port
}

enum Scenario {
    ADVERSARIAL_QA
    ADVERSARIAL_CONVERSATION
    ADVERSARIAL_INDIRECT_JAILBREAK
}

function New-BcCopilotSimulation {
    param (
        [Scenario]$Scenario = [Scenario]::ADVERSARIAL_QA,
        [int]$MaxConversationTurns = 3,
        [int]$MaxSimulationResults = 100,
        [switch]$UPIA,
        [int]$Seed = $null,
        [string]$BaseUri = $DefaultBaseUri
    )

    if ($null -eq $Seed) {
        $Seed = Get-Random -Minimum 0 -Maximum 1000000
    }   

    $Simulation = Invoke-RestMethod `
        -Uri ("{0}/simulation" -f $BaseUri) `
        -Method Post `
        -Headers @{ "Content-Type" = "application/json" } `
        -Body (@{ 
                scenario = $Scenario.ToString();
                max_conversation_turns = $MaxConversationTurns;
                max_simulation_results = $MaxSimulationResults;
                upia = $UPIA;
                randomization_seed = $Seed;
                } | ConvertTo-Json)
    
    return $Simulation
}

function Get-BcCopilotHarmRequest
{
    param (
        [object]$Simulation,
        [switch]$Peek,
        [string]$BaseUri = $DefaultBaseUri
    )
    if ($Peek) {
        Invoke-RestMethod `
            -Uri ("{0}/simulation/{1}/queries/peek" -f $BaseUri, $Simulation.Id) `
            -Method Get
    } else 
    {
        Invoke-RestMethod `
            -Uri ("{0}/simulation/{1}/queries" -f $BaseUri, $Simulation.Id) `
            -Method Get
    }
}

function Set-BcCopilotHarmResponse
{
    param (
        [object]$Simulation,
        [string]$Response = [string]::Empty,
        [switch]$TerminateConversation,
        [string]$BaseUri = $DefaultBaseUri
    )

    if ($TerminateConversation) {
        $Response += ". GOODBYE!"
    }

    Invoke-RestMethod `
        -Uri ("{0}/simulation/{1}/responses" -f $BaseUri, $Simulation.Id) `
        -Method Put `
        -Headers @{ "Content-Type" = "application/json" } `
        -Body (@{ response = $Response } | ConvertTo-Json)
}

<#
.SYNOPSIS
    Invoke BC Copilot Evaluation and store result in Azure AI Studio.
.DESCRIPTION
    This script invokes BC Copilot Evaluation.
.PARAMETER EvaluationName
    The name of the evaluation.
.PARAMETER Evaluators
    The evaluation metrics to use.
    Built-in metrics are deined here:
        https://learn.microsoft.com/en-us/azure/ai-studio/how-to/develop/flow-evaluate-sdk#required-data-input-for-built-in-evaluators

    For custom metrics, see the README.
.PARAMETER Data
    Either a path a test dataset file or an array of objects with test data.
.PARAMETER ColumnMapping
    If the data does not have the columns query, response, context, ground_truth, a column mapping can be added.
.EXAMPLE
    Invoke-BcCopilotEvaluation `
        -EvaluationName "MyEvaluation" `
        -Evaluators "SelfHarmEvaluator", "ViolenceEvaluator" `
        -Data "Samples\sample-columnmapping.jsonl" `
        -ColumnMapping (@{
            query = "`${data.question}";
            response = "`${data.answer}"
        } | ConvertTo-Json)

    This example create the evaluation "MyEvaluation" using the SelfHarmEvaluator and ViolenceEvaluator metrics.
    The test data is loaded from the file "Samples\sample-columnmapping.jsonl" 
    and a column mapping is provided, mapping "question" to "query" and "answer" to "response".
#>
function Invoke-BcCopilotEvaluation
{
    param (
        [string]$EvaluationName = $null,
        [string[]]$Evaluators = @(),
        [object]$Data,
        [object]$ColumnMapping = $null,
        [string]$BaseUri = $DefaultBaseUri,
        [string]$VenvName = "venv"
    )

    if ($Data -is [string]) {
        $Data = (Resolve-Path $Data).Path
    }
    
    $Arguments = @{
        data = $Data;
        evaluators = $Evaluators;
        out_file = (New-TemporaryFile).FullName
    }
    if ($EvaluationName) {
        $Arguments.name = $EvaluationName
    }
    if ($ColumnMapping) {
        $Arguments.column_mapping = $ColumnMapping
    }

    Enable-BcCopilotEvaluationPrerequisites -VenvName $VenvName

    Write-Host "Starting BC Copilot evaluation. Writing results to $($Arguments.out_file)."
    python (Join-Path $PSScriptRoot "Python\bc_evaluation.py") ($Arguments | ConvertTo-Json -Depth 10)

    $Evaluation = Get-Content $Arguments.out_file | ConvertFrom-Json

    Remove-Item $Arguments.out_file

    return $Evaluation
}

# SIG # Begin signature block
# MIIoJQYJKoZIhvcNAQcCoIIoFjCCKBICAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBRYUgTE6l/r5sF
# cgYQzhGbQNB4VY25B8Gynw5IOpZvIaCCDXYwggX0MIID3KADAgECAhMzAAAEBGx0
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
# /Xmfwb1tbWrJUnMTDXpQzTGCGgUwghoBAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAAQEbHQG/1crJ3IAAAAABAQwDQYJYIZIAWUDBAIB
# BQCggZAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwLwYJKoZIhvcNAQkEMSIE
# IH7BBLCfMV/pPHCau33CdyEr/J0y0AtpmLsa8mZOvaZKMEIGCisGAQQBgjcCAQwx
# NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20wDQYJKoZIhvcNAQEBBQAEggEAr21P1IAiSpNApS/Q2FT2Yxo+mTmc35mr
# w61kZkBdcDt0QNlw6PJk40IyvgDjQbslUYERN/SA6xKZpT9ZqYTU0p9n45PiAvpr
# 4vytASl4w6vzOUm9NfRPi9DTqLQL/VSF73QHCHQGFkveYA4pZvulxl6QbyCFkRrA
# 9qTIJBylr1QB8caS3iwOhiT7P/Sp8xYxk3juAi3Swb4Cbo1UsElp/bSHOItNCuIX
# ilTnudBZk8kgtJ3t2mzzLqOBexoIQKvM2WZhqXEhKeRKJGT6WMmGfAOzTsSlZYKy
# V7yIxMJSuFh80icrvkhQcj8I5KpHfPW6KP8goW+CGkjqLZJv7Jj7TaGCF60wghep
# BgorBgEEAYI3AwMBMYIXmTCCF5UGCSqGSIb3DQEHAqCCF4YwgheCAgEDMQ8wDQYJ
# YIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYB
# BAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCB190wjK1hD1bwIKAz0rovuAXY5FveY
# dXhAgxfFNndt/QIGZ/VApeneGBMyMDI1MDQyMjEyMDAyMi4xOTNaMASAAgH0oIHZ
# pIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYD
# VQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNV
# BAsTHm5TaGllbGQgVFNTIEVTTjo2QjA1LTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEfswggcoMIIFEKADAgECAhMzAAAB
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
# CGJ/2XBjU02N7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIDVjCCAj4CAQEwggEBoYHZ
# pIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYD
# VQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNV
# BAsTHm5TaGllbGQgVFNTIEVTTjo2QjA1LTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAFU9eSpdx
# s0a06JFIuGFHIj/I+36ggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDANBgkqhkiG9w0BAQsFAAIFAOuxioEwIhgPMjAyNTA0MjIwMzI0NDlaGA8y
# MDI1MDQyMzAzMjQ0OVowdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA67GKgQIBADAH
# AgEAAgICkjAHAgEAAgISGTAKAgUA67LcAQIBADA2BgorBgEEAYRZCgQCMSgwJjAM
# BgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEB
# CwUAA4IBAQAe5shfLjN+gOsrXgQtV80ZmcW3Om2hlqBvgrKX6gTfsdx6BquaJ7pn
# 7Dmn0/8Lr+yhu8r6HuwqXTHhxQLbPRjR7oxiTU0WMsKNsvgKvQkmHSoyZbmkcVN0
# YN0ssW4pPjs4GR7/eTrjBP5s3j7SpB2xlMhvSyQEEJOod75ojymNj6bigXo8y7Oq
# PFDvCOc9xIEmfjm1ai/lHtfZ5WpoxxFv2euNWGpE6mQwlNTDNgT2uMVaFAoZ3aec
# +pkS4N+7214rU/p0aTg8drgceMl0XlJ24KarFGOoFdaE+8XXEvO6ryDmO+4omIC7
# pXE3BH4ZEzcCiMuhsTyQl8d//NJipmgVMYIEDTCCBAkCAQEwgZMwfDELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAH2gy8malRdIsEAAQAAAfYwDQYJYIZI
# AWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG
# 9w0BCQQxIgQgAF1rlCkH6MvrkwQJaC47NK4EH18YiJeNYy6M8Olr7gIwgfoGCyqG
# SIb3DQEJEAIvMYHqMIHnMIHkMIG9BCArYUzxlF6m5USLS4f8NXL/8aoNEVdsCZRm
# F+LlQjG2ojCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMz
# AAAB9oMvJmpUXSLBAAEAAAH2MCIEIMl6dwpYxZAZNA33OhWjMJcl2rapUB1SZepU
# KwH1eYJzMA0GCSqGSIb3DQEBCwUABIICAKzIxuL55WMJUvTPF0dVjgYGhAV4V08Z
# SwSp6y6bdw+slmj+2fb7z6heE2Ugo8Z+kc9VdVV1u0BToTA1Bse6Tu7C5XMY9FC1
# HYWjisTu6eRBH98zuOx7g5jQHZCEBATx1nOOXKsJHBA7Eji6Ekv7Dfjt/VtkBBM3
# o5nNITAGy4qjE6pwcunF5i6insQZG912PnO0l/d9ewHDlfoUoxL1xHmdI70LGzCK
# sEzvQVhR5e+0GL4X/OjUzE9MOOWjuHXhz5tI5VBN5qHmUyaXjhPiq8y+zMAHOhVP
# 8BkT/+O6W5q9MXZwiORbgkWnxP7wCQmIyMruiA8hn7SJRhLW+OWkZ9B9hS3AimzV
# DKUkHZLTjBz78JrAqpP2My+iJwl1qbdkZrDy1h13cJcluaomen5rZRdELn8pxJNm
# 0FFaxmtay6Asi+iUXt8Lp0E0xVvoWVMqRRWH0hLx7DHzHt6mnGXdRkl7gMXV7pIB
# 4cYvuYOxn7b1RcN1zVQkji7xPCzwBg7K+fdqhx1fSRpLptu5KyHIZB0g7OKdr3J1
# xNrQqf66FRasfWf2ntL6gOUE7Be30M9ncJMmC10TXKHboX3iBpma/wjD4mo+FY27
# X1HfsZ6wHUm4NY/R9ihgYqGDMQ6RX8gkxx8Ev+31SBz3C6zcyr8Kcs43WTwba4WR
# TZdyYQa/X72r
# SIG # End signature block
