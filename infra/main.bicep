metadata name = 'Real-time Ingestion Fabric Solution Accelerator'
metadata description = '''SAS Gold Standard Solution Accelerator for Real-time Ingestion with Fabric.
'''
@minLength(1)
@maxLength(20)
@description('Optional. A friendly string representing the application/solution name to give to all resource names in this deployment. This should be 3-16 characters long.')
param solutionName string = 'rtifsa'

@maxLength(5)
@description('Optional. A unique text value for the solution. This is used to ensure resource names are unique for global resources. Defaults to a 5-character substring of the unique string generated from the subscription ID, resource group name, and solution name.')
param solutionUniqueText string = substring(uniqueString(subscription().id, resourceGroup().name, solutionName), 0, 5)

@minLength(3)
@metadata({ azd: { type: 'location' } })
@description('Optional. Azure region for all services. Defaults to the tenant\' location to avoid usage of Microsoft Fabric multi-geo capabilities.')
param location string = resourceGroup().location

@description('Optional. Enable/Disable usage telemetry for module.')
param enableTelemetry bool = true

@description('Optional. An array of user object IDs or service principal object IDs that will be assigned the Fabric Capacity Admin role. This can be used to add additional admins beyond the default admin which is the user assigned managed identity created as part of this deployment.')
param fabricAdminMembers array = []

@allowed([
  'F2'
  'F4'
  'F8'
  'F16'
  'F32'
  'F64'
  'F128'
  'F256'
  'F512'
  'F1024'
  'F2048'
])
@description('Optional. SKU tier of the Fabric resource.')
param skuName string = 'F2'

@description('Specifies the object id of a Microsoft Entra ID user to allow Event Hub data access for event simulation. This is typically the object id of the system administrator who deploys the Azure resources. Defaults to the deploying user.')
param userObjectId string = deployer().objectId

@description('Optional. Tags to apply to all resources.')
param tags resourceInput<'Microsoft.Resources/resourceGroups@2025-04-01'>.tags = {}

// ============================================================================
// EXISTING RESOURCE PARAMETERS
// When these are provided, the deployment will use existing resources instead
// of creating new ones. Set these via azd env set before running azd up.
// ============================================================================

@description('Optional. Name of an existing Event Hub Namespace to use. When provided, a new Event Hub Namespace will not be created.')
param existingEventHubNamespaceName string = ''

@description('Optional. Name of an existing Event Hub within the namespace to use. When provided along with existingEventHubNamespaceName, a new Event Hub will not be created.')
param existingEventHubName string = ''

@description('Optional. Resource group name where the existing Event Hub Namespace is located. Required when using existingEventHubNamespaceName that is in a different resource group.')
param existingEventHubResourceGroupName string = ''

@description('Optional. Name of an existing Fabric Capacity to use. When provided, a new Fabric Capacity will not be created.')
param existingFabricCapacityName string = ''

// Determine whether to use existing resources
// Scenarios:
// 1. Create new namespace + new event hub: neither existingEventHubNamespaceName nor existingEventHubName set
// 2. Use existing namespace, create new event hub: only existingEventHubNamespaceName set
// 3. Use existing namespace + existing event hub: both set
var useExistingEventHubNamespace = !empty(existingEventHubNamespaceName)
var useExistingEventHub = !empty(existingEventHubNamespaceName) && !empty(existingEventHubName)
var useExistingFabricCapacity = !empty(existingFabricCapacityName)

var solutionSuffix = toLower(trim(replace(
  replace(
    replace(replace(replace(replace('${solutionName}${solutionUniqueText}', '-', ''), '_', ''), '.', ''), '/', ''),
    ' ',
    ''
  ),
  '*',
  ''
)))

var allTags = union(
  {
    'azd-env-name': solutionName
    TemplateName: 'Real-time Ingestion Fabric Solution Accelerator'
    SecurityControl: 'Ignore' // TODO - temp tag to override MSFT subscription controls for testing
  },
  tags
)

resource resourceGroupTags 'Microsoft.Resources/tags@2021-04-01' = {
  name: 'default'
  properties: {
    tags: union(reference(resourceGroup().id, '2021-04-01', 'Full').?tags ?? {}, allTags)
  }
}

var eventHubNamespaceName = useExistingEventHubNamespace ? existingEventHubNamespaceName : 'evhns${solutionSuffix}'
var eventHubName = useExistingEventHub ? existingEventHubName : 'evh${solutionSuffix}'

