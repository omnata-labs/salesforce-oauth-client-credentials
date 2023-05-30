/*
 * Loops back to itself and uses a named credential to directly get an OAuth token via client credentials
 */
global class OAuthClientCredentialsAuthProvider extends Auth.AuthProviderPluginClass{
  private String clientCredentialsName;
  private String scope;
  private String authProviderUrlSuffix;

  // This method is responsible for returning the custom metadata storing the api credentials and other details
  global String getCustomMetadataType(){
    return 'Client_Credentials_OAuth__mdt';
  }

  // This method is responsible to initiate the authorization code flow.
  // Since we're using Client Credentials instead of Authorization Code, we just redirect straight back
  // to the return URL (invoking handleCallback below)
  global PageReference initiate(Map<String, String> authProviderConfiguration, String stateToPropagate){
    setParameters(authProviderConfiguration);
    final String callbackUrl = URL.getSalesforceBaseUrl().toExternalForm() + '/services/authcallback/' + authProviderUrlSuffix+'?state='+stateToPropagate;
    return new PageReference(callbackUrl);
  }

  private void setParameters(Map<String, String> authProviderConfiguration){
    clientCredentialsName = authProviderConfiguration.get('Named_Credentials_Name__c');
    authProviderUrlSuffix = authProviderConfiguration.get('AuthProviderURLSuffix__c');
    scope = authProviderConfiguration.get('OAuth_Scopes__c');
  }

  /*
   This method is invoked when the admin is landed directly back here after 'initiate' above.
   It uses the other set of Named Credentials to get an OAuth token
   */
  global Auth.AuthProviderTokenResponse handleCallback(Map<String, String> authProviderConfiguration, Auth.AuthProviderCallbackState state){
    setParameters(authProviderConfiguration);
    Map<String,String> queryParams = state.queryParameters;
    String sfdcState = queryParams.get('state');
    OAuthTokenResponse response = getAccessToken();
    return new Auth.AuthProviderTokenResponse('OAuthClientCredentialsAuthProvider', response.access_token, 'Not a real refresh token', sfdcState);
  }

  /*
   Client Credentials don't use refresh tokens, so if we're ever asked we just ask directly for another access token
   */
  override global Auth.OAuthRefreshResult refresh(Map<String, String> authProviderConfiguration, String refreshToken){
    setParameters(authProviderConfiguration);
    OAuthTokenResponse response = getAccessToken();
    try{
      return new Auth.OAuthRefreshResult(response.access_token, 'Not a real refresh token');
    }
    catch(OAuthException e){
      return new Auth.OAuthRefreshResult(null, null, e.getMessage());
    }
  }

  private OAuthTokenResponse getAccessToken(){
    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:' + clientCredentialsName);
    req.setHeader('Accept', 'application/json');
    req.setHeader('Content-type', 'application/x-www-form-urlencoded');
    // https://datatracker.ietf.org/doc/html/rfc6749#section-4.4.2
    String body = 'grant_type=client_credentials&scope=' + EncodingUtil.urlEncode(scope, 'UTF-8');
    req.setBody(body);
    req.setMethod('POST');
    Http http = new Http();
    System.HttpResponse response = http.send(req);
    String responseBody = response.getBody();
    if (response.getStatusCode()==200){
      return (OAuthTokenResponse)JSON.deserialize(responseBody, OAuthTokenResponse.class);
    }
    OAuthTokenResponseError error = (OAuthTokenResponseError)JSON.deserialize(responseBody, OAuthTokenResponseError.class);
    ///System.debug(error);
    throw new OAuthException('Error getting access token: ' + error.error + ':' + error.error_description);
  }

  /*
   We can't provide much in the way of user information, since this is a system->system connection
   */
  global Auth.UserData getUserInfo(Map<String, String> authProviderConfiguration, Auth.AuthProviderTokenResponse response){
    return new Auth.UserData(null, null, null, null, null, null, null, null, 'Generic Client Credentials', null, null);
  }

  /*
   Wrapper class to handle Access Token API response
   per https://datatracker.ietf.org/doc/html/rfc6749#section-4.4.3
   */
  private class OAuthTokenResponse{
    public String access_token;
    public Integer expires_in;
    public String token_type;
  }

  private class OAuthTokenResponseError{
    public String error;
    public String error_description;
  }

  public class OAuthException extends Exception {}

}