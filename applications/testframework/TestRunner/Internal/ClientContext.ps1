#requires -Version 5.0
using namespace Microsoft.Dynamics.Framework.UI.Client
using namespace Microsoft.Dynamics.Framework.UI.Client.Interactions

class ClientContext {

    $events = @()
    $clientSession = $null
    $culture = ""
    $caughtForm = $null
    $IgnoreErrors = $true

    ClientContext([string] $serviceUrl, [pscredential] $credential, [timespan] $interactionTimeout, [string] $culture) 
    {
        $this.Initialize($serviceUrl, ([AuthenticationScheme]::UserNamePassword), (New-Object System.Net.NetworkCredential -ArgumentList $credential.UserName, $credential.Password), $interactionTimeout, $culture)
    }

    ClientContext([string] $serviceUrl, [pscredential] $credential) 
    {
        $this.Initialize($serviceUrl, ([AuthenticationScheme]::UserNamePassword), (New-Object System.Net.NetworkCredential -ArgumentList $credential.UserName, $credential.Password), ([timespan]::FromHours(12)), 'en-US')
    }

    ClientContext([string] $serviceUrl, [timespan] $interactionTimeout, [string] $culture) 
    {
        $this.Initialize($serviceUrl, ([AuthenticationScheme]::Windows), $null, $interactionTimeout, $culture)
    }
    
    ClientContext([string] $serviceUrl) 
    {
        $this.Initialize($serviceUrl, ([AuthenticationScheme]::Windows), $null, ([timespan]::FromHours(12)), 'en-US')
    }

    ClientContext([string] $serviceUrl, [Microsoft.Dynamics.Framework.UI.Client.tokenCredential] $tokenCredential, [timespan] $interactionTimeout = ([timespan]::FromHours(12)), [string] $culture = 'en-US')
    {
        $this.Initialize($serviceUrl, ([AuthenticationScheme]::AzureActiveDirectory), $tokenCredential, $interactionTimeout, $culture)
    }
    
    Initialize([string] $serviceUrl, [AuthenticationScheme] $authenticationScheme, [System.Net.ICredentials] $credential, [timespan] $interactionTimeout, [string] $culture) {
                  
        $clientServicesUrl = $serviceUrl
        if(-not $clientServicesUrl.Contains("/cs/"))
        {
            if($clientServicesUrl.Contains("?"))
            {
                $clientServicesUrl = $clientServicesUrl.Insert($clientServicesUrl.LastIndexOf("?"),"cs/")
            }
            else
            {
                $clientServicesUrl = $clientServicesUrl.TrimEnd("/")
                $clientServicesUrl = $clientServicesUrl + "/cs/"
            }
        }
        $addressUri = New-Object System.Uri -ArgumentList $clientServicesUrl
        $jsonClient = New-Object JsonHttpClient -ArgumentList $addressUri, $credential, $authenticationScheme
        $httpClient = ($jsonClient.GetType().GetField("httpClient", [Reflection.BindingFlags]::NonPublic -bor [Reflection.BindingFlags]::Instance)).GetValue($jsonClient)
        $httpClient.Timeout = $interactionTimeout
        $this.clientSession = New-Object ClientSession -ArgumentList $jsonClient, (New-Object NonDispatcher), (New-Object 'TimerFactory[TaskTimer]')
        $this.culture = $culture
        $this.OpenSession()
    }

