@description('Environment name for the resources')
param envName string
@description('Location for all resources')
param location string = resourceGroup().location

var webAppHash = toLower(substring(uniqueString(envName), 0, 7))
var webAppName = '${envName}-node-${webAppHash}'
var easyAuthManagedIdentitySettingName = 'OVERRIDE_USE_MI_FIC_ASSERTION_CLIENTID'

resource easyAuthIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${webAppName}-auth'
  location: location
}

resource appServicePlan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: webAppName
  location: location
  sku: {
    name: 'B1'
    tier: 'Basic'
    size: 'B1'
    capacity: 1
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

resource webApp 'Microsoft.Web/sites@2024-11-01' = {
  name: webAppName
  location: location
  kind: 'app,linux'
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'NODE|22-lts'
      alwaysOn: true
      appSettings: [
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
        {
          name: easyAuthManagedIdentitySettingName
          value: easyAuthIdentity.properties.clientId
        }
      ]
    }
  }
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${easyAuthIdentity.id}': {}
    }
  }
  tags: {
    'azd-service-name': 'web'
  }
}

module entraApp 'entra-app.bicep' = {
  name: 'entra-app'
  params: {
    envName: envName
    webAppUrl: 'https://${webApp.properties.defaultHostName}'
    managedIdentityPrincipalId: easyAuthIdentity.properties.principalId
  }
}

resource webAppAuthSettings 'Microsoft.Web/sites/config@2024-11-01' = {
  name: '${webApp.name}/authsettingsV2'
  properties: {
    platform: {
      enabled: true
    }
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: 'RedirectToLoginPage'
      redirectToProvider: 'azureActiveDirectory'
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          clientId: entraApp.outputs.clientId
          clientSecretSettingName: easyAuthManagedIdentitySettingName
          openIdIssuer: '${environment().authentication.loginEndpoint}${subscription().tenantId}/v2.0'
        }
        validation: {
          allowedAudiences: [
            entraApp.outputs.clientId
          ]
        }
      }
    }
    login: {
      tokenStore: {
        enabled: true
      }
    }
    httpSettings: {
      requireHttps: true
    }
  }
}

output AZURE_LOCATION string = location
output SERVICE_WEB_IDENTITY_PRINCIPAL_ID string = webApp.identity.principalId
output SERVICE_WEB_NAME string = webApp.name
output SERVICE_WEB_URI string = 'https://${webApp.properties.defaultHostName}'
output AZURE_AUTH_APP_CLIENT_ID string = entraApp.outputs.clientId
output AZURE_AUTH_APP_OBJECT_ID string = entraApp.outputs.appObjectId
