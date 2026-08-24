using namespace System.Net
param($Request, $TriggerMetadata)

$ITGJsonDepth = 8
# $VerbosePreference = "Continue"

Write-Information ("Incoming {0} {1}" -f $Request.Method,$Request.Url)

Function ImmediateFailure ($Message, $Company, $Details) {
    $Err = "$($Message)  Company: $($Company)  Method: $($Request.Method)"
    if ($Details) {
        $Err += " \n Details: " + $Details
    }
    Write-Error $Err
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        headers    = @{'content-type' = 'application\json' }
        StatusCode = [httpstatuscode]::OK
        Body       = @{"Error" = $Message } | convertto-json
    })
    exit 1
}

function Build-Body {
 param($whitelistObj, $sourceObj, $depth = 1)
    # Safety Checks
    if ($depth -gt ($ITGJsonDepth + 2)) {
        Write-Error "Possible recursion loop or source object is deeper than expected."
        Return
    } 
    if (-not $sourceObj) {
        Return
    }

    # 1. Dictionary / Hashtable mapping
    if ($whitelistObj -is [hashtable] -or $whitelistObj -is [System.Collections.Specialized.OrderedDictionary]) {
        # When the whitelist object is a dictionary, loop over the keys and if they exist in the 
        # source object, recurse. Note that any extra keys will not be checked or logged.
        $counter = 0
        $newObjectHash = [ordered]@{}
        
        foreach ($key in $whitelistObj.keys) {
            # Safely check if the property exists on the source payload
            $keyExists = if ($sourceObj -is [System.Collections.IDictionary]) {
                $sourceObj.Contains($key)
            } else {
                $null -ne $sourceObj.PSObject.Properties[$key]
            }

            if ($keyExists) {
                $counter++
                
                # If the value is truthy, recurse
                if ($sourceObj.$key) {
                    if ($sourceObj.$key -is [array]) {
                        # forces existing arrays to stay as arrays. Without this, arrays with 1 item get reduced to just that item (not in an array).
                        $newObjectHash[$key] = @(Build-Body -whitelistObj $whitelistObj[$key] -sourceObj $sourceObj.$key -depth ($depth + 1))
                    } else {
                        $newObjectHash[$key] = Build-Body -whitelistObj $whitelistObj[$key] -sourceObj $sourceObj.$key -depth ($depth + 1)
                    }
                } 
                # If the value is falsy (null, false, 0), keep it as is
                elseif (-not $sourceObj.$key) {
                    $newObjectHash[$key] = $sourceObj.$key 
                }
            }
        }
        $sourceSize = if ($sourceObj.PSObject.Properties) { $sourceObj.PSObject.Properties.Count } else { 0 }
        Write-Debug ("{0}/{1} keys were whitelisted from the source dictionary." -f $counter, $sourceSize)
        
        return $newObjectHash
    } 
    
    # 2. Array mapping (YAML schema list)
    elseif ($whitelistObj -is [System.Collections.Generic.List`1[System.Object]] -and $whitelistObj.count -eq 1) {
        # When the whitelist object is a list with a single member, loop over the source and store the results in an array.
        $results = [System.Collections.Generic.List[object]]::new()
        
        # Ensure the source is actually enumerable before looping
        if ($sourceObj -is [System.Collections.IEnumerable] -and $sourceObj -isnot [string] -and $sourceObj -isnot [hashtable]) {
            foreach ($item in $sourceObj) {
                $results.Add((Build-Body -whitelistObj $whitelistObj[0] -sourceObj $item -depth ($depth + 1)))
            }
        } else {
            # Fallback if the source is a single item but the schema expects a list
            $results.Add((Build-Body -whitelistObj $whitelistObj[0] -sourceObj $sourceObj -depth ($depth + 1)))
        }
        return $results.ToArray()
    } 
    
    # 3. String (Leaf node)
    elseif ($whitelistObj -is [string]) {
        # When the whitelist object is a string, store the value of the source object and move on.
        # Note that if the value is a list/dict, it will still add everything.
        # TODO: Validate source object data types.
        return $sourceObj
    } 
    
    # 4. Catch unexpected schemas
    else {
        Write-Error "Unexpected format of whitelist object. Check your configuration: $($whitelistObj | ConvertTo-Json -Depth 2)"
        Return
    }
}
$clientToken = $request.headers.'x-api-key'

# Get a list of all the API Keys. Find the correct API Key if it exists.
$ApiKeys = (Get-ChildItem env:APIKey_*)
$ApiKey = $ApiKeys | Where-Object { $_.Value -eq $clientToken }

# Check if the client's API token matches our stored version and that it's not too short.
# Without this check, a misconfigured environmental variable could allow unauthenticated access.
if (!$ApiKey -or $ApiKey.Value.Length -lt 14 -or $clientToken -ne $ApiKey.Value) {
    Write-Information "Originating IP: $($request.headers.'Originating-IP')"
    ImmediateFailure -Message "401 - API token does not match" -Company $ApiKey
}

$DISABLE_ORGLIST_CSV = ($Env:DISABLE_ORGLIST_CSV -and (($Env:DISABLE_ORGLIST_CSV).ToLower() -eq 'true'))

if ($Request.Body.PermissionsCheckOnly) {
    Write-Verbose "Running permissions only check" -Verbose
}

If (-not $DISABLE_ORGLIST_CSV) {
    # Get the client's IP address
    if ($Request.Body.PermissionsCheckOnly) {
        $ClientIP = $request.headers.'Originating-IP'
    } else {
        $ClientIP = ($request.headers.'X-Forwarded-For' -split ':')[0]
    }
    if (-not $ClientIP -and $request.url.StartsWith("http://localhost:")) {
        $ClientIP = "localtesting"
    }

    # Get the organization associated with the API key
    $ApiKeyOrg = ($ApiKey.Name -split '_')[1]

    # Cache the CSV payload
    if (-not $global:OrgListCache) {
        $global:OrgListCache = Import-Csv ($TriggerMetadata.FunctionDirectory + "\OrgList.csv") -Delimiter ","
    }
    $OrgList = $global:OrgListCache

    # Check the client's IP against the IP/org whitelist.
    $AllowedOrgs = $OrgList | where-object { ($_.ip -eq $ClientIP -or $_.ip -eq "*") -and ($_.APIKeyName -eq $ApiKeyOrg -or $_.APIKeyName -eq $ApiKey.Name) }
    if (!$AllowedOrgs) { 
        ImmediateFailure -Message "401 - No match found in allowed IPs list" -Company $ApiKeyOrg -Details $ClientIP
    }

}

if ($Request.Body.PermissionsCheckOnly) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::OK
        Body = "success"
    })
    exit
}

## Whitelisting endpoints & data.
if (-not $global:EndpointsCache) {
    # Load and parse the YAML only once per worker instance
    if (-not (Get-Command 'ConvertFrom-Yaml' -errorAction SilentlyContinue)) {
        Import-Module powershell-yaml -Function ConvertFrom-Yaml
    }
    $global:EndpointsCache = Get-Content -Raw ($TriggerMetadata.FunctionDirectory + "\..\whitelisted-endpoints.yml") | ConvertFrom-Yaml -Ordered
    Remove-Module powershell-yaml -ErrorAction SilentlyContinue
}

$endpoints = $global:EndpointsCache

$resource_types = @('checklists', 'checklist_templates', 'configurations', 'contacts', 'documents', `
                    'domains', 'locations', 'passwords', 'ssl_certificates', 'flexible_assets', 'tickets')

$resourceUri = $request.Query.ResourceURI
$resourceUri_generic = ([string]$resourceUri).TrimEnd("/") -replace "/\d+","/:id"
$resourceUri_generic_by_type = [string]$resourceUri_generic
foreach ($type in $resource_types) {
    $resourceUri_generic_by_type = $resourceUri_generic_by_type -replace "\/$type","/:type"
}

# Log the body of the request if the debug level is trace. 
if ($VerbosePreference -eq 'Continue' -and $Request.Body) {
    Write-Verbose ("Incoming Body: {0}" -f ($Request.Body|ConvertTo-Json -depth $ITGJsonDepth)) -Verbose
}

# Check to see if the called API endpoint & method has been whitelisted.
foreach ($key in $endpoints.keys) {
    if (($endpoints[$key].endpoints -contains $resourceUri_generic -or $endpoints[$key].endpoints -contains $resourceUri_generic_by_type) -and 
            $endpoints[$key].methods -contains $request.Method) {
        $endpointKey = $key
        break
    }
}
if (-not $endpointKey) {
    ImmediateFailure -Message "401 - Unauthorized endpoint or method: $endpointKey" -Company $ApiKeyOrg -Details ($Request.Body|ConvertTo-Json -depth $ITGJsonDepth)
}

# Build new query string from required and whitelisted parameters
$itgQuery = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)
foreach ($filter in $endpoints[$endpointKey].required_parameters.Keys) {
    $itgQuery.Add($filter, $endpoints[$endpointKey].required_parameters.$filter)
}
foreach ($filter in $endpoints[$endpointKey].allowed_parameters) {
    if ($request.Query.$filter) {
        $itgQuery.Add($filter, $request.Query.$filter)
    }
}

# Combine resource URI and query string
$uriBuilder = [System.UriBuilder]("{0}{1}" -f $ENV:ITGlueURI,$resourceUri)
$uriBuilder.Query = $itgQuery.ToString()
$itgUri = $uriBuilder.Uri.OriginalString
Write-Information ("Outgoing {0} {1}" -f $Request.Method,$itgUri)

# Construct new request for IT Glue
$itgHeaders = @{"x-api-key" = $ENV:ITGlueAPIKey}
$itgMethod = $Request.Method
if ($request.body) {
    Write-Information ($request.body)
    $oldBody = $request.body | convertfrom-json
    $itgBody = Build-Body $endpoints[$endpointKey].createbody $oldBody
    $itgBodyJson = $itgBody | ConvertTo-Json -Depth $ITGJsonDepth

    # Free up memory
    $oldBody = $null
    $itgBody = $null
} else {
    $itgBodyJson = $null
}

# Log outgoing body if the debug level is trace. 
if ($itgBodyJson) {
    Write-Verbose "Outgoing body: $itgBodyJson" -Verbose
}

# Send request to IT Glue
$SuccessfullQuery = $false
$attempt = 2
while ($attempt -gt 0 -and -not $SuccessfullQuery) {
    try {
        $itgResponse = Invoke-WebRequest -Method $itgMethod -ContentType "application/vnd.api+json; charset=utf-8" `
                                 -Uri $itgUri -Body $itgBodyJson -Headers $itgHeaders -UseBasicParsing -ErrorAction Stop
		$itgRequest = [String]::new($itgResponse.Content) | ConvertFrom-Json -AsHashtable -Depth ($ITGJsonDepth + 2)
        $itgRequest.data = @($itgRequest.data)
        $itgResponse = $null  # release the raw response string immediately to save memory
        $SuccessfullQuery = $true
    } catch {
        $attempt--
        if ($attempt -eq 0) {
            Write-Warning $_.Exception.Message
            #$ErrorDetails = $_.ErrorDetails.Message | ConvertFrom-Json
            #Write-Warning "Reason: $($ErrorDetails.errors.detail)"
            # don't respond with $_.Exception.Message to avoid leaking any unexpected information.
            #ImmediateFailure "$($_.Exception.Response.StatusCode.value__) - Failed after 2 attempts to $itgUri." 

            # The below could have security implications, testing
            ImmediateFailure -Message "$($_.Exception.Response.StatusCode.value__) - Failed after 2 attempts to $itgUri. (Reason: $($ErrorDetails.errors.detail -join ", "))" -Company $ApiKeyOrg -Details $itgBodyJson
        }
        start-sleep (get-random -Minimum 1 -Maximum 10)
    }
}

# For organization specific data, only return records linked to the authorized client.
if ($itgRequest -and $itgRequest.data -and $itgRequest.data[0] -and ($itgRequest.data.type -contains "organizations" -or 
    $itgRequest.data[0]['attributes']['organization-id'])) {

    $orgIdSet = [System.Collections.Generic.HashSet[string]]($allowedOrgs.ITGlueOrgID)
    $allowAll = $orgIdSet.Contains("*")

    $itgRequest.data = $itgRequest.data | Where-Object {
        $DISABLE_ORGLIST_CSV -or $allowAll -or 
        ($_.type -eq "organizations" -and $orgIdSet.Contains([string]$_.id)) -or
        $orgIdSet.Contains([string]$_.attributes.'organization-id')
    }
}

# Strip out any paramaters from the body which haven't been explicitly whitelisted.
if ($endpoints[$endpointKey].returnbody) {
    $itgReturnBody = Build-Body $endpoints[$endpointKey].returnbody $itgRequest
    if ($itgRequest.meta) {
        $itgReturnBody['meta'] = $itgRequest.meta
    }
    if ($itgRequest.links) {
        $itgReturnBody['links'] = $itgRequest.links
    }
} else {
    $itgReturnBody = @{}
}

$itgRequest = $null # free up memory from the original request object as much as possible before we do any more processing.

# Log response body if the debug level is trace. 
if ($VerbosePreference -eq 'Continue' -and $itgReturnBody) {
    Write-Verbose ("Response body: {0}" -f ($itgReturnBody | Convertto-Json -Depth $ITGJsonDepth)) -Verbose
}

# Return the final object.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    headers    = @{'content-type' = 'application\json; charset=utf-8' }
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body       = ($itgReturnBody | ConvertTo-Json -Depth $ITGJsonDepth)
})

$itgReturnBody = $null # free up memory from the response body as much as possible before exiting.