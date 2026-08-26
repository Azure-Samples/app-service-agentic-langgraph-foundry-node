extension microsoftGraphV1

@description('Environment name used to create a unique Entra app registration')
param envName string

@description('URL of the deployed App Service app')
param webAppUrl string

@description('Principal ID of the user-assigned identity used by App Service authentication')
param managedIdentityPrincipalId string

resource app 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: 'task-manager-${envName}'
  displayName: 'Task Manager (${envName})'
  signInAudience: 'AzureADMyOrg'
  requiredResourceAccess: []
  api: {
    requestedAccessTokenVersion: 2
  }
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
  tags: [
    'AppServiceIntegratedApp'
    'WindowsAzureActiveDirectoryIntegratedApp'
  ]
}

output clientId string = app.appId
output appObjectId string = app.id
output uniqueName string = app.uniqueName
