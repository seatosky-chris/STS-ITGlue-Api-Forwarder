# AzGlue, a secure API gateway for IT Glue

This project was made by [Kelvin Tegelaar](https://github.com/KelvinTegelaar)'s repo hosted on [KelvinTegelaar/AzGlue](https://github.com/KelvinTegelaar/AzGlue) and originally posted to his own blog [cyberdrain.com](https://www.cyberdrain.com/documenting-with-powershell-handling-it-glue-api-security-and-rate-limiting/).

The main version is a result of merging Angus Warrens version with many security improvements, and [Anguswarren/AzGlue](https://github.com/AngusWarren/AzGlue) and Kelvin's repo.

The current release tries to maintain backwards compatibility with Kelvin's existing gateway and public scripts. In the future, There might be changes that require deeper modification of the AzGlue function which does not allow to retain backwards compatibility. 

This version has been modified by Chris Jantzen. Per-Organization API Key's have been implemented. Additionally, the structure of the API output has been modified to return data in a more similar matter to how the IT Glue Powershell commands return the data. This allows it to more easily work with existing scripts. 

### Changes made/planned by [AngusWarren]:
- [x] Allow local dev, testing and deployment with VSCode's [Azure Functions extension](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-azurefunctions).
- [x] Prevent misconfigured gateways from accepting empty API keys.
- [x] Restrict returned data from the /organizations endpoint to honor OrgId whitelisting.
- [x] Allow clients to post new passwords without allowing them to retrieve existing passwords.
- [x] Allow whitelisting specific API endpoints.
- [x] When relaying requests, allow per-endpoint filtering and validation of:
  - [x] Supported HTTP methods (POST/PATCH/PUT/DELETE).
  - [x] Query string parameters.
  - [x] Payload data sent to IT Glue.
  - [x] Payload data returned to the client.
- [x] Move IT Glue API key to Azure Key Vault.
- [ ] Set up default whitelisted-endpoints.yml file to work with Kelvin Tegelaar's existing scripts.

### Changes made/planned by [chrisjantzen]:
- [x] Add contacts and locations to the endpoint whitelist.
- [x] Fix stripped data in deep nested return values due to low depth JSON encoding.
- [x] Modify script to return data in the same format as the IT Glue Powershell commands.
- [x] Implement per-client API keys.

### Goals for second release:
- [x] Per-client API keys  
- [ ] System to only returned data relevant to the specific PC making the request.

### Progress setting up whitelisted-endpoints.yml defaults:
  - [x] IT-Glue-ADDS-Documentation.ps1
  - [ ] IT-Glue-ADGroups-Documentation.ps1
  - [ ] IT-Glue-AzureADSettings-Documentation.ps1
  - [x] IT-glue-BitLocker-Documentation.ps1
  - [x] ITGlue-Device-AuditLog.ps1
  - [x] ITGlue-DeviceSync.ps1
  - [x] IT-Glue-FileSharePermissions-Documentation.ps1
  - [x] IT-Glue-HyperV-Documentation.ps1
  - [ ] IT-Glue-intuneApplication-Documentation.ps1
  - [x] IT-Glue-LAPSAlternative-Documentation.ps1
  - [ ] IT-Glue-Network-Documentation.ps1
  - [ ] IT-Glue-O365-MailboxPermissions-Documentation.ps1
  - [ ] IT-Glue-O365-Teams-Documentation.ps1
  - [ ] IT-Glue-O365-UsageReports-Documentation.ps1
  - [ ] IT-Glue-Server-Documentation.ps1
  - [x] IT-Glue-SQL-Documentation.ps1
  - [x] IT-Glue-Unifi-Documentation.ps1

### Basic setup
1. Install the [Azure Functions extensions](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-azurefunctions) for VS Code. Also install [Azure Functions Core Tools](https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local?tabs=windows%2Ccsharp%2Cbash#v2) if you want to test locally.
2. Copy the local.settings.json.example file, and remove the .example extension. 
3. Populate the APIKey_ORG, ITGlueAPIKey & ITGlueURI environmental variables here. The API Key must be 14 or more characters. A UUID will work well for this. See the [Multi-Organization Setup](#multi-organization-setup) section below if you want separate API keys per organization.
4. Copy OrgList.csv.example and remove the .example extension.
5. Update to match your environment. See the Multi-Organization setup section for more info on configuring this file.
6. Right click on the "AzGluePS" directory, and select "open with Code".
7. Open the "run.ps1" file and press F5. 
8. Test it locally using the "http://localhost:7071/api/${functionName}?ResourceURI=" URI.
9. Open the Azure tab on the left, open Functions, click the "Deploy to Function App.." button to create/deploy the app in Azure.
10. Open the Function App in the [Azure Portal](https://portal.azure.com/). (You can find your Function App easily by searching the name you used in the top search bar.)
11. Set up application settings:
    1. Open the Azure portal, open your Function App, open Configuration > Application settings.
    2. Add APIKey_ORG (or your per organization keys), ITGlueAPIKey & ITGlueURI environmental variables here.
    3. If you've got a Key Vault, you can authorize the system managed identity and provide access to the key through the Application settings [using this process](https://docs.microsoft.com/en-us/azure/app-service/app-service-key-vault-references)
12. Finally, to get your function token, navigate to Functions > App Keys. Copy the "default" key. You will need to use this in the BaseUri (see Basic Usage section below).

### Basic usage:
Once the gateway is deployed to Azure Functions, you can use the standard IT Glue Powershell module to query it.
```PowerShell
Import-Module ITGlueAPI
$functionSite = "ITGlueAzureGateway" # You can get this by navigating to your App Function in the Azure Portal, see the URL on the Overview page
$functionName = "AzGlueForwarder"
$functionToken = "default_app_key_generated_by_Azure"

# note that the base Uri should end with the = sign.
Add-ITGlueBaseUri "https://${functionSite}.azurewebsites.net/api/${functionName}?code=${functionToken}&ResourceURI="
Add-ITGlueApiKey "organizations_api_key_saved_in_functions_environmental_variables" # APIKey_ORG

Get-ITGluePasswords -organization_id 1234
```

While it's running locally you can use something like this for the Base URI:
```PowerShell
$functionName = "AzGlueForwarder"
Add-ITGlueBaseUri "http://localhost:7071/api/${functionName}?ResourceURI="
```

### Multi-Organization Setup
If you want a different API Key per organization, use the following setup method:
1. Edit the local.settings.json file, add an entry for each organization with the API Key as the variable. Name each using the format: **APIKey_*ORG*** (Where ***ORG*** is the name of the organization or an acronym. It should have no spaces or symbols. (e.g. "APIKey_HappyFrog") To make this process easier, you can use this APIKeyGenerator.ps1 script.
2. Edit the OrgList.csv file, add an entry for each organization. 
   1. The first column should contain the IP that can access this resource.
   2. The second is the ID of the organization in IT Glue
   3. The third should match the local.settings.json file. It can be either the organization's name or acronym (e.g. HappyFrog), or the full name of the API Key (e.g. APIKey_HappyFrog).
3. In the Azure Portal in the application settings, add each API Key that you added in local.settings.json. 

### Original README
See https://www.cyberdrain.com/documenting-with-powershell-handling-it-glue-api-security-and-rate-limiting/ for more information.

After my previous blogs the comment I’ve received most was worries about the API key. If they key gets stolen you’re giving away the keys to the castle. The API has no limitations and with a leaked key all your documentation could be download. I’ve been discussing this issue with IT-Glue for some time but haven’t gotten a real solution yet. This has forced me to look for a solution myself. I gave myself some requirements for the solution.

- The solution needed to be simple and accessible for everyone.
- The solution needed to have multiple levels of authentication; an API key, IP whitelisting, and organization whitelisting.
- The solution needed to block requests for all passwords/files/etc for all organizations.
- The solution needed to allow some form of handling of the API rate limiting, e.g. repeating a request if it was rate limited.
- The solution needed to be able to used, without adapting any scripts (except URLs and API codes.)
- So after some research I decided to use an Azure Function for this. I’ve blogged about Azure Functions before, but the main reason is that running this function in the consumption model will cost us nothing (or next to nothing if you are an extremely heavy user.)

### Contributions & Thanks

The project is open to any PR and/or direct contributors. Feel free to contact kelvin (at) limenetworks.nl if you'd like to be a direct contributor. Special thanks goes out to [AngusWarren](https://github.com/AngusWarren) for the amazing changes to the security of the AzGlue function. 
