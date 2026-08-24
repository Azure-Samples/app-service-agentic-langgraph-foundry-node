@description('Environment name for the resources')
param envName string
@description('Location for all resources')
param location string = resourceGroup().location

var webAppHash = toLower(substring(uniqueString(envName), 0, 7))
var webAppName = '${envName}-node-${webAppHash}'
var appServiceAuthManagedIdentitySettingName = 'OVERRIDE_USE_MI_FIC_ASSERTION_CLIENTID'

resource appServiceAuthIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
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
          name: appServiceAuthManagedIdentitySettingName
          value: appServiceAuthIdentity.properties.clientId
        }
        {
          name: 'WEBSITE_AUTH_AAD_ALLOWED_TENANTS'
          value: tenant().tenantId
        }
      ]
    }
  }
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${appServiceAuthIdentity.id}': {}
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
    managedIdentityPrincipalId: appServiceAuthIdentity.properties.principalId
  }
}

resource webAppAuthSettings 'Microsoft.Web/sites/config@2024-11-01' = {
  name: '${webApp.name}/authsettingsV2'
  properties: {
    clearInboundClaimsMapping: 'false'
    platform: {
      enabled: true
      runtimeVersion: '~1'
    }
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: 'RedirectToLoginPage'
      redirectToProvider: 'azureActiveDirectory'
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        isAutoProvisioned: true
        login: {
          disableWWWAuthenticate: false
        }
        registration: {
          clientId: entraApp.outputs.clientId
          clientSecretSettingName: appServiceAuthManagedIdentitySettingName
          openIdIssuer: 'https://sts.windows.net/${tenant().tenantId}/v2.0'
        }
        validation: {
          allowedAudiences: [
            'api://${entraApp.outputs.clientId}'
          ]
          defaultAuthorizationPolicy: {
            allowedApplications: [
              entraApp.outputs.clientId
            ]
            allowedPrincipals: {}
          }
        }
      }
    }
    login: {
      cookieExpiration: {
        convention: 'FixedTime'
        timeToExpiration: '08:00:00'
      }
      nonce: {
        nonceExpirationInterval: '00:05:00'
        validateNonce: true
      }
      preserveUrlFragmentsForLogins: false
      tokenStore: {
        enabled: true
        tokenRefreshExtensionHours: 72
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
