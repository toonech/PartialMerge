<#
CimType Enum from https://github.com/PowerShell/MMI/blob/cf32fc695b/src/Microsoft.Management.Infrastructure/CimType.cs

The following have no explicit handling:

Reference, ReferenceArray

The following have been handled:
String, StringArray
Boolean, BooleanArray
UInt8, UInt8Array
SInt8, SInt8Array
UInt16, UInt16Array
SInt16, SInt16Array
UInt32, UInt32Array
SInt32, SInt32Array
UInt64, UInt64Array
SInt64, SInt64Array
Real32, Real32Array
Real64, Real64Array
Char16, Char16Array
DateTime, DateTimeArray
Instance (Externally Solved)
InstanceArray (Externally Solved)
#>

class Resource
{
    [string] $Name # Either the ResourceID or CimClassType, used to build the alias
    [string] $InstanceType # The CimClassType of the instance
    [int] $AKA # Alias is a reserved powershell variable
    [hashtable] $Properties # Property entry is Name = Value. Value should be preformated and ready to print.

    Resource()
    {
        $this.Properties = [hashtable]::new()
    }

    Resource([String]$ResourceName, [String]$ResourceType, [String]$ResourceAlias)
    {
        $this.Properties = [hashtable]::new()
        $this.Name = $ResourceName
        $this.InstanceType = $ResourceType
        $this.AKA = $ResourceAlias
    }

    [void] AddProperty([String]$Key, $Value)
    {
        $this.AddProperty($Key, $Value, $false)
    }

    [void] AddProperty([String]$Key, $Value, $SkipStringQuotes)
    {
        switch ($Value.GetType().Name)
        {
            "CimInstance"
            {
                throw "Cannot handle CimInstance as a value of a property, should be handled outside of this class"
            }
            "CimInstance[]"
            {
                throw "Cannot handle CimInstance[] as a value of a property, should be handled outside of this class"
            }
            {$_ -in @("Int64", "Double", "Boolean")}
            {
                $this.Properties.Add($Key, "$Value")
                break;
            }
            {$_ -in @("Int64[]", "Double[]", "Boolean[]")}
            {
                $line = "{`r`n"
                $values = @()
                foreach ($val in $Value)
                {
                    $values += "    $val"
                }
                $line += $values -join ",`r`n"
                $line += "`r`n  }"
                $this.Properties.Add($Key, $line)
                break;
            }
            "Char"
            {
                $this.Properties.Add($Key, "'$Value'")
                break;
            }
            "Char[]"
            {
                $line = "{`r`n"
                $values = @()
                foreach ($val in $Value)
                {
                    if ($SkipStringQuotes)
                    {
                        $values += "    $val"
                    }
                    else
                    {
                        $values += "    '$val'"
                    }
                }
                $line += $values -join ",`r`n"
                $line += "`r`n  }"
                $this.Properties.Add($Key, $line)
                break;
            }
            "String[]"
            {
                $line = "{`r`n"
                $values = @()
                foreach ($val in $Value)
                {
                    if ($SkipStringQuotes)
                    {
                        $values += "    $($val.ToString() -replace "\\", "\\" -replace"[`r]*`n", "\n" -replace '"', '\"')"
                    }
                    else
                    {
                        $values += '    "' + ($val -replace "\\", "\\" -replace "[`r]*`n", "\n" -replace '"', '\"') + '"'
                    }
                }
                $line += $values -join ",`r`n"
                $line += "`r`n  }"
                $this.Properties.Add($Key, $line)
                break;
            }
            Default
            {
                if ($SkipStringQuotes)
                {
                    $this.Properties.Add($Key, "$Value")
                }
                else
                {
                    $this.Properties.Add($Key, '"' + ($Value -replace "\\", "\\" -replace "[`r]*`n", "\n" -replace '"', '\"') + '"')
                }
            }
        }
    }

    [string] GetAlias()
    {
        # Pad the resource alias to 4 digits for 9,999 resources of the same type without complicating regex to find
        # aliases in the value of properties
        return "`${0}_{1:d4}" -f $this.InstanceType, $this.AKA
    }

    [string] ToString()
    {
        if ($this.InstanceType -eq 'OMI_ConfigurationDocument')
        {
            $resString = "instance of {0}`r`n{{`r`n" -f $this.InstanceType
        }
        else
        {
            $resString = "instance of {0} as {1}`r`n{{`r`n" -f $this.InstanceType, $this.GetAlias()
        }
        foreach ($property in $this.Properties.GetEnumerator())
        {
            $resString += "  {0} = {1};`r`n" -f $property.Name, $property.Value
        }
        $resString += "};`r`n"
        return $resString
    }
}

class ResourceExpander
{
    [System.Collections.Generic.LinkedList[Resource]] $Resources
    [Hashtable] hidden $Aliases
    [Resource] hidden $OmiStamp

