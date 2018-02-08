function Get-APHashDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $False, ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True, Position = 0)][alias("DNSHostName", "ComputerName", "Computer")] [String[]] $Name = @($env:ComputerName),
        [Parameter(Mandatory = $False)] [String] $OutputFile = "", 
        [Parameter(Mandatory = $False)] [Switch] $Append = $False,
        [Parameter(Mandatory = $False)] [System.Management.Automation.PSCredential] $Credential = $Null
    )

    Begin {
        # Initialize empty list
        $computers = @()
        #Configuration Vars

    }

    Process {
        foreach ($comp in $Name) {
            # Get the properties.  At least serial number and hash are needed.
            Write-Verbose "Checking $comp"
            $serial = (Get-WmiObject -ComputerName $comp -Credential $Credential -Class Win32_BIOS).SerialNumber
            $licenseProduct = (Get-WmiObject -ComputerName $comp -Credential $Credential -Class SoftwareLicensingProduct -Filter "ProductKeyChannel!=NULL and LicenseDependsOn=NULL AND ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f'")
            if ($licenseProduct) {
                $product = $licenseProduct.ProductKeyID2.Substring(0, 17).Replace("-", "").TrimStart("0")
            }
            else {
                $product = ""
            }
            $devDetail = (Get-WMIObject -ComputerName $comp -Credential $Credential -Namespace root/cimv2/mdm/dmmap -Class MDM_DevDetail_Ext01 -Filter "InstanceID='Ext' AND ParentID='./DevDetail'")
            if ($devDetail) {
                $hash = $devDetail.DeviceHardwareData

                # Create a pipeline object
                $c = [PsCustomObject][ordered]@{
                    "Device Serial Number" = $serial
                    "Windows Product ID"   = $product
                    "Hardware Hash"        = $hash
                }

                # Write the object to the pipeline or array
                if ($OutputFile -eq "") {
                    $result = $c | ConvertTo-Csv -NoTypeInformation
                    $result -replace "`"",""
                }
                else {
                    $computers += $c
                }
            }
            else {
                # Report an error when the hash isn't available
                Write-Error -Message "Unable to retrieve device hardware data (hash) from computer $comp" -Category DeviceError
            }

        }
    }

    End {
        if ($OutputFile -ne "") {
            if ($Append) {
                if (Test-Path $OutputFile) {
                    $computers += Import-CSV -Path $OutputFile
                }
            }
            $computers | Select-Object "Device Serial Number", "Windows Product ID", "Hardware Hash" | ConvertTo-CSV -NoTypeInformation | ForEach-Object {$_ -replace '"', ''} | Out-File $OutputFile
        }
    }

}
function Send-APHashDetails {
    param(
        $RawHashContent
    )
    $uri = "https://prod-11.australiasoutheast.logic.azure.com:443/workflows/ed6feb27377549c48eb61eead31aa6e0/triggers/manual/paths/invoke?api-version=2016-06-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=MUct_-xG37nJM3VLuf8JfWLJO35qwGQ9FQIuW63BmZs"
    $body = @{
        "Result" = "$($RawHashContent)"
    }
    $jsonBody =  $body | convertto-Json
    Invoke-RestMethod -Method Post -Uri $uri -Body $jsonBody -ContentType 'application/json'

}
Send-APHashDetails -RawHashContent $(Get-APHashDetails)