    OpenSession() {
        $clientSessionParameters = New-Object ClientSessionParameters
        $clientSessionParameters.CultureId = $this.culture
        $clientSessionParameters.UICultureId = $this.culture
        $clientSessionParameters.AdditionalSettings.Add("IncludeControlIdentifier", $true)        
    
        $this.events += @(Register-ObjectEvent -InputObject $this.clientSession -EventName MessageToShow -Action {
            Write-Host -ForegroundColor Yellow "Message : $($EventArgs.Message)"
        })
        $this.events += @(Register-ObjectEvent -InputObject $this.clientSession -EventName CommunicationError -Action {
            HandleError -ErrorMessage "CommunicationError : $($EventArgs.Exception.Message)"
        })
        $this.events += @(Register-ObjectEvent -InputObject $this.clientSession -EventName UnhandledException -Action {
            HandleError -ErrorMessage "UnhandledException : $($EventArgs.Exception.Message)"
        })
        $this.events += @(Register-ObjectEvent -InputObject $this.clientSession -EventName InvalidCredentialsError -Action {
            HandleError -ErrorMessage "InvalidCredentialsError"
        })
        $this.events += @(Register-ObjectEvent -InputObject $this.clientSession -EventName UriToShow -Action {
            Write-Host -ForegroundColor Yellow "UriToShow : $($EventArgs.UriToShow)"
        })
        $this.events += @(Register-ObjectEvent -InputObject $this.clientSession -EventName DialogToShow -Action {
            $form = $EventArgs.DialogToShow
            if ( $form.ControlIdentifier -eq "00000000-0000-0000-0800-0000836bd2d2" ) {
                $errorControl = $form.ContainedControls | Where-Object { $_ -is [ClientStaticStringControl] } | Select-Object -First 1                
                HandleError -ErrorMessage "ERROR: $($errorControl.StringValue)"
            } elseif ( $form.ControlIdentifier -eq "00000000-0000-0000-0300-0000836bd2d2" ) {
                $errorControl = $form.ContainedControls | Where-Object { $_ -is [ClientStaticStringControl] } | Select-Object -First 1                
                Write-Host -ForegroundColor Yellow "WARNING: $($errorControl.StringValue)"
            } elseif ( $form.MappingHint -eq "InfoDialog" ) {
                $errorControl = $form.ContainedControls | Where-Object { $_ -is [ClientStaticStringControl] } | Select-Object -First 1                
                Write-Host -ForegroundColor Yellow "INFO: $($errorControl.StringValue)"
            }
        })
    
        $this.clientSession.OpenSessionAsync($clientSessionParameters)
        $this.AwaitState([ClientSessionState]::Ready)
    }

    SetIgnoreServerErrors([bool] $IgnoreServerErrors) {
        $this.IgnoreErrors = $IgnoreServerErrors
    }

   HandleError([string] $ErrorMessage) {
        Remove-ClientSession
        if ($this.IgnoreErrors) {
            Write-Host -ForegroundColor Red $ErrorMessage
        } else {
            throw $ErrorMessage
        }
   }   

    Dispose() {
        $this.events | % { Unregister-Event $_.Name }
        $this.events = @()
    
        try {
            if ($this.clientSession -and ($this.clientSession.State -ne ([ClientSessionState]::Closed))) {
                $this.clientSession.CloseSessionAsync()
                $this.AwaitState([ClientSessionState]::Closed)
            }
        }
        catch {
        }
    }
    
    AwaitState([ClientSessionState] $state) {
        While ($this.clientSession.State -ne $state) {
            Start-Sleep -Milliseconds 100
            if ($this.clientSession.State -eq [ClientSessionState]::InError) {
                if ($this.clientSession.LastException) {
                    Write-Host -ForegroundColor Red "ClientSession in Error. LastException: $($this.clientSession.LastException.Message)"
                    Write-Host -ForegroundColor Red "StackTrace: $($this.clientSession.LastException.StackTrace)"
                }
                throw "ClientSession in Error"
            }
            if ($this.clientSession.State -eq [ClientSessionState]::TimedOut) {
                throw "ClientSession timed out"
            }
            if ($this.clientSession.State -eq [ClientSessionState]::Uninitialized) {
                throw "ClientSession is Uninitialized"
            }
        }
    }
    
    InvokeInteraction([ClientInteraction] $interaction) {
        $this.clientSession.InvokeInteractionAsync($interaction)
        $this.AwaitState([ClientSessionState]::Ready)
    }
    
    [ClientLogicalForm] InvokeInteractionAndCatchForm([ClientInteraction] $interaction) {
        $Global:PsTestRunnerCaughtForm = $null
        $formToShowEvent = Register-ObjectEvent -InputObject $this.clientSession -EventName FormToShow -Action { 
            $Global:PsTestRunnerCaughtForm = $EventArgs.FormToShow
        }
        try {
            $this.InvokeInteraction($interaction)
            if (!($Global:PsTestRunnerCaughtForm)) {
                $this.CloseAllWarningOrInfoForms()
            }
        }
        catch
        {
            $ErrorMessage = $_.Exception.Message
            $FailedItem = $_.Exception.ItemName
            Write-Host "Error:" $ErrorMessage "Item: " $FailedItem
        }
        finally {
            Unregister-Event -SourceIdentifier $formToShowEvent.Name
        }
        $form = $Global:PsTestRunnerCaughtForm
        Remove-Variable PsTestRunnerCaughtForm -Scope Global
        return $form
    }
    