    ResourceExpander()
    {
        $this.Resources = [System.Collections.Generic.LinkedList[Resource]]::new()
        $this.Aliases = [HashTable]::new()


        $this.OmiStamp = [Resource]::new()
        $this.OmiStamp.Name = "OmiConfig"
        $this.OmiStamp.InstanceType = "OMI_ConfigurationDocument"
        $this.OmiStamp.Properties.Add("Name", '"PartialMergeResult"')
        $this.OmiStamp.Properties.Add("Version", '"2.0.0"')
        $this.OmiStamp.Properties.Add("MinimumCompatibleVersion", '"1.0.0"')
        $this.OmiStamp.Properties.Add("Author", "`"$([System.Environment]::UserName)`"")
        $this.OmiStamp.Properties.Add("GenerationDate", "`"$(Get-Date)`"")
        $this.OmiStamp.Properties.Add("GenerationHost", "`"$([System.Environment]::MachineName)`"")
    }

    [void] ProcessMof([System.Collections.Generic.List[CimInstance]] $Mof)
    {
        foreach ($resource in $Mof)
        {
            if ($resource.CimClass.CimClassName -eq 'OMI_ConfigurationDocument')
            {
                foreach ($property in $resource.CimInstanceProperties)
                {
                    if (-not $this.OmiStamp.Properties.ContainsKey($property.Name))
                    {
                        $this.OmiStamp.AddProperty($property.Name, $property.Value)
                    }
                }
                continue
            }
            $this.AddInstance($resource)
        }
    }

    [void] AddInstance([CimInstance]$Instance)
    {
        try
        {
            $resType = $Instance.CimClass.CimClassName
            $resAKA = $this.NextAlias($resType)
            $resName = $this.GetName($Instance)
            $resource = [Resource]::new($resName, $resType, $resAKA)
            $this.Resources.AddLast($resource)

            foreach ($property in $Instance.CimInstanceProperties)
            {
                if ($property.CimType -eq 'Instance')
                {
                    $resource.AddProperty($property.Name, [string]$this.AddInstance($property.Value, $resource), $true)
                }
                elseif ($property.CimType -eq 'InstanceArray')
                {
                    $resource.AddProperty($property.Name, [string[]]$this.AddInstance($property.Value, $resource), $true)
                }
                else
                {
                    $resource.AddProperty($property.Name, $property.Value)
                }
            }
        }
        catch
        {
            Write-Error -Message 'Error [ResourceExpander]::AddInstance([CimInstance]$Instance):`r`n$_'
        }
    }

    [string] hidden AddInstance([CimInstance]$Instance, [Resource]$ParentResource)
    {
        try
        {
            $resType = $Instance.CimClass.CimClassName
            $resAKA = $this.NextAlias($resType)
            $resName = $this.GetName($Instance)
            $resource = [Resource]::new($resName, $resType, $resAKA)

            # Add this before the parent so it's printed out first
            $this.Resources.AddBefore($this.Resources.Find($ParentResource), $resource)

            foreach ($property in $Instance.CimInstanceProperties)
            {
                if ($property.CimType -eq 'Instance')
                {
                    $resource.AddProperty($property.Name, [string]$this.AddInstance($property.Value, $resource), $true)
                }
                elseif ($property.CimType -eq 'InstanceArray')
                {
                    $resource.AddProperty($property.Name, [string[]]$this.AddInstance($property.Value, $resource), $true)
                }
                else
                {
                    $Resource.AddProperty($property.Name, $property.Value)
                }
            }
            return $resource.GetAlias()
        }
        catch
        {
            return $null
        }
    }

    [string[]] hidden AddInstance([CimInstance[]]$Instances, [Resource]$ParentResource)
    {
        # Unroll the CimInstance Array and call AddInstance for each actual instance
        try
        {
            [string[]]$aka = @() # To keep track of all the aliases being returned
            foreach ($instance in $Instances)
            {
                $aka += $this.AddInstance($instance, $ParentResource)
            }
            return $aka
        }
        catch
        {
            return $null
        }
    }

    [int] hidden NextAlias([String]$ResourceType)
    {
        if (-not $this.Aliases.ContainsKey($ResourceType))
        {
            $this.Aliases.Add($ResourceType, 0)
        }

        $this.Aliases.$ResourceType ++

        return $this.Aliases.$ResourceType
    }

    [string] hidden GetName([CimInstance]$Instance)
    {
        $resName = $Instance.ResourceId
        if ($null -eq $resName)
        {
            $resName = $Instance.CimClass.CimClassName
        }

        return $resName
    }

    [String] ToString()
    {
        $current = $this.Resources.First

        $sb = [System.Text.StringBuilder]::new()
        do
        {
            $sb.Append($current.Value.ToString()) | Out-Null
        }
        until ($null -eq ($current = $current.Next))

        $sb.Append($this.OmiStamp.ToString()) | Out-Null
        return $sb.ToString()
    }
}

<#
.SYNOPSIS
    Detects and catalogs all compiled MOF files for a single client.
.DESCRIPTION
    Recursively evaluates subdirectories for MOF files belonging to a single client and imports them to get an
    array of all CimInstances.
.PARAMETER MofFolder
    The base folder that contains the compiled partials.  Ideal situation is to have each partial compile it's
    resulting mofs into it's own folder.
.PARAMETER ClientName
    The name that identifies the client mofs, such as IP address or HostName.
.EXAMPLE
    $serverMofData = Get-ClientMofs -MofFolder C:\Mofs -ClientName 192.168.0.10

    Given a folder structure of:
    C:\Mofs
      - \Core
        - 192.168.0.10.mof
      - \Sql
        - 192.168.0.10.mof

    Searches the C:\Mofs folder and subfolders for files named '192.168.0.10.mof' and generates the following
    hashtable:
    @{
        'Core-192.168.0.10.mof' = @([CimInstance], [CimInstance])
        'Sql-192.168.0.10.mof' = @([CimInstance], [CimInstance])
    }
.INPUTS
    None.
.OUTPUTS
    Hashtable of CimInstance Arrays
.NOTES
    This function is provided to facilitate the use of 'Import-Module' rather than 'using module'. However if
    access to the underlying classes are needed the module will have to be loaded with a 'using module' statement.
#>
function Get-ClientMofs
{
    [CmdletBinding()]
    [OutputType([Hashtable])]
    param (
        [Parameter()]
        [String]
        $MofFolder,

        [Parameter()]
        [String]
        $ClientName
    )

    $allMofs = Get-ChildItem -Path $MofFolder -Include "$ClientName.mof" -Recurse
    $mofData = @{}
    foreach ($mof in $allMofs)
    {
        $key = "{0}-{1}" -f $mof.Directory.Name, $mof.Name
        $mofData.Add($key, [Microsoft.PowerShell.DesiredStateConfiguration.Internal.DscClassCache]::ImportInstances($mof.FullName, 4))
    }

    return $mofData
}

<#
.SYNOPSIS
    Parses a hashtable generated by Get-ClientMofs to create a single list of CimInstances.
.DESCRIPTION
    Using a hashtable like one generated by Get-ClientMofs, process each array of CimInstances to create a
    single LinkedList of [Resource] objects.  The list will be correctly ordered that so resources that are
    dependant on another, such as MSFT_Credential, come after the needed resource.  Additionally each resource
    type will be correctly and uniquely aliased to prevent naming issues.
.PARAMETER MofData
    A hashtable of arrays.  The key names do not matter and are only to increase troubleshooting speed when
    working with the hashtable.
.EXAMPLE
    $mergedList = Merge-ClientMofs -MofData $serverMofData
.EXAMPLE
    $mergedList = Get-ClientMofs @splatParams | Merge-ClientMofs
.INPUTS
    Hashtable of CimInstance Arrays.
.OUTPUTS
    ResourceExpander.  Custom class used in this module.
.NOTES
    This function is provided to facilitate the use of 'Import-Module' rather than 'using module'. However if
    access to the underlying classes are needed the module will have to be loaded with a 'using module' statement.
#>
function Merge-ClientMofs
{
    [CmdletBinding()]
    [OutputType([ResourceExpander])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Hashtable]
        $MofData
    )

    $allData = [ResourceExpander]::new()

    foreach ($mof in $MofData.GetEnumerator())
    {
        $allData.ProcessMof($mof.Value)
    }

    return $allData
}

<#
.SYNOPSIS
    Generates a single MOF file based on a ResourceExpander object
.DESCRIPTION
    Uses the LinkedList of a ResourceExpander (created by Merge-ClientMofs) to generate a properly formated
    MOF that is the combination of all the partials found by Get-ClientMofs and writes it to a file.  Will
    also generate a checksum for the file if the GenerateChecksum switch is provided.
.PARAMETER CombinedMofs
    A single ResourceExpander.  Merge-ClientMofs will output this when executed.
.PARAMETER OutputFile
    The path to the file that this function should created.
.PARAMETER GenerateChecksum
    Switch, when used will execute New-DscChecksum on the MOF after it is created.
.EXAMPLE
    Write-MergeMof -CombinedMofs $mergedList -OutputFile C:\PullServer\Configurations\server1.mof -GenerateChecksum
    Will create the merged MOF file server1.mof at the specified path along with a server1.mof.checksum file
.INPUTS
    ResourceExpander. A custom class used by this module to facilitate the merging of partial MOFs into a
    single file.
.OUTPUTS
    None.
.NOTES
    This function is provided to facilitate the use of 'Import-Module' rather than 'using module'. However if
    access to the underlying classes are needed the module will have to be loaded with a 'using module' statement.
#>
function Write-MergeMof
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ResourceExpander]
        $CombinedMofs,

        [Parameter(Mandatory = $true)]
        [String]
        $OutputFile,

        [Parameter()]
        [Swtich]
        $GenerateChecksum
    )

    $CombinedMofs.ToString() | Set-Content -Path $OutputFile -Force -Encoding utf8
    if ($GenerateChecksum)
    {
        New-DscChecksum -Path $OutputFile
    }
}

Export-ModuleMember -Function Get-ClientMofs, Merge-ClientMofs, Write-MergeMof
