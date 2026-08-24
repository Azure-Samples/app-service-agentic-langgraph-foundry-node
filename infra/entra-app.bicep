extension microsoftGraphV1

@description('Environment name used to create a unique Entra app registration')
param envName string

@description('URL of the deployed App Service app')
param webAppUrl string

@description('Principal ID of the user-assigned identity used by App Service authentication')
param managedIdentityPrincipalId string

var microsoftGraphAppId = '00000003-0000-0000-c000-000000000000'
var userReadScopeId = 'e1fe6dd8-ba31-4d61-89e7-88639da4683d'

resource app 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: 'task-manager-${envName}'
  displayName: 'Task Manager (${envName})'
  signInAudience: 'AzureADMyOrg'
  requiredResourceAccess: [
    {
      resourceAppId: microsoftGraphAppId
      resourceAccess: [
        {
          id: userReadScopeId
          type: 'Scope'
        }
      ]
    }
  ]
  web: {
    homePageUrl: webAppUrl
    implicitGrantSettings: {
      enableAccessTokenIssuance: false
      enableIdTokenIssuance: true
    }
    redirectUris: [
      '${webAppUrl}/.auth/login/aad/callback'
    ]
  }

  resource managedIdentityCredential 'federatedIdentityCredentials@v1.0' = {
    name: '${app.uniqueName}/app-service-authentication'
    description: 'Allow App Service authentication to use a managed identity instead of a client secret'
    audiences: [
      'api://AzureADTokenExchange'
    ]
    issuer: '${environment().authentication.loginEndpoint}${tenant().tenantId}/v2.0'
    subject: managedIdentityPrincipalId
  }
}

resource servicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: app.appId
}

output clientId string = app.appId
output appObjectId string = app.id