    [ClientLogicalForm] OpenForm([int] $page) {
        $interaction = New-Object OpenFormInteraction
        $interaction.Page = $page
        return $this.InvokeInteractionAndCatchForm($interaction)
    }
    
    CloseForm([ClientLogicalForm] $form) {
        $this.InvokeInteraction((New-Object CloseFormInteraction -ArgumentList $form))
    }
    
    [ClientLogicalForm[]]GetAllForms() {
        $forms = @()
        foreach ($form in $this.clientSession.OpenedForms) {
            $forms += $form
        }
        return $forms
    }
    
    [string]GetErrorFromErrorForm() {
        $errorText = ""
        $this.GetAllForms() | % {
            $form = $_
            if ( $form.ControlIdentifier -eq "00000000-0000-0000-0800-0000836bd2d2" ) {
                $form.ContainedControls | Where-Object { $_ -is [ClientStaticStringControl] } | % {
                    $errorText = $_.StringValue
                }
            }
        }
        return $errorText
    }
    
    [string]GetWarningFromWarningForm() {
        $warningText = ""
        $this.GetAllForms() | % {
            $form = $_
            if ( $form.ControlIdentifier -eq "00000000-0000-0000-0300-0000836bd2d2" ) {
                $form.ContainedControls | Where-Object { $_ -is [ClientStaticStringControl] } | % {
                    $warningText = $_.StringValue
                }
            }
        }
        return $warningText
    }

    [Hashtable]GetFormInfo([ClientLogicalForm] $form) {
    
        function Dump-RowControl {
            Param(
                [ClientLogicalControl] $control
            )
            @{
                "$($control.Name)" = $control.ObjectValue
            }
        }
    
        function Dump-Control {
            Param(
                [ClientLogicalControl] $control,
                [int] $indent
            )
    
            $output = @{
                "name" = $control.Name
                "type" = $control.GetType().Name
            }
            if ($control -is [ClientGroupControl]) {
                $output += @{
                    "caption" = $control.Caption
                    "mappingHint" = $control.MappingHint
                }
            } elseif ($control -is [ClientStaticStringControl]) {
                $output += @{
                    "value" = $control.StringValue
                }
            } elseif ($control -is [ClientInt32Control]) {
                $output += @{
                    "value" = $control.ObjectValue
                }
            } elseif ($control -is [ClientStringControl]) {
                $output += @{
                    "value" = $control.stringValue
                }
            } elseif ($control -is [ClientActionControl]) {
                $output += @{
                    "caption" = $control.Caption
                }
            } elseif ($control -is [ClientFilterLogicalControl]) {
            } elseif ($control -is [ClientRepeaterControl]) {
                $output += @{
                    "$($control.name)" = @()
                }
                $index = 0
                while ($true) {
                    if ($index -ge ($control.Offset + $control.DefaultViewport.Count)) {
                        $this.ScrollRepeater($control, 1)
                    }
                    $rowIndex = $index - $control.Offset
                    if ($rowIndex -ge $control.DefaultViewport.Count) {
                        break 
                    }
                    $row = $control.DefaultViewport[$rowIndex]
                    $rowoutput = @{}
                    $row.Children | % { $rowoutput += Dump-RowControl -control $_ }
                    $output[$control.name] += $rowoutput
                    $index++
                }
            }
            else {
            }
            $output
        }
    
        return @{
            "title" = "$($form.Name) $($form.Caption)"
            "controls" = $form.Children | % { Dump-Control -output $output -control $_ -indent 1 }
        }
    }
    
    CloseAllForms() {
        $this.GetAllForms() | % { $this.CloseForm($_) }
    }

    CloseAllErrorForms() {
        $this.GetAllForms() | % {
            if ($_.ControlIdentifier -eq "00000000-0000-0000-0800-0000836bd2d2") {
                $this.CloseForm($_)
            }
        }
    }