// Reference existing Event Hub Namespace when creating a new Event Hub in it
resource existingEventHubNamespaceRef 'Microsoft.EventHub/namespaces@2024-01-01' existing = if (useExistingEventHubNamespace && !useExistingEventHub) {
  name: existingEventHubNamespaceName
}

// Create new Event Hub in existing namespace (when namespace exists but event hub doesn't)
resource newEventHubInExistingNamespace 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = if (useExistingEventHubNamespace && !useExistingEventHub) {
  parent: existingEventHubNamespaceRef
  name: eventHubName
  properties: {
    messageRetentionInDays: 1
  }
}

// Create new Event Hub Namespace with Event Hub when not using existing namespace
module eventHubNamespace 'br/public:avm/res/event-hub/namespace:0.13.0' = if (!useExistingEventHubNamespace) {
  name: take('avm.res.event-hub.namespace.${eventHubNamespaceName}', 64)
  params: {
    name: eventHubNamespaceName
    location: location
    skuName: 'Standard'
    skuCapacity: 1
    disableLocalAuth: false // NOTE: local auth is currently needed in order to create connection with Fabric via SAS token
    eventhubs: [
      {
        name: eventHubName
        messageRetentionInDays: 1
      }
    ]
    roleAssignments: [
      {
        roleDefinitionIdOrName: 'Azure Event Hubs Data Sender'
        principalId: userObjectId
      }
    ]
    enableTelemetry: enableTelemetry
  }
}

var fabricCapacityResourceName = useExistingFabricCapacity ? existingFabricCapacityName : 'fc${solutionSuffix}'
var fabricCapacityDefaultAdmins = deployer().?userPrincipalName == null
  ? [deployer().objectId]
  : [deployer().userPrincipalName]
var fabricTotalAdminMembers = union(fabricCapacityDefaultAdmins, fabricAdminMembers)

// Create new Fabric Capacity when not using existing resources
module fabricCapacity 'br/public:avm/res/fabric/capacity:0.1.2' = if (!useExistingFabricCapacity) {
  name: take('avm.res.fabric.capacity.${fabricCapacityResourceName}', 64)
  params: {
    name: fabricCapacityResourceName
    location: location
    skuName: skuName
    adminMembers: fabricTotalAdminMembers
    enableTelemetry: enableTelemetry
  }
}

@description('The location the resources were deployed to')
output AZURE_LOCATION string = location

@description('The name of the resource group')
output AZURE_RESOURCE_GROUP string = resourceGroup().name

@description('The name of the Fabric capacity resource')
#disable-next-line BCP318
output AZURE_FABRIC_CAPACITY_NAME string = useExistingFabricCapacity ? existingFabricCapacityName : fabricCapacity!.outputs.name

@description('The identities added as Fabric Capacity Admin members')
output AZURE_FABRIC_CAPACITY_ADMINISTRATORS array = fabricTotalAdminMembers

@description('The name of the Event Hub Namespace for ingestion.')
output AZURE_EVENT_HUB_NAMESPACE_NAME string = useExistingEventHubNamespace ? existingEventHubNamespaceName : eventHubNamespace!.outputs.name

@description('The hostname of the Event Hub Namespace for ingestion.')
output AZURE_EVENT_HUB_NAMESPACE_HOSTNAME string = useExistingEventHubNamespace ? '${existingEventHubNamespaceName}.servicebus.windows.net' : '${eventHubNamespace!.outputs.name}.servicebus.windows.net'

@description('The name of the Event Hub for ingestion.')
output AZURE_EVENT_HUB_NAME string = eventHubName

@description('The solution name suffix used for resource naming.')
output SOLUTION_SUFFIX string = solutionSuffix

@description('Indicates whether an existing Event Hub Namespace was used.')
output USING_EXISTING_EVENT_HUB_NAMESPACE bool = useExistingEventHubNamespace

@description('Indicates whether an existing Event Hub was used.')
output USING_EXISTING_EVENT_HUB bool = useExistingEventHub

@description('Indicates whether existing Fabric Capacity was used.')
output USING_EXISTING_FABRIC_CAPACITY bool = useExistingFabricCapacity

@description('The resource group name where the Event Hub Namespace is located.')
output AZURE_EVENT_HUB_RESOURCE_GROUP string = useExistingEventHubNamespace && !empty(existingEventHubResourceGroupName) ? existingEventHubResourceGroupName : resourceGroup().name
