enum OAuthProviderType {
  GitHub = 'github',
  BitBucket = 'bitbucket'
}

export abstract class OAuthProvider {
  static providers = Object.keys(OAuthProviderType).map(key => `'${OAuthProviderType[key]}'`).join(', ');

  public name;

  constructor(
    public type: OAuthProviderType,
    public clientID: string,
    public authorizeUrl: string,
    public redirectUrl: string,
    public signupUrl: string,
    public useState: boolean,
    public params: object) {

    if (!this.type) {
      console.error(`Please configure Builder with an OAuth provider. Supported providers are ${OAuthProvider.providers}.`);
    }

    if (!this.clientID) {
      console.error(`Please configure Builder with your OAuth application's client ID.`);
    }

    if (!this.authorizeUrl) {
      console.error(`Please configure Builder with an OAuth authorization URL. (e.g., 'https://github.com/login/oauth/authorize')`);
    }

    if (!this.redirectUrl) {
      console.error(`Please configure Builder with an OAuth redirect URL. (e.g., 'https://yourdomain.com/oauth/redirect')`);
    }

    if (!this.signupUrl) {
      console.warn(`Consider configuring Builder with an OAuth signup URL for your users. (e.g., 'https://github.com/join').`);
    }
  }

  static fromConfig(type: string, clientID: string, authorizeUrl: string, redirectUrl: string, signupUrl: string, state: string): OAuthProvider {
    switch (type) {
      case OAuthProviderType.GitHub:
        return new GitHubProvider(clientID, authorizeUrl, redirectUrl, signupUrl, state);
      case OAuthProviderType.BitBucket:
        return new BitBucketProvider(clientID, authorizeUrl, redirectUrl, signupUrl);
      case undefined:
      case '':
        console.error(`Please configure Builder with an OAuth provider. Supported providers are ${OAuthProvider.providers}.`);
        break;
      default:
        console.error(`Unsupported OAuth provider '${type}'. Supported providers are ${OAuthProvider.providers}.`);
    }
  }
}

class GitHubProvider extends OAuthProvider {
  name: string = 'GitHub';

  constructor(clientID: string, authorizeUrl: string, redirectUrl: string, signupUrl: string, state: string) {
    super(
      OAuthProviderType.GitHub,
      clientID,
      authorizeUrl,
      redirectUrl,
      signupUrl,
      true,
      {
        client_id: clientID,
        redirect_uri: redirectUrl,
        state: state
      }
    );
  }
}

class BitBucketProvider extends OAuthProvider {
  name: string = 'BitBucket';

  constructor(clientID: string, authorizeUrl: string, redirectUrl: string, signupUrl: string) {
    super(
      OAuthProviderType.BitBucket,
      clientID,
      authorizeUrl,
      redirectUrl,
      signupUrl,
      false,
      {
        client_id: clientID,
        response_type: 'code'
      }
    );
  }
}