    CloseAllWarningOrInfoForms() {
        while ($this.HasWarningOrInfoForms()) {
            $form = $this.clientSession.TopMostInteractiveForm;
            $this.CloseForm($form)
            $this.AwaitState([ClientSessionState]::Ready)
        }
    }

    [bool]HasWarningOrInfoForms() {
        $form = $this.clientSession.TopMostInteractiveForm;
        if($form -eq $null) {
            return $false
        }

        if ($form.ControlIdentifier -eq "00000000-0000-0000-0300-0000836bd2d2" -or $form.MappingHint -eq "InfoDialog") {
            return $true
        }
        return $false
    }
    
    [ClientLogicalControl]GetControlByCaption([ClientLogicalControl] $control, [string] $caption) {
        return $control.ContainedControls | Where-Object { $_.Caption.Replace("&","") -eq $caption } | Select-Object -First 1
    }
    
    [ClientLogicalControl]GetControlByName([ClientLogicalControl] $control, [string] $name) {
        return $control.ContainedControls | Where-Object { $_.Name -eq $name } | Select-Object -First 1
    }
    
    [ClientLogicalControl]GetControlByType([ClientLogicalControl] $control, [Type] $type) {
        return $control.ContainedControls | Where-Object { $_ -is $type } | Select-Object -First 1
    }
    
    SaveValue([ClientLogicalControl] $control, [string] $newValue) {
        $this.InvokeInteraction((New-Object SaveValueInteraction -ArgumentList $control, $newValue))
    }
    
    ScrollRepeater([ClientRepeaterControl] $repeater, [int] $by) {
        $this.InvokeInteraction((New-Object ScrollRepeaterInteraction -ArgumentList $repeater, $by))
    }
    
    ActivateControl([ClientLogicalControl] $control) {
        $this.InvokeInteraction((New-Object ActivateControlInteraction -ArgumentList $control))
    }
    
    [ClientActionControl]GetActionByCaption([ClientLogicalControl] $control, [string] $caption) {
        return $control.ContainedControls | Where-Object { ($_ -is [ClientActionControl]) -and ($_.Caption.Replace("&","") -eq $caption) } | Select-Object -First 1
    }
    
    [ClientActionControl]GetActionByName([ClientLogicalControl] $control, [string] $name) {
        return $control.ContainedControls | Where-Object { ($_ -is [ClientActionControl]) -and ($_.Name -eq $name) } | Select-Object -First 1
    }
    
    InvokeAction([ClientActionControl] $action) {
        $this.InvokeInteraction((New-Object InvokeActionInteraction -ArgumentList $action))
        $this.CloseAllWarningOrInfoForms()
    }
    
    [ClientLogicalForm]InvokeActionAndCatchForm([ClientActionControl] $action) {
        return $this.InvokeInteractionAndCatchForm((New-Object InvokeActionInteraction -ArgumentList $action))
    }
}
# SIG # Begin signature block
# MIIoJQYJKoZIhvcNAQcCoIIoFjCCKBICAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBqluPnVwQ2SdQV
# SqBDLSjL8y+ZixEVs8IGV+27+kBAXaCCDXYwggX0MIID3KADAgECAhMzAAAEhV6Z
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
# IJ7kjQyHWTdKQSkeSnxiqmzgihTU9T1TWtWlVN0QOBjTMEIGCisGAQQBgjcCAQwx
# NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20wDQYJKoZIhvcNAQEBBQAEggEAWJ3FqqIzkwV0gqY/OJvLwsebpzwyzewy
# cDhNeTavCIxq8HwLK4FYVIRIfmEgIsJzxapxPzVC+EegHbzuy/Kk0f4rkANlDxK8
# z5MOGZTsXdpBrTuZYGToiIhQCqTlNq7CmQ7Nuv+SATOP5snRZf5ahv5rJ5mUseQm
# tS4kSWeJFgsHqVfG4aDDuRxFyv5TS8Gioy7Du7iWuk8q4BFitVEWLOY5I2/JDuhb
# 4M2F3orG40ZuMZSbnbyXXrT/xti/0w14e3jzFSiROwd6FW3UgAuV0ZKFpGzEToW1
# SzAO71KhM7F8IyAdSZJihOydAn8yw1XH7+g+BTL09FjTZyQoqE7SkqGCF60wghep
# BgorBgEEAYI3AwMBMYIXmTCCF5UGCSqGSIb3DQEHAqCCF4YwgheCAgEDMQ8wDQYJ
# YIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYB
# BAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCBdab9zZn1xy9wPwOqpcSSbFSETRC8S
# CrU3/0wIhrvSIQIGaKOvpzkoGBMyMDI1MDkxMjE3MDEyNC43NThaMASAAgH0oIHZ
# pIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYD
# VQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNV
# BAsTHm5TaGllbGQgVFNTIEVTTjo0MDFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEfswggcoMIIFEKADAgECAhMzAAAB
# /tCowns0IQsBAAEAAAH+MA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFBDQSAyMDEwMB4XDTI0MDcyNTE4MzExOFoXDTI1MTAyMjE4MzExOFowgdMx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1p
# Y3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNo
# aWVsZCBUU1MgRVNOOjQwMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQg
# VGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKC
# AgEAvLwhFxWlqA43olsE4PCegZ4mSfsH2YTSKEYv8Gn3362Bmaycdf5T3tQxpP3N
# Wm62YHUieIQXw+0u4qlay4AN3IonI+47Npi9fo52xdAXMX0pGrc0eqW8RWN3bfzX
# PKv07O18i2HjDyLuywYyKA9FmWbePjahf9Mwd8QgygkPtwDrVQGLyOkyM3VTiHKq
# hGu9BCGVRdHW9lmPMrrUlPWiYV9LVCB5VYd+AEUtdfqAdqlzVxA53EgxSqhp6Jbf
# EKnTdcfP6T8Mir0HrwTTtV2h2yDBtjXbQIaqycKOb633GfRkn216LODBg37P/xwh
# odXT81ZC2aHN7exEDmmbiWssjGvFJkli2g6dt01eShOiGmhbonr0qXXcBeqNb6Qo
# F8jX/uDVtY9pvL4j8aEWS49hKUH0mzsCucIrwUS+x8MuT0uf7VXCFNFbiCUNRTof
# xJ3B454eGJhL0fwUTRbgyCbpLgKMKDiCRub65DhaeDvUAAJT93KSCoeFCoklPavb
# gQyahGZDL/vWAVjX5b8Jzhly9gGCdK/qi6i+cxZ0S8x6B2yjPbZfdBVfH/NBp/1L
# n7xbeOETAOn7OT9D3UGt0q+KiWgY42HnLjyhl1bAu5HfgryAO3DCaIdV2tjvkJay
# 2qOnF7Dgj8a60KQT9QgfJfwXnr3ZKibYMjaUbCNIDnxz2ykCAwEAAaOCAUkwggFF
# MB0GA1UdDgQWBBRvznuJ9SU2g5l/5/b+5CBibbHF3TAfBgNVHSMEGDAWgBSfpxVd
# AF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIw
# UENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBo
# dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUy
# MFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYG
# A1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0B
# AQsFAAOCAgEAiT4NUvO2lw+0dDMtsBuxmX2o3lVQqnQkuITAGIGCgI+sl7ZqZOTD
# d8LqxsH4GWCPTztc3tr8AgBvsYIzWjFwioCjCQODq1oBMWNzEsKzckHxAzYo5Sze
# 7OPkMA3DAxVq4SSR8y+TRC2GcOd0JReZ1lPlhlPl9XI+z8OgtOPmQnLLiP9qzpTH
# wFze+sbqSn8cekduMZdLyHJk3Niw3AnglU/WTzGsQAdch9SVV4LHifUnmwTf0i07
# iKtTlNkq3bx1iyWg7N7jGZABRWT2mX+YAVHlK27t9n+WtYbn6cOJNX6LsH8xPVBR
# YAIRVkWsMyEAdoP9dqfaZzwXGmjuVQ931NhzHjjG+Efw118DXjk3Vq3qUI1re34z
# MMTRzZZEw82FupF3viXNR3DVOlS9JH4x5emfINa1uuSac6F4CeJCD1GakfS7D5ay
# NsaZ2e+sBUh62KVTlhEsQRHZRwCTxbix1Y4iJw+PDNLc0Hf19qX2XiX0u2SM9CWT
# Tjsz9SvCjIKSxCZFCNv/zpKIlsHx7hQNQHSMbKh0/wwn86uiIALEjazUszE0+X6r
# cObDfU4h/O/0vmbF3BMR+45rAZMAETJsRDPxHJCo/5XGhWdg/LoJ5XWBrODL44YN
# rN7FRnHEAAr06sflqZ8eeV3FuDKdP5h19WUnGWwO1H/ZjUzOoVGiV3gwggdxMIIF
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
# BAsTHm5TaGllbGQgVFNTIEVTTjo0MDFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAhGNHD/a7
# Q0bQLWVG9JuGxgLRXseggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDANBgkqhkiG9w0BAQsFAAIFAOxueIAwIhgPMjAyNTA5MTIxMDQ2MjRaGA8y
# MDI1MDkxMzEwNDYyNFowdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA7G54gAIBADAH
# AgEAAgINhDAHAgEAAgISRTAKAgUA7G/KAAIBADA2BgorBgEEAYRZCgQCMSgwJjAM
# BgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEB
# CwUAA4IBAQBZzHDi+UYwjCF8DeRRwMLCD0fC+YTIkaYQZIbbC1BV9tUDim6dNEU+
# jVOlvOpD+h5+XOCPTEk71PEXuS/LcbvEA2rG3T+Xa8ZIgHGqFvoFmup0Tw1mE9Nc
# 6dj+yJJHP1Z0Z4lz+f8pZS7PzvBryzXnyGQ2cw5RxIWANaM0FY2mEeE0GptSyUYR
# qw4VU1E88QXEXQAnDSd/fUh+FPm9S4fwipzLAkBWQplqG53is0aV69Vhc2PQ2h8c
# ubqByf8uxwe9rR8sVSh7YF5+oW/F1K1KVSRSHSK5Gy3sLjdwX3FQFTFlEAXE1jNL
# 25cxYZBiV7DgPXTC4fWtPvPYUDxL3GhaMYIEDTCCBAkCAQEwgZMwfDELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAH+0KjCezQhCwEAAQAAAf4wDQYJYIZI
# AWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG
# 9w0BCQQxIgQgm7NlrVELW61G20CZ4ZWSDBvWWpDBhIkzhHHIrQ3QSw4wgfoGCyqG
# SIb3DQEJEAIvMYHqMIHnMIHkMIG9BCARhczd/FPInxjR92m2hPWqc+vGOG1+/I0W
# tkCstyh0eTCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMz
# AAAB/tCowns0IQsBAAEAAAH+MCIEIB8pzEE6fGN6zJdOIlyO1Y43FF4a6meAm2Mt
# OHpaNJ2xMA0GCSqGSIb3DQEBCwUABIICAIX+kbD2OYieIJYhQDbEtOSkVlnw6+ny
# ADUcUzfBkC4RDV5eBRphbN05RQa9VPck+J6SFf+IhsBPCgiN/X47SZJx2WwdcDk+
# mDrrvNPifXhGMOhXU2PXtkiNSsDsrmKYwJwMDngR+EewiIl7V/O41GI0TzKE6Jnb
# eW0l6v9sHB8qiASnOLauP8Z2Uso3R0hV4gTCbWPcCpnW2ERk2i42U4nWVFgdNzzv
# PhkhImC0hlO4Jc6O2pJeSK4M5zei16yo0j23gCJ9GxgHv0DkbjZ20eZsBUL7NUr9
# qc2voalBDKcoG7ht1ZUJQyqlShwjCGACLheH53IJ1/VhAISON8Cvpo1IO4Ty0lRy
# /2ad2+52rSM4/GMap/9zNHE97koZYQ0YNM9Y4JWOHS9De2gGxFyQve2kpfI9u/iU
# 0Fwxe6HgErhTzapNAdJsVhiN6B9qTkXvqjisMlHdrfhmX3E+DNPWjCCNHj7U5m4I
# A7rGvPk+qtCPRpMGlLspruZvdATouZH1GIHQbWCYXjuKkKIcufe/4x+jfE7LzV8o
# YdLaDZ1b5mK52B97GWwYO3uu9DmO7MM0frZfXjr8fxPIw+l+TcBpcAgFSOvsKrHM
# 8VLuPuSnygFMXGB3idJnoypP2/6DeSwnNtmbWFNpVr7xARRPIyFrfK5o5Z61a30i
# K0cuxEf6tSml
# SIG # End signature